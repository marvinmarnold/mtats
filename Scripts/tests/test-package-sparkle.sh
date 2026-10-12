#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
Scripts/package-app.sh -c release >/dev/null
Scripts/check-bundle.sh .build/mtats.app --release --signed --sparkle
[[ -d .build/mtats.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices ]] \
  && { echo "  XPCServices should be stripped (non-sandboxed host; spike (b))" >&2; exit 1; }
Scripts/fetch-sparkle-tools.sh >/dev/null
for t in generate_keys sign_update generate_appcast; do [[ -x ".build/sparkle-tools/bin/$t" ]] || { echo "  missing $t" >&2; exit 1; }; done
Scripts/smoke-test.sh
