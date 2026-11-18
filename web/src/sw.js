// SkpShare service worker – app shell offline support. (Model files are cached by the app itself.)
const SHELL = 'skpshare-shell-__BUILD_ID__';
const PRECACHE = self.__PRECACHE__;

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(SHELL).then((c) => c.addAll(PRECACHE.map((p) => new Request(p, { cache: 'reload' })))).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k.startsWith('skpshare-shell-') && k !== SHELL).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return; // blob:/data: textures etc.
  if (url.origin !== location.origin || url.pathname.includes('/api/') || url.pathname.includes('/__offline/')) return;

  if (req.mode === 'navigate') {
    // Network first so new deployments show up; fall back to the cached shell offline.
    e.respondWith(fetch(req).catch(() => caches.match(new URL('./', self.registration.scope).href, { ignoreSearch: true })));
    return;
  }
  // Static assets: cache first (hashed file names never change).
  e.respondWith(caches.match(req, { ignoreSearch: true }).then((hit) => hit || fetch(req).then((res) => {
    if (res.ok && (url.pathname.includes('/assets/') || url.pathname.includes('/libs/') || url.pathname.includes('/icons/'))) {
      const copy = res.clone();
      caches.open(SHELL).then((c) => c.put(req, copy));
    }
    return res;
  })));
});
