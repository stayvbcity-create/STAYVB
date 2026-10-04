-- ═══════════════════════════════════════════════════════════════════
-- stay_extension.sql — mašina za produženje boravka.
--
-- Gost na poslednji ceo dan boravka dobija ponudu: još jedna noć po
-- nižoj ceni (koju smeštaj sam odredi) plus aktivnost po ceni mrtvog
-- termina (koju atrakcija sama odredi). Niko ne daje gratis — oba
-- prodaju kapacitet koji bi propao.
--
-- Tok: gost prihvati -> status "accepted" -> vlasnik potvrdi u panelu
-- -> kreira se rezervacija aktivnosti i datum odjave se pomera za dan.
--
-- Pokreni jednom u Supabase SQL editoru.
-- ═══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- 1. NOVA POLJA
-- ══════════════════════════════════════════════════════════════════

-- Datum odjave gosta (bez njega ne znamo kada je poslednji dan)
ALTER TABLE public.guests ADD COLUMN IF NOT EXISTS checkout_date date;

-- Smeštaj: prekidač i cena noći za produženje
ALTER TABLE public.partners
    ADD COLUMN IF NOT EXISTS ext_active boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS ext_night_price integer;

-- Atrakcija: cena za mrtve termine i vremenski okvir u kojem važi
ALTER TABLE public.bookable_resources
    ADD COLUMN IF NOT EXISTS ext_active boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS ext_price_rsd integer,
    ADD COLUMN IF NOT EXISTS ext_time_from time,
    ADD COLUMN IF NOT EXISTS ext_time_to time;

-- Zapamćena cena po osobi na rezervaciji. Bez ovoga bi se provizija
-- za sniženu cenu obračunala na redovnu cenu termina.
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS unit_price_rsd integer;

-- ══════════════════════════════════════════════════════════════════
-- 2. TABELA PONUDA
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.stay_extension_offers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_id uuid NOT NULL REFERENCES public.guests(id),
    accommodation_id uuid NOT NULL REFERENCES public.partners(id),
    stay_checkout_date date NOT NULL,
    night_price integer NOT NULL,
    night_regular_price integer,
    status text NOT NULL DEFAULT 'offered',   -- offered|accepted|confirmed|declined|rejected|expired
    guest_name text,
    guest_phone text,
    resource_id uuid REFERENCES public.bookable_resources(id),
    activity_slot time,
    activity_qty integer,
    activity_price integer,
    activity_regular_price integer,
    booking_id uuid REFERENCES public.bookings(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    accepted_at timestamptz,
    decided_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ext_offer_guest_stay
    ON public.stay_extension_offers(guest_id, stay_checkout_date);
CREATE INDEX IF NOT EXISTS idx_ext_offer_acc
    ON public.stay_extension_offers(accommodation_id, status, created_at DESC);

ALTER TABLE public.stay_extension_offers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ext_offers_admin ON public.stay_extension_offers;
CREATE POLICY ext_offers_admin ON public.stay_extension_offers FOR ALL TO authenticated
    USING (public.is_admin()) WITH CHECK (public.is_admin());
-- Anon nema nikakav direktan pristup: sve ide kroz funkcije ispod.

-- ══════════════════════════════════════════════════════════════════
-- 3. PROVIZIJA KORISTI ZAPAMĆENU CENU
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_apartment_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource_price integer;
    v_attraction_id uuid;
    v_sharing_active boolean;
    v_pct integer;
    v_acc_type text;
    v_acc_premium boolean;
    v_amount integer;
BEGIN
    IF NEW.redeemed_at IS NULL OR OLD.redeemed_at IS NOT NULL THEN RETURN NEW; END IF;
    IF NEW.accommodation_id IS NULL THEN RETURN NEW; END IF;

    SELECT price_rsd, partner_id INTO v_resource_price, v_attraction_id
    FROM public.bookable_resources WHERE id = NEW.resource_id;
    IF NOT FOUND THEN RETURN NEW; END IF;

    -- cena sa rezervacije ima prednost (sniženi termin, produženje boravka)
    v_resource_price := COALESCE(NEW.unit_price_rsd, v_resource_price, 0);

    SELECT commission_sharing_active, apartment_commission_pct
    INTO v_sharing_active, v_pct
    FROM public.partners WHERE id = v_attraction_id;
    IF NOT FOUND OR NOT COALESCE(v_sharing_active, false) OR COALESCE(v_pct, 0) <= 0 THEN
        RETURN NEW;
    END IF;

    SELECT type, is_premium INTO v_acc_type, v_acc_premium
    FROM public.partners WHERE id = NEW.accommodation_id;
    IF NOT FOUND OR v_acc_type NOT IN ('apartment','hotel') OR NOT COALESCE(v_acc_premium, false) THEN
        RETURN NEW;
    END IF;

    v_amount := ROUND(v_resource_price * NEW.qty * v_pct / 100.0);
    IF v_amount <= 0 THEN RETURN NEW; END IF;

    INSERT INTO public.apartment_commissions
        (booking_id, apartment_partner_id, attraction_partner_id, amount_rsd, commission_pct_applied)
    VALUES (NEW.id, NEW.accommodation_id, v_attraction_id, v_amount, v_pct)
    ON CONFLICT (booking_id) DO NOTHING;

    RETURN NEW;
END;
$$;

-- Gostinska rezervacija pamti cenu po osobi
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
    v_price integer;
BEGIN
    IF p_qty IS NULL OR p_qty < 1 OR p_qty > 20 THEN
        RAISE EXCEPTION 'Neispravna količina' USING ERRCODE = '22023';
    END IF;
    IF coalesce(trim(p_name), '') = '' OR coalesce(trim(p_phone), '') = '' THEN
        RAISE EXCEPTION 'Nedostaju podaci gosta' USING ERRCODE = '22023';
    END IF;
    SELECT price_rsd INTO v_price FROM public.bookable_resources
    WHERE id = p_resource_id AND is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Termin nije aktivan' USING ERRCODE = '22023';
    END IF;

    SELECT g.id INTO v_guest FROM public.guests g WHERE g.token = p_guest_token;

    INSERT INTO public.bookings (resource_id, guest_id, accommodation_id, booking_date, slot_time,
                                 qty, guest_name, guest_phone, status, unit_price_rsd)
    VALUES (p_resource_id, v_guest, p_accommodation_id, p_date, p_slot::time,
            p_qty, trim(p_name), trim(p_phone), 'confirmed', v_price)
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- Pregled na skeneru koristi zapamćenu cenu
CREATE OR REPLACE FUNCTION public.booking_preview(p_scanner_token text, p_booking_id uuid)
RETURNS TABLE(
    ok boolean, msg text, guest_name text, booking_date text, slot_time text, qty integer,
    resource_name text, description text, unit_price integer, total integer, accommodation_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_partner_id uuid;
    v_b record;
BEGIN
    SELECT p.id INTO v_partner_id FROM public.partners p
    WHERE p.scanner_token = p_scanner_token AND p.is_active = true AND p.type = 'attraction';
    IF v_partner_id IS NULL THEN
        RETURN QUERY SELECT false, 'Nevažeći link.'::text, NULL::text, NULL::text, NULL::text,
            NULL::integer, NULL::text, NULL::text, NULL::integer, NULL::integer, NULL::text;
        RETURN;
    END IF;

    SELECT b.guest_name, b.booking_date::text AS bdate, substring(b.slot_time::text, 1, 5) AS bslot,
           b.qty, b.status, b.redeemed_at,
           r.name AS rname, r.description AS rdesc,
           COALESCE(b.unit_price_rsd, r.price_rsd) AS rprice, r.partner_id AS rpartner,
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

-- ══════════════════════════════════════════════════════════════════
-- 4. GOST: datum odjave
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.set_guest_checkout(p_guest_token text, p_nights integer)
RETURNS date
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_date date;
BEGIN
    IF p_nights IS NULL OR p_nights < 1 OR p_nights > 60 THEN
        RAISE EXCEPTION 'Neispravan broj noći' USING ERRCODE = '22023';
    END IF;
    UPDATE public.guests
    SET checkout_date = COALESCE(checkin_date, CURRENT_DATE) + p_nights
    WHERE token = p_guest_token
    RETURNING checkout_date INTO v_date;
    RETURN v_date;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- 5. GOST: ponuda za produženje
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.guest_extension_offer(p_guest_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_g record;
    v_acc record;
    v_offer record;
    v_regular integer;
    v_expires timestamptz;
    v_options jsonb;
BEGIN
    SELECT id, accommodation_id, checkin_date, checkout_date
    INTO v_g FROM public.guests WHERE token = p_guest_token;
    IF NOT FOUND OR v_g.accommodation_id IS NULL THEN
        RETURN jsonb_build_object('state','none');
    END IF;
    IF v_g.checkout_date IS NULL THEN
        RETURN jsonb_build_object('state','need_checkout_date');
    END IF;

    SELECT id, name, type, ext_active, ext_night_price
    INTO v_acc FROM public.partners
    WHERE id = v_g.accommodation_id AND is_active = true AND type IN ('hotel','apartment');
    IF NOT FOUND OR NOT v_acc.ext_active OR COALESCE(v_acc.ext_night_price,0) <= 0 THEN
        RETURN jsonb_build_object('state','none');
    END IF;

    -- postojeća ponuda za ovaj boravak
    SELECT * INTO v_offer FROM public.stay_extension_offers
    WHERE guest_id = v_g.id AND stay_checkout_date = v_g.checkout_date;

    IF FOUND AND v_offer.status IN ('confirmed','rejected','declined') THEN
        RETURN jsonb_build_object(
            'state', v_offer.status, 'offer_id', v_offer.id,
            'booking_id', v_offer.booking_id,
            'night_price', v_offer.night_price,
            'new_checkout', (v_offer.stay_checkout_date + 1)::text);
    END IF;

    IF FOUND AND v_offer.status = 'accepted' THEN
        RETURN jsonb_build_object('state','accepted','offer_id', v_offer.id,
            'night_price', v_offer.night_price, 'activity_price', v_offer.activity_price);
    END IF;

    -- ponuda se prikazuje samo na poslednji ceo dan boravka
    IF v_g.checkout_date <> CURRENT_DATE + 1 THEN
        RETURN jsonb_build_object('state','none');
    END IF;

    IF FOUND AND v_offer.status = 'offered' AND v_offer.expires_at <= now() THEN
        UPDATE public.stay_extension_offers SET status = 'expired' WHERE id = v_offer.id;
        RETURN jsonb_build_object('state','expired');
    END IF;
    IF FOUND AND v_offer.status = 'expired' THEN
        RETURN jsonb_build_object('state','expired');
    END IF;

    v_expires := (date_trunc('day', now() AT TIME ZONE 'Europe/Belgrade') + interval '20 hours')
                 AT TIME ZONE 'Europe/Belgrade';

    IF NOT FOUND THEN
        SELECT max(price_per_night) INTO v_regular FROM public.accommodation_listings
        WHERE partner_id = v_acc.id AND is_active = true;

        INSERT INTO public.stay_extension_offers
            (guest_id, accommodation_id, stay_checkout_date, night_price, night_regular_price, expires_at)
        VALUES (v_g.id, v_acc.id, v_g.checkout_date, v_acc.ext_night_price, v_regular, v_expires)
        ON CONFLICT (guest_id, stay_checkout_date) DO NOTHING;

        SELECT * INTO v_offer FROM public.stay_extension_offers
        WHERE guest_id = v_g.id AND stay_checkout_date = v_g.checkout_date;
    END IF;

    -- do tri aktivnosti sa sniženom cenom za mrtve termine
    SELECT jsonb_agg(o) INTO v_options FROM (
        SELECT r.id AS resource_id, r.name AS resource_name, r.description,
               p.name AS attraction_name, r.ext_price_rsd AS price, r.price_rsd AS regular_price,
               substring(r.ext_time_from::text,1,5) AS time_from,
               substring(r.ext_time_to::text,1,5) AS time_to
        FROM public.bookable_resources r
        JOIN public.partners p ON p.id = r.partner_id
        WHERE r.is_active = true AND r.ext_active = true
          AND COALESCE(r.ext_price_rsd,0) > 0 AND r.ext_time_from IS NOT NULL
          AND p.is_active = true AND p.type = 'attraction'
        ORDER BY (COALESCE(r.price_rsd,0) - r.ext_price_rsd) DESC
        LIMIT 3
    ) o;

    RETURN jsonb_build_object(
        'state','offered',
        'offer_id', v_offer.id,
        'accommodation_name', v_acc.name,
        'night_price', v_offer.night_price,
        'night_regular_price', v_offer.night_regular_price,
        'expires_at', v_offer.expires_at,
        'new_checkout', (v_g.checkout_date + 1)::text,
        'options', COALESCE(v_options, '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.guest_accept_extension(
    p_guest_token text, p_resource_id uuid, p_qty integer, p_name text, p_phone text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_g record;
    v_offer record;
    v_r record;
BEGIN
    IF coalesce(trim(p_name),'') = '' OR coalesce(trim(p_phone),'') = '' THEN
        RAISE EXCEPTION 'Unesite ime i telefon' USING ERRCODE = '22023';
    END IF;

    SELECT id, checkout_date INTO v_g FROM public.guests WHERE token = p_guest_token;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'msg', 'Gost nije prepoznat.'); END IF;

    SELECT * INTO v_offer FROM public.stay_extension_offers
    WHERE guest_id = v_g.id AND stay_checkout_date = v_g.checkout_date AND status = 'offered';
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'msg', 'Ponuda više nije aktivna.'); END IF;
    IF v_offer.expires_at <= now() THEN
        UPDATE public.stay_extension_offers SET status = 'expired' WHERE id = v_offer.id;
        RETURN jsonb_build_object('ok', false, 'msg', 'Ponuda je istekla.');
    END IF;

    SELECT r.id, r.ext_price_rsd, r.price_rsd, r.ext_time_from
    INTO v_r FROM public.bookable_resources r
    JOIN public.partners p ON p.id = r.partner_id
    WHERE r.id = p_resource_id AND r.is_active AND r.ext_active
      AND COALESCE(r.ext_price_rsd,0) > 0 AND p.is_active AND p.type = 'attraction';
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'msg', 'Aktivnost nije dostupna.'); END IF;

    UPDATE public.stay_extension_offers SET
        status = 'accepted', accepted_at = now(),
        guest_name = trim(p_name), guest_phone = trim(p_phone),
        resource_id = v_r.id, activity_qty = GREATEST(1, LEAST(COALESCE(p_qty,1), 20)),
        activity_slot = v_r.ext_time_from,
        activity_price = v_r.ext_price_rsd, activity_regular_price = v_r.price_rsd
    WHERE id = v_offer.id;

    RETURN jsonb_build_object('ok', true, 'msg', 'Čeka se potvrda domaćina.');
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- 6. VLASNIK SMEŠTAJA: pregled i potvrda
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.owner_extension_offers(p_access_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id uuid;
    v_rows jsonb;
BEGIN
    SELECT id INTO v_id FROM public.partners
    WHERE access_token = p_access_token AND is_active = true AND type IN ('hotel','apartment');
    IF v_id IS NULL THEN RETURN '[]'::jsonb; END IF;

    SELECT jsonb_agg(x ORDER BY x.created_at DESC) INTO v_rows FROM (
        SELECT o.id, o.status, o.night_price, o.guest_name, o.guest_phone,
               o.stay_checkout_date::text AS checkout_date, o.activity_qty,
               o.activity_price, o.created_at, o.expires_at,
               r.name AS resource_name, p.name AS attraction_name
        FROM public.stay_extension_offers o
        LEFT JOIN public.bookable_resources r ON r.id = o.resource_id
        LEFT JOIN public.partners p ON p.id = r.partner_id
        WHERE o.accommodation_id = v_id
          AND o.created_at > now() - interval '30 days'
    ) x;
    RETURN COALESCE(v_rows, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.owner_decide_extension(
    p_access_token text, p_offer_id uuid, p_confirm boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id uuid;
    v_offer record;
    v_res record;
    v_slot time;
    v_taken integer;
    v_booking uuid;
BEGIN
    SELECT id INTO v_id FROM public.partners
    WHERE access_token = p_access_token AND is_active = true AND type IN ('hotel','apartment');
    IF v_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'msg', 'Nevažeći pristup.'); END IF;

    SELECT * INTO v_offer FROM public.stay_extension_offers
    WHERE id = p_offer_id AND accommodation_id = v_id AND status = 'accepted';
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'msg', 'Ponuda nije u statusu za potvrdu.'); END IF;

    IF NOT p_confirm THEN
        UPDATE public.stay_extension_offers SET status = 'rejected', decided_at = now() WHERE id = v_offer.id;
        RETURN jsonb_build_object('ok', true, 'msg', 'Ponuda je odbijena.');
    END IF;

    SELECT id, total_qty, ext_time_from, ext_time_to, ext_price_rsd
    INTO v_res FROM public.bookable_resources WHERE id = v_offer.resource_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'msg', 'Aktivnost nije dostupna.'); END IF;

    -- prvi slobodan pun sat u okviru mrtvog termina, za dan produženja
    v_slot := COALESCE(v_offer.activity_slot, v_res.ext_time_from);
    WHILE v_slot <= COALESCE(v_res.ext_time_to, v_res.ext_time_from) LOOP
        SELECT COALESCE(sum(qty), 0) INTO v_taken FROM public.bookings
        WHERE resource_id = v_res.id AND booking_date = v_offer.stay_checkout_date
          AND slot_time = v_slot AND status <> 'cancelled';
        EXIT WHEN v_taken + v_offer.activity_qty <= COALESCE(v_res.total_qty, 0);
        v_slot := v_slot + interval '1 hour';
    END LOOP;

    IF v_slot > COALESCE(v_res.ext_time_to, v_res.ext_time_from) THEN
        RETURN jsonb_build_object('ok', false, 'msg', 'Aktivnost je popunjena za taj dan.');
    END IF;

    INSERT INTO public.bookings (resource_id, guest_id, accommodation_id, booking_date, slot_time,
                                 qty, guest_name, guest_phone, status, unit_price_rsd)
    VALUES (v_res.id, v_offer.guest_id, v_id, v_offer.stay_checkout_date, v_slot,
            v_offer.activity_qty, v_offer.guest_name, v_offer.guest_phone, 'confirmed', v_offer.activity_price)
    RETURNING id INTO v_booking;

    UPDATE public.guests SET checkout_date = checkout_date + 1 WHERE id = v_offer.guest_id;

    UPDATE public.stay_extension_offers
    SET status = 'confirmed', decided_at = now(), booking_id = v_booking, activity_slot = v_slot
    WHERE id = v_offer.id;

    RETURN jsonb_build_object('ok', true, 'msg', 'Produženje je potvrđeno.', 'booking_id', v_booking);
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- 7. GRANTOVI
-- ══════════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION public.set_guest_checkout(text, integer) TO anon;
GRANT EXECUTE ON FUNCTION public.guest_extension_offer(text) TO anon;
GRANT EXECUTE ON FUNCTION public.guest_accept_extension(text, uuid, integer, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.owner_extension_offers(text) TO anon;
GRANT EXECUTE ON FUNCTION public.owner_decide_extension(text, uuid, boolean) TO anon;
GRANT UPDATE (ext_active, ext_night_price) ON public.partners TO anon;
GRANT UPDATE (ext_active, ext_price_rsd, ext_time_from, ext_time_to) ON public.bookable_resources TO anon;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ stay_extension.sql
-- ═══════════════════════════════════════════════════════════════════
