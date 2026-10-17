#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
F=Scripts/tests/fixtures/appcast-two-items.xml
fail() { echo "  $*" >&2; exit 1; }
APPCAST_FILE=$F Scripts/appcast-guard.sh stable 138 >/dev/null || fail "138 > 137 should pass"
APPCAST_FILE=$F Scripts/appcast-guard.sh stable 137 2>/dev/null && fail "equal build (re-tag of same commit) must fail"
APPCAST_FILE=$F Scripts/appcast-guard.sh stable 5 2>/dev/null && fail "lower build must fail"
E=$(mktemp); printf '<?xml version="1.0"?><rss version="2.0"><channel><title>mtats</title></channel></rss>' >"$E"
APPCAST_FILE=$E Scripts/appcast-guard.sh beta 1 >/dev/null || fail "empty feed should pass"
rm -f "$E"
Scripts/appcast-guard.sh nightly 1 2>/dev/null && fail "unknown channel must fail"
exit 0
