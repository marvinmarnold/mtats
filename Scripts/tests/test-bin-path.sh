#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Hosted runners (Xcode 26.6) don't create the .build/<config> symlink that newer toolchains do;
# the packaging scripts must ask SwiftPM for the real product directory instead.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
if grep -nE '\.build/\$\{?CONFIG\}?[/"[:space:]]' Scripts/package-app.sh Scripts/build-plugin.sh; then
  echo "  scripts must use the --show-bin-path directory, not .build/\$CONFIG" >&2; exit 1
fi
grep -q -- '--show-bin-path' Scripts/package-app.sh || { echo "  package-app.sh must call --show-bin-path" >&2; exit 1; }
exit 0
