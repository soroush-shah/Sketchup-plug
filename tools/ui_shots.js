// Screenshots of the dialog with mocked Ruby side. node ui_shots.js previews.json outdir
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const data = fs.readFileSync(process.argv[2], 'utf8');
  const out = process.argv[3];
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 420, height: 1500 }, deviceScaleFactor: 1 });
  const errs = [];
  p.on('pageerror', e => errs.push(e.message));
  p.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
  await p.addInitScript(`
    window.__D = ${data};
    window.__calls = [];
    window.MOCK = {
      ready: () => setTimeout(() => { FS.recv(__D.init); FS.recv({type:'source', kind:'face', count:1}); }, 0),
      preview: (s) => { const st = JSON.parse(s); window.__calls.push(st); const pv = __D.previews[st.pattern]; if (pv) setTimeout(() => FS.recv(pv), 0); },
      save_state: () => {}, apply: (s) => setTimeout(() => FS.recv({type:'done', full: 120, cut: 34, time: 0.42}), 50)
    };`);
  await p.goto('file://' + path.resolve('src/banian_floor_studio/ui/html/index.html'));
  await p.waitForTimeout(400);
  const pats = ['herringbone', 'wood', 'hexagon', 'voronoi'];
  for (const pat of pats) {
    await p.click(`.pat[data-pat="${pat}"]`);
    await p.waitForTimeout(300);
    await p.screenshot({ path: path.join(out, `ui_${pat}.png`), fullPage: true });
  }
  await p.click('#lang');
  await p.click('.pat[data-pat="chevron"]');
  await p.waitForTimeout(300);
  await p.screenshot({ path: path.join(out, 'ui_fa_chevron.png'), fullPage: true });
  await p.click('#modes button[data-mode="divide"]');
  await p.click('.pat[data-pat="brick"]');
  await p.waitForTimeout(300);
  await p.screenshot({ path: path.join(out, 'ui_fa_divide.png'), fullPage: true });
  await p.click('#apply');
  await p.waitForTimeout(150);
  await p.screenshot({ path: path.join(out, 'ui_fa_done.png'), clip: { x: 0, y: 0, width: 420, height: 820 } });
  // 820px real dialog height view
  await p.setViewportSize({ width: 420, height: 820 });
  await p.screenshot({ path: path.join(out, 'ui_window.png') });
  const last = await p.evaluate(() => window.__calls[window.__calls.length - 1]);
  console.log('last state:', JSON.stringify(last).slice(0, 300));
  console.log('errors:', errs);
  await b.close();
})();
