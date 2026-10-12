#!/usr/bin/env bash
# Scripts/package-app.sh
# SPDX-License-Identifier: MIT
set -euo pipefail

swift build -c debug
for widget in CPU RAM GPU Network; do
  Scripts/build-plugin.sh "$widget" "${widget}PluginMain"
done

APP=".build/mtats.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Plugins"

cp .build/debug/mtats "$APP/Contents/MacOS/mtats"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>mtats</string>
  <key>CFBundleIdentifier</key><string>com.mtats.app</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

for widget in CPU RAM GPU Network; do
  cp -R ".build/plugins/${widget}Widget.bundle" "$APP/Contents/Resources/Plugins/"
done

# Host must find MTatsPluginKit.dylib next to itself at runtime.
cp .build/debug/libMTatsPluginKit.dylib "$APP/Contents/MacOS/"
install_name_tool -add_rpath "@executable_path" "$APP/Contents/MacOS/mtats" 2>/dev/null || true

codesign -s - --identifier com.mtats.app --deep -f "$APP"

echo "Packaged $APP"
