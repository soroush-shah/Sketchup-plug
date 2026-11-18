// Renders the SVG app icon to the PNG sizes needed by the PWA manifest, iOS and the SketchUp toolbar.
// Usage: node tools/make_icons.cjs   (needs Playwright + Chromium)
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const render = async (svgFile, size, out) => {
    const svg = fs.readFileSync(svgFile, 'utf8');
    await p.setViewportSize({ width: size, height: size });
    await p.setContent(`<html><body style="margin:0;background:transparent">${svg.replace('<svg ', `<svg width="${size}" height="${size}" `)}</body></html>`);
    await p.screenshot({ path: out, omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
    console.log('wrote', path.relative(root, out));
  };
  const appIcon = path.join(root, 'web/public/icons/icon.svg');
  await render(appIcon, 192, path.join(root, 'web/public/icons/icon-192.png'));
  await render(appIcon, 512, path.join(root, 'web/public/icons/icon-512.png'));
  const plug = path.join(root, 'plugin/skpshare/ui/icon.svg');
  await render(plug, 24, path.join(root, 'plugin/skpshare/ui/icon_small.png'));
  await render(plug, 32, path.join(root, 'plugin/skpshare/ui/icon.png'));
  await b.close();
})();
