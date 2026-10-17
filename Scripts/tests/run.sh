#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
# CI exports release variables into the job environment; tests must control them.
unset MTATS_VERSION MTATS_BUILD MTATS_CHANNEL MTATS_IDENTITY
status=0
for t in Scripts/tests/test-*.sh; do
  if bash "$t"; then echo "PASS $t"; else echo "FAIL $t"; status=1; fi
done
exit $status
