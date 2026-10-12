#!/usr/bin/env bash
# Scripts/package-app.sh
# SPDX-License-Identifier: MIT
# Usage: package-app.sh [-c debug|release]   (default debug; Scripts/dev.sh uses the default)
set -euo pipefail
CONFIG=debug
while getopts "c:" opt; do case "$opt" in c) CONFIG="$OPTARG" ;; *) exit 2 ;; esac; done
case "$CONFIG" in debug) CONFIG_DIR=Debug ;; release) CONFIG_DIR=Release ;; *) echo "configuration must be debug or release" >&2; exit 2 ;; esac

# The relink below reads the swiftbuild backend's intermediates layout; pin the backend.
swift build -c "$CONFIG" --build-system swiftbuild
for widget in CPU RAM GPU Network; do
  Scripts/build-plugin.sh "$widget" "${widget}PluginMain" "$CONFIG"
done

SPARKLE_FW=$(find .build/artifacts -type d -path '*Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' 2>/dev/null | head -1)
[[ -n "$SPARKLE_FW" ]] || { echo "package-app.sh: Sparkle.framework not found under .build/artifacts" >&2; exit 1; }

APP=".build/mtats.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/Plugins"

# ADR-0005 Task 10 addendum: SwiftPM statically embeds same-package targets into an executable,
# so relink the Host's objects ourselves against the dynamic MTatsPluginKit. Only this
# configuration's objects: a debug and a release build can coexist on one checkout, and
# matching both would duplicate every symbol or ship debug code in a release.
OBJ_DIRS=$(find .build/out/Intermediates.noindex -type d -path "*/${CONFIG_DIR}/mtats-p.build/Objects-normal/arm64" 2>/dev/null || true)
if [[ -z "$OBJ_DIRS" || $(wc -l <<<"$OBJ_DIRS") -ne 1 ]]; then
  echo "package-app.sh: expected exactly one ${CONFIG_DIR} object directory for the mtats target, found:" >&2
  echo "${OBJ_DIRS:-<none>}" >&2
  echo "See ADR-0005's Task 10 addendum and the spec's spike (b) outcome." >&2
  exit 1
fi
MTATS_OBJECTS=$(find "$OBJ_DIRS" -maxdepth 1 -name '*.o' ! -name '*-testable.o')
swiftc -o "$APP/Contents/MacOS/mtats" \
  $MTATS_OBJECTS \
  -L ".build/$CONFIG" -lMTatsPluginKit \
  -F "$(dirname "$SPARKLE_FW")" -framework Sparkle \
  -Xlinker -rpath -Xlinker "@executable_path/../Frameworks"

Scripts/render-info-plist.sh "$APP/Contents/Info.plist" "$CONFIG"

for widget in CPU RAM GPU Network; do
  cp -R ".build/plugins/${widget}Widget.bundle" "$APP/Contents/Resources/Plugins/"
done
cp ".build/$CONFIG/libMTatsPluginKit.dylib" "$APP/Contents/Frameworks/"
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
# mtats is not sandboxed; Sparkle's XPC services exist only for sandboxed hosts (spec spike (b) outcome).
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"

Scripts/sign-app.sh "$APP"
echo "Packaged $APP ($CONFIG)"
