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

-- RLS politike filtriraju REDOVE, ali osnovni GRANT na tabelu mora
-- postojati da bi anon/authenticated uopšte smeli da pokušaju upit
-- (bez ovoga Postgres vraća "permission denied for table" pre nego
-- sto RLS dodje na red).
GRANT SELECT ON public.app_settings TO anon;
GRANT SELECT, INSERT, UPDATE ON public.app_settings TO authenticated;

INSERT INTO public.app_settings(key, value) VALUES ('android_apk_enabled', true)
ON CONFLICT (key) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ app_settings.sql
-- ═══════════════════════════════════════════════════════════════════
