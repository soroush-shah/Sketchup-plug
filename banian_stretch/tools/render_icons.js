// Renders the SVG toolbar icons to PNG (fallback) and PDF (macOS vector icons).
// Usage: node banian_stretch/tools/render_icons.js [--sheet out.png]
'use strict';

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ICON_DIR = path.resolve(__dirname, '../src/banian_stretch/icons');
const sheetArg = process.argv.indexOf('--sheet');
const sheetPath = sheetArg > 0 ? process.argv[sheetArg + 1] : null;

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  const icons = fs.readdirSync(ICON_DIR).filter((f) => f.endsWith('.svg')).sort();

  for (const file of icons) {
    const name = path.basename(file, '.svg');
    const svg = fs.readFileSync(path.join(ICON_DIR, file), 'utf8');
    const html = `<html><body style="margin:0;background:transparent">
      <div style="width:24px;height:24px">${svg}</div></body></html>`;

    // PNG fallback at 2x (48 px); SketchUp scales it to the toolbar size.
    await page.setViewportSize({ width: 24, height: 24 });
    const hi = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 24, height: 24 } });
    await hi.setContent(html);
    await hi.screenshot({ path: path.join(ICON_DIR, `${name}.png`), omitBackground: true });
    await hi.close();

    // Vector PDF for macOS toolbars.
    await page.setContent(html.replace('<html>', '<html><head><style>@page{size:24px 24px;margin:0}</style></head>'));
    await page.pdf({ path: path.join(ICON_DIR, `${name}.pdf`), width: '24px', height: '24px',
      printBackground: false, pageRanges: '1' });
  }

  if (sheetPath) {
    const cells = icons.map((f) => {
      const svg = fs.readFileSync(path.join(ICON_DIR, f), 'utf8');
      return `<figure><div class="big">${svg}</div><div class="small">${svg}</div>
        <figcaption>${path.basename(f, '.svg')}</figcaption></figure>`;
    }).join('');
    const sheet = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 760, height: 300 } });
    await sheet.setContent(`<html><body style="font:11px sans-serif;margin:12px;display:flex;flex-wrap:wrap;gap:10px;background:#eef0f3">
      <style>figure{margin:0;width:76px;text-align:center}.big svg{width:64px;height:64px;background:#fff;border-radius:6px}
      .small svg{width:24px;height:24px}</style>${cells}</body></html>`);
    await sheet.screenshot({ path: sheetPath, fullPage: true });
  }

  await browser.close();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
