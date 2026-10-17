#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: site-data.sh <site-dir> [<artifact-dir> <stable|beta>]
# Fills the website's published data before `npm run build`: src/data/latest.json and
# public/latest.json (stable), public/appcast.xml, public/beta/appcast.xml. Anonymous reads from the
# public bucket; no credentials needed (run it before any auth step). With an artifact dir (release
# job), the channel being released comes from the artifact instead of the bucket.
# Prints "bootstrap" when no stable release exists yet (latest.json is a 404). Only a 404 counts as
# "not published yet"; any other fetch failure exits non-zero so a transient error never deploys an
# empty feed or removes the download button (committed placeholders are kept only on a 404).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Scripts/release-env.sh"
SITE="$1"; ART="${2:-}"; CHANNEL="${3:-}"
if [[ -n "$ART" ]]; then
  case "$CHANNEL" in stable|beta) ;; *) echo "channel must be stable or beta" >&2; exit 2 ;; esac
fi
B="https://storage.googleapis.com/$MTATS_BUCKET"
mkdir -p "$SITE/src/data" "$SITE/public/beta"

fetch() { # <object> <dest>: 0 fetched, 3 not published (dest untouched), else exit
  local rc=0; "$ROOT/Scripts/fetch-published.sh" "$B/$1" "$2" || rc=$?
  case "$rc" in 0|3) return "$rc" ;; *) echo "site-data: fetching $1 failed; not deploying" >&2; exit 1 ;; esac
}

if [[ "$CHANNEL" == stable ]]; then
  cp "$ART/latest.json" "$SITE/src/data/latest.json"
  cp "$ART/appcast.xml" "$SITE/public/appcast.xml"
else
  rc=0; fetch latest.json "$SITE/src/data/latest.json" || rc=$?
  if [[ $rc == 3 ]]; then rm -f "$SITE/src/data/latest.json" "$SITE/public/latest.json"; echo bootstrap; fi
  fetch appcast.xml "$SITE/public/appcast.xml" || true # 3: keep the committed placeholder
fi
[[ -f "$SITE/src/data/latest.json" ]] && cp "$SITE/src/data/latest.json" "$SITE/public/latest.json"
if [[ "$CHANNEL" == beta ]]; then
  cp "$ART/appcast.xml" "$SITE/public/beta/appcast.xml"
else
  fetch beta/appcast.xml "$SITE/public/beta/appcast.xml" || true # 3: keep the committed placeholder
fi
exit 0
