/**
 * StayVB v2 — config.js
 * ═══════════════════════════════════════════════════════════════════
 * JEDINI fajl koji sadrži Supabase ključeve.
 * Uključuje se u SVE HTML stranice kao PRVI script tag:
 *
 *   <script src="config.js"></script>
 *
 * NAPOMENA O BEZBEDNOSTI:
 * ───────────────────────
 * SUPABASE_ANON_KEY je JAVNI ključ — dizajniran da bude vidljiv.
 * Prava zaštita je RLS (Row Level Security) u bazi, ne skrivanje ključa.
 * NIKADA ne stavljati service_role ključ ovde ili bilo gde u HTML/JS.
 *
 * ADMIN LOZINKA:
 * ──────────────
 * Nije sačuvana kao plain text — samo SHA-256 hash.
 * Promeni lozinku: otvori browser konzolu i ukucaj:
 *   stayvbConfig.hashPassword('novaLozinka').then(h => console.log(h))
 * Zatim zalepi hash u ADMIN_HASH ispod.
 * ═══════════════════════════════════════════════════════════════════
 */

window.STAYVB_CONFIG = (function () {

    // ── Supabase konekcija ─────────────────────────────────────────
    // ⚠️  ZAMENI sa svojim ključevima iz Supabase Dashboard → Settings → API
    const SUPABASE_URL = 'https://TVOJ_PROJEKAT.supabase.co';
    const SUPABASE_ANON_KEY = 'TVOJ_ANON_KLJUC';

    // ── Admin hash ─────────────────────────────────────────────────
    // SHA-256 hash admin lozinke
    // Default lozinka: StayVB2024!  (PROMENI PRE DEPLOY-a)
    // Kako generisati novi hash: pozovi hashPassword() u konzoli
    const ADMIN_HASH = 'd923beddc6b3a0112d357d097d9f873f95ea0464acd09020829b3a3c2bd6fa7e';

    // ── App podešavanja ────────────────────────────────────────────
    const APP_URL = 'https://TVOJ_DOMEN.com';   // bez trailing slash
    const PARTNER_PANEL_URL = APP_URL + '/partner.html';
    const STAMP_URL = APP_URL + '/stamp.html';

    // Loyalty: koliko pečata treba za nagradu
    const LOYALTY_GOAL = 10;

    // Guest token expiry (dani)
    const GUEST_EXPIRY_DAYS = 14;

    // Max PIN pokušaja pre blokade
    const MAX_PIN_ATTEMPTS = 5;

    // ── Privatni Supabase klijent ──────────────────────────────────
    // Kreira se jednom, koristi se svuda
    let _sb = null;

    function getClient() {
        if (!_sb) {
            if (typeof supabase === 'undefined') {
                console.error('StayVB: Supabase JS nije učitan. Dodaj script tag pre config.js.');
                return null;
            }
            _sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
                auth: { persistSession: false }  // ne čuvamo Supabase auth session
            });
        }
        return _sb;
    }

    // ── Admin autentifikacija ──────────────────────────────────────
    // Hashuje lozinku SHA-256 u browseru (bez slanja na server)
    async function hashPassword(password) {
        const msgBuffer = new TextEncoder().encode(password);
        const hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer);
        const hashArray = Array.from(new Uint8Array(hashBuffer));
        return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
    }

    async function verifyAdmin(password) {
        const hash = await hashPassword(password);
        return hash === ADMIN_HASH;
    }

    // Admin session u sessionStorage (važi samo dok je tab otvoren)
    function setAdminSession() {
        sessionStorage.setItem('stayvb_admin', '1');
        sessionStorage.setItem('stayvb_admin_ts', Date.now().toString());
    }

    function checkAdminSession() {
        const ts = parseInt(sessionStorage.getItem('stayvb_admin_ts') || '0');
        const age = Date.now() - ts;
        // Session važi 4 sata
        if (sessionStorage.getItem('stayvb_admin') === '1' && age < 4 * 60 * 60 * 1000) {
            return true;
        }
        clearAdminSession();
        return false;
    }

    function clearAdminSession() {
        sessionStorage.removeItem('stayvb_admin');
        sessionStorage.removeItem('stayvb_admin_ts');
    }

    // ── Partner autentifikacija ────────────────────────────────────
    // Čita token iz URL-a: partner.html?t=TOKEN
    function getPartnerToken() {
        return new URLSearchParams(window.location.search).get('t') || '';
    }

    // Login poziva SECURITY DEFINER funkciju u bazi
    // PIN nikad ne ide u direktan SELECT
    async function partnerLogin(token, pin) {
        const sb = getClient();
        if (!sb) return { ok: false, error: 'Konekcija nije dostupna' };

        if (!token || token.length < 10) {
            return { ok: false, error: 'Nevažeći link. Kontaktirajte administratora.' };
        }

        if (!pin || pin.length < 4) {
            return { ok: false, error: 'Unesite PIN (min 4 cifre).' };
        }

        const { data, error } = await sb.rpc('partner_login', {
            p_token: token,
            p_pin: pin
        });

        if (error) {
            console.error('Login RPC error:', error.message);
            return { ok: false, error: 'Greška pri prijavi. Pokušajte ponovo.' };
        }

        if (!data || data.length === 0) {
            return { ok: false, error: 'Nevažeći link ili PIN.' };
        }

        const result = data[0];

        if (!result.login_ok) {
            return { ok: false, error: result.error_msg || 'Pogrešan PIN.' };
        }

        // Sačuvaj partner sesiju u sessionStorage
        sessionStorage.setItem('stayvb_partner', JSON.stringify({
            id: result.id,
            name: result.name,
            type: result.type,
            token: token,
            ts: Date.now()
        }));

        return { ok: true, partner: result };
    }

    function getPartnerSession() {
        try {
            const raw = sessionStorage.getItem('stayvb_partner');
            if (!raw) return null;
            const s = JSON.parse(raw);
            const age = Date.now() - (s.ts || 0);
            // Partner sesija važi 8 sati
            if (age > 8 * 60 * 60 * 1000) {
                sessionStorage.removeItem('stayvb_partner');
                return null;
            }
            return s;
        } catch { return null; }
    }

    function clearPartnerSession() {
        sessionStorage.removeItem('stayvb_partner');
    }

    // ── Guest token ────────────────────────────────────────────────
    // UUID token koji identifikuje gostov uređaj, bez registracije
    function getOrCreateGuestToken() {
        let token = localStorage.getItem('stayvb_guest_token');
        if (!token) {
            token = 'g_' + Date.now() + '_' +
                    Math.random().toString(36).substring(2, 15);
            localStorage.setItem('stayvb_guest_token', token);
        }
        return token;
    }

    // ── URL helperi ────────────────────────────────────────────────
    // Generiše partner panel URL za dati token
    function partnerUrl(accessToken) {
        return PARTNER_PANEL_URL + '?t=' + encodeURIComponent(accessToken);
    }

    // Generiše QR stamp URL za dati partner_code
    function stampUrl(partnerCode) {
        return STAMP_URL + '?code=' + encodeURIComponent(partnerCode);
    }

    // ── Zajednički Supabase helperi ────────────────────────────────
    // Sigurno selektovanje — nikad ne selektuj pin, access_token
    const SAFE_PARTNER_COLUMNS = `
        id, name, type, is_premium, is_active,
        loyalty_enabled, has_booking,
        hh_active, hh_date, hh_start, hh_end,
        partner_code, lat, lng, phone, whatsapp,
        created_at
    `;

    // Analytics — tih poziv, ne blokira UI
    async function trackAction(partnerId, guestId, action) {
        const sb = getClient();
        if (!sb) return;
        try {
            await sb.from('analytics_clicks').insert({
                partner_id: partnerId || null,
                guest_id: guestId || null,
                action: action,
                device_type: /Mobi|Android/i.test(navigator.userAgent) ? 'mobile' : 'desktop'
            });
        } catch { /* tih fail — analytics nije kritično */ }
    }

    // ── XSS zaštita ───────────────────────────────────────────────
    function escapeHtml(str) {
        return String(str ?? '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#x27;');
    }

    // ── Javni API ──────────────────────────────────────────────────
    return {
        // Konekcija
        db: getClient,

        // Konstante
        APP_URL,
        LOYALTY_GOAL,
        GUEST_EXPIRY_DAYS,
        SAFE_PARTNER_COLUMNS,

        // Admin
        verifyAdmin,
        hashPassword,
        setAdminSession,
        checkAdminSession,
        clearAdminSession,

        // Partner
        getPartnerToken,
        partnerLogin,
        getPartnerSession,
        clearPartnerSession,

        // Gost
        getOrCreateGuestToken,

        // URL generatori
        partnerUrl,
        stampUrl,

        // Utils
        trackAction,
        escapeHtml,
    };

})();

// Kratki alias za lakše korišćenje
window.C = window.STAYVB_CONFIG;
