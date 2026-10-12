#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d); trap 'hdiutil detach -quiet "$T/mnt" 2>/dev/null || true; rm -rf "$T"' EXIT
[[ -d .build/mtats.app ]] || Scripts/package-app.sh >/dev/null
Scripts/make-dmg.sh .build/mtats.app "$T/x.dmg"
hdiutil attach -quiet -nobrowse -mountpoint "$T/mnt" "$T/x.dmg"
[[ -d "$T/mnt/mtats.app" ]] || { echo "  app missing from DMG" >&2; exit 1; }
[[ "$(readlink "$T/mnt/Applications")" == "/Applications" ]] || { echo "  Applications symlink missing" >&2; exit 1; }
