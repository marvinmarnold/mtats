#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
Scripts/package-app.sh -c release >/dev/null
Scripts/check-bundle.sh .build/mtats.app --release --signed
Scripts/smoke-test.sh
