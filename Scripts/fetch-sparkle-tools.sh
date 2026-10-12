#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Fetches Sparkle's CLI tools (generate_keys, sign_update, generate_appcast) at the version
# pinned in Package.swift, verified against a recorded SHA-256.
set -euo pipefail
cd "$(dirname "$0")/.."
SPARKLE_VERSION="2.10.0"
SPARKLE_TOOLS_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
DEST=.build/sparkle-tools
[[ -x "$DEST/bin/generate_appcast" ]] && exit 0
mkdir -p "$DEST"
curl -fsSL -o "$DEST/sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
echo "$SPARKLE_TOOLS_SHA256  $DEST/sparkle.tar.xz" | shasum -a 256 -c -
tar -xJf "$DEST/sparkle.tar.xz" -C "$DEST" ./bin
rm "$DEST/sparkle.tar.xz"
