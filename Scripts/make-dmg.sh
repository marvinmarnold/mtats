#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: make-dmg.sh <path/to/mtats.app> <out.dmg>
# Drag-to-Applications image with the app icon as the volume icon (spec 2026-10-17 §7.2).
set -euo pipefail
APP="$1"; OUT="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE=$(mktemp -d); MNT=$(mktemp -d); RW="$STAGE.rw.dmg"
cleanup() { hdiutil detach -quiet "$MNT" 2>/dev/null || true; rm -rf "$STAGE" "$MNT" "$RW"; }
trap cleanup EXIT
ditto "$APP" "$STAGE/mtats.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
hdiutil create -quiet -volname "mtats $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$MNT" "$RW"
# Finder's kHasCustomIcon flag (0x0400) lives at byte offset 8 of the 32-byte com.apple.FinderInfo attribute.
xattr -wx com.apple.FinderInfo \
  "0000000000000000040000000000000000000000000000000000000000000000" "$MNT"
hdiutil detach -quiet "$MNT"
rm -f "$OUT"
hdiutil convert -quiet "$RW" -format UDZO -o "$OUT"
echo "Created $OUT"
