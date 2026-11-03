// Renders icons/*.svg to PNG (24 + 32 px for toolbar icons, 24 px for cursors).
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const dir = path.join(__dirname, '..', 'src', 'banian_browser', 'icons');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.svg'))) {
    const svg = fs.readFileSync(path.join(dir, f), 'utf8');
    const name = f.replace('.svg', '');
    const sizes = name.startsWith('cursor_') ? [[24, name + '.png']] : [[24, name + '_24.png'], [32, name + '_32.png']];
    for (const [s, out] of sizes) {
      await p.setViewportSize({ width: s, height: s });
      await p.setContent(`<html><body style="margin:0;background:transparent">${svg.replace('width="24" height="24"', `width="${s}" height="${s}"`)}</body></html>`);
      await p.screenshot({ path: path.join(dir, out), omitBackground: true, clip: { x: 0, y: 0, width: s, height: s } });
    }
    if (name.startsWith('cursor_')) fs.unlinkSync(path.join(dir, f));
  }
  await b.close();
})();
