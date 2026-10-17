#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: check-bundle.sh <path/to/mtats.app> [--release] [--sparkle] [--signed]
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"; shift
RELEASE=0; SPARKLE=0; SIGNED=0
for a in "$@"; do case "$a" in --release) RELEASE=1;; --sparkle) SPARKLE=1;; --signed) SIGNED=1;; *) echo "unknown flag $a" >&2; exit 2;; esac; done
HOST="$APP/Contents/MacOS/mtats"
fail() { echo "check-bundle: $*" >&2; exit 1; }

[[ -f "$APP/Contents/Frameworks/libMTatsPluginKit.dylib" ]] || fail "libMTatsPluginKit.dylib not in Contents/Frameworks"
ls "$APP/Contents/MacOS" | grep -q '\.dylib$' && fail "a dylib is still in Contents/MacOS"
otool -L "$HOST" | grep -q "@rpath/libMTatsPluginKit.dylib" || fail "Host does not reference @rpath/libMTatsPluginKit.dylib"
RPATHS=$(otool -l "$HOST" | awk '/LC_RPATH/{getline; getline; print $2}')
[[ "$RPATHS" == "@executable_path/../Frameworks" ]] || fail "Host rpaths must be exactly @executable_path/../Frameworks, got: $RPATHS"
# Captured first: `grep -q` closing the pipe early would SIGPIPE nm and fail under pipefail.
SYMBOLS=$(nm "$HOST" | xcrun swift-demangle)
grep -Eq '^[[:space:]]+U protocol descriptor for MTatsPluginKit.PluginEntry$' <<<"$SYMBOLS" \
  || fail "PluginEntry descriptor is not an undefined reference (ADR-0005 static-embedding regression)"
for b in "$APP"/Contents/Resources/Plugins/*.bundle; do
  bin="$b/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$b/Contents/Info.plist")"
  if (( RELEASE )); then otool -l "$bin" | grep -A2 LC_RPATH | grep -q '/debug' && fail "$(basename "$b") ships a dev rpath"; fi
done
PB=/usr/libexec/PlistBuddy
[[ "$($PB -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$(Scripts/version.sh version)" ]] || fail "CFBundleShortVersionString mismatch"
[[ "$($PB -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$(Scripts/version.sh build)" ]] || fail "CFBundleVersion mismatch"
if (( RELEASE )); then
  [[ "$($PB -c 'Print :SUFeedURL' "$APP/Contents/Info.plist")" == "https://mtats.app/appcast.xml" ]] || fail "release SUFeedURL"
else
  $PB -c 'Print :SUFeedURL' "$APP/Contents/Info.plist" >/dev/null 2>&1 && fail "debug bundle must not contain SUFeedURL"
fi
if (( SPARKLE )); then
  [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]] || fail "Sparkle.framework missing"
  otool -L "$HOST" | grep -q "@rpath/Sparkle.framework/Versions/B/Sparkle" || fail "Host does not link Sparkle"
fi
if (( SIGNED )); then
  codesign --verify --deep --strict "$APP" || fail "codesign --verify --deep --strict failed"
  ENT=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)
  [[ "$(grep -o '<key>[^<]*</key>' <<<"$ENT")" == "<key>com.apple.security.cs.disable-library-validation</key>" ]] \
    || fail "entitlements must be exactly disable-library-validation, got: $(grep -o '<key>[^<]*</key>' <<<"$ENT" | tr '\n' ' ')"
  SIGINFO=$(codesign -d --verbose=4 "$APP" 2>&1)
  grep -q 'flags=.*runtime' <<<"$SIGINFO" || fail "hardened runtime flag missing"
fi
echo "check-bundle: OK ($APP)"
