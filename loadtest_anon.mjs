// ═══════════════════════════════════════════════════════════════════
// loadtest_anon.mjs — test iz perspektive GOSTA (anon ključ, bez
// admin naloga) + provera bezbednosti skenera i zaštićenih kolona.
//
// Pokretanje (posle loadtest_seed_v2.sql + loadtest_stress_update.sql):
//   node loadtest_anon.mjs
//
// Nema upisa u bazu. Jedini "write" pozivi su PATCH/RPC nad
// nepostojećim ID-jem (0 redova), da se proveri da li anon sme da
// menja zabranjene kolone.
// ═══════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';

const cfg = readFileSync(new URL('./config.js', import.meta.url), 'utf8');
const URL_BASE = cfg.match(/SUPABASE_URL = '([^']+)'/)[1];
const KEY = cfg.match(/SUPABASE_ANON_KEY = '([^']+)'/)[1];
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Accept-Profile': 'public', 'Content-Profile': 'public' };
const TODAY = new Date().toLocaleDateString('sv-SE');
const FAKE_ID = '00000000-0000-0000-0000-000000000000';

const results = [];
const check = (name, pass, detail = '') => {
  results.push({ name, pass, detail });
  console.log(`${pass ? '✅' : '❌'} ${name}${detail ? ' — ' + detail : ''}`);
};

async function get(path, extraHeaders = {}) {
  const t0 = performance.now();
  const r = await fetch(`${URL_BASE}/rest/v1/${path}`, { headers: { ...H, ...extraHeaders } });
  const ms = performance.now() - t0;
  const text = await r.text();
  let body; try { body = JSON.parse(text); } catch { body = text; }
  return { status: r.status, body, ms, headers: r.headers };
}

async function count(path) {
  const r = await get(path, { Prefer: 'count=exact', Range: '0-0' });
  const cr = r.headers.get('content-range') || '';
  return { ...r, count: Number(cr.split('/')[1]) || 0 };
}

async function rpc(fn, args) {
  const t0 = performance.now();
  const r = await fetch(`${URL_BASE}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: { ...H, 'Content-Type': 'application/json' }, body: JSON.stringify(args),
  });
  const ms = performance.now() - t0;
  const text = await r.text();
  let body; try { body = JSON.parse(text); } catch { body = text; }
  return { status: r.status, body, ms };
}

// ── 1. Gost vidi test podatke (anon) ──────────────────────────────
console.log('\n── 1. Čitanje kao gost (anon) ──');
const hotels = await count('partners?select=id&partner_code=like.TST_HOTEL_*&type=eq.hotel');
const rests = await count('partners?select=id&partner_code=like.TST_REST_*&type=eq.restaurant');
const apts = await count('partners?select=id&partner_code=like.TST_APT_*&type=eq.apartment');
check('Partneri vidljivi anon-u (30/200/300)', hotels.count === 30 && rests.count === 200 && apts.count === 300,
  `${hotels.count} / ${rests.count} / ${apts.count}`);

const guests = await count('guests?select=id&token=like.TESTGUEST_*');
check('Gosti vidljivi anon-u za lookup po tokenu (3000)', guests.count === 3000, `${guests.count}`);

const hh = await count(`partners?select=id&partner_code=like.TST_*&hh_active=eq.true&hh_date=eq.${TODAY}`);
check('Happy Hour aktivan danas (230)', hh.count === 230, `${hh.count}`);

// ── 2. Zaštićene kolone NISU dostupne anon-u ─────────────────────
console.log('\n── 2. Zaštićene kolone (pin, access_token, scanner_token) ──');
for (const col of ['pin', 'access_token', 'scanner_token']) {
  const r = await get(`partners?select=${col}&limit=1`);
  const blocked = r.status >= 400;
  check(`anon NE može da čita kolonu "${col}"`, blocked, `HTTP ${r.status}`);
}

// ── 3. Skener: lažni tokeni ne vraćaju ništa ─────────────────────
console.log('\n── 3. Skener (scanner_login / get / regenerate) ──');
const fakeScan = await rpc('scanner_login', { p_scanner_token: randomUUID().replace(/-/g, '') });
check('scanner_login sa nasumičnim tokenom vraća prazno', Array.isArray(fakeScan.body) && fakeScan.body.length === 0,
  `HTTP ${fakeScan.status}`);

const emptyScan = await rpc('scanner_login', { p_scanner_token: '' });
check('scanner_login sa praznim tokenom vraća prazno', Array.isArray(emptyScan.body) && emptyScan.body.length === 0,
  `HTTP ${emptyScan.status}`);

const fakeGet = await rpc('get_scanner_token', { p_access_token: randomUUID().replace(/-/g, '') });
check('get_scanner_token sa nasumičnim access_token vraća null', fakeGet.body === null, `HTTP ${fakeGet.status}`);

const fakeRegen = await rpc('regenerate_scanner_token', { p_access_token: randomUUID().replace(/-/g, '') });
check('regenerate_scanner_token sa nasumičnim access_token vraća null', fakeRegen.body === null, `HTTP ${fakeRegen.status}`);

// ── 4. Anon NE sme da upiše scanner_token direktno ───────────────
console.log('\n── 4. Zabranjeni upisi (0 redova, samo provera dozvola) ──');
const directWrite = await fetch(`${URL_BASE}/rest/v1/partners?id=eq.${FAKE_ID}`, {
  method: 'PATCH', headers: { ...H, 'Content-Type': 'application/json', Prefer: 'return=representation' },
  body: JSON.stringify({ scanner_token: 'hacked' }),
});
check('anon NE može direktno da postavi scanner_token', directWrite.status >= 400, `HTTP ${directWrite.status}`);

const directPin = await fetch(`${URL_BASE}/rest/v1/partners?id=eq.${FAKE_ID}`, {
  method: 'PATCH', headers: { ...H, 'Content-Type': 'application/json' },
  body: JSON.stringify({ pin: '0000' }),
});
check('anon NE može direktno da menja pin', directPin.status >= 400, `HTTP ${directPin.status}`);

// ── 5. Opterećenje kao gost (anon), 400 upita, 25 paralelnih ─────
console.log('\n── 5. Opterećenje kao gost (400 upita, 25 paralelno) ──');
const MIX = [
  { w: 30, mk: () => get('partners?select=id,name,type,hh_active,hh_date,lat,lng&type=in.(restaurant,hotel)&partner_code=like.TST_*&is_active=eq.true') },
  { w: 20, mk: () => get('partner_content?select=partner_id,current_offer,offer_expires_at&current_offer=not.is.null&limit=500') },
  { w: 15, mk: () => get('partners?select=id,lat,lng,hh_active&lat=gte.43.59&lat=lte.43.65&lng=gte.20.86&lng=lte.20.93&partner_code=like.TST_*') },
  { w: 10, mk: () => get(`events?select=id,title,event_date&title=like.TEST*&event_date=gte.${TODAY}&limit=200`) },
  { w: 10, mk: () => get('accommodation_listings?select=id,partner_id,title,price_per_night&is_active=eq.true&limit=400') },
  { w: 15, mk: () => get(`guests?select=id,accommodation_id&token=like.TESTGUEST_*&checkin_date=eq.${TODAY}&limit=1000`) },
];
const queue = Array.from({ length: 400 }, () => {
  const r = Math.random() * 100; let acc = 0;
  for (const k of MIX) { acc += k.w; if (r < acc) return k; }
  return MIX[MIX.length - 1];
});
const lat = []; let okN = 0, failN = 0, idx = 0;
const tStart = performance.now();
await Promise.all(Array.from({ length: 25 }, async () => {
  while (idx < queue.length) {
    const k = queue[idx++];
    try {
      const r = await k.mk();
      if (r.status < 400) okN++; else failN++;
      lat.push(r.ms);
    } catch { failN++; }
  }
}));
const secs = (performance.now() - tStart) / 1000;
const pct = (arr, p) => { const s = [...arr].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.ceil(p / 100 * s.length) - 1)] || 0; };
const p95 = Math.round(pct(lat, 95));
console.log(`   uspešno ${okN}/400 · p50 ${Math.round(pct(lat, 50))} ms · p95 ${p95} ms · ${(400 / secs).toFixed(1)} zahteva/s`);
check('Uspešnost opterećenja ≥ 99%', okN / 400 >= 0.99, `${((okN / 400) * 100).toFixed(1)}%`);
check('p95 latencija ≤ 1500 ms', p95 <= 1500, `${p95} ms`);

// ── Rezime ────────────────────────────────────────────────────────
const failed = results.filter(r => !r.pass);
console.log(`\n═══ REZULTAT: ${results.length - failed.length}/${results.length} prošlo ═══`);
if (failed.length) {
  console.log('Palo:');
  failed.forEach(f => console.log(' - ' + f.name + (f.detail ? ' (' + f.detail + ')' : '')));
}
process.exitCode = failed.length ? 1 : 0;
