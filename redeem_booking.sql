-- ═══════════════════════════════════════════════════════════════════
-- redeem_booking.sql — realizacija rezervacije ide ISKLJUČIVO kroz
-- funkciju koja u bazi proverava da skenirajući token pripada atrakciji
-- čiji je resurs u rezervaciji.
--
-- Pre ove izmene anon ključ (javan u browseru) mogao je direktno da
-- menja bookings.redeemed_at i accommodation_id — bilo čiju rezervaciju,
-- uz mogućnost da lažno veže apartman i izazove proviziju.
--
-- Pokreni jednom u Supabase SQL editoru.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Ukini direktno pisanje anon-a u bookings (zadržavamo samo
--    otkazivanje statusa koje koristi panel partnera, i INSERT koji
--    koristi guest rezervacija).
REVOKE UPDATE ON public.bookings FROM anon;
REVOKE UPDATE (accommodation_id, redeemed_at) ON public.bookings FROM anon;
GRANT UPDATE (status) ON public.bookings TO anon;

-- 2. Jedina ulazna tačka za realizaciju.
CREATE OR REPLACE FUNCTION public.redeem_booking(p_scanner_token text, p_booking_id uuid)
RETURNS TABLE(ok boolean, guest_name text, resource_name text, msg text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_partner_id uuid;
    v_b record;
BEGIN
    SELECT p.id INTO v_partner_id
    FROM public.partners p
    WHERE p.scanner_token = p_scanner_token
      AND p.is_active = true
      AND p.type = 'attraction';

    IF v_partner_id IS NULL THEN
        RETURN QUERY SELECT false, NULL::text, NULL::text, 'Nevažeći link.'::text;
        RETURN;
    END IF;

    SELECT b.guest_name, b.status, b.redeemed_at, r.name AS rname, r.partner_id AS rpartner
    INTO v_b
    FROM public.bookings b
    JOIN public.bookable_resources r ON r.id = b.resource_id
    WHERE b.id = p_booking_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT false, NULL::text, NULL::text, 'Kod nije prepoznat.'::text;
        RETURN;
    END IF;

    IF v_b.rpartner <> v_partner_id THEN
        RETURN QUERY SELECT false, NULL::text, NULL::text, 'Ova rezervacija ne pripada ovom biznisu.'::text;
        RETURN;
    END IF;

    IF v_b.status = 'cancelled' THEN
        RETURN QUERY SELECT false, v_b.guest_name, v_b.rname, 'Rezervacija je otkazana.'::text;
        RETURN;
    END IF;

    IF v_b.redeemed_at IS NOT NULL THEN
        RETURN QUERY SELECT false, v_b.guest_name, v_b.rname,
            ('Kod je već iskorišćen: ' || to_char(v_b.redeemed_at AT TIME ZONE 'Europe/Belgrade', 'DD.MM.YYYY HH24:MI'))::text;
        RETURN;
    END IF;

    UPDATE public.bookings SET redeemed_at = now()
    WHERE id = p_booking_id AND redeemed_at IS NULL;

    RETURN QUERY SELECT true, v_b.guest_name, v_b.rname, 'Realizovano'::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.redeem_booking(text, uuid) TO anon;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ redeem_booking.sql
-- ═══════════════════════════════════════════════════════════════════
