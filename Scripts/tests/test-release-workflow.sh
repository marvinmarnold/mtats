#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Structural assertions on release.yml and site.yml (no YAML parser needed: plain line order).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
R="$ROOT/.github/workflows/release.yml"; S="$ROOT/.github/workflows/site.yml"
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# The publish job of release.yml, from its key to the end of the file (it is the last job).
awk '/^  publish:/{p=1} p' "$R" >"$T/publish.yml"
[[ -s "$T/publish.yml" ]] || fail "release.yml has no publish job"
line() { grep -n -m1 -F -- "$2" "$1" | cut -d: -f1; }

# A value appended to $GITHUB_ENV is invisible to the step that wrote it. The publish job decides the
# site bootstrap flag and builds in the same step, so it must export the variable there.
grep -q 'export MTATS_SITE_BOOTSTRAP=1' "$R" || fail "release.yml must export MTATS_SITE_BOOTSTRAP=1 in the step that builds the site"

# I-3: no third-party npm code runs while GCP credentials exist; no GITHUB_TOKEN left in .git/config.
for f in "$T/publish.yml" "$S"; do
  n=$(basename "$f")
  a=$(line "$f" 'google-github-actions/auth@'); b=$(line "$f" 'npm run build'); c=$(line "$f" 'npm ci')
  [[ -n "$a" && -n "$b" && -n "$c" ]] || fail "$n: expected auth, npm ci and npm run build"
  (( c < a && b < a )) || fail "$n: npm ci / npm run build must run before google-github-actions/auth"
  grep -A3 'actions/checkout@' "$f" | grep -q 'persist-credentials: false' || fail "$n: checkout must set persist-credentials: false"
done

# I-4 / M-3: published data is fetched only through scripts where 404 is the only "not published yet".
for f in "$R" "$S"; do
  grep -q 'curl ' "$f" && fail "$(basename "$f"): fetch published data via Scripts/fetch-published.sh or Scripts/site-data.sh, not curl"
done
grep -q 'Scripts/site-data.sh site out' "$T/publish.yml" || fail "release.yml publish job must build site data with Scripts/site-data.sh"
grep -q 'Scripts/site-data.sh site' "$S" || fail "site.yml must build site data with Scripts/site-data.sh"
grep -q 'Scripts/fetch-published.sh .*appcast.xml" "$W/appcast.xml"' "$R" || fail "release.yml appcast step must use fetch-published.sh"

# I-2: the GitHub Release step is re-runnable.
grep -q 'gh release view' "$T/publish.yml" || fail "GitHub Release step must check gh release view before creating"

# I-5: Hosting can be re-synced from the bucket without a commit.
grep -q '^  workflow_dispatch:' "$S" || fail "site.yml must offer workflow_dispatch"

# M-4: the signing keychain stays unlocked across a slow notarization.
grep -q 'set-keychain-settings -lut 21600' "$R" || fail "keychain lock timeout must be 21600 s"
u=$(grep -n 'security unlock-keychain' "$R" | tail -1 | cut -d: -f1)
d=$(line "$R" 'codesign --force --timestamp --sign "$MTATS_IDENTITY" "$DMG"')
n=$(line "$R" 'Scripts/notarize.sh .build/mtats.app')
[[ -n "$u" && -n "$d" && -n "$n" ]] && (( n < u && u < d )) || fail "re-unlock the keychain after app notarization, before DMG signing"
exit 0
