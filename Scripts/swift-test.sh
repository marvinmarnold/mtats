#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs `swift test` with the Sparkle framework on the dynamic-loader path. Xcode 26.x (hosted
# runners) does not embed binary frameworks in the test bundle, so dlopen fails without this.
# Usage: swift-test.sh [swift test args...]
set -euo pipefail
cd "$(dirname "$0")/.."
FW=$(find .build/artifacts -type d -path '*Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' 2>/dev/null | head -1 || true)
if [[ -z "$FW" ]]; then
  swift build --build-system swiftbuild >/dev/null  # resolves the Sparkle binary artifact
  FW=$(find .build/artifacts -type d -path '*Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' | head -1)
fi
DYLD_FRAMEWORK_PATH="$PWD/$(dirname "$FW")${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}" exec swift test --build-system swiftbuild "$@"
