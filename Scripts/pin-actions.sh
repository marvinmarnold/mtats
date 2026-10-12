#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Pins every `uses: owner/repo@vN` in .github/workflows to a full commit SHA (kept as a comment).
# Re-run after adding or editing a workflow. Needs `gh` authenticated (read-only API calls).
set -euo pipefail
cd "$(dirname "$0")/.."
for ref in $(grep -ho 'uses: [^ ]*@v[0-9][^ ]*' .github/workflows/*.yml | awk '{print $2}' | sort -u); do
  repo=${ref%@*}; tag=${ref#*@}
  sha=$(gh api "repos/$repo/commits/$tag" --jq .sha)
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "pin-actions: could not resolve $ref" >&2; exit 1; }
  sed -i '' "s#uses: $repo@$tag\$#uses: $repo@$sha \# $tag#" .github/workflows/*.yml
done
echo "pinned:"; grep -h 'uses:' .github/workflows/*.yml | sort -u
