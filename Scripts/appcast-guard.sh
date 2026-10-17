#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: appcast-guard.sh <stable|beta> <build>
# Fails unless <build> is greater than every sparkle:version already in the channel's appcast
# (Sparkle orders by CFBundleVersion; spec §Versioning). APPCAST_FILE overrides the fetch.
set -euo pipefail
CHANNEL="$1"; BUILD="$2"
case "$CHANNEL" in stable) PREFIX="" ;; beta) PREFIX="beta/" ;; *) echo "channel must be stable or beta" >&2; exit 2 ;; esac
FEED="${APPCAST_FILE:-}"
if [[ -z "$FEED" ]]; then
  FEED=$(mktemp); trap 'rm -f "$FEED"' EXIT
  CODE=$(curl -s -o "$FEED" -w '%{http_code}' "https://storage.googleapis.com/mtats-releases/${PREFIX}appcast.xml")
  case "$CODE" in 200) ;; 404) : >"$FEED" ;; *) echo "appcast-guard: fetching appcast returned HTTP $CODE" >&2; exit 1 ;; esac
fi
MAX=$(/usr/bin/python3 - "$FEED" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
nums = [int(n) for n in re.findall(r"<sparkle:version>\s*(\d+)\s*</sparkle:version>", text)]
nums += [int(n) for n in re.findall(r'sparkle:version="(\d+)"', text)]
print(max(nums) if nums else 0)
PY
)
if (( BUILD <= MAX )); then
  echo "appcast-guard: build $BUILD is not greater than published build $MAX on $CHANNEL" >&2; exit 1
fi
echo "appcast-guard: build $BUILD > $MAX on $CHANNEL"
