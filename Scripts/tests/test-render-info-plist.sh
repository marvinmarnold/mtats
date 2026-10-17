#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PB=/usr/libexec/PlistBuddy

MTATS_VERSION=1.2.3 MTATS_BUILD=42 Scripts/render-info-plist.sh "$T/r.plist" release
plutil -lint -s "$T/r.plist" || fail "release plist invalid"
[[ "$($PB -c 'Print :CFBundleShortVersionString' "$T/r.plist")" == "1.2.3" ]] || fail "version"
[[ "$($PB -c 'Print :CFBundleVersion' "$T/r.plist")" == "42" ]] || fail "build"
[[ "$($PB -c 'Print :LSMinimumSystemVersion' "$T/r.plist")" == "14.0" ]] || fail "min OS"
grep -q "__" "$T/r.plist" && fail "unreplaced token in release plist"

# Review Focus: a debug package must never poll the production feed.
MTATS_VERSION=1.2.3 MTATS_BUILD=42 Scripts/render-info-plist.sh "$T/d.plist" debug
$PB -c 'Print :SUFeedURL' "$T/d.plist" >/dev/null 2>&1 && fail "debug plist must not contain SUFeedURL"
Scripts/render-info-plist.sh "$T/x.plist" bogus 2>/dev/null && fail "bad configuration should fail"
KEY=$($PB -c 'Print :SUPublicEDKey' "$T/r.plist") || fail "SUPublicEDKey missing"
[[ $(printf %s "$KEY" | base64 -d 2>/dev/null | wc -c) -eq 32 ]] || fail "SUPublicEDKey is not a 32-byte Ed25519 key"
exit 0
