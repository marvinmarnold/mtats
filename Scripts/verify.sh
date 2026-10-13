#!/usr/bin/env bash
# Scripts/verify.sh
# SPDX-License-Identifier: MIT
set -euo pipefail

echo "== swift build =="
swift build

echo "== swift test =="
swift test

echo "== package app =="
Scripts/package-app.sh

echo "== smoke test =="
Scripts/smoke-test.sh

echo "== GLM review =="
DIFF=$(git diff main --stat; echo; git diff main)
SPEC=$(cat docs/superpowers/specs/2026-10-11-mtats-v1-design.md)
PROMPT="You are reviewing a diff against mtats' v1 spec (attached below). Report ONLY unresolved high-severity findings (correctness bugs, spec violations, crashes) as a numbered list, or the single line NO_FINDINGS if there are none. Be specific: file, line, what's wrong, why it matters against the spec.

=== SPEC ===
$SPEC

=== DIFF ===
$DIFF"

RESULT=$(dsh --profile headless "$PROMPT")
echo "$RESULT"

if echo "$RESULT" | grep -q "NO_FINDINGS"; then
  echo "VERIFICATION PASSED: build clean, tests pass, smoke test passed, GLM found no high-severity issues."
  exit 0
else
  echo "VERIFICATION INCOMPLETE: GLM findings above need fixing, then re-run Scripts/verify.sh."
  exit 1
fi
