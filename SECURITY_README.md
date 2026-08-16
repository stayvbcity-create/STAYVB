# StayVB v2 — Bezbednosno uputstvo za postavljanje

## Redosled fajlova pre deploy-a

### 1. Supabase podešavanja

**Dashboard → Settings → API:**
- Kopiraj `Project URL` i `anon/public` ključ
- **NIKADA** ne koristiti `service_role` ključ u HTML fajlovima
- Klikni "Regenerate" ako si ključ ikad delio javno

**Dashboard → Settings → API → CORS:**
- Allowed origins: `https://TVOJ-DOMEN.com`
- Ukloni `*` (wildcard) ako postoji

**Dashboard → Authentication → Rate Limits:**
- Postavi rate limit na RPC pozive

---

### 2. config.js — obavezne izmene

Otvori `config.js` i zameni:

```js
const SUPABASE_URL = 'https://TVOJ_PROJEKAT.supabase.co';
const SUPABASE_ANON_KEY = 'TVOJ_ANON_KLJUC';
const APP_URL = 'https://TVOJ_DOMEN.com';
const ADMIN_EMAIL = 'tvoj-admin@email.com';
```

**Admin nalog (od v2.2 — pravi Supabase Auth, ne lokalni hash):**
1. Supabase Dashboard → Authentication → Users → Add User
2. Unesi email (mora se poklapati sa `ADMIN_EMAIL` u config.js) i lozinku, čekiraj "Auto Confirm User"
3. Pokreni `security_hardening_v2.sql` (ako već nije pokrenut) — on dodaje taj email u `admin_users` tabelu preko koje RLS politike prepoznaju admina
4. Dashboard → Authentication → Sign In / Providers → Email → isključi "Allow new users to sign up" (da niko ne može sam da napravi authenticated nalog)

**Promena admin lozinke:** Dashboard → Authentication → Users → izaberi nalog → Reset Password (ili obriši i napravi novi sa istim emailom).

---

### 3. Redosled script tagova u svakom HTML fajlu

```html
<!-- 1. Supabase JS (mora biti prvi) -->
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>

<!-- 2. Config (ključevi i helperi) -->
<script src="config.js"></script>

<!-- 3. Security guard (zaštita stranica) -->
<script src="security-guard.js"></script>

<!-- 4. Lang init (Google Translate) -->
<script src="lang-init.js"></script>

<!-- 5. Tailwind i ostalo -->
<script src="https://cdn.tailwindcss.com"></script>
```

---

### 4. Kako koristiti zaštitu na stranicama

**partner.html** — na vrhu `<script>` bloka:
```js
window.addEventListener('DOMContentLoaded', function() {
    const token = StayVBGuard.requirePartner();
    if (!token) return; // stranica je blokirana
    // ostatak inicijalizacije...
});
```

**admin.html** — na vrhu `<script>` bloka:
```js
window.addEventListener('DOMContentLoaded', function() {
    StayVBGuard.requireAdmin(function() {
        initAdminPanel(); // poziva se tek posle uspešnog logina
    });
});
```

---

### 5. Kako generisati partner URL u admin panelu

Admin panel poziva SQL funkciju:
```js
const { data } = await C.db().rpc('admin_create_partner', {
    p_name: 'Restoran Primer',
    p_type: 'restaurant',
    p_pin: '4521',
    p_partner_code: 'REST_PRIMER',
    p_phone: '+381641234567'
});

// data[0].partner_url = 'partner.html?t=abc123xyz...'
// Admin kopira/šalje ovaj URL partneru
```

Za regenerisanje tokena (ako je partner izgubio link):
```js
const { data } = await C.db().rpc('regenerate_partner_token', {
    p_partner_id: 'uuid-partnera'
});
// data = novi token
// novi URL: C.partnerUrl(data)
```

---

### 6. Šta je zaštićeno

| Napad | Zaštita |
|-------|---------|
| Neko vidi anon ključ u DevTools | RLS politike na svim tabelama — bez prava nema pristupa |
| Brute force PIN-a | `partner_login()` blokira posle 5 pokušaja, `pg_sleep` usporava |
| Pristup tuđem partner panelu | Token u URL-u je jedinstven + PIN potvrda |
| Čitanje PIN-ova/tokena iz baze | `pin`/`access_token` kolone nisu čitljive za anon ulogu (column-level GRANT), samo `partner_login()` (SECURITY DEFINER) ih koristi interno |
| XSS napad | `C.escapeHtml()` na svim korisničkim podacima pre prikaza |
| Admin bez lozinke | Pravi Supabase Auth login (email+lozinka), sessionStorage sesija (važi 4h) |
| Admin sesija ostaje otvorena | Auto-expire posle 4h neaktivnosti |
| Poziv admin funkcija (kreiranje partnera, promena tokena, naplata) bez logina | Svaka admin RPC funkcija proverava `is_admin()` unutar baze pre izvršavanja, nezavisno od front-end provere |

---

### 7. Šta NIJE zaštićeno (i zašto je ok)

- **Anon ključ je vidljiv** — to je normalno za Supabase, dizajniran je da bude javan
- **Partner URL sadrži token** — token je nasumičan string od 24 karaktera (2^144 kombinacija), praktično nemoguće pogoditi
- **Guest token u localStorage** — gost nema privilegovani pristup, samo piše pečate i rezervacije

---

### 8. Fajlovi sistema i njihove zavisnosti

```
config.js          ← MORA biti učitan pre svega
security-guard.js  ← zavisi od config.js
lang-init.js       ← nezavisan
index.html         ← config.js, lang-init.js
stamp.html         ← config.js, lang-init.js
happy-hour.html    ← config.js, lang-init.js
radar.html         ← config.js, lang-init.js
dogadjaji.html     ← config.js, lang-init.js
atrakcije.html     ← config.js, lang-init.js
share.html         ← config.js, lang-init.js
partner.html       ← config.js, security-guard.js, lang-init.js
admin.html         ← config.js, security-guard.js, lang-init.js
```
