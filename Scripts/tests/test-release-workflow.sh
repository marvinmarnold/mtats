#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# A value appended to $GITHUB_ENV is invisible to the step that wrote it. The publish job sets the
# site bootstrap flag and builds in the same step, so it must also export the variable there.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
grep -q 'export MTATS_SITE_BOOTSTRAP=1' "$ROOT/.github/workflows/release.yml" \
  || { echo "  release.yml must export MTATS_SITE_BOOTSTRAP=1 in the step that builds the site" >&2; exit 1; }
exit 0
