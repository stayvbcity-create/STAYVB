/**
 * StayVB — lang-init.js
 * ─────────────────────────────────────────────────────────────────
 * Uključi ovaj fajl u SVAKU stranicu sistema PRE Google Translate
 * skripte. Automatski primenjuje sačuvani jezik gosta.
 *
 * Kako dodati u stranicu (kopirati u <head>, pre </head>):
 *
 *   <script src="lang-init.js"></script>
 *   <script>
 *     function googleTranslateElementInit() {
 *       new google.translate.TranslateElement({
 *         pageLanguage: 'sr',
 *         includedLanguages: 'en,de,ru,bg,zh-CN',
 *         autoDisplay: false
 *       }, 'google_translate_element');
 *       STAYVB_LANG.onWidgetReady();
 *     }
 *   </script>
 *   <script src="//translate.google.com/translate_a/element.js?cb=googleTranslateElementInit"></script>
 *
 * U <body> dodati (može biti display:none):
 *   <div id="google_translate_element" style="display:none"></div>
 *
 * CSS koji treba dodati (sakrij GT toolbar):
 *   .goog-te-banner-frame, .skiptranslate { display:none!important; }
 *   body { top: 0 !important; }
 *   body.translated-ltr, body.translated-rtl { margin-top: 0 !important; }
 * ─────────────────────────────────────────────────────────────────
 */

window.STAYVB_LANG = (function () {

    var LS_KEY = 'stayvb_lang';

    var LANGS = {
        '':     { flag: '🇷🇸', label: 'Srpski',    native: 'Srpski'    },
        'en':   { flag: '🇬🇧', label: 'English',   native: 'English'   },
        'de':   { flag: '🇩🇪', label: 'Deutsch',   native: 'Deutsch'   },
        'ru':   { flag: '🇷🇺', label: 'Русский',   native: 'Русский'   },
        'bg':   { flag: '🇧🇬', label: 'Български', native: 'Български' },
        'zh-CN':{ flag: '🇨🇳', label: '中文',      native: '中文'      }
    };

    // Čita trenutni sačuvani jezik
    function get() {
        return localStorage.getItem(LS_KEY) || '';
    }

    // Postavlja GT cookie (koji GT čita pri učitavanju stranice)
    function applyGTCookie(langCode) {
        var exp = 'expires=Fri, 31 Dec 2099 23:59:59 GMT; path=/';
        if (!langCode) {
            // Srpski — briši cookie
            document.cookie = 'googtrans=; path=/; expires=Thu, 01 Jan 1970 00:00:00 UTC';
            document.cookie = 'googtrans=; path=/; domain=' + location.hostname + '; expires=Thu, 01 Jan 1970 00:00:00 UTC';
        } else {
            var val = '/sr/' + langCode;
            document.cookie = 'googtrans=' + val + '; ' + exp;
            document.cookie = 'googtrans=' + val + '; domain=' + location.hostname + '; ' + exp;
        }
    }

    // Primeni odmah pri učitavanju (pre GT widgeta) — GT čita cookie
    applyGTCookie(get());

    // Kad se GT widget učita — sinhronizuj select i zakači listener
    function onWidgetReady() {
        var saved = get();
        var attempt = 0;
        var interval = setInterval(function () {
            var sel = document.querySelector('.goog-te-combo');
            if (sel) {
                clearInterval(interval);
                // Postavi vrednost select-a na sačuvani jezik
                if (saved && sel.value !== saved) {
                    sel.value = saved;
                    sel.dispatchEvent(new Event('change', { bubbles: true }));
                }
                // Prati promene — ako korisnik menja jezik negde drugde
                sel.addEventListener('change', function () {
                    localStorage.setItem(LS_KEY, sel.value || '');
                    applyGTCookie(sel.value || '');
                    _updatePills(sel.value || '');
                });
            }
            if (++attempt > 40) clearInterval(interval); // max 4s
        }, 100);
    }

    // Programski postavi jezik (poziva se klikom na zastavu/pill)
    function set(langCode) {
        localStorage.setItem(LS_KEY, langCode);
        applyGTCookie(langCode);
        _updatePills(langCode);
        window.location.reload();
    }

    // Osvežava CSS klasu .active na lang pillama (ako postoje)
    function _updatePills(activeLang) {
        Object.keys(LANGS).forEach(function (code) {
            var id = 'langpill-' + (code === '' ? 'sr' : code);
            var el = document.getElementById(id);
            if (el) el.classList.toggle('active', code === activeLang);
        });
    }

    // Inicijalizuj pills čim je DOM spreman
    document.addEventListener('DOMContentLoaded', function () {
        _updatePills(get());
    });

    return {
        get: get,
        set: set,
        onWidgetReady: onWidgetReady,
        langs: LANGS
    };

})();
