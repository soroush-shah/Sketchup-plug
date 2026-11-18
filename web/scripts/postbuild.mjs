// Copies runtime libraries the viewer loads on demand (KTX2 texture transcoder) next to the app.
import { cpSync, mkdirSync, existsSync, readdirSync, rmSync } from 'node:fs';
const out = new URL('../../server/public/', import.meta.url);
const basis = new URL('../node_modules/three/examples/jsm/libs/basis/', import.meta.url);
mkdirSync(new URL('libs/basis/', out), { recursive: true });
for (const f of ['basis_transcoder.js', 'basis_transcoder.wasm']) cpSync(new URL(f, basis), new URL('libs/basis/' + f, out));
// Remove stale hashed assets from previous builds.
const assets = new URL('assets/', out);
if (existsSync(assets)) {
  const index = (await import('node:fs')).readFileSync(new URL('index.html', out), 'utf8');
  const sw = (await import('node:fs')).readFileSync(new URL('sw.js', out), 'utf8');
  for (const f of readdirSync(assets)) if (!index.includes(f) && !sw.includes(f)) rmSync(new URL(f, assets));
}
console.log('postbuild: copied basis transcoder');
