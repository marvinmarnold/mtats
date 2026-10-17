// SPDX-License-Identifier: MIT
// Writes site/firebase.json. /download points at the current stable DMG from latest.json.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';

const bootstrap = process.env.MTATS_SITE_BOOTSTRAP === '1';
const latestPath = new URL('../src/data/latest.json', import.meta.url);
if (!existsSync(latestPath) && !bootstrap) {
  console.error('src/data/latest.json missing (set MTATS_SITE_BOOTSTRAP=1 before the first release)');
  process.exit(1);
}
const latest = existsSync(latestPath) ? JSON.parse(readFileSync(latestPath, 'utf8')) : null;
const feedHeaders = [
  { key: 'Content-Type', value: 'application/xml; charset=utf-8' },
  { key: 'Cache-Control', value: 'public, max-age=300' },
];
const redirects = [
  { source: '/releases/:file*', destination: 'https://storage.googleapis.com/mtats-releases/releases/:file', type: 302 },
];
if (latest) {
  redirects.unshift({ source: '/download', destination: `/releases/mtats-${latest.version}.dmg`, type: 302 });
}
const config = {
  hosting: {
    public: 'dist',
    cleanUrls: true,
    headers: [
      { source: '/appcast.xml', headers: feedHeaders },
      { source: '/beta/appcast.xml', headers: feedHeaders },
      { source: '/latest.json', headers: [{ key: 'Cache-Control', value: 'public, max-age=300' }] },
    ],
    redirects,
  },
};
writeFileSync(new URL('../firebase.json', import.meta.url), JSON.stringify(config, null, 2) + '\n');
console.log(`firebase.json written (${latest ? `download → ${latest.version}` : 'bootstrap, no /download'})`);
