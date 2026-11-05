// Renders icons/*.svg -> *_16.png, *_24.png and *.pdf (Mac vector icons).
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const dir = path.resolve(process.argv[2]);
  const b = await chromium.launch();
  for (const f of fs.readdirSync(dir).filter(n => n.endsWith('.svg'))) {
    const svg = fs.readFileSync(path.join(dir, f), 'utf8');
    const base = f.replace('.svg', '');
    for (const s of [16, 24]) {
      const p = await b.newPage({ viewport: { width: s, height: s }, deviceScaleFactor: 1 });
      await p.setContent(`<html><body style="margin:0;background:transparent">${svg.replace('width="24" height="24"', `width="${s}" height="${s}"`)}</body></html>`);
      await p.screenshot({ path: path.join(dir, `${base}_${s}.png`), omitBackground: true, clip: { x: 0, y: 0, width: s, height: s } });
      await p.close();
    }
    const p = await b.newPage();
    await p.setContent(`<html><head><style>@page{size:24px 24px;margin:0}html,body{margin:0}</style></head><body>${svg}</body></html>`);
    await p.pdf({ path: path.join(dir, `${base}.pdf`), width: '24px', height: '24px', printBackground: true, pageRanges: '1' });
    await p.close();
  }
  await b.close();
})();
