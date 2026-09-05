-- ═══════════════════════════════════════════════════════════════════
-- app_settings — jednostavna key/value tabela za globalne prekidače
-- aplikacije (npr. uključi/isključi Android APK instalaciju).
-- Pokreni jednom u Supabase SQL editoru.
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.app_settings (
    key   TEXT PRIMARY KEY,
    value BOOLEAN NOT NULL
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_settings_select_public ON public.app_settings;
DROP POLICY IF EXISTS app_settings_all_admin ON public.app_settings;

-- Svi (anon) smeju samo da čitaju — index.html na osnovu ovoga odlučuje
-- da li da nudi Android APK instalaciju.
CREATE POLICY app_settings_select_public ON public.app_settings
    FOR SELECT TO anon USING (true);

-- Samo admin (admin.html, prijavljen kroz Supabase Auth) sme da menja.
CREATE POLICY app_settings_all_admin ON public.app_settings
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

INSERT INTO public.app_settings(key, value) VALUES ('android_apk_enabled', true)
ON CONFLICT (key) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ app_settings.sql
-- ═══════════════════════════════════════════════════════════════════
