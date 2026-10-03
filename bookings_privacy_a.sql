-- ═══════════════════════════════════════════════════════════════════
-- bookings_privacy_a.sql — KORAK 1 (pokreni PRE deploy-a novog koda).
--
-- Dodaje funkcije kojima gost čita svoje rezervacije i kreira rezervaciju
-- bez direktnog pristupa tabeli, i vlasničko čitanje rezervacija i provizija
-- (partner koji je poslao svoj token vidi samo svoje redove).
--
-- Ništa ne uklanja, pa je bezbedno pokrenuti i pre nego što novi kod bude
-- live. Korak 2 (bookings_privacy_b.sql) pokreće se TEK posle deploy-a.
-- ═══════════════════════════════════════════════════════════════════

-- Gost vidi SVOJE aktivne rezervacije (po svom guest_token)
CREATE OR REPLACE FUNCTION public.guest_active_bookings(p_guest_token text)
RETURNS TABLE(id uuid, booking_date date, slot_time text, qty integer,
              resource_name text, description text, price_rsd integer,
              partner_id uuid, partner_name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT b.id, b.booking_date, substring(b.slot_time::text, 1, 5), b.qty,
           r.name, r.description, r.price_rsd, r.partner_id, p.name
    FROM public.bookings b
    JOIN public.guests g ON g.id = b.guest_id AND g.token = p_guest_token
    JOIN public.bookable_resources r ON r.id = b.resource_id
    JOIN public.partners p ON p.id = r.partner_id
    WHERE b.status = 'confirmed' AND b.redeemed_at IS NULL
    ORDER BY b.created_at DESC
$$;

-- Gost kreira rezervaciju (validacija na serveru)
CREATE OR REPLACE FUNCTION public.create_guest_booking(
    p_resource_id uuid, p_guest_token text, p_accommodation_id uuid,
    p_date date, p_slot text, p_qty integer, p_name text, p_phone text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_guest uuid;
    v_id uuid;
BEGIN
    IF p_qty IS NULL OR p_qty < 1 OR p_qty > 20 THEN
        RAISE EXCEPTION 'Neispravna količina' USING ERRCODE = '22023';
    END IF;
    IF coalesce(trim(p_name), '') = '' OR coalesce(trim(p_phone), '') = '' THEN
        RAISE EXCEPTION 'Nedostaju podaci gosta' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.bookable_resources WHERE id = p_resource_id AND is_active) THEN
        RAISE EXCEPTION 'Termin nije aktivan' USING ERRCODE = '22023';
    END IF;

    SELECT g.id INTO v_guest FROM public.guests g WHERE g.token = p_guest_token;

    INSERT INTO public.bookings (resource_id, guest_id, accommodation_id, booking_date, slot_time,
                                 qty, guest_name, guest_phone, status)
    VALUES (p_resource_id, v_guest, p_accommodation_id, p_date, p_slot::time,
            p_qty, trim(p_name), trim(p_phone), 'confirmed')
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.guest_active_bookings(text) TO anon;
GRANT EXECUTE ON FUNCTION public.create_guest_booking(uuid, text, uuid, date, text, integer, text, text) TO anon;

-- Vlasnik (sa svojim x-partner-token) čita rezervacije svog biznisa i
-- svoje goste (hotel), kao i provizije gde je na bilo kojoj strani
DROP POLICY IF EXISTS owner_select_bookings ON public.bookings;
CREATE POLICY owner_select_bookings ON public.bookings FOR SELECT TO anon
    USING (
        public.owns_partner(accommodation_id)
        OR EXISTS (SELECT 1 FROM public.bookable_resources r
                   WHERE r.id = bookings.resource_id AND public.owns_partner(r.partner_id))
    );

DROP POLICY IF EXISTS owner_select_commissions ON public.apartment_commissions;
CREATE POLICY owner_select_commissions ON public.apartment_commissions FOR SELECT TO anon
    USING (public.owns_partner(apartment_partner_id) OR public.owns_partner(attraction_partner_id));

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ bookings_privacy_a.sql
-- ═══════════════════════════════════════════════════════════════════
