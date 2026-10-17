#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '<?xml version="1.0"?><rss version="2.0"><channel><title>t</title></channel></rss>' >"$T/feed.xml"
GOOD="file://$T/feed.xml"
# The update guard (M-1) reads the channel appcast; tests feed it a local file instead of the bucket.
export APPCAST_FILE="$T/feed.xml"
run() { PREFLIGHT_SKIP_BUILD=1 "$@" ; }

# Positive: valid version, notes exist, feed serves an appcast.
OUT=$(PREFLIGHT_SKIP_BUILD=1 PREFLIGHT_FEED_URL="$GOOD" Scripts/release-preflight.sh 0.1.0) || fail "valid case should pass"
grep -q 'git tag -a v0.1.0' <<<"$OUT" || fail "should print the tag command"

# Review Focus: refuse to tag while mtats.app does not serve a valid feed.
PREFLIGHT_SKIP_BUILD=1 PREFLIGHT_FEED_URL="https://mtats.invalid/appcast.xml" Scripts/release-preflight.sh 0.1.0 >/dev/null 2>&1 && fail "unreachable feed must fail"
printf 'not a feed' >"$T/bad.xml"
PREFLIGHT_SKIP_BUILD=1 PREFLIGHT_FEED_URL="file://$T/bad.xml" Scripts/release-preflight.sh 0.1.0 >/dev/null 2>&1 && fail "non-appcast body must fail"
PREFLIGHT_SKIP_BUILD=1 PREFLIGHT_FEED_URL="$GOOD" Scripts/release-preflight.sh 9.9.9 >/dev/null 2>&1 && fail "missing Releases/9.9.9.md must fail"
PREFLIGHT_FEED_URL="$GOOD" Scripts/release-preflight.sh not-a-version >/dev/null 2>&1 && fail "malformed version must fail"

# M-1: the update guard runs before the immutable tag exists, on the channel derived from the version.
COUNT=$(git rev-list --count HEAD)
printf '<rss><channel><item><sparkle:version>%s</sparkle:version></item></channel></rss>' "$COUNT" >"$T/same.xml"
PREFLIGHT_SKIP_BUILD=1 PREFLIGHT_FEED_URL="$GOOD" APPCAST_FILE="$T/same.xml" Scripts/release-preflight.sh 0.1.0 >/dev/null 2>&1 \
  && fail "build equal to the published build must fail preflight"
printf '<rss><channel><item><sparkle:version>%s</sparkle:version></item></channel></rss>' "$((COUNT - 1))" >"$T/lower.xml"
PREFLIGHT_SKIP_BUILD=1 PREFLIGHT_FEED_URL="$GOOD" APPCAST_FILE="$T/lower.xml" Scripts/release-preflight.sh 0.1.0 >/dev/null \
  || fail "build greater than the published build should pass"
# The channel comes from the version: an rc is guarded against the beta feed.
NOTES=Releases/9.9.9-rc.1.md; trap 'rm -rf "$T" "$NOTES"' EXIT; echo notes >"$NOTES"
OUT=$(PREFLIGHT_SKIP_BUILD=1 PREFLIGHT_FEED_URL="$GOOD" APPCAST_FILE="$T/lower.xml" Scripts/release-preflight.sh 9.9.9-rc.1 2>&1) \
  || fail "rc case should pass: $OUT"
grep -q 'on beta' <<<"$OUT" || fail "an rc must be guarded against the beta channel: $OUT"
rm -f "$NOTES"
exit 0
