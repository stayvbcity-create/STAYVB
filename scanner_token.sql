-- ═══════════════════════════════════════════════════════════════════
-- scanner_token.sql — odvojen, ograničen pristup za SKENIRANJE kodova,
-- nezavisan od glavnog pristupa vlasnika atrakcije (access_token).
--
-- Vlasnik ovaj link daje radniku (npr. šalje na telefon) — radnik
-- njime otvara SAMO kameru za skeniranje, bez pristupa cenama,
-- podešavanju provizije, ili bilo čemu drugom iz panela. Vlasnik u
-- svakom trenutku može da regeneriše link (stari odmah prestaje da
-- radi), bez da to utiče na njegov sopstveni pristup panelu.
--
-- Isti bezbednosni obrazac kao partner_login() — scanner_token se
-- NIKAD ne izlaže kroz običan SELECT grant (anon ne sme da ga čita
-- iz tabele direktno, samo kroz ove funkcije), da ne bi neko mogao
-- da pokupi tuđe tokene masovnim upitom.
--
-- Pokreni jednom u Supabase SQL editoru.
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.partners ADD COLUMN IF NOT EXISTS scanner_token text UNIQUE;

-- ── Radnik otvara scan.html?s=<scanner_token> — ova funkcija to proverava
CREATE OR REPLACE FUNCTION public.scanner_login(p_scanner_token text)
RETURNS TABLE(id uuid, name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT p.id, p.name
    FROM public.partners p
    WHERE p.scanner_token = p_scanner_token
      AND p.is_active = true
      AND p.type = 'attraction';
END;
$$;

-- ── Vlasnik (dokazuje se svojim access_token-om iz partner.html
--    sesije) vidi svoj trenutni link za radnika
CREATE OR REPLACE FUNCTION public.get_scanner_token(p_access_token text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_token text;
BEGIN
    SELECT scanner_token INTO v_token FROM public.partners
    WHERE access_token = p_access_token AND is_active = true AND type = 'attraction';
    RETURN v_token;
END;
$$;

-- ── Vlasnik generiše NOV link — stari odmah prestaje da radi
--    (npr. kad radnik ode, ili posumnja da je link procureo)
CREATE OR REPLACE FUNCTION public.regenerate_scanner_token(p_access_token text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_new text;
BEGIN
    -- gen_random_uuid() je ugrađen u Postgres (za razliku od gen_random_bytes
    -- koji zahteva pgcrypto ekstenziju) — dve spojene UUID vrednosti daju
    -- dovoljno entropije za ovaj token.
    v_new := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
    UPDATE public.partners SET scanner_token = v_new
    WHERE access_token = p_access_token AND is_active = true AND type = 'attraction';
    IF NOT FOUND THEN RETURN NULL; END IF;
    RETURN v_new;
END;
$$;

GRANT EXECUTE ON FUNCTION public.scanner_login(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_scanner_token(text) TO anon;
GRANT EXECUTE ON FUNCTION public.regenerate_scanner_token(text) TO anon;

-- Namerno NEMA GRANT SELECT na scanner_token kolonu za anon — jedini
-- način da se do nje dođe je kroz gornje funkcije.

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ scanner_token.sql
-- ═══════════════════════════════════════════════════════════════════
