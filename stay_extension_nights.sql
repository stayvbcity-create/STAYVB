-- ═══════════════════════════════════════════════════════════════════
-- stay_extension_nights.sql — pitanje o broju noći sada se postavlja
-- odmah posle izbora jezika, pre nego što aplikacija učita sadržaj.
--
-- Zato funkcija mora da zna i kod objekta i da sama napravi gosta ako
-- red još ne postoji, jer se u tom trenutku gost još nije "upisao".
--
-- Pokreni jednom u Supabase SQL editoru (posle stay_extension.sql).
-- ═══════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.set_guest_checkout(text, integer);

CREATE OR REPLACE FUNCTION public.set_guest_checkout(
    p_guest_token text,
    p_nights integer,
    p_accommodation_code text DEFAULT NULL)
RETURNS date
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_acc uuid;
    v_date date;
BEGIN
    IF p_nights IS NULL OR p_nights < 1 OR p_nights > 60 THEN
        RAISE EXCEPTION 'Neispravan broj noći' USING ERRCODE = '22023';
    END IF;
    IF coalesce(p_guest_token, '') = '' THEN
        RAISE EXCEPTION 'Nedostaje token gosta' USING ERRCODE = '22023';
    END IF;

    IF p_accommodation_code IS NOT NULL THEN
        SELECT id INTO v_acc FROM public.partners
        WHERE partner_code = p_accommodation_code AND is_active = true
          AND type IN ('hotel','apartment');
    END IF;

    UPDATE public.guests
    SET checkout_date = COALESCE(checkin_date, CURRENT_DATE) + p_nights,
        accommodation_id = COALESCE(accommodation_id, v_acc)
    WHERE token = p_guest_token
    RETURNING checkout_date INTO v_date;

    IF v_date IS NULL THEN
        INSERT INTO public.guests (token, accommodation_id, checkin_date, checkout_date, lang)
        SELECT p_guest_token, v_acc, CURRENT_DATE, CURRENT_DATE + p_nights, 'sr'
        WHERE NOT EXISTS (SELECT 1 FROM public.guests WHERE token = p_guest_token);

        SELECT checkout_date INTO v_date FROM public.guests WHERE token = p_guest_token;
    END IF;

    RETURN v_date;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_guest_checkout(text, integer, text) TO anon;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ stay_extension_nights.sql
-- ═══════════════════════════════════════════════════════════════════
