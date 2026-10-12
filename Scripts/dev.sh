#!/usr/bin/env bash
# Scripts/dev.sh
# SPDX-License-Identifier: MIT
#
# One-command dev loop: quit the running mtats, rebuild + repackage, relaunch.
#   Scripts/dev.sh           rebuild and relaunch once
#   Scripts/dev.sh --watch   do that again every time a source file changes
#   Scripts/dev.sh --test    run the unit tests first (a failure stops the relaunch)
set -euo pipefail
cd "$(dirname "$0")/.."

WATCH=0
RUN_TESTS=0
for arg in "$@"; do
  case "$arg" in
    --watch) WATCH=1 ;;
    --test) RUN_TESTS=1 ;;
    *) echo "usage: Scripts/dev.sh [--watch] [--test]" >&2; exit 2 ;;
  esac
done

WATCHED=(Sources Plugins Scripts Package.swift)

cycle() {
  local started=$SECONDS
  if (( RUN_TESTS )); then
    swift test --build-system swiftbuild 2>&1 | grep -E "error|failed|Executed [0-9]+ tests, with [1-9]" || true
  fi
  # Quit the old copy before overwriting the bundle it is running from.
  pkill -x mtats 2>/dev/null || true
  for _ in {1..20}; do pgrep -x mtats >/dev/null 2>&1 || break; sleep 0.1; done

  if Scripts/package-app.sh >/tmp/mtats-dev-build.log 2>&1; then
    open .build/mtats.app
    echo "[dev] relaunched in $((SECONDS - started))s"
  else
    echo "[dev] BUILD FAILED — old app left closed. Errors:" >&2
    grep -E "error" /tmp/mtats-dev-build.log | grep -v "SwiftDriver\|Build failed" | cut -c1-220 | head -8 >&2 || tail -15 /tmp/mtats-dev-build.log >&2
  fi
}

cycle
(( WATCH )) || exit 0

echo "[dev] watching ${WATCHED[*]} — Ctrl-C to stop"
if command -v fswatch >/dev/null 2>&1; then
  # --latency batches a burst of saves (editors write several files) into one rebuild.
  fswatch -o --latency 0.5 -e '\.build' "${WATCHED[@]}" | while read -r _; do cycle; done
else
  # No fswatch: poll file modification times. Slightly slower to notice, nothing to install.
  stamp() { find "${WATCHED[@]}" -type f \( -name '*.swift' -o -name '*.plist' -o -name '*.sh' \) -exec stat -f '%m' {} + 2>/dev/null | sort -n | tail -1; }
  last=$(stamp)
  while sleep 1; do
    now=$(stamp)
    if [[ "$now" != "$last" ]]; then last=$now; cycle; last=$(stamp); fi
  done
fi
