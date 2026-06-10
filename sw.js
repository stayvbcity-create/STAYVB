// ═══════════════════════════════════════════════════════════════════
// StayVB v2 — Service Worker
// ═══════════════════════════════════════════════════════════════════

const CACHE_NAME = 'stayvb-v2-cache';

// Statički fajlovi koji se keširaju pri instalaciji
const STATIC_ASSETS = [
  './manifest.json',
  './icon192.png',
  './icon512.png',
  './config.js',
  './security-guard.js',
  './lang-init.js',
];

// ── Install ─────────────────────────────────────────────────────────
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(STATIC_ASSETS))
      .then(() => self.skipWaiting())
  );
});

// ── Activate — briši stare cache verzije ────────────────────────────
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys
          .filter(key => key !== CACHE_NAME)
          .map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

// ── Fetch strategija ────────────────────────────────────────────────
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);

  // 1. Supabase API — uvek mreža, nikad cache
  if (url.hostname.includes('supabase.co') ||
      url.hostname.includes('translate.google') ||
      url.hostname.includes('googleapis.com') ||
      url.hostname.includes('flagcdn.com')) {
    event.respondWith(
      fetch(event.request, { cache: 'no-store' })
        .catch(() => new Response('', { status: 503 }))
    );
    return;
  }

  // 2. HTML stranice — Network first, fallback na cache
  if (event.request.mode === 'navigate' ||
      url.pathname.endsWith('.html') ||
      url.pathname === '/') {
    event.respondWith(
      fetch(event.request, { cache: 'no-store' })
        .then(response => {
          // Sačuvaj svežu kopiju u cache
          if (response.ok) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then(c => c.put(event.request, clone));
          }
          return response;
        })
        .catch(() =>
          caches.match(event.request)
            .then(cached => cached || caches.match('./index.html'))
        )
    );
    return;
  }

  // 3. JS/CSS/slike — Cache first, fallback na mreža
  event.respondWith(
    caches.match(event.request)
      .then(cached => {
        if (cached) return cached;

        return fetch(event.request)
          .then(response => {
            if (!response || response.status !== 200) return response;
            const clone = response.clone();
            caches.open(CACHE_NAME).then(c => c.put(event.request, clone));
            return response;
          });
      })
  );
});
