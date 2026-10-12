#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: publish.sh <artifact-dir> <stable|beta> <version>
# Uploads the release artifact to the bucket. DMG names are immutable: an existing object fails.
# PUBLISH_DRY_RUN=1 prints the commands (PUBLISH_FAKE_EXISTING simulates existing objects); for tests.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/release-env.sh
DIR="$1"; CHANNEL="$2"; VERSION="$3"
case "$CHANNEL" in stable) PREFIX="" ;; beta) PREFIX="beta/" ;; *) echo "channel must be stable or beta" >&2; exit 2 ;; esac
B="gs://$MTATS_BUCKET"; P=(--project "$MTATS_GCP_PROJECT")

run() { if [[ "${PUBLISH_DRY_RUN:-0}" == 1 ]]; then echo "$*"; else "$@"; fi; }
exists() {
  if [[ "${PUBLISH_DRY_RUN:-0}" == 1 ]]; then [[ " ${PUBLISH_FAKE_EXISTING:-} " == *" $1 "* ]]; return; fi
  gcloud storage objects describe "$B/$1" "${P[@]}" >/dev/null 2>&1
}

DMG="releases/mtats-${VERSION}.dmg"
if exists "$DMG"; then echo "publish.sh: $B/$DMG already exists; DMG names are immutable" >&2; exit 1; fi
run gcloud storage cp "$DIR/mtats-${VERSION}.dmg" "$B/$DMG" "${P[@]}" \
  --content-type=application/x-apple-diskimage --cache-control="public, max-age=31536000, immutable"
run gcloud storage cp "$DIR/mtats-${VERSION}.dmg.sha256" "$B/$DMG.sha256" "${P[@]}" --cache-control="public, max-age=31536000, immutable"
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
