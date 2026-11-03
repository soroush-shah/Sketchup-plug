// node dev/preview_importer.js <model file> <outdir> [ratio]
// Runs the import dialog in Chromium with a fake Ruby bridge that streams real files,
// then checks what would be sent to SketchUp.
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const MODEL = process.argv[2] === 'MODEL';
const file = MODEL ? __filename : path.resolve(process.argv[2]);
const out = process.argv[3] || '.';
const ratio = process.argv[4] ? +process.argv[4] : 1;
(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
  const page = await browser.newPage({ viewport: { width: 1160, height: 720 } });
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  const sent = { begin: null, geoms: {}, finish: null, thumb: false };
  await page.exposeFunction('__rb', async (json) => {
    const m = JSON.parse(json);
    const a = m.args || {};
    let data = true;
    switch (m.cmd) {
      case 'model_data': {
        const P = [], UV = [], T = [], seg = 80, ring = 50;
        for (let r = 0; r <= ring; r++) for (let s = 0; s <= seg; s++) { const th = Math.PI * r / ring, ph = 2 * Math.PI * s / seg;
          P.push(+(20 * Math.sin(th) * Math.cos(ph)).toFixed(4), +(20 * Math.sin(th) * Math.sin(ph)).toFixed(4), +(20 + 20 * Math.cos(th)).toFixed(4)); UV.push(s / seg * 4, r / ring * 2); }
        for (let r = 0; r < ring; r++) for (let s = 0; s < seg; s++) { const a = r * (seg + 1) + s, b = a + seg + 1; T.push(a, b, a + 1, a + 1, b, b + 1); }
        data = { materials: [{ name: 'Wood', color: '#c8743d', opacity: 1, tex: { path: path.join(process.env.FIX || '', 'tex/wood.png') } }],
          nodes: [{ n: 'Ball', m: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1], g: 'd0', c: [{ n: 'Copy', m: [1,0,0,0, 0,1,0,0, 0,0,1,0, 60,0,0,1], g: 'd0', c: [] }] }],
          geoms: { d0: [{ mat: 0, pts: P, uvs: UV, tris: T }] } };
        break;
      }
      case 'init': if (MODEL) { data = { mode: 'simplify', lang: 'en', theme: 'dark', settings: {}, su: 26 }; break; }
        data = { mode: 'file', lang: 'fa', theme: 'light', settings: { import_ratio: Math.round(ratio * 100) }, su: 26,
        file: { path: file, name: path.basename(file), ext: path.extname(file).slice(1).toLowerCase(), size: fs.statSync(file).size, dir: path.dirname(file) } }; break;
      case 'read': {
        let p = a.path;
        if (!fs.existsSync(p)) { const alt = path.join(a.base || '', path.basename(p)); p = fs.existsSync(alt) ? alt : null; }
        if (!p) { data = { missing: true }; break; }
        const buf = fs.readFileSync(p);
        data = { size: buf.length, path: p };
        setTimeout(async () => {
          for (let o = 0; o < buf.length || o === 0; o += 65536) {
            const last = o + 65536 >= buf.length;
            await page.evaluate(([req, d, last]) => BI.emit('chunk', { req, data: d, last }), [a.req, buf.slice(o, o + 65536).toString('base64'), last]);
            if (last) break;
          }
        }, 5);
        break;
      }
      case 'thumb': sent.thumb = a.png.length > 100; break;
      case 'begin': sent.begin = a; break;
      case 'geom': (sent.geoms[a.key] = sent.geoms[a.key] || []).push(...a.parts); break;
      case 'finish': sent.finish = a; break;
    }
    setTimeout(() => page.evaluate(([id, d]) => BI.reply(id, { ok: true, data: d }), [m.id, data]), 2);
  });
  await page.addInitScript(() => { window.sketchup = { bi_call: (j) => window.__rb(j) }; });
  await page.goto('file://' + path.join(__dirname, '..', 'src', 'banian_browser', 'ui', 'importer.html'));
  await page.waitForFunction(() => window.BI && BI.state && BI.state.entries.length > 0 && document.getElementById('busy').classList.contains('hidden'), null, { timeout: 60000 });
  await page.waitForTimeout(1200);
  const name = path.basename(file).replace(/\W/g, '_');
  await page.screenshot({ path: path.join(out, 'imp_' + name + '.png') });
  const stats = await page.evaluate(() => ({ entries: BI.state.entries.length, meshes: BI.state.entries.reduce((s, e) => s + e.meshes.length, 0),
    tris: BI.state.entries.reduce((s, e) => s + (e.reduced ? e.reduced.after : e.tris), 0), unit: BI.state.unitGuess, up: BI.state.up, missing: BI.state.missing }));
  await page.click('[data-act="go"]');
  await page.waitForFunction(() => true);
  for (let i = 0; i < 100 && !sent.finish; i++) await page.waitForTimeout(100);
  const parts = Object.values(sent.geoms).flat();
  const tris = parts.reduce((s, p) => s + p.tris.length / 3, 0);
  const uvParts = parts.filter(p => p.uvs).length;
  const mats = (sent.begin && sent.begin.materials) || [];
  console.log(JSON.stringify({ file: path.basename(file), stats, thumb: sent.thumb, geoms: Object.keys(sent.geoms).length, parts: parts.length, trisSent: tris, uvParts,
    materials: mats.map(m => ({ name: m.name, tex: m.tex ? (m.tex.path ? 'path:' + path.basename(m.tex.path) : 'data:' + m.tex.ext) : null })),
    nodes: sent.begin && sent.begin.nodes ? JSON.stringify(sent.begin.nodes).length : 0, buildScale: sent.begin && sent.begin.buildScale, finish: sent.finish, errors }, null, 1));
  await browser.close();
})();
