#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: publish.sh <artifact-dir> <stable|beta> <version>
# Uploads the release artifact to the bucket. Re-runnable: DMG names are immutable, so an existing
# DMG with the same bytes is skipped (a re-run after a partial publish resumes), an existing DMG
# with different bytes fails, and an error while checking aborts. New DMGs are uploaded with
# --if-generation-match=0, so GCS itself refuses to overwrite an object that appeared meanwhile.
# PUBLISH_DRY_RUN=1 prints the gcloud commands instead of running them; for tests.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/release-env.sh
DIR="$1"; CHANNEL="$2"; VERSION="$3"
case "$CHANNEL" in stable) PREFIX="" ;; beta) PREFIX="beta/" ;; *) echo "channel must be stable or beta" >&2; exit 2 ;; esac
B="gs://$MTATS_BUCKET"; P=(--project "$MTATS_GCP_PROJECT")

run() { if [[ "${PUBLISH_DRY_RUN:-0}" == 1 ]]; then echo "$*"; else "$@"; fi; }
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

NAME="mtats-${VERSION}.dmg"; DMG="releases/$NAME"
WANT=$(cut -d' ' -f1 "$DIR/$NAME.sha256")
[[ "$(sha256 "$DIR/$NAME")" == "$WANT" ]] || { echo "publish.sh: $DIR/$NAME does not match its .sha256" >&2; exit 1; }

# Existence check over the public HTTPS endpoint: only a 404 means "absent".
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
rc=0; Scripts/fetch-published.sh "https://storage.googleapis.com/$MTATS_BUCKET/$DMG" "$T/existing.dmg" || rc=$?
case "$rc" in
  0) if [[ "$(sha256 "$T/existing.dmg")" == "$WANT" ]]; then
       echo "publish.sh: $B/$DMG already published with identical bytes (sha256 $WANT); skipping upload" >&2
     else
       echo "publish.sh: $B/$DMG already exists with different bytes; DMG names are immutable" >&2; exit 1
     fi ;;
  3) run gcloud storage cp "$DIR/$NAME" "$B/$DMG" "${P[@]}" --if-generation-match=0 \
       --content-type=application/x-apple-diskimage --cache-control="public, max-age=31536000, immutable" ;;
  *) echo "publish.sh: could not determine whether $B/$DMG exists; aborting" >&2; exit 1 ;;
esac
run gcloud storage cp "$DIR/$NAME.sha256" "$B/$DMG.sha256" "${P[@]}" --cache-control="public, max-age=31536000, immutable"
run gcloud storage cp "$DIR/appcast.xml" "$B/${PREFIX}appcast.xml" "${P[@]}" \
  --content-type="application/xml; charset=utf-8" --cache-control="no-cache"
# A prerelease must not change what the website and /download point at (stable latest.json).
if [[ "$CHANNEL" == stable ]]; then
  run gcloud storage cp "$DIR/latest.json" "$B/latest.json" "${P[@]}" \
    --content-type=application/json --cache-control="no-cache"
else
  run gcloud storage cp "$DIR/latest.json" "$B/beta/latest.json" "${P[@]}" \
    --content-type=application/json --cache-control="no-cache"
fi
echo "published $VERSION to $CHANNEL"
