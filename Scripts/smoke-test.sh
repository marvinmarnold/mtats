#!/usr/bin/env bash
# Scripts/smoke-test.sh
# SPDX-License-Identifier: MIT
set -euo pipefail

APP=".build/mtats.app"
LOG=$(mktemp)

# Launch the real executable directly rather than via `open` — `open -W`'s own PID is not
# the launched app's PID, so measuring it would report `open`'s (near-zero) CPU/RSS instead
# of mtats'. exit-after is set comfortably longer than the sleep below so the process is
# still running (and measurable) at the moment we sample it.
"$APP/Contents/MacOS/mtats" --smoke-test-exit-after=8 >"$LOG" 2>&1 &
PID=$!
sleep 3

if ! kill -0 "$PID" 2>/dev/null; then
  echo "FAIL: mtats exited early"; cat "$LOG"; exit 1
fi

CPU_PCT=$(ps -p "$PID" -o %cpu= | tr -d ' ')
RSS_KB=$(ps -p "$PID" -o rss= | tr -d ' ')
RSS_MB=$((RSS_KB / 1024))

kill "$PID" 2>/dev/null || true

echo "CPU: ${CPU_PCT}% RSS: ${RSS_MB}MB"

if (( $(echo "$CPU_PCT > 5.0" | bc -l) )); then
  echo "FAIL: CPU usage ${CPU_PCT}% exceeds the budget (spec allows ~1%, failing above 5% to allow for the ps sampling window)"
  exit 1
fi
if (( RSS_MB > 80 )); then
  echo "FAIL: RSS ${RSS_MB}MB exceeds the budget (spec targets ~40-50MB, failing above 80MB)"
  exit 1
fi

echo "PASS"
