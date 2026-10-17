#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The swiftbuild backend names the executable target's object directory differently across
# toolchains (Xcode 27: mtats-p.build; Xcode 26.6 on hosted runners: mtats.build).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { mkdir -p "$T/$1/Objects-normal/arm64"; }

mk "p.noindex/mtats.build/Debug/mtats-p.build"; mk "p.noindex/mtats.build/Debug/CPUCore.build"
got=$("$ROOT/Scripts/find-host-objects.sh" "$T/p.noindex" Debug) || fail "xcode27 layout not found"
[[ "$got" == */Debug/mtats-p.build/Objects-normal/arm64 ]] || fail "xcode27 layout: $got"

rm -rf "$T/p.noindex"
mk "r.noindex/mtats.build/Debug/mtats.build"; mk "r.noindex/mtats.build/Debug/mtats-10EF2EAD86EE-testable.build"
got=$("$ROOT/Scripts/find-host-objects.sh" "$T/r.noindex" Debug) || fail "hosted-runner layout not found"
[[ "$got" == */Debug/mtats.build/Objects-normal/arm64 ]] || fail "runner layout: $got"
"$ROOT/Scripts/find-host-objects.sh" "$T/r.noindex" Release 2>/dev/null && fail "Release must not match Debug objects"

mk "r.noindex/mtats.build/Debug/mtats-p.build"
"$ROOT/Scripts/find-host-objects.sh" "$T/r.noindex" Debug 2>/dev/null && fail "ambiguous layout must fail"
exit 0
