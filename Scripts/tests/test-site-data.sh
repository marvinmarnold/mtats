#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# site-data.sh (I-4): only a 404 is "no release yet"; any other fetch failure fails the deploy
# instead of silently shipping bootstrap mode or the empty placeholder feed.
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
source Scripts/tests/lib-fake-curl.sh
install_fake_curl "$T/bin"
export FAKE_CURL_ROOT="$T/srv" FAKE_CURL_LOG="$T/curl.log"
M="$FAKE_CURL_ROOT/mtats-releases"; mkdir -p "$M/beta"
echo '{"version":"1.0.0"}' >"$M/latest.json"; echo stable-feed >"$M/appcast.xml"; echo beta-feed >"$M/beta/appcast.xml"
site() { rm -rf "$T/site"; mkdir -p "$T/site/src/data" "$T/site/public/beta"
  echo placeholder >"$T/site/public/appcast.xml"; echo placeholder >"$T/site/public/beta/appcast.xml"; }
S="$T/site"

# Everything published: copied in, not bootstrap.
site; OUT=$(Scripts/site-data.sh "$S") || fail "all-200 should pass"
[[ -z "$OUT" ]] || fail "must not report bootstrap when latest.json exists: $OUT"
[[ "$(cat "$S/src/data/latest.json")" == '{"version":"1.0.0"}' ]] || fail "src/data/latest.json"
[[ "$(cat "$S/public/latest.json")" == '{"version":"1.0.0"}' ]] || fail "public/latest.json"
[[ "$(cat "$S/public/appcast.xml")" == stable-feed ]] || fail "public/appcast.xml"
[[ "$(cat "$S/public/beta/appcast.xml")" == beta-feed ]] || fail "public/beta/appcast.xml"

# Nothing published yet (all 404): bootstrap, placeholders kept.
site; OUT=$(FAKE_CURL_ROOT="$T/empty" Scripts/site-data.sh "$S" 2>/dev/null) || fail "all-404 should pass"
[[ "$OUT" == bootstrap ]] || fail "404 on latest.json must report bootstrap, got: $OUT"
[[ ! -e "$S/src/data/latest.json" && ! -e "$S/public/latest.json" ]] || fail "bootstrap must not leave a latest.json"
[[ "$(cat "$S/public/appcast.xml")" == placeholder ]] || fail "404 appcast keeps the placeholder"

# Transient errors must fail the job (I-4), for each object.
for p in latest.json appcast.xml beta/appcast.xml; do
  for code in 503 000; do
    site; FAKE_CURL_CODES="mtats-releases/$p=$code" Scripts/site-data.sh "$S" >/dev/null 2>&1 \
      && fail "HTTP $code on $p must fail, not fall back"
  done
done

# Release job, stable: the artifact is the source for the stable data; only the beta feed is fetched.
A="$T/art"; mkdir -p "$A"; echo '{"version":"2.0.0"}' >"$A/latest.json"; echo new-stable-feed >"$A/appcast.xml"
site; : >"$FAKE_CURL_LOG"
OUT=$(FAKE_CURL_CODES="mtats-releases/latest.json=503 mtats-releases/appcast.xml=503" Scripts/site-data.sh "$S" "$A" stable) \
  || fail "stable release must not fetch the stable objects it is about to publish"
[[ -z "$OUT" ]] || fail "stable release is never bootstrap"
[[ "$(cat "$S/src/data/latest.json")" == '{"version":"2.0.0"}' ]] || fail "stable: src/data/latest.json from artifact"
[[ "$(cat "$S/public/latest.json")" == '{"version":"2.0.0"}' ]] || fail "stable: public/latest.json from artifact"
[[ "$(cat "$S/public/appcast.xml")" == new-stable-feed ]] || fail "stable: appcast from artifact"
[[ "$(cat "$S/public/beta/appcast.xml")" == beta-feed ]] || fail "stable: beta feed fetched"

# Release job, beta: beta feed from the artifact; stable page data and feed fetched (unchanged by an rc).
echo new-beta-feed >"$A/appcast.xml"
site; OUT=$(FAKE_CURL_CODES="mtats-releases/beta/appcast.xml=503" Scripts/site-data.sh "$S" "$A" beta) || fail "beta release"
[[ "$(cat "$S/public/beta/appcast.xml")" == new-beta-feed ]] || fail "beta: beta feed from artifact"
[[ "$(cat "$S/src/data/latest.json")" == '{"version":"1.0.0"}' ]] || fail "beta: stable latest.json fetched, not the rc's"
[[ "$(cat "$S/public/appcast.xml")" == stable-feed ]] || fail "beta: stable feed fetched"

Scripts/site-data.sh "$S" "$A" nightly >/dev/null 2>&1 && fail "unknown channel must fail"
exit 0
