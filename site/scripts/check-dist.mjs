// SPDX-License-Identifier: MIT
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
const LIMIT = 2 * 1024 * 1024;
const bad = [];
function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const s = statSync(p);
    if (s.isDirectory()) walk(p);
    else if (s.size > LIMIT || name.endsWith('.dmg')) bad.push(`${p} (${s.size} bytes)`);
  }
}
walk(new URL('../dist', import.meta.url).pathname);
if (bad.length) { console.error('Files too large for Hosting:\n' + bad.join('\n')); process.exit(1); }
console.log('dist size check OK');
