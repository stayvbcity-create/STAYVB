/* StayVB v2 — config.js — v2.1 */
window.STAYVB_CONFIG = (function () {

    const SUPABASE_URL = 'https://zapmsxvwxjeoglpzldhl.supabase.co';
    const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InphcG1zeHZ3eGplb2dscHpsZGhsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMjY4NDQsImV4cCI6MjA5NjcwMjg0NH0.szTiMlsQJZCgbFE89eRn1YIN133smnEkPhVmcaVmGqM';
    const APP_URL = 'https://vb.staytag.rs';
    const PARTNER_PANEL_URL = APP_URL + '/partner.html';
    const STAMP_URL = APP_URL + '/stamp.html';
    const LOYALTY_GOAL = 10;
    const GUEST_EXPIRY_DAYS = 14;
    const ADMIN_HASH = 'd923beddc6b3a0112d357d097d9f873f95ea0464acd09020829b3a3c2bd6fa7e';
    const SAFE_PARTNER_COLUMNS = `id, name, type, is_premium, is_active, loyalty_enabled, has_booking, hh_active, hh_date, hh_start, hh_end, partner_code, lat, lng, phone, whatsapp, created_at`;

    let _sb = null;
    function getClient() {
        if (!_sb) {
            if (typeof supabase === 'undefined') { console.error('Supabase JS nije učitan.'); return null; }
            _sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { persistSession: false } });
        }
        return _sb;
    }

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

    function setAdminSession() {
        sessionStorage.setItem('stayvb_admin', '1');
        sessionStorage.setItem('stayvb_admin_ts', Date.now().toString());
    }

    function checkAdminSession() {
        const ts = parseInt(sessionStorage.getItem('stayvb_admin_ts') || '0');
        const age = Date.now() - ts;
        if (sessionStorage.getItem('stayvb_admin') === '1' && age < 4 * 60 * 60 * 1000) return true;
        clearAdminSession();
        return false;
    }

    function clearAdminSession() {
        sessionStorage.removeItem('stayvb_admin');
        sessionStorage.removeItem('stayvb_admin_ts');
    }

    function getPartnerToken() {
        return new URLSearchParams(window.location.search).get('t') || '';
    }

    async function partnerLogin(token, pin) {
        const sb = getClient();
        if (!sb) return { ok: false, error: 'Konekcija nije dostupna' };
        if (!token || token.length < 10) return { ok: false, error: 'Nevažeći link.' };
        if (!pin || pin.length < 4) return { ok: false, error: 'Unesite PIN.' };
        const { data, error } = await sb.rpc('partner_login', { p_token: token, p_pin: pin });
        if (error) return { ok: false, error: 'Greška pri prijavi.' };
        if (!data || data.length === 0) return { ok: false, error: 'Nevažeći link ili PIN.' };
        const result = data[0];
        if (!result.login_ok) return { ok: false, error: result.error_msg || 'Pogrešan PIN.' };
        sessionStorage.setItem('stayvb_partner', JSON.stringify({ id: result.id, name: result.name, type: result.type, token: token, ts: Date.now() }));
        return { ok: true, partner: result };
    }

    function getPartnerSession() {
        try {
            const raw = sessionStorage.getItem('stayvb_partner');
            if (!raw) return null;
            const s = JSON.parse(raw);
            if (Date.now() - (s.ts || 0) > 8 * 60 * 60 * 1000) { sessionStorage.removeItem('stayvb_partner'); return null; }
            return s;
        } catch { return null; }
    }

    function clearPartnerSession() { sessionStorage.removeItem('stayvb_partner'); }

    function getOrCreateGuestToken() {
        let token = localStorage.getItem('stayvb_guest_token');
        if (!token) {
            token = 'g_' + Date.now() + '_' + Math.random().toString(36).substring(2, 15);
            localStorage.setItem('stayvb_guest_token', token);
        }
        return token;
    }

    function partnerUrl(accessToken) { return PARTNER_PANEL_URL + '?t=' + encodeURIComponent(accessToken); }
    function stampUrl(partnerCode) { return STAMP_URL + '?code=' + encodeURIComponent(partnerCode); }

    async function trackAction(partnerId, guestId, action) {
        const sb = getClient();
        if (!sb) return;
        try {
            await sb.from('analytics_clicks').insert({ partner_id: partnerId || null, guest_id: guestId || null, action: action, device_type: /Mobi|Android/i.test(navigator.userAgent) ? 'mobile' : 'desktop' });
        } catch { }
    }

    function escapeHtml(str) {
        return String(str ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#x27;');
    }

    return {
        db: getClient,
        APP_URL, LOYALTY_GOAL, GUEST_EXPIRY_DAYS, SAFE_PARTNER_COLUMNS,
        verifyAdmin, hashPassword,
        setAdminSession, checkAdminSession, clearAdminSession,
        getPartnerToken, partnerLogin, getPartnerSession, clearPartnerSession,
        getOrCreateGuestToken,
        partnerUrl, stampUrl,
        trackAction, escapeHtml,
    };
})();

window.C = window.STAYVB_CONFIG;
