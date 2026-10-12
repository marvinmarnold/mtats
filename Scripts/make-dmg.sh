#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: make-dmg.sh <path/to/mtats.app> <out.dmg>
set -euo pipefail
APP="$1"; OUT="$2"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/mtats.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -quiet -volname "mtats $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT"
echo "Created $OUT"
