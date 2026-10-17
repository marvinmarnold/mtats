#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Renders Resources/AppIcon.icns and the site's icon assets from Scripts/render-icon.swift.
# Resources/AppIcon.svg is the human-readable master of the same drawing (used as the SVG favicon).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=.build/icon
rm -rf "$OUT"
swift Scripts/render-icon.swift "$OUT"
iconutil -c icns "$OUT/AppIcon.iconset" -o Resources/AppIcon.icns
# favicon.svg: the master cropped to the squircle (D8). Only the root element's three attributes change.
sed -e 's#viewBox="0 0 1024 1024" width="1024" height="1024"#viewBox="100 100 824 824" width="824" height="824"#' \
  Resources/AppIcon.svg > site/public/favicon.svg
grep -q 'viewBox="100 100 824 824"' site/public/favicon.svg || { echo "make-icon.sh: favicon viewBox substitution failed" >&2; exit 1; }
cp "$OUT/favicon-32.png" "$OUT/apple-touch-icon.png" "$OUT/og.png" site/public/
echo "icon: Resources/AppIcon.icns and site/public/{favicon.svg,favicon-32.png,apple-touch-icon.png,og.png} written"
