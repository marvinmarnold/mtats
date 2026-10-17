#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
source Scripts/tests/lib-fake-curl.sh
install_fake_curl "$T/bin"
export FAKE_CURL_ROOT="$T/srv"; mkdir -p "$FAKE_CURL_ROOT/mtats-releases/releases"
A="$T/art"; mkdir -p "$A"
echo dmg-bytes >"$A/mtats-1.0.0.dmg"
(cd "$A" && shasum -a 256 mtats-1.0.0.dmg >mtats-1.0.0.dmg.sha256)
for f in appcast.xml latest.json; do echo x >"$A/$f"; done
pub() { PUBLISH_DRY_RUN=1 Scripts/publish.sh "$A" "$@"; }

# New version: DMG absent (404) → uploaded with a server-side creation precondition.
OUT=$(pub stable 1.0.0)
grep -q 'cp .*/mtats-1.0.0.dmg gs://mtats-releases/releases/mtats-1.0.0.dmg ' <<<"$OUT" || fail "DMG upload missing"
grep 'gs://mtats-releases/releases/mtats-1.0.0.dmg ' <<<"$OUT" | grep -q -- '--if-generation-match=0' \
  || fail "DMG upload must carry --if-generation-match=0 (never overwrite, enforced by GCS)"
grep -q 'gs://mtats-releases/appcast.xml' <<<"$OUT" || fail "stable appcast upload missing"
grep -q 'gs://mtats-releases/latest.json' <<<"$OUT" || fail "stable latest.json upload missing"
grep -q -- '--project mtats-release' <<<"$OUT" || fail "commands must pass --project"

OUT=$(pub beta 1.0.0)
grep -q 'gs://mtats-releases/beta/appcast.xml' <<<"$OUT" || fail "beta appcast path"
grep -q 'gs://mtats-releases/latest.json' <<<"$OUT" && fail "beta must not touch stable latest.json"

# Re-run after a partial publish (I-2): identical DMG already in the bucket → skip it, publish the rest.
cp "$A/mtats-1.0.0.dmg" "$FAKE_CURL_ROOT/mtats-releases/releases/"
OUT=$(pub stable 1.0.0) || fail "an identical existing DMG must not fail the publish (re-run must resume)"
grep -q 'gs://mtats-releases/releases/mtats-1.0.0.dmg ' <<<"$OUT" && fail "an identical existing DMG must not be uploaded again"
grep -q 'gs://mtats-releases/appcast.xml' <<<"$OUT" || fail "re-run must still publish the appcast"
grep -q 'gs://mtats-releases/latest.json' <<<"$OUT" || fail "re-run must still publish latest.json"

# Review Focus: never overwrite a released DMG — different bytes under the same name fail, nothing uploaded.
echo other-bytes >"$FAKE_CURL_ROOT/mtats-releases/releases/mtats-1.0.0.dmg"
OUT=$(pub stable 1.0.0 2>/dev/null) && fail "a different existing DMG must fail the publish"
[[ -z "$OUT" ]] || fail "nothing may be uploaded when the existing DMG differs: $OUT"
rm "$FAKE_CURL_ROOT/mtats-releases/releases/mtats-1.0.0.dmg"

# I-1: an error checking for the DMG is not "absent" — it aborts before any upload.
for code in 503 403 000; do
  OUT=$(FAKE_CURL_CODES="mtats-releases/releases/mtats-1.0.0.dmg=$code" pub stable 1.0.0 2>/dev/null) \
    && fail "an existence-check error ($code) must abort the publish"
  [[ -z "$OUT" ]] || fail "nothing may be uploaded after an existence-check error ($code): $OUT"
done

# The artifact must be self-consistent: its .sha256 must match its DMG.
echo tampered >"$A/mtats-1.0.0.dmg"
pub stable 1.0.0 >/dev/null 2>&1 && fail "artifact DMG not matching its .sha256 must fail"
exit 0
