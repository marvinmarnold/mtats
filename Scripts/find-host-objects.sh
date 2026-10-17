#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: find-host-objects.sh <Intermediates.noindex dir> <Debug|Release>
# Prints the single object directory of the mtats executable target for that configuration.
# The directory is mtats-p.build on Xcode 27 and mtats.build on Xcode 26.x (hosted runners);
# the *-testable.build directory is never matched.
set -euo pipefail
ROOT_DIR="$1"; CONFIG_DIR="$2"
DIRS=$(find "$ROOT_DIR" -type d \( -path "*/${CONFIG_DIR}/mtats-p.build/Objects-normal/arm64" -o -path "*/${CONFIG_DIR}/mtats.build/Objects-normal/arm64" \) 2>/dev/null || true)
if [[ -z "$DIRS" || $(wc -l <<<"$DIRS") -ne 1 ]]; then
  echo "find-host-objects.sh: expected exactly one ${CONFIG_DIR} object directory for the mtats target, found:" >&2
  echo "${DIRS:-<none>}" >&2
  exit 1
fi
echo "$DIRS"
