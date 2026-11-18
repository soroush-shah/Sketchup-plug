import { defineConfig, type Plugin } from 'vite';
import preact from '@preact/preset-vite';
import { readFileSync } from 'node:fs';

/** Emits sw.js with the list of built files so the app shell works offline. */
function serviceWorker(): Plugin {
  return {
    name: 'skpshare-sw',
    apply: 'build',
    generateBundle(_opts, bundle) {
      const files = Object.keys(bundle).filter((f) => !f.endsWith('.map'));
      const src = readFileSync(new URL('./src/sw.js', import.meta.url), 'utf8')
        .replace('self.__PRECACHE__', JSON.stringify(['./', ...files, 'manifest.webmanifest', 'icons/icon.svg']))
        .replace('__BUILD_ID__', Date.now().toString(36));
      this.emitFile({ type: 'asset', fileName: 'sw.js', source: src });
    },
  };
}

export default defineConfig({
  base: './',
  plugins: [preact(), serviceWorker()],
  build: {
    outDir: '../server/public',
    emptyOutDir: false,
    chunkSizeWarningLimit: 1500,
    rollupOptions: { output: { manualChunks: (id) => (id.includes('node_modules/three') ? 'three' : undefined) } },
  },
  server: { proxy: { '/api': 'http://127.0.0.1:8089' } },
});
