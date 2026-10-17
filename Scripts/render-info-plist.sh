#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: render-info-plist.sh <out-plist> <debug|release>
set -euo pipefail
OUT="$1"; CONFIG="${2:-}"
DIR="$(cd "$(dirname "$0")" && pwd)"
case "$CONFIG" in debug|release) ;; *) echo "configuration must be debug or release" >&2; exit 2 ;; esac
VERSION="$("$DIR/version.sh" version)"
BUILD="$("$DIR/version.sh" build)"
sed -e "s/__VERSION__/${VERSION//\//\\/}/" -e "s/__BUILD__/$BUILD/" -e "s/__COPYRIGHT_YEAR__/$(date +%Y)/" \
  "$DIR/Host-Info.plist.template" > "$OUT"
if [[ "$CONFIG" == debug ]]; then
  # Dev builds must never poll the production feed (spec §Versioning).
  /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$OUT"
fi
plutil -lint -s "$OUT"
