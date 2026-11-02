#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Re-renders the icon into a temp dir and checks the iconset members, the committed .icns, and key pixels of the Pulse M icon and the site assets.
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
# Pixel probe. Usage: probe.swift <png> <check>...; a check is "x,y,RRGGBB,alpha,tol" in that PNG's pixel
# coordinates (NSBitmapImageRep.getPixel addresses rows from the top, and render-icon.swift flips the context so
# SVG y=0 is the top row, so on a 1024 render SVG coordinates apply directly), or "red" (some opaque pixel is
# clearly the Pulse M red, i.e. the trace survives downscaling).
cat > "$T/probe.swift" <<'EOF'
import AppKit
let args = CommandLine.arguments
let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: args[1])))!
// Raw 8-bit samples (the PNG is tagged sRGB). Not colorAt(...).usingColorSpace(.sRGB): AppKit labels the
// rep NSCalibratedRGBColorSpace and that conversion shifts the values by a Generic RGB -> sRGB transform.
func px(_ x: Int, _ y: Int) -> [Int] {
    var p = [Int](repeating: 0, count: 4); rep.getPixel(&p, atX: x, y: y); return p
}
var ok = true
for check in args.dropFirst(2) {
    if check == "red" {
        var found = false
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
            let p = px(x, y); if p[3] == 255 && p[0] >= 160 && p[1] <= 90 && p[2] <= 90 { found = true }
        } }
        if !found { print("\(args[1]): no red pixel"); ok = false }
        continue
    }
    let f = check.split(separator: ",").map(String.init)
    let x = Int(f[0])!, y = Int(f[1])!, hex = Int(f[2], radix: 16)!, al = Int(f[3])!, tol = Int(f[4])!
    let want = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF, al], got = px(x, y)
    let channels = al == 0 ? [3] : [0, 1, 2, 3]       // a fully transparent pixel has no meaningful colour
    if channels.contains(where: { abs(got[$0] - want[$0]) > tol }) {
        print("\(args[1]) (\(x),\(y)): want \(want) got \(got)"); ok = false
    }
}
exit(ok ? 0 : 1)
EOF
probe() { swift "$T/probe.swift" "$@" || fail "pixel probe failed: $1"; }
# Pulse M on the 1024 canvas: bone squircle; ECG trace stroked #15151A (width 176) under #D7322D (width 100),
# clipped to the squircle. (2,2) and (98,612) are outside the squircle; (104,612) and (920,612) are the clipped
# tails at the left and right edges. (160,612) is on the left tail's centre line; (160,542) and (160,682) are 70 px
# off it: inside the 88 px outline, outside the 50 px red core. (512,556) is the middle valley vertex; (423,454) is
# the midpoint of segment (334,352)-(512,556). (512,200) and (512,820) are bone above and below the trace (y 264-700).
ICON_CHECKS=(2,2,000000,0,0 98,612,000000,0,0 104,612,D7322D,255,3 920,612,D7322D,255,3
  160,612,D7322D,255,2 160,542,15151A,255,2 160,682,15151A,255,2 512,556,D7322D,255,2 423,454,D7322D,255,2
  512,200,F3EBD9,255,2 512,820,F3EBD9,255,2)
probe "$T/AppIcon.iconset/icon_512x512@2x.png" "${ICON_CHECKS[@]}"
for m in icon_16x16 icon_16x16@2x icon_32x32; do probe "$T/AppIcon.iconset/$m.png" red; done
# The committed .icns is the current drawing, not a stale render.
probe "$T/roundtrip.iconset/icon_512x512@2x.png" "${ICON_CHECKS[@]}"
probe "$T/roundtrip.iconset/icon_16x16.png" red
# Site tiles fill the canvas (D8): in a 180 px tile pixel p is SVG 100 + p*824/180, so (90,2) -> (512,109) bone and
# (30,112) -> (237,613) on the left tail; the very corner is transparent. Checked on a fresh render and the committed file.
TILE_CHECKS=(0,0,000000,0,0 90,2,F3EBD9,255,2 30,112,D7322D,255,3)
probe "$T/apple-touch-icon.png" "${TILE_CHECKS[@]}"
probe site/public/apple-touch-icon.png "${TILE_CHECKS[@]}"
probe site/public/favicon-32.png red 0,0,000000,0,0
# OG card: dark ground, 360 px tile at (120,135); SVG (512,556) lands at (300,334) and SVG (512,134) at (300,150).
probe site/public/og.png 20,20,0E1218,255,2 300,334,D7322D,255,3 300,150,F3EBD9,255,2
# favicon.svg is the master with only the root element changed (D8); site budgets from spec 2026-10-17 §8.
grep -q '#D7322D' Resources/AppIcon.svg || fail "Resources/AppIcon.svg is not Pulse M"
diff <(tail -n +2 Resources/AppIcon.svg) <(tail -n +2 site/public/favicon.svg) >/dev/null || fail "site/public/favicon.svg out of sync with Resources/AppIcon.svg"
grep -q 'viewBox="100 100 824 824"' site/public/favicon.svg || fail "favicon.svg not cropped to the squircle"
for b in og.png:120000 apple-touch-icon.png:20000 favicon-32.png:3000 favicon.svg:2000; do
  [[ "$(stat -f%z "site/public/${b%%:*}")" -le "${b##*:}" ]] || fail "site/public/${b%%:*} over its ${b##*:} byte budget"
done
echo "icon checks OK"
