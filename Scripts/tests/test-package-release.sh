#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Builds debug then release on the same checkout (Review Focus: the release relink must not
# pick up debug objects), then checks the release bundle.
set -euo pipefail
cd "$(dirname "$0")/../.."
Scripts/package-app.sh -c debug >/dev/null
Scripts/check-bundle.sh .build/mtats.app
Scripts/package-app.sh -c release >/dev/null
Scripts/check-bundle.sh .build/mtats.app --release
Scripts/smoke-test.sh
