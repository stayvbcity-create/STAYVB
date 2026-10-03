-- ═══════════════════════════════════════════════════════════════════
-- hotel_commission_test.sql — end-to-end test provizije za HOTELE.
--
-- Sve je u jednom DO bloku (jedna transakcija). Na kraju bloka namerno
-- se baca greška koja nosi izveštaj; ona automatski poništava transakciju,
-- pa test partner, rezervacije i provizije NISU ostali u bazi.
-- Izveštaj je u poruci greške (crveno), to je očekivano.
--
-- Preduslov: seed (loadtest_seed_v2.sql) i hotel_commissions.sql.
-- ═══════════════════════════════════════════════════════════════════

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
    v_apt        text;
    v_paid       timestamptz;
    v_report     text := '';
    v_pass       int := 0;
    v_total      int := 0;
    v_ok         boolean;
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

    -- 1. Rezervacija gosta PREMIUM hotela: 2 osobe × 1000 RSD × 10 % = 200 RSD
    INSERT INTO public.bookings (resource_id, booking_date, slot_time, qty, guest_name, guest_phone, status, accommodation_id)
    VALUES (v_res, CURRENT_DATE, '23:01', 2, 'TEST Gost Hotel', '+381600000001', 'confirmed', v_hot)
    RETURNING id INTO v_book;

    SELECT * INTO v_r FROM public.redeem_booking(v_token, v_book);
    v_ok := v_r.ok;
    v_total := v_total + 1; IF v_ok THEN v_pass := v_pass + 1; END IF;
    v_report := v_report || format('%s  Realizacija preko skenera (premium hotel) — %s' || E'\n',
        CASE WHEN v_ok THEN '✅ PROŠLO' ELSE '❌ PALO' END, v_r.msg);

    SELECT count(*), coalesce(max(amount_rsd), 0), coalesce(max(commission_pct_applied), 0), max(apartment_partner_id::text)
    INTO v_cnt, v_amt, v_pct, v_apt
    FROM public.apartment_commissions WHERE booking_id = v_book;

    v_ok := v_cnt = 1;
    v_total := v_total + 1; IF v_ok THEN v_pass := v_pass + 1; END IF;
    v_report := v_report || format('%s  Provizija upisana tačno jednom — redova: %s' || E'\n',
        CASE WHEN v_ok THEN '✅ PROŠLO' ELSE '❌ PALO' END, v_cnt);

    v_ok := v_amt = 200;
    v_total := v_total + 1; IF v_ok THEN v_pass := v_pass + 1; END IF;
    v_report := v_report || format('%s  Iznos = 2 × 1000 × 10 %% = 200 RSD — iznos: %s RSD, %%: %s' || E'\n',
        CASE WHEN v_ok THEN '✅ PROŠLO' ELSE '❌ PALO' END, v_amt, v_pct);

    v_ok := v_apt = v_hot::text;
    v_total := v_total + 1; IF v_ok THEN v_pass := v_pass + 1; END IF;
    v_report := v_report || format('%s  Provizija pripada HOTELU (ne atrakciji) — %s' || E'\n',
        CASE WHEN v_ok THEN '✅ PROŠLO' ELSE '❌ PALO' END, CASE WHEN v_ok THEN 'ok' ELSE 'pogrešan partner' END);

    -- 2. Ponovna realizacija istog koda ne sme da napravi drugu proviziju
    SELECT * INTO v_r FROM public.redeem_booking(v_token, v_book);
    SELECT count(*) INTO v_cnt FROM public.apartment_commissions WHERE booking_id = v_book;
    v_ok := v_r.ok = false;
    v_total := v_total + 1; IF v_ok THEN v_pass := v_pass + 1; END IF;
    v_report := v_report || format('%s  Drugi pokušaj realizacije je odbijen — %s' || E'\n',
        CASE WHEN v_ok THEN '✅ PROŠLO' ELSE '❌ PALO' END, v_r.msg);

    v_ok := v_cnt = 1;
    v_total := v_total + 1; IF v_ok THEN v_pass := v_pass + 1; END IF;
    v_report := v_report || format('%s  Posle drugog pokušaja i dalje 1 provizija — redova: %s' || E'\n',
        CASE WHEN v_ok THEN '✅ PROŠLO' ELSE '❌ PALO' END, v_cnt);

    -- 3. Gost BASIC hotela ne stvara proviziju
    INSERT INTO public.bookings (resource_id, booking_date, slot_time, qty, guest_name, guest_phone, status, accommodation_id)
    VALUES (v_res, CURRENT_DATE, '23:02', 2, 'TEST Gost Basic', '+381600000002', 'confirmed', v_hot_basic)
    RETURNING id INTO v_book2;
    PERFORM public.redeem_booking(v_token, v_book2);
    SELECT count(*) INTO v_cnt FROM public.apartment_commissions WHERE booking_id = v_book2;
    v_ok := v_cnt = 0;
    v_total := v_total + 1; IF v_ok THEN v_pass := v_pass + 1; END IF;
    v_report := v_report || format('%s  Basic hotel NE dobija proviziju — redova: %s' || E'\n',
        CASE WHEN v_ok THEN '✅ PROŠLO' ELSE '❌ PALO' END, v_cnt);

    -- 4. Lažni token ne realizuje rezervaciju
    INSERT INTO public.bookings (resource_id, booking_date, slot_time, qty, guest_name, guest_phone, status, accommodation_id)
    VALUES (v_res, CURRENT_DATE, '23:03', 1, 'TEST Lažni token', '+381600000003', 'confirmed', v_hot)
    RETURNING id INTO v_book2;
    SELECT * INTO v_r FROM public.redeem_booking('lazan-token', v_book2);
    v_ok := v_r.ok = false;
    v_total := v_total + 1; IF v_ok THEN v_pass := v_pass + 1; END IF;
    v_report := v_report || format('%s  Lažni token ne realizuje rezervaciju — %s' || E'\n',
        CASE WHEN v_ok THEN '✅ PROŠLO' ELSE '❌ PALO' END, v_r.msg);

    -- 5. Isplata se knjiži tek kad OBE strane potvrde
    UPDATE public.apartment_commissions SET attraction_paid_confirmed = true WHERE booking_id = v_book;
    UPDATE public.apartment_commissions SET apartment_paid_confirmed = true WHERE booking_id = v_book;
    SELECT paid_at INTO v_paid FROM public.apartment_commissions WHERE booking_id = v_book;
    v_ok := v_paid IS NOT NULL;
    v_total := v_total + 1; IF v_ok THEN v_pass := v_pass + 1; END IF;
    v_report := v_report || format('%s  Isplata se knjiži kad obe strane potvrde — %s' || E'\n',
        CASE WHEN v_ok THEN '✅ PROŠLO' ELSE '❌ PALO' END, CASE WHEN v_ok THEN 'paid_at postavljen' ELSE 'paid_at je NULL' END);

    RAISE EXCEPTION E'\nHOTEL PROVIZIJA TEST: %/% prošlo\n%\n(Ovo je namerna greška: transakcija je poništena, test podaci nisu ostali u bazi.)',
        v_pass, v_total, v_report;
END;
$$;
