#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '<?xml version="1.0"?><rss version="2.0"><channel><title>t</title></channel></rss>' >"$T/feed.xml"
GOOD="file://$T/feed.xml"
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
exit 0
