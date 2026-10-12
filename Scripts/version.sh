#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: version.sh version|build
# version: MTATS_VERSION, else the tag at HEAD without "v", else 0.0.0-dev+<describe>.
# build:   MTATS_BUILD, else `git rev-list --count HEAD` (Sparkle orders by this; spec §Versioning).
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
  version)
    if [[ -n "${MTATS_VERSION:-}" ]]; then echo "$MTATS_VERSION"; exit 0; fi
    if tag=$(git describe --tags --exact-match --match 'v*' 2>/dev/null); then echo "${tag#v}"; exit 0; fi
    echo "0.0.0-dev+$(git describe --tags --match 'v*' --always --dirty)" ;;
  build)
    if [[ -n "${MTATS_BUILD:-}" ]]; then echo "$MTATS_BUILD"; exit 0; fi
    git rev-list --count HEAD ;;
  *) echo "usage: version.sh version|build" >&2; exit 2 ;;
esac
