const CACHE = 'rezeptgarten-shell-v118';
const SHELL = ['/', '/static/style.css?v=118', '/static/theme.js?v=31', '/static/app.js?v=118', '/static/week-placeholder-four.png', '/static/week-placeholder-steak-v2.png', '/static/week-placeholder-resteessen.png', '/static/brand.svg', '/static/manifest.webmanifest', '/static/icon-192.png', '/static/icon-512.png', '/static/icon-maskable-512.png'];
self.addEventListener('install', event => { event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL))); self.skipWaiting(); });
self.addEventListener('activate', event => { event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET' || new URL(event.request.url).origin !== self.location.origin) return;
  const path = new URL(event.request.url).pathname;
  // Personal recipes, account data and authenticated images never enter the shared shell cache.
  if (path.startsWith('/api/')) return;
  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request).catch(() => caches.match('/')));
  } else if (SHELL.some(url => new URL(url, self.location.origin).pathname === path)) {
    event.respondWith(fetch(event.request).then(response => {
      if (response.ok) { const copy = response.clone(); caches.open(CACHE).then(cache => cache.put(event.request, copy)); }
      return response;
    }).catch(() => caches.match(event.request)));
  }
});
