/**
 * StayVB v2 — security-guard.js
 * ═══════════════════════════════════════════════════════════════════
 * Štiti stranice koje zahtevaju login.
 * Uključuje se ODMAH posle config.js, pre svega drugog.
 *
 * Upotreba:
 *
 *   Na partner.html:
 *     StayVBGuard.requirePartner();
 *
 *   Na admin.html:
 *     StayVBGuard.requireAdmin();
 *
 * Ako uslov nije ispunjen — stranica se blokira i prikazuje login.
 * ═══════════════════════════════════════════════════════════════════
 */

window.StayVBGuard = (function () {

    // ── Partner zaštita ────────────────────────────────────────────
    // Poziva se na partner.html pri učitavanju
    // Vraća token iz URL-a ili null ako ne postoji
    function requirePartner() {
        const token = C.getPartnerToken();

        if (!token || token.length < 10) {
            _blockPage(
                '🔒 Nevažeći link',
                'Ovaj link je nevažeći ili je istekao.',
                'Kontaktirajte administratora za novi link.',
                false
            );
            return null;
        }

        return token;
    }

    // ── Admin zaštita ──────────────────────────────────────────────
    // Poziva se na admin.html pri učitavanju
    // Ako nema sesije — prikazuje login formu
    function requireAdmin(onSuccess) {
        if (C.checkAdminSession()) {
            if (onSuccess) onSuccess();
            return true;
        }
        _showAdminLogin(onSuccess);
        return false;
    }

    // ── Admin login forma ──────────────────────────────────────────
    function _showAdminLogin(onSuccess) {
        const overlay = document.createElement('div');
        overlay.id = 'admin-login-overlay';
        overlay.style.cssText = `
            position: fixed; inset: 0; z-index: 9999;
            background: #0f172a;
            display: flex; align-items: center; justify-content: center;
            font-family: 'Inter', sans-serif;
        `;

        overlay.innerHTML = `
            <div style="
                background: #1e293b;
                border: 1px solid rgba(251,191,36,0.20);
                border-radius: 2rem;
                padding: 2.5rem 2rem;
                width: 100%;
                max-width: 340px;
                text-align: center;
            ">
                <div style="font-size: 2.5rem; margin-bottom: 1rem;">🔐</div>
                <h2 style="
                    color: #fbbf24;
                    font-size: 1.1rem;
                    font-weight: 900;
                    letter-spacing: 0.08em;
                    text-transform: uppercase;
                    margin: 0 0 0.5rem;
                ">Admin Pristup</h2>
                <p style="
                    color: rgba(255,255,255,0.4);
                    font-size: 11px;
                    font-weight: 700;
                    text-transform: uppercase;
                    letter-spacing: 0.14em;
                    margin: 0 0 2rem;
                ">StayVB God Mode</p>

                <input
                    type="password"
                    id="admin-pwd-input"
                    placeholder="Unesite lozinku"
                    autocomplete="current-password"
                    style="
                        width: 100%;
                        padding: 1rem 1.25rem;
                        background: rgba(255,255,255,0.06);
                        border: 1px solid rgba(255,255,255,0.10);
                        border-radius: 1rem;
                        color: white;
                        font-size: 14px;
                        font-weight: 700;
                        font-family: inherit;
                        text-align: center;
                        letter-spacing: 0.1em;
                        outline: none;
                        margin-bottom: 1rem;
                    "
                >

                <p id="admin-err" style="
                    color: #f87171;
                    font-size: 11px;
                    font-weight: 800;
                    min-height: 18px;
                    margin: 0 0 1rem;
                    display: none;
                "></p>

                <button
                    id="admin-login-btn"
                    onclick="StayVBGuard._submitAdminLogin()"
                    style="
                        width: 100%;
                        padding: 1rem;
                        background: linear-gradient(135deg, #d97706, #f59e0b);
                        color: #0f172a;
                        border: none;
                        border-radius: 1rem;
                        font-size: 12px;
                        font-weight: 900;
                        text-transform: uppercase;
                        letter-spacing: 0.12em;
                        cursor: pointer;
                        font-family: inherit;
                    "
                >Prijavi se →</button>

                <p style="
                    margin-top: 1.5rem;
                    font-size: 9px;
                    color: rgba(255,255,255,0.2);
                    font-weight: 700;
                    letter-spacing: 0.12em;
                    text-transform: uppercase;
                ">StayVB v2 · Zaštićen pristup</p>
            </div>
        `;

        document.body.appendChild(overlay);

        // Enter key
        const input = document.getElementById('admin-pwd-input');
        if (input) {
            input.addEventListener('keydown', function (e) {
                if (e.key === 'Enter') StayVBGuard._submitAdminLogin();
            });
            setTimeout(() => input.focus(), 100);
        }

        // Čuvamo callback
        window._adminLoginCallback = onSuccess || null;
    }

    // Poziva se klikom na dugme (mora biti globalna jer je u innerHTML)
    async function _submitAdminLogin() {
        const input = document.getElementById('admin-pwd-input');
        const errEl = document.getElementById('admin-err');
        const btn   = document.getElementById('admin-login-btn');

        if (!input || !errEl || !btn) return;

        const pwd = input.value.trim();
        if (!pwd) {
            errEl.textContent = 'Unesite lozinku.';
            errEl.style.display = 'block';
            return;
        }

        btn.textContent = 'Provjera...';
        btn.disabled = true;

        // Simuliramo kratko kašnjenje (sprečava timing napade)
        await new Promise(r => setTimeout(r, 600));

        const ok = await C.verifyAdmin(pwd);

        if (ok) {
            C.setAdminSession();
            const overlay = document.getElementById('admin-login-overlay');
            if (overlay) overlay.remove();
            if (window._adminLoginCallback) window._adminLoginCallback();
        } else {
            errEl.textContent = 'Pogrešna lozinka. Pokušajte ponovo.';
            errEl.style.display = 'block';
            input.value = '';
            input.focus();
            btn.textContent = 'Prijavi se →';
            btn.disabled = false;
        }
    }

    // ── Blokada stranice ───────────────────────────────────────────
    function _blockPage(title, message, sub, showBack) {
        document.body.innerHTML = `
            <div style="
                min-height: 100vh;
                display: flex;
                flex-direction: column;
                align-items: center;
                justify-content: center;
                background: #0f172a;
                font-family: 'Inter', sans-serif;
                padding: 2rem;
                text-align: center;
            ">
                <div style="font-size: 3rem; margin-bottom: 1.5rem;">🔒</div>
                <h1 style="
                    color: #f87171;
                    font-size: 1.2rem;
                    font-weight: 900;
                    margin: 0 0 0.75rem;
                ">${StayVBGuard._esc(title)}</h1>
                <p style="
                    color: rgba(255,255,255,0.6);
                    font-size: 13px;
                    font-weight: 600;
                    margin: 0 0 0.5rem;
                    max-width: 280px;
                ">${StayVBGuard._esc(message)}</p>
                <p style="
                    color: rgba(255,255,255,0.35);
                    font-size: 11px;
                    font-weight: 700;
                    margin: 0 0 2rem;
                ">${StayVBGuard._esc(sub)}</p>
                ${showBack !== false ? `
                    <a href="index.html" style="
                        padding: 0.75rem 1.5rem;
                        background: rgba(255,255,255,0.06);
                        border: 1px solid rgba(255,255,255,0.10);
                        border-radius: 1rem;
                        color: rgba(255,255,255,0.6);
                        font-size: 11px;
                        font-weight: 900;
                        text-decoration: none;
                        text-transform: uppercase;
                        letter-spacing: 0.12em;
                    ">← Nazad</a>
                ` : ''}
            </div>
        `;
    }

    // Siguran escaping za _blockPage (C možda još nije inicijalizovan)
    function _esc(str) {
        return String(str || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
    }

    // ── Logout helperi ─────────────────────────────────────────────
    function logoutAdmin() {
        C.clearAdminSession();
        window.location.href = 'admin.html';
    }

    function logoutPartner() {
        C.clearPartnerSession();
        const token = C.getPartnerToken();
        // Ostajemo na istom URL-u (token ostaje u URL-u) ali brišemo sesiju
        window.location.reload();
    }

    return {
        requirePartner,
        requireAdmin,
        logoutAdmin,
        logoutPartner,
        _submitAdminLogin,
        _blockPage,
        _esc,
    };

})();
