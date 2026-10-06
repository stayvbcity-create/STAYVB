-- ═══════════════════════════════════════════════════════════════════
-- tonight_stay.sql — "Ostanite večeras": gost za stolom u restoranu
-- dobija ponudu slobodnog smeštaja za noćas po nižoj ceni.
--
-- Ko je u ponudi: premium apartmani i hoteli koji su u svom panelu
-- uključili "Večeras za goste restorana" i upisali cenu za noćas.
-- Apartman se ne prikazuje ako u njemu noćas ima gosta. Hotel se
-- prikazuje dok god ima uključenu ponudu (sam je gasi kad se popuni).
--
-- Tok: gost pošalje zahtev -> upit stiže smeštaju (Rezervacije) ->
-- domaćin potvrdi -> ako je gost izabrao aktivnost, pravi se
-- rezervacija za sutra po ceni mrtvog termina.
--
-- Restoran nema proviziju na noćenje. Ni aktivnost iz ove ponude
-- nema proviziju (atrakcija je već dala sniženu cenu).
--
-- Pokreni jednom u Supabase SQL editoru.
-- ═══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- 1. NOVA POLJA
-- ══════════════════════════════════════════════════════════════════

-- Smeštaj: pristanak i cena za noćas (uz oglas sa slikama)
ALTER TABLE public.accommodation_listings
    ADD COLUMN IF NOT EXISTS tonight_active boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS tonight_price integer;

ALTER TABLE public.accommodation_listings DROP CONSTRAINT IF EXISTS tonight_price_range;
ALTER TABLE public.accommodation_listings ADD CONSTRAINT tonight_price_range
    CHECK (tonight_price IS NULL OR tonight_price BETWEEN 0 AND 999999) NOT VALID;

-- Upit: odakle je došao i šta je gost tražio
ALTER TABLE public.accommodation_inquiries
    ADD COLUMN IF NOT EXISTS source text,                 -- 'tonight' ili NULL (obična stranica Smeštaj)
    ADD COLUMN IF NOT EXISTS source_partner_id uuid REFERENCES public.partners(id),
    ADD COLUMN IF NOT EXISTS source_label text,           -- naziv restorana
    ADD COLUMN IF NOT EXISTS offer_price integer,         -- cena noći za noćas
    ADD COLUMN IF NOT EXISTS regular_price integer,
    ADD COLUMN IF NOT EXISTS resource_id uuid REFERENCES public.bookable_resources(id),
    ADD COLUMN IF NOT EXISTS activity_label text,
    ADD COLUMN IF NOT EXISTS activity_qty integer,
    ADD COLUMN IF NOT EXISTS activity_price integer,
    ADD COLUMN IF NOT EXISTS booking_id uuid REFERENCES public.bookings(id);

CREATE INDEX IF NOT EXISTS idx_inquiries_tonight
    ON public.accommodation_inquiries(listing_id, checkin_date) WHERE source = 'tonight';

-- Domaćin menja pristanak i cenu samo na svom oglasu (owner_accommodation_listings)
GRANT UPDATE (tonight_active, tonight_price) ON public.accommodation_listings TO anon;

-- ══════════════════════════════════════════════════════════════════
-- 2. PONUDA ZA STO: slobodni smeštaji + sniženje aktivnosti
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.tonight_offers(p_restaurant_id uuid, p_guest_token text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rest record;
    v_today date := (now() AT TIME ZONE 'Europe/Belgrade')::date;
    v_hour integer := extract(hour FROM now() AT TIME ZONE 'Europe/Belgrade');
    v_stays jsonb;
    v_acts jsonb;
BEGIN
    SELECT id, name INTO v_rest FROM public.partners
    WHERE id = p_restaurant_id AND is_active = true
      AND type = 'restaurant' AND is_premium = true;
    IF NOT FOUND THEN RETURN jsonb_build_object('state','none'); END IF;

    -- Gost koji već ima smeštaj u Banji ne dobija ovu ponudu
    IF p_guest_token IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.guests g
        WHERE g.token = p_guest_token AND g.accommodation_id IS NOT NULL
          AND (g.checkout_date > v_today
               OR (g.checkout_date IS NULL AND g.checkin_date >= v_today - 2))
    ) THEN
        RETURN jsonb_build_object('state','staying');
    END IF;

    -- Kasno je za "večeras"
    IF v_hour >= 23 THEN RETURN jsonb_build_object('state','late'); END IF;

    SELECT jsonb_agg(s) INTO v_stays FROM (
        SELECT l.id AS listing_id, COALESCE(NULLIF(l.title,''), p.name) AS title,
               p.type, l.location_label, l.highlight, l.guests, l.bedrooms,
               l.photo_urls[1:4] AS photos,
               l.tonight_price AS price,
               NULLIF(l.price_per_night, 0) AS regular_price
        FROM public.accommodation_listings l
        JOIN public.partners p ON p.id = l.partner_id
        WHERE l.is_active AND l.tonight_active
          AND COALESCE(l.tonight_price, 0) > 0
          AND (COALESCE(l.price_per_night, 0) = 0 OR l.tonight_price < l.price_per_night)
          AND p.is_active AND p.is_premium AND p.type IN ('apartment','hotel')
          -- apartman: noćas bez gosta
          AND (p.type = 'hotel' OR (
                NOT EXISTS (
                    SELECT 1 FROM public.guests g
                    WHERE g.accommodation_id = p.id
                      AND COALESCE(g.checkin_date, v_today) <= v_today
                      AND (g.checkout_date > v_today
                           OR (g.checkout_date IS NULL AND g.checkin_date >= v_today - 2)))
            AND NOT EXISTS (
                    SELECT 1 FROM public.accommodation_inquiries q
                    WHERE q.partner_id = p.id AND q.status = 'confirmed'
                      AND q.checkin_date <= v_today AND q.checkout_date > v_today)))
        ORDER BY (1 - l.tonight_price::numeric / NULLIF(l.price_per_night, 0)) DESC NULLS LAST,
                 l.tonight_price
        LIMIT 12
    ) s;

    -- Aktivnosti za sutra po ceni mrtvog termina
    SELECT jsonb_agg(a) INTO v_acts FROM (
        SELECT r.id AS resource_id, r.name AS resource_name, p.name AS attraction_name,
               r.ext_price_rsd AS price, r.price_rsd AS regular_price,
               substring(r.ext_time_from::text,1,5) AS time_from,
               substring(r.ext_time_to::text,1,5) AS time_to
        FROM public.bookable_resources r
        JOIN public.partners p ON p.id = r.partner_id
        WHERE r.is_active AND r.ext_active
          AND COALESCE(r.ext_price_rsd,0) > 0 AND r.ext_time_from IS NOT NULL
          AND p.is_active AND p.type = 'attraction'
        ORDER BY (COALESCE(r.price_rsd,0) - r.ext_price_rsd) DESC
        LIMIT 4
    ) a;

    IF v_stays IS NULL THEN RETURN jsonb_build_object('state','none'); END IF;

    RETURN jsonb_build_object(
        'state','offered',
        'restaurant', v_rest.name,
        'stays', v_stays,
        'activities', COALESCE(v_acts, '[]'::jsonb));
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- 3. GOST: zahtev za noćas
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.request_tonight_stay(
    p_restaurant_id uuid, p_listing_id uuid, p_name text, p_phone text,
    p_guests integer, p_resource_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rest record;
    v_l record;
    v_rid uuid;
    v_rlabel text;
    v_rprice integer;
    v_today date := (now() AT TIME ZONE 'Europe/Belgrade')::date;
    v_phone text := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
    v_guests integer := GREATEST(1, LEAST(COALESCE(p_guests, 2), 20));
    v_id uuid;
BEGIN
    IF coalesce(trim(p_name),'') = '' OR length(v_phone) < 6 THEN
        RETURN jsonb_build_object('ok', false, 'msg', 'Unesite ime i broj telefona.');
    END IF;

    SELECT id, name INTO v_rest FROM public.partners
    WHERE id = p_restaurant_id AND is_active AND type = 'restaurant' AND is_premium;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'msg', 'Ponuda nije dostupna.'); END IF;

    SELECT l.id, l.partner_id, l.tonight_price, NULLIF(l.price_per_night,0) AS regular,
           p.name, p.phone, p.whatsapp
    INTO v_l
    FROM public.accommodation_listings l JOIN public.partners p ON p.id = l.partner_id
    WHERE l.id = p_listing_id AND l.is_active AND l.tonight_active AND COALESCE(l.tonight_price,0) > 0
      AND p.is_active AND p.is_premium AND p.type IN ('apartment','hotel');
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'msg', 'Ovaj smeštaj više nije slobodan.'); END IF;

    -- zaštita od slučajnog ponavljanja
    IF (SELECT count(*) FROM public.accommodation_inquiries
        WHERE source = 'tonight' AND guest_phone = v_phone AND checkin_date = v_today) >= 3 THEN
        RETURN jsonb_build_object('ok', false, 'msg', 'Već ste poslali zahteve za večeras. Javite se domaćinu direktno.');
    END IF;

    IF p_resource_id IS NOT NULL THEN
        SELECT r.id, p.name || ' · ' || r.name, r.ext_price_rsd
        INTO v_rid, v_rlabel, v_rprice
        FROM public.bookable_resources r JOIN public.partners p ON p.id = r.partner_id
        WHERE r.id = p_resource_id AND r.is_active AND r.ext_active
          AND COALESCE(r.ext_price_rsd,0) > 0 AND p.is_active AND p.type = 'attraction';
    END IF;

    INSERT INTO public.accommodation_inquiries
        (listing_id, partner_id, checkin_date, checkout_date, guest_count, guest_name, guest_phone,
         message, status, source, source_partner_id, source_label, offer_price, regular_price,
         resource_id, activity_label, activity_qty, activity_price)
    VALUES
        (v_l.id, v_l.partner_id, v_today, v_today + 1, v_guests, trim(p_name), v_phone,
         'Večeras, gost iz restorana ' || v_rest.name, 'new', 'tonight', v_rest.id, v_rest.name,
         v_l.tonight_price, v_l.regular,
         v_rid, v_rlabel, CASE WHEN v_rid IS NOT NULL THEN v_guests END, v_rprice)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('ok', true, 'id', v_id,
        'host_name', v_l.name, 'host_phone', COALESCE(NULLIF(v_l.whatsapp,''), v_l.phone),
        'price', v_l.tonight_price);
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- 4. DOMAĆIN: potvrda ili odbijanje (pravi rezervaciju aktivnosti)
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.owner_decide_tonight(
    p_access_token text, p_inquiry_id uuid, p_confirm boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id uuid;
    v_q record;
    v_res record;
    v_slot time;
    v_taken integer;
    v_booking uuid;
BEGIN
    SELECT id INTO v_id FROM public.partners
    WHERE access_token = p_access_token AND access_token <> '' AND is_active AND type IN ('hotel','apartment');
    IF v_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'msg', 'Nevažeći pristup.'); END IF;

    SELECT * INTO v_q FROM public.accommodation_inquiries
    WHERE id = p_inquiry_id AND partner_id = v_id AND source = 'tonight'
      AND status IN ('new','contacted');
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'msg', 'Zahtev nije u statusu za potvrdu.'); END IF;

    IF NOT p_confirm THEN
        UPDATE public.accommodation_inquiries SET status = 'declined' WHERE id = v_q.id;
        RETURN jsonb_build_object('ok', true, 'msg', 'Zahtev je odbijen.');
    END IF;

    IF v_q.resource_id IS NOT NULL THEN
        SELECT id, total_qty, ext_time_from, ext_time_to
        INTO v_res FROM public.bookable_resources WHERE id = v_q.resource_id;
        IF FOUND THEN
            v_slot := v_res.ext_time_from;
            WHILE v_slot <= COALESCE(v_res.ext_time_to, v_res.ext_time_from) LOOP
                SELECT COALESCE(sum(qty), 0) INTO v_taken FROM public.bookings
                WHERE resource_id = v_res.id AND booking_date = v_q.checkout_date
                  AND slot_time = v_slot AND status <> 'cancelled';
                EXIT WHEN v_taken + COALESCE(v_q.activity_qty,1) <= COALESCE(v_res.total_qty, 0);
                v_slot := v_slot + interval '1 hour';
            END LOOP;

            IF v_slot <= COALESCE(v_res.ext_time_to, v_res.ext_time_from) THEN
                INSERT INTO public.bookings (resource_id, guest_id, accommodation_id, booking_date, slot_time,
                                             qty, guest_name, guest_phone, status, unit_price_rsd)
                VALUES (v_res.id, NULL, v_id, v_q.checkout_date, v_slot,
                        COALESCE(v_q.activity_qty,1), v_q.guest_name, v_q.guest_phone, 'confirmed', v_q.activity_price)
                RETURNING id INTO v_booking;
            END IF;
        END IF;
    END IF;

    UPDATE public.accommodation_inquiries SET status = 'confirmed', booking_id = v_booking WHERE id = v_q.id;

    RETURN jsonb_build_object('ok', true,
        'msg', CASE WHEN v_q.resource_id IS NOT NULL AND v_booking IS NULL
                    THEN 'Noćenje je potvrđeno. Aktivnost je popunjena za sutra — javite gostu.'
                    ELSE 'Noćenje je potvrđeno.' END,
        'booking_id', v_booking);
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- 5. PROVIZIJA: ni produženje ni "večeras" nemaju proviziju
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

    -- Rezervacija nastala iz produženja boravka ili ponude "večeras": bez provizije
    IF EXISTS (SELECT 1 FROM public.stay_extension_offers WHERE booking_id = NEW.id)
       OR EXISTS (SELECT 1 FROM public.accommodation_inquiries WHERE booking_id = NEW.id) THEN
        RETURN NEW;
    END IF;

    SELECT price_rsd, partner_id INTO v_resource_price, v_attraction_id
    FROM public.bookable_resources WHERE id = NEW.resource_id;
    IF NOT FOUND THEN RETURN NEW; END IF;

    -- cena sa rezervacije ima prednost (sniženi termin)
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

-- ══════════════════════════════════════════════════════════════════
-- 6. GRANTOVI
-- ══════════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION public.tonight_offers(uuid, text) TO anon;
GRANT EXECUTE ON FUNCTION public.request_tonight_stay(uuid, uuid, text, text, integer, uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.owner_decide_tonight(text, uuid, boolean) TO anon;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ tonight_stay.sql
-- ═══════════════════════════════════════════════════════════════════
