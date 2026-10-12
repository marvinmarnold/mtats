#!/usr/bin/env bash
# Scripts/build-plugin.sh
# SPDX-License-Identifier: MIT
set -euo pipefail

# Usage: build-plugin.sh <WidgetName> <PrincipalClassName> [debug|release]
# Builds Plugins/<WidgetName>Widget/PluginMain.swift into .build/plugins/<WidgetName>Widget.bundle,
# linking against the Core library for <WidgetName> and the shared MTatsPluginKit.
# package-app.sh runs `swift build` for the configuration first.

NAME="$1"
PRINCIPAL_CLASS="$2"
CONFIG="${3:-debug}"
case "$CONFIG" in debug) OPT=(-Onone -g) ;; release) OPT=(-O) ;; *) echo "configuration must be debug or release" >&2; exit 2 ;; esac

OUT_DIR=".build/plugins/${NAME}Widget.bundle/Contents/MacOS"
rm -rf ".build/plugins/${NAME}Widget.bundle"
mkdir -p "$OUT_DIR"

RPATH=()
if [[ "$CONFIG" == debug ]]; then
  # Dev only: lets a bundle in .build/plugins find .build/debug when loaded standalone.
  # Inside mtats.app dyld matches the install name against the Host's copy first (ADR-0005).
  RPATH=(-Xlinker -rpath -Xlinker "@loader_path/../../../../debug")
fi

swiftc -emit-library -module-name "${NAME}Plugin" "${OPT[@]}" \
  -I ".build/$CONFIG" -L ".build/$CONFIG" -l"MTatsPluginKit" -l"${NAME}Core" \
  "Plugins/${NAME}Widget/PluginMain.swift" \
  -o "$OUT_DIR/${NAME}Widget" \
  ${RPATH[@]+"${RPATH[@]}"}

cp "Plugins/${NAME}Widget/Info.plist" ".build/plugins/${NAME}Widget.bundle/Contents/Info.plist"
echo "Built .build/plugins/${NAME}Widget.bundle ($CONFIG, principal class: $PRINCIPAL_CLASS)"
