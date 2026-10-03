-- ═══════════════════════════════════════════════════════════════════
-- hotel_commission_test.sql — end-to-end test provizije za HOTELE.
--
-- Sve se radi u jednoj transakciji i na kraju se RADI ROLLBACK, pa
-- se u bazi ništa ne zadržava (test partner, rezervacije, provizije —
-- sve nestaje). Rezultat se prikazuje u poslednjoj tabeli.
--
-- Pokreni u Supabase SQL editoru (sve odjednom). Preduslov: seed
-- (loadtest_seed_v2.sql) i hotel_commissions.sql moraju biti pokrenuti.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE TEMP TABLE st_results(ord int, name text, pass boolean, detail text);

DO $$
DECLARE
    v_hot        uuid;
    v_hot_basic  uuid;
    v_attr       uuid;
    v_res        uuid;
    v_book       uuid;
    v_book2      uuid;
    v_token      text;
    v_r          record;
    v_cnt        int;
    v_amt        int;
    v_pct        int;
    v_apt        uuid;
    v_paid       timestamptz;
BEGIN
    SELECT id INTO v_hot FROM public.partners
    WHERE type = 'hotel' AND is_premium AND partner_code LIKE 'TST_%' ORDER BY partner_code LIMIT 1;
    SELECT id INTO v_hot_basic FROM public.partners
    WHERE type = 'hotel' AND NOT is_premium AND partner_code LIKE 'TST_%' ORDER BY partner_code LIMIT 1;
    IF v_hot IS NULL OR v_hot_basic IS NULL THEN
        RAISE EXCEPTION 'Nema TST premium i basic hotela — prvo pokreni loadtest_seed_v2.sql';
    END IF;

    v_token := replace(gen_random_uuid()::text, '-', '');
    INSERT INTO public.partners (name, type, pin, partner_code, access_token, is_active, is_premium, plan,
                                 lat, lng, phone, commission_sharing_active, apartment_commission_pct, scanner_token)
    VALUES ('TEST Atrakcija Provizija', 'attraction', '9999', 'TST_ATTR_COMM',
            replace(gen_random_uuid()::text, '-', ''), true, false, 'basic',
            43.62, 20.895, '+381600000000', true, 10, v_token)
    RETURNING id INTO v_attr;

    INSERT INTO public.bookable_resources (partner_id, name, total_qty, price_rsd, is_active)
    VALUES (v_attr, 'Test vožnja', 10, 1000, true)
    RETURNING id INTO v_res;

    -- Rezervacija gosta PREMIUM hotela (2 osobe, 1000 RSD po osobi, 10 % provizije => 200 RSD)
    INSERT INTO public.bookings (resource_id, booking_date, slot_time, qty, guest_name, guest_phone, status, accommodation_id)
    VALUES (v_res, CURRENT_DATE, '23:01', 2, 'TEST Gost Hotel', '+381600000001', 'confirmed', v_hot)
    RETURNING id INTO v_book;

    SELECT * INTO v_r FROM public.redeem_booking(v_token, v_book);
    INSERT INTO st_results VALUES (1, 'Realizacija rezervacije preko skenera (premium hotel)', v_r.ok, v_r.msg);

    SELECT count(*), coalesce(max(amount_rsd), 0), coalesce(max(commission_pct_applied), 0), max(apartment_partner_id)
    INTO v_cnt, v_amt, v_pct, v_apt
    FROM public.apartment_commissions WHERE booking_id = v_book;

    INSERT INTO st_results VALUES (2, 'Provizija upisana tačno jednom', v_cnt = 1, 'redova: ' || v_cnt);
    INSERT INTO st_results VALUES (3, 'Iznos = 2 × 1000 × 10 % = 200 RSD', v_amt = 200, 'iznos: ' || v_amt || ' RSD, % = ' || v_pct);
    INSERT INTO st_results VALUES (4, 'Provizija pripada HOTELU (ne atrakciji)', v_apt = v_hot,
        CASE WHEN v_apt = v_hot THEN 'ok' ELSE 'pogrešan partner' END);

    -- Ponovna realizacija istog koda ne sme da napravi drugu proviziju
    SELECT * INTO v_r FROM public.redeem_booking(v_token, v_book);
    SELECT count(*) INTO v_cnt FROM public.apartment_commissions WHERE booking_id = v_book;
    INSERT INTO st_results VALUES (5, 'Drugi pokušaj realizacije je odbijen', v_r.ok = false, v_r.msg);
    INSERT INTO st_results VALUES (6, 'Posle drugog pokušaja i dalje 1 provizija', v_cnt = 1, 'redova: ' || v_cnt);

    -- Gost BASIC hotela (bez premium statusa) ne stvara proviziju
    INSERT INTO public.bookings (resource_id, booking_date, slot_time, qty, guest_name, guest_phone, status, accommodation_id)
    VALUES (v_res, CURRENT_DATE, '23:02', 2, 'TEST Gost Basic', '+381600000002', 'confirmed', v_hot_basic)
    RETURNING id INTO v_book2;
    PERFORM public.redeem_booking(v_token, v_book2);
    SELECT count(*) INTO v_cnt FROM public.apartment_commissions WHERE booking_id = v_book2;
    INSERT INTO st_results VALUES (7, 'Basic hotel NE dobija proviziju', v_cnt = 0, 'redova: ' || v_cnt);

    -- Lažni token ne sme da realizuje ništa
    INSERT INTO public.bookings (resource_id, booking_date, slot_time, qty, guest_name, guest_phone, status, accommodation_id)
    VALUES (v_res, CURRENT_DATE, '23:03', 1, 'TEST Lažni token', '+381600000003', 'confirmed', v_hot)
    RETURNING id INTO v_book2;
    SELECT * INTO v_r FROM public.redeem_booking('lazan-token', v_book2);
    INSERT INTO st_results VALUES (8, 'Lažni token ne realizuje rezervaciju', v_r.ok = false, v_r.msg);

    -- Obostrana potvrda isplate: tek kad OBE strane potvrde, paid_at se postavlja
    UPDATE public.apartment_commissions SET attraction_paid_confirmed = true WHERE booking_id = v_book;
    UPDATE public.apartment_commissions SET apartment_paid_confirmed = true WHERE booking_id = v_book;
    SELECT paid_at INTO v_paid FROM public.apartment_commissions WHERE booking_id = v_book;
    INSERT INTO st_results VALUES (9, 'Isplata se knjiži kad obe strane potvrde', v_paid IS NOT NULL,
        CASE WHEN v_paid IS NULL THEN 'paid_at je NULL' ELSE 'paid_at postavljen' END);
END;
$$;

SELECT ord AS "#", name AS "Provera",
       CASE WHEN pass THEN '✅ PROŠLO' ELSE '❌ PALO' END AS "Rezultat",
       detail AS "Detalj"
FROM st_results
ORDER BY ord;

ROLLBACK;
