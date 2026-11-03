// node dev/test_decimate.js  - checks the polygon reducer on a UV sphere and a flat grid
global.window = global;
require('../src/banian_browser/ui/decimate.js');
function sphere(seg, ring) {
  const P = [], UV = [], I = [];
  for (let r = 0; r <= ring; r++) for (let s = 0; s <= seg; s++) {
    const th = Math.PI * r / ring, ph = 2 * Math.PI * s / seg;
    P.push(Math.sin(th) * Math.cos(ph), Math.sin(th) * Math.sin(ph), Math.cos(th)); UV.push(s / seg, r / ring);
  }
  for (let r = 0; r < ring; r++) for (let s = 0; s < seg; s++) {
    const a = r * (seg + 1) + s, b = a + seg + 1;
    I.push(a, b, a + 1, a + 1, b, b + 1);
  }
  return { positions: new Float32Array(P), uvs: new Float32Array(UV), indices: new Uint32Array(I), groups: null };
}
function grid(n) {
  const P = [], I = [];
  for (let y = 0; y <= n; y++) for (let x = 0; x <= n; x++) P.push(x, y, 0);
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) { const a = y * (n + 1) + x; I.push(a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1); }
  const G = new Int32Array(I.length / 3); for (let t = 0; t < G.length; t++) G[t] = (t % (2 * n)) < n ? 0 : 1;
  return { positions: new Float32Array(P), uvs: null, indices: new Uint32Array(I), groups: G };
}
let fails = 0;
const check = (n, c) => { console.log((c ? 'PASS ' : 'FAIL ') + n); if (!c) fails++; };
(async () => {
  let t0 = Date.now();
  const s = sphere(400, 250);
  const r = await BBDecimate.simplify(s, { ratio: 0.1 });
  const ms = Date.now() - t0;
  console.log(`sphere ${r.before} -> ${r.after} tris in ${ms} ms`);
  check('sphere reduced to ~10%', r.after <= r.before * 0.11 && r.after > r.before * 0.05);
  let maxDev = 0, nan = false;
  for (let i = 0; i < r.positions.length; i += 3) {
    const d = Math.hypot(r.positions[i], r.positions[i + 1], r.positions[i + 2]);
    if (isNaN(d)) nan = true; maxDev = Math.max(maxDev, Math.abs(d - 1));
  }
  check('vertices stay on the sphere (no NaN)', !nan && maxDev < 1e-5);
  check('UVs kept', r.uvs && r.uvs.length / 2 === r.positions.length / 3);
  let degenerate = 0;
  for (let t = 0; t < r.indices.length; t += 3) { const [a, b, c] = [r.indices[t], r.indices[t + 1], r.indices[t + 2]]; if (a === b || b === c || a === c) degenerate++; }
  check('no degenerate triangles', degenerate === 0);
  const tol = await BBDecimate.simplify(sphere(200, 120), { ratio: 0, tolerance: 0.002 });
  check('tolerance mode stops early', tol.after > 200 && tol.after < tol.before);
  const g = await BBDecimate.simplify(grid(60), { ratio: 0.01 });
  console.log(`grid ${g.before} -> ${g.after}`);
  check('flat grid collapses strongly but keeps material border', g.after < g.before * 0.2 && new Set(g.groups).size === 2);
  const same = await BBDecimate.simplify(grid(10), { ratio: 1 });
  check('ratio 1 keeps everything', same.after === same.before);
  console.log(fails ? fails + ' FAILED' : 'ALL PASSED');
  process.exit(fails ? 1 : 0);
})();
