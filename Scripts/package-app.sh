#!/usr/bin/env bash
# Scripts/package-app.sh
# SPDX-License-Identifier: MIT
set -euo pipefail

# The relink below reads this backend's intermediates layout; pin it rather than depend on
# whatever SwiftPM's default happens to be (`--build-system native` lays objects out elsewhere).
swift build -c debug --build-system swiftbuild
for widget in CPU RAM GPU Network; do
  Scripts/build-plugin.sh "$widget" "${widget}PluginMain"
done

APP=".build/mtats.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Plugins"

# SwiftPM statically embeds same-package target dependencies into an executable product,
# even when that dependency is also wrapped in a `type: .dynamic` library product (confirmed
# empirically: `nm .build/debug/mtats` shows a locally-DEFINED copy of MTatsPluginKit's
# protocol descriptors, not an external/undefined reference to libMTatsPluginKit.dylib).
# That defeats ADR-0005's single-shared-image requirement: the Host's own `as? PluginEntry.Type`
# cast would check against ITS OWN embedded copy of the protocol descriptor, which is a
# different instance than the one every dynamically-loaded plugin bundle links against via
# `-lMTatsPluginKit`, so the cast always fails and PluginLoader "successfully" loads zero
# widgets. Fix: relink the SwiftPM-compiled object files for Sources/mtats/*.swift ourselves,
# explicitly against the dynamic library, exactly like build-plugin.sh already does for
# plugins — this makes the Host reference the same single dylib image as every plugin.
MTATS_OBJECTS=$(find .build/out/Intermediates.noindex -path "*/mtats-p.build/Objects-normal/arm64/*.o" ! -name "*-testable.o" 2>/dev/null || true)
if [[ -z "$MTATS_OBJECTS" ]]; then
  echo "package-app.sh: found no compiled objects for the mtats target under .build/out/Intermediates.noindex." >&2
  echo "The swiftbuild backend's layout may have changed; see ADR-0005's Task 10 addendum." >&2
  exit 1
fi
swiftc -o "$APP/Contents/MacOS/mtats" \
  $MTATS_OBJECTS \
  -L .build/debug -lMTatsPluginKit \
  -Xlinker -rpath -Xlinker "@executable_path"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>mtats</string>
  <key>CFBundleIdentifier</key><string>com.mtats.app</string>
  <key>CFBundleName</key><string>mtats</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

for widget in CPU RAM GPU Network; do
  cp -R ".build/plugins/${widget}Widget.bundle" "$APP/Contents/Resources/Plugins/"
done

# Host must find MTatsPluginKit.dylib next to itself at runtime (rpath set at link time above).
cp .build/debug/libMTatsPluginKit.dylib "$APP/Contents/MacOS/"

codesign -s - --identifier com.mtats.app --deep -f "$APP"

echo "Packaged $APP"
