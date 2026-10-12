#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '# mtats 0.1.0\n\nFirst release.\n\n- CPU <and> RAM\n- GPU & Network\n' >"$T/n.md"
/usr/bin/python3 Scripts/notes-to-html.py "$T/n.md" "$T/n.html"
grep -q '<h2>mtats 0.1.0</h2>' "$T/n.html"
grep -q '<p>First release.</p>' "$T/n.html"
grep -q '<li>CPU &lt;and&gt; RAM</li>' "$T/n.html"
grep -q '<li>GPU &amp; Network</li>' "$T/n.html"
[[ $(grep -c '<ul>' "$T/n.html") -eq 1 ]]
