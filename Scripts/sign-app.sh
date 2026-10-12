#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: sign-app.sh <path/to/mtats.app> [identity]
# Inside-out signing (spec §Bundle layout & signing). No identity → ad-hoc ("-").
set -euo pipefail
APP="$1"; IDENTITY="${2:--}"
ENTITLEMENTS="$(cd "$(dirname "$0")" && pwd)/mtats.entitlements"
FLAGS=(--force --options runtime --sign "$IDENTITY")
[[ "$IDENTITY" != "-" ]] && FLAGS+=(--timestamp)
sign() { codesign "${FLAGS[@]}" "$@"; }

# 1. Shared plugin framework
sign --identifier com.mtats.MTatsPluginKit "$APP/Contents/Frameworks/libMTatsPluginKit.dylib"

# 2. Sparkle, deepest first (enumerated, not hardcoded; spec §Bundle layout)
SP="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SP" ]]; then
  if [[ -d "$SP/Versions/B/XPCServices" ]]; then
    for x in "$SP"/Versions/B/XPCServices/*.xpc; do
      if [[ "$x" == *Downloader.xpc ]]; then sign --preserve-metadata=entitlements "$x"; else sign "$x"; fi
    done
  fi
  [[ -e "$SP/Versions/B/Autoupdate" ]] && sign "$SP/Versions/B/Autoupdate"
  [[ -d "$SP/Versions/B/Updater.app" ]] && sign "$SP/Versions/B/Updater.app"
  sign "$SP"
fi

# 3. Built-in plugins, identifier from each bundle's own plist
for b in "$APP"/Contents/Resources/Plugins/*.bundle; do
  sign --identifier "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$b/Contents/Info.plist")" "$b"
done

# 4. The app
sign --identifier com.mtats.app --entitlements "$ENTITLEMENTS" "$APP"

codesign --verify --deep --strict "$APP"
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q get-task-allow; then
  echo "sign-app.sh: get-task-allow is present; notarization would reject this build" >&2; exit 1
fi
echo "Signed $APP ($([[ "$IDENTITY" == "-" ]] && echo ad-hoc || echo "$IDENTITY"))"
