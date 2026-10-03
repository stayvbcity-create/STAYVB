-- ═══════════════════════════════════════════════════════════════════
-- booking_details.sql — šta rezervacija obuhvata, cena, i pregled
-- rezervacije na skeneru (ime gosta, stavka, cena, odakle gost dolazi)
-- pre nego što atrakcija potvrdi realizaciju.
--
-- Pokreni jednom u Supabase SQL editoru.
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.bookable_resources
    ADD COLUMN IF NOT EXISTS description text,
    ADD COLUMN IF NOT EXISTS price_rsd integer NOT NULL DEFAULT 0;

-- Pregled rezervacije za skener (samo čitanje, bez promene stanja)
CREATE OR REPLACE FUNCTION public.booking_preview(p_scanner_token text, p_booking_id uuid)
RETURNS TABLE(
    ok boolean,
    msg text,
    guest_name text,
    booking_date text,
    slot_time text,
    qty integer,
    resource_name text,
    description text,
    unit_price integer,
    total integer,
    accommodation_name text
)
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
    WHERE p.scanner_token = p_scanner_token AND p.is_active = true AND p.type = 'attraction';

    IF v_partner_id IS NULL THEN
        RETURN QUERY SELECT false, 'Nevažeći link.'::text, NULL::text, NULL::text, NULL::text,
            NULL::integer, NULL::text, NULL::text, NULL::integer, NULL::integer, NULL::text;
        RETURN;
    END IF;

    SELECT b.guest_name, b.booking_date::text AS bdate, substring(b.slot_time::text, 1, 5) AS bslot,
           b.qty, b.status, b.redeemed_at,
           r.name AS rname, r.description AS rdesc, r.price_rsd AS rprice, r.partner_id AS rpartner,
           a.name AS aname
    INTO v_b
    FROM public.bookings b
    JOIN public.bookable_resources r ON r.id = b.resource_id
    LEFT JOIN public.partners a ON a.id = b.accommodation_id
    WHERE b.id = p_booking_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT false, 'Kod nije prepoznat.'::text, NULL::text, NULL::text, NULL::text,
            NULL::integer, NULL::text, NULL::text, NULL::integer, NULL::integer, NULL::text;
        RETURN;
    END IF;

    IF v_b.rpartner <> v_partner_id THEN
        RETURN QUERY SELECT false, 'Ova rezervacija ne pripada ovom biznisu.'::text, NULL::text, NULL::text, NULL::text,
            NULL::integer, NULL::text, NULL::text, NULL::integer, NULL::integer, NULL::text;
        RETURN;
    END IF;

    RETURN QUERY SELECT
        (v_b.status <> 'cancelled' AND v_b.redeemed_at IS NULL),
        CASE
            WHEN v_b.status = 'cancelled' THEN 'Rezervacija je otkazana.'
            WHEN v_b.redeemed_at IS NOT NULL THEN 'Kod je već iskorišćen: ' || to_char(v_b.redeemed_at AT TIME ZONE 'Europe/Belgrade', 'DD.MM.YYYY HH24:MI')
            ELSE 'Spremno za realizaciju'
        END::text,
        v_b.guest_name, v_b.bdate, v_b.bslot, v_b.qty, v_b.rname, v_b.rdesc,
        v_b.rprice, (v_b.rprice * v_b.qty)::integer, v_b.aname;
END;
$$;

GRANT EXECUTE ON FUNCTION public.booking_preview(text, uuid) TO anon;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ booking_details.sql
-- ═══════════════════════════════════════════════════════════════════
