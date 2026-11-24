const CACHE = 'rezeptgarten-shell-v163';
const SHELL = ['/', '/static/changelog.html', '/static/style.css?v=144', '/static/theme.js?v=31', '/static/app.js?v=152', '/static/week-placeholder-four.png', '/static/week-placeholder-steak-v2.png', '/static/week-placeholder-resteessen.png', '/static/manifest.webmanifest?v=2', '/static/icon-192.png?v=2', '/static/icon-512.png?v=2', '/static/icon-maskable-512.png?v=2'];
self.addEventListener('install', event => { event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL))); self.skipWaiting(); });
self.addEventListener('activate', event => { event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET' || new URL(event.request.url).origin !== self.location.origin) return;
  const path = new URL(event.request.url).pathname;
  // Personal recipes, account data and authenticated images never enter the shared shell cache.
  if (path.startsWith('/api/')) return;
  if (event.request.mode === 'navigate' && (path === '/' || path === '/static/changelog.html')) {
    event.respondWith(caches.open(CACHE).then(cache => cache.match(path)).then(cached => cached || fetch(event.request)));
  } else if (SHELL.some(url => new URL(url, self.location.origin).pathname === path)) {
    event.respondWith(caches.open(CACHE).then(cache => cache.match(event.request)).then(cached => cached || fetch(event.request)));
  }
});
