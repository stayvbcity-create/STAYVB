// ═══════════════════════════════════════════════════════════════════
// StayVB v2 — Service Worker
// ═══════════════════════════════════════════════════════════════════
const CACHE_NAME = 'stayvb-v2-cache';
const SUPABASE_URL = 'https://zapmsxvwxjeoglpzldhl.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InphcG1zeHZ3eGplb2dscHpsZGhsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMjY4NDQsImV4cCI6MjA5NjcwMjg0NH0.szTiMlsQJZCgbFE89eRn1YIN133smnEkPhVmcaVmGqM';

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

// ── Activate ────────────────────────────────────────────────────────
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

// ── Fetch strategija ────────────────────────────────────────────────
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  if (!event.request.url.startsWith('http')) return;
  const url = new URL(event.request.url);

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

  if (event.request.mode === 'navigate' ||
      url.pathname.endsWith('.html') ||
      url.pathname === '/') {
    event.respondWith(
      fetch(event.request, { cache: 'no-store' })
        .then(response => {
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

// ═══════════════════════════════════════════════════════════════════
// ── Push notifikacije ───────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════

self.addEventListener('push', event => {
  if (!event.data) return;
  let data;
  try { data = event.data.json(); } catch { data = { title: 'StayVB', body: event.data.text() }; }

  event.waitUntil(
    self.registration.showNotification(data.title || 'StayVB', {
      body: data.body || '',
      icon: './icon192.png',
      badge: './icon192.png',
      vibrate: [200, 100, 200],
      tag: data.tag || 'stayvb',
      renotify: true,
      data: { url: data.url || './' },
      actions: [
        { action: 'open',    title: '👀 Pogledaj' },
        { action: 'dismiss', title: 'Zatvori' }
      ]
    })
  );
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  if (event.action === 'dismiss') return;
  const url = event.notification.data?.url || './';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(cls => {
      const existing = cls.find(c => c.url.includes('stayvb') || c.url.includes('localhost'));
      if (existing) { existing.focus(); existing.navigate(url); }
      else clients.openWindow(url);
    })
  );
});

// ═══════════════════════════════════════════════════════════════════
// ── Geofencing — 100m, jednom dnevno po partneru ────────────────────
// ═══════════════════════════════════════════════════════════════════

// cooldown: partnerId → timestamp poslednje notifikacije
const lastNotified = {};

// Klijent šalje lokaciju svakih 5 min — SW provjeri geofence
self.addEventListener('message', event => {
  if (event.data?.type === 'LOCATION_UPDATE') {
    const { lat, lng } = event.data;
    if (lat && lng) checkGeofence(lat, lng);
  }
  // Klijent traži lokaciju natrag (za fallback)
  if (event.data?.type === 'GET_LOCATION') {
    event.ports[0].postMessage(null); // SW ne može sam dohvatiti lokaciju
  }
});

async function checkGeofence(lat, lng) {
  const today = new Date().toISOString().split('T')[0];
  const now   = new Date();
  const nowMins = now.getHours() * 60 + now.getMinutes();

  // Dohvati aktivne partnere sa koordinatama (restaurant, attraction, business)
  let partners, promos;
  try {
    const [pRes, cRes] = await Promise.all([
      fetch(`${SUPABASE_URL}/rest/v1/partners?select=id,name,type,lat,lng,hh_active,hh_start,hh_end,hh_date,partner_code&is_active=eq.true&lat=not.is.null&type=in.(restaurant,attraction,business)`, {
        headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
      }),
      fetch(`${SUPABASE_URL}/rest/v1/partner_content?select=partner_id,current_offer,offer_expires_at`, {
        headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
      })
    ]);
    partners = pRes.ok ? await pRes.json() : [];
    promos   = cRes.ok ? await cRes.json() : [];
  } catch { return; }

  // Indeks promo po partner_id
  const promoMap = {};
  promos.forEach(p => {
    if (p.current_offer) promoMap[p.partner_id] = p;
  });

  for (const p of partners) {
    if (!p.lat || !p.lng) continue;

    // Udaljenost u metrima
    const dist = haversine(lat, lng, p.lat, p.lng);
    if (dist > 100) continue; // Van 100m — preskočil

    // Provjeri aktivnu ponudu
    const isHH = p.hh_active && p.hh_date === today && isHHActive(p, nowMins);
    const promo = promoMap[p.id];
    const hasPromo = promo && (!promo.offer_expires_at || new Date(promo.offer_expires_at) > now);

    if (!isHH && !hasPromo) continue; // Nema aktivne ponude

    // Cooldown — jednom dnevno po partneru
    const lastTime = lastNotified[p.id] || 0;
    if (Date.now() - lastTime < 24 * 60 * 60 * 1000) continue;
    lastNotified[p.id] = Date.now();

    // Sastavi poruku
    const distLabel = `${Math.round(dist)}m od vas`;
    let title, body, url;

    if (isHH && hasPromo) {
      title = `🔥🎯 ${p.name}`;
      body  = `Happy Hour + Akcija! ${distLabel}`;
      url   = './happy-hour.html';
    } else if (isHH) {
      title = `🔥 ${p.name}`;
      body  = `Happy Hour aktivan! ${distLabel}`;
      url   = './happy-hour.html';
    } else {
      title = `🎯 ${p.name}`;
      body  = `${promo.current_offer} · ${distLabel}`;
      url   = './radar.html';
    }

    await self.registration.showNotification(title, {
      body,
      icon:    './icon192.png',
      badge:   './icon192.png',
      vibrate: [300, 100, 300],
      tag:     `geo-${p.id}`,
      renotify: false,
      data: { url },
      actions: [
        { action: 'open',    title: '👀 Pogledaj' },
        { action: 'dismiss', title: 'Možda kasnije' }
      ]
    });
  }
}

function isHHActive(p, nowMins) {
  if (!p.hh_start || !p.hh_end) return false;
  const [sh, sm] = p.hh_start.split(':').map(Number);
  const [eh, em] = p.hh_end.split(':').map(Number);
  const s = sh * 60 + sm;
  const e = eh * 60 + em;
  return s < e ? nowMins >= s && nowMins <= e : nowMins >= s || nowMins <= e;
}

// Haversine — udaljenost u metrima između dvije GPS tačke
function haversine(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat/2)**2
    + Math.cos(lat1*Math.PI/180) * Math.cos(lat2*Math.PI/180) * Math.sin(dLng/2)**2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}
