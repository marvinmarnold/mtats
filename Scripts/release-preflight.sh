#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: release-preflight.sh <version>   e.g. 0.1.0 or 0.1.0-rc.1
# Run locally before pushing a release tag (spec §Testing). Prints the tag command on success.
# PREFLIGHT_SKIP_BUILD=1, PREFLIGHT_FEED_URL (and appcast-guard.sh's APPCAST_FILE) exist for tests.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-}"
fail() { echo "preflight: $*" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || fail "version must look like 1.2.3 or 1.2.3-rc.1"
[[ -s "Releases/${VERSION}.md" ]] || fail "Releases/${VERSION}.md is missing or empty"
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && fail "tag v$VERSION already exists"
FEED_URL="${PREFLIGHT_FEED_URL:-https://mtats.app/appcast.xml}"
FEED=$(curl -fsS --max-time 15 "$FEED_URL") || fail "$FEED_URL is not reachable — finish Phase 5 before tagging"
grep -q '<rss' <<<"$FEED" || fail "$FEED_URL does not look like an appcast"
# The workflow's update guard, run here too: once the tag is pushed its name is burned (immutable).
CHANNEL=stable; [[ "$VERSION" == *-rc.* ]] && CHANNEL=beta
Scripts/appcast-guard.sh "$CHANNEL" "$(git rev-list --count HEAD)" || fail "update guard failed for $CHANNEL"
if [[ "${PREFLIGHT_SKIP_BUILD:-0}" != 1 ]]; then
  [[ "$(git branch --show-current)" == main ]] || fail "not on main"
  git fetch -q origin main
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not up to date with origin/main"
  [[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean"
  Scripts/swift-test.sh >/dev/null || fail "swift test failed"
  Scripts/tests/run.sh >/dev/null || fail "shell tests failed"
  Scripts/package-app.sh -c release >/dev/null && Scripts/smoke-test.sh || fail "release package or smoke test failed"
fi
echo "preflight OK. Tag with:"
echo "  git tag -a v$VERSION -m \"mtats $VERSION\" && git push origin v$VERSION"
