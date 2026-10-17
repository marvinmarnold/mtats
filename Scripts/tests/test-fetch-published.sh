#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# fetch-published.sh: only HTTP 404 means "not published yet"; every other failure is an error.
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
source Scripts/tests/lib-fake-curl.sh
install_fake_curl "$T/bin"
export FAKE_CURL_ROOT="$T/srv"; mkdir -p "$FAKE_CURL_ROOT/b"; echo hello >"$FAKE_CURL_ROOT/b/x.json"
U=https://storage.googleapis.com/b

Scripts/fetch-published.sh "$U/x.json" "$T/out.json" || fail "200 should exit 0"
[[ "$(cat "$T/out.json")" == hello ]] || fail "200 must write the body to dest"

echo keep >"$T/keep"
rc=0; Scripts/fetch-published.sh "$U/missing.json" "$T/keep" 2>/dev/null || rc=$?
[[ $rc == 3 ]] || fail "404 should exit 3, got $rc"
[[ "$(cat "$T/keep")" == keep ]] || fail "404 must leave dest untouched"

rc=0; FAKE_CURL_CODES="b/x.json=503" Scripts/fetch-published.sh "$U/x.json" "$T/keep" 2>/dev/null || rc=$?
[[ $rc != 0 && $rc != 3 ]] || fail "503 must be an error (not 0/3), got $rc"
[[ "$(cat "$T/keep")" == keep ]] || fail "an error must leave dest untouched"

rc=0; FAKE_CURL_CODES="b/x.json=000" Scripts/fetch-published.sh "$U/x.json" "$T/keep" 2>/dev/null || rc=$?
[[ $rc != 0 && $rc != 3 ]] || fail "a transport error must be an error (not 0/3), got $rc"

rc=0; FAKE_CURL_CODES="b/x.json=403" Scripts/fetch-published.sh "$U/x.json" "$T/keep" 2>/dev/null || rc=$?
[[ $rc != 0 && $rc != 3 ]] || fail "403 must be an error, got $rc"
exit 0
