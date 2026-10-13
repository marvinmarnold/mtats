#!/usr/bin/env bash
# Scripts/build-plugin.sh
# SPDX-License-Identifier: MIT
set -euo pipefail

# Usage: build-plugin.sh <WidgetName> <PrincipalClassName>
# Builds Plugins/<WidgetName>/PluginMain.swift into .build/plugins/<WidgetName>Widget.bundle,
# linking against the Core library for <WidgetName> and the shared MTatsPluginKit — exactly
# the mechanism validated in spikes/plugin-loading-identity/.

NAME="$1"              # e.g. CPU
PRINCIPAL_CLASS="$2"   # e.g. CPUPluginMain

# Same backend as package-app.sh, so .build/debug points at the same products.
swift build --build-system swiftbuild # ensure MTatsPluginKit + <NAME>Core are up to date

OUT_DIR=".build/plugins/${NAME}Widget.bundle/Contents/MacOS"
mkdir -p "$OUT_DIR"

swiftc -emit-library -module-name "${NAME}Plugin" \
  -I .build/debug -L .build/debug -l"MTatsPluginKit" -l"${NAME}Core" \
  "Plugins/${NAME}Widget/PluginMain.swift" \
  -o "$OUT_DIR/${NAME}Widget" \
  -Xlinker -rpath -Xlinker "@loader_path/../../../../debug"
  # $OUT_DIR is .build/plugins/<Name>Widget.bundle/Contents/MacOS — 4 levels up from
  # there lands back at .build/, so appending "debug" (not ".build/debug") reaches
  # .build/debug. Verify with: cd "$OUT_DIR" && cd ../../../../debug && pwd
  # Once copied into mtats.app this rpath points nowhere, and that's fine: dyld matches the
  # @rpath/libMTatsPluginKit.dylib install name against the copy the Host already loaded
  # before it consults rpaths at all (ADR-0005).

cp "Plugins/${NAME}Widget/Info.plist" ".build/plugins/${NAME}Widget.bundle/Contents/Info.plist"
codesign -s - --identifier "com.mtats.plugin.${NAME}" -f ".build/plugins/${NAME}Widget.bundle"

echo "Built .build/plugins/${NAME}Widget.bundle (principal class: $PRINCIPAL_CLASS)"
