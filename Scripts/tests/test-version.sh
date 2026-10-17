#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q && git config user.email t@t && git config user.name t
mkdir Scripts && cp "$ROOT/Scripts/version.sh" Scripts/
for i in 1 2 3; do git commit -q --allow-empty -m "c$i"; done

[[ "$(Scripts/version.sh build)" == "3" ]] || fail "build should be commit count 3"
[[ "$(MTATS_BUILD=99 Scripts/version.sh build)" == "99" ]] || fail "MTATS_BUILD override"
[[ "$(Scripts/version.sh version)" == 0.0.0-dev+* ]] || fail "untagged repo should give 0.0.0-dev+<hash>, got $(Scripts/version.sh version)"
git tag -a v1.2.3 -m v1.2.3
[[ "$(Scripts/version.sh version)" == "1.2.3" ]] || fail "tagged HEAD should give 1.2.3, got $(Scripts/version.sh version)"
[[ "$(MTATS_VERSION=4.5.6 Scripts/version.sh version)" == "4.5.6" ]] || fail "MTATS_VERSION override"
Scripts/version.sh bogus 2>/dev/null && fail "bad argument should exit non-zero"
exit 0
