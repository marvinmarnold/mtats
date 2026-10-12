#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for f in mtats-1.0.0.dmg mtats-1.0.0.dmg.sha256 appcast.xml latest.json; do echo x >"$T/$f"; done

OUT=$(PUBLISH_DRY_RUN=1 Scripts/publish.sh "$T" stable 1.0.0)
grep -q 'gs://mtats-releases/releases/mtats-1.0.0.dmg' <<<"$OUT" || fail "DMG upload missing"
grep -q 'gs://mtats-releases/appcast.xml' <<<"$OUT" || fail "stable appcast upload missing"
grep -q 'gs://mtats-releases/latest.json' <<<"$OUT" || fail "stable latest.json upload missing"
grep -q -- '--project mtats-release' <<<"$OUT" || fail "commands must pass --project"

OUT=$(PUBLISH_DRY_RUN=1 Scripts/publish.sh "$T" beta 1.0.0)
grep -q 'gs://mtats-releases/beta/appcast.xml' <<<"$OUT" || fail "beta appcast path"
grep -q 'gs://mtats-releases/latest.json' <<<"$OUT" && fail "beta must not touch stable latest.json"

# Review Focus: never overwrite a released DMG.
PUBLISH_DRY_RUN=1 PUBLISH_FAKE_EXISTING=releases/mtats-1.0.0.dmg Scripts/publish.sh "$T" stable 1.0.0 >/dev/null 2>&1 \
  && fail "an existing DMG name must fail the publish"
exit 0
