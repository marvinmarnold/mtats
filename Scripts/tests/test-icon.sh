#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Re-renders the icon into a temp dir and checks the iconset members, the committed .icns, and key pixels.
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
swift Scripts/render-icon.swift "$T" >/dev/null
for m in icon_16x16:16 icon_16x16@2x:32 icon_32x32:32 icon_32x32@2x:64 icon_128x128:128 icon_128x128@2x:256 \
         icon_256x256:256 icon_256x256@2x:512 icon_512x512:512 icon_512x512@2x:1024; do
  f="$T/AppIcon.iconset/${m%%:*}.png"; px="${m##*:}"
  [[ -f "$f" ]] || fail "missing $f"
  [[ "$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')" == "$px" ]] || fail "$f width != $px"
  [[ "$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')" == "$px" ]] || fail "$f height != $px"
  [[ "$(sips -g hasAlpha "$f" | awk '/hasAlpha/{print $2}')" == "yes" ]] || fail "$f has no alpha channel"
done
[[ "$(ls "$T/AppIcon.iconset" | wc -l | tr -d ' ')" == "10" ]] || fail "iconset must have exactly 10 members"
iconutil -c icns "$T/AppIcon.iconset" -o "$T/AppIcon.icns" || fail "iconutil failed"
[[ -f Resources/AppIcon.icns ]] || fail "Resources/AppIcon.icns not committed"
[[ "$(stat -f%z Resources/AppIcon.icns)" -le 1048576 ]] || fail "AppIcon.icns larger than 1 MB"
iconutil -c iconset Resources/AppIcon.icns -o "$T/roundtrip.iconset" || fail "committed icns does not round-trip"
[[ -f "$T/roundtrip.iconset/icon_512x512@2x.png" ]] || fail "committed icns lacks the 1024 member"
# Pixel checks on the 1024 render. NSBitmapImageRep.colorAt(x:y:) addresses rows from the top, and
# render-icon.swift flips the context so SVG y=0 is the top row, so SVG coordinates apply directly.
cat > "$T/probe.swift" <<'EOF'
import AppKit
let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
// Raw 8-bit samples (the PNG is tagged sRGB). Not colorAt(...).usingColorSpace(.sRGB): AppKit labels the
// rep NSCalibratedRGBColorSpace and that conversion shifts the values by a Generic RGB -> sRGB transform.
func px(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
    var p = [Int](repeating: 0, count: 4); rep.getPixel(&p, atX: x, y: y)
    return (p[0], p[1], p[2], p[3])
}
func near(_ a: (Int, Int, Int, Int), _ r: Int, _ g: Int, _ b: Int, _ al: Int, tol: Int) -> Bool {
    abs(a.0 - r) <= tol && abs(a.1 - g) <= tol && abs(a.2 - b) <= tol && abs(a.3 - al) <= tol
}
var ok = true
if !near(px(2, 2), 0, 0, 0, 0, tol: 0) { print("corner (2,2) not transparent: \(px(2, 2))"); ok = false }
if !near(px(240, 630), 0xF2, 0xF4, 0xF7, 255, tol: 2) { print("band (240,630) wrong: \(px(240, 630))"); ok = false }
if !near(px(512, 498), 0x15, 0x80, 0x3D, 255, tol: 2) { print("sparkline (512,498) wrong: \(px(512, 498))"); ok = false }
if !near(px(512, 200), 0x36, 0x3F, 0x4C, 255, tol: 4) { print("background (512,200) wrong: \(px(512, 200))"); ok = false }
exit(ok ? 0 : 1)
EOF
swift "$T/probe.swift" "$T/AppIcon.iconset/icon_512x512@2x.png" || fail "pixel probe failed"
# Site tiles fill the canvas (D8): the 180 px touch icon is opaque band colour at its centre-left and transparent only at the very corner.
cat > "$T/tile.swift" <<'EOF'
import AppKit
let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
let corner = rep.colorAt(x: 0, y: 0)!.alphaComponent
let edge = rep.colorAt(x: 90, y: 2)!.usingColorSpace(.sRGB)!       // top edge centre: inside the squircle, background gradient
exit(corner == 0 && edge.alphaComponent == 1 && edge.blueComponent > edge.redComponent ? 0 : 1)
EOF
swift "$T/tile.swift" "$T/apple-touch-icon.png" || fail "touch icon does not fill the canvas"
echo "icon checks OK"
