#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: fetch-published.sh <url> <dest>
# Fetches a published object. Exit 0: fetched into <dest>. Exit 3: HTTP 404 (not published yet;
# <dest> untouched). Any other status or transport error: exit 1 (<dest> untouched). Only a 404
# may be read as "no release yet" — a transient error must never look like an empty feed.
set -euo pipefail
URL="$1"; DEST="$2"
TMP=$(mktemp "${DEST}.XXXXXX"); trap 'rm -f "$TMP"' EXIT
CODE=$(curl -sS --retry 3 --retry-delay 2 --max-time 60 -o "$TMP" -w '%{http_code}' "$URL") || {
  echo "fetch-published: $URL: transport error (HTTP ${CODE:-000})" >&2; exit 1; }
case "$CODE" in
  200) chmod 644 "$TMP"; mv "$TMP" "$DEST"; trap - EXIT ;;
  404) echo "fetch-published: $URL: 404 (not published yet)" >&2; exit 3 ;;
  *) echo "fetch-published: $URL: HTTP $CODE" >&2; exit 1 ;;
esac
