-- ═══════════════════════════════════════════════════════════════════
-- loadtest_seed_v2.sql — simulacija 30 hotela, 200 restorana, 300
-- apartmana i 3000 gostiju.
--
-- SVI test-redovi su prepoznatljivo obeleženi:
--   partner_code  LIKE 'TST_%'
--   guests.token  LIKE 'TESTGUEST_%'
-- Čišćenje: loadtest_cleanup.sql (isti kao i za v1).
--
-- Pokreni u Supabase SQL editoru. Traje par sekundi.
-- ═══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- 1. PARTNERI — 30 hotela, 200 restorana, 300 apartmana
-- ══════════════════════════════════════════════════════════════════

-- 30 hotela — svaki treći Premium
INSERT INTO public.partners (name, type, pin, partner_code, access_token, is_active, is_premium, loyalty_enabled, plan, lat, lng, phone, show_in_city_info)
SELECT
    'TEST Hotel ' || i, 'hotel', lpad((1000+i)::text,4,'0'), 'TST_HOTEL_'||i,
    replace(gen_random_uuid()::text,'-',''),
    true, (i % 3 = 0), (i % 3 = 0), CASE WHEN i % 3 = 0 THEN 'premium' ELSE 'basic' END,
    43.6200 + (random()-0.5)*0.03, 20.8950 + (random()-0.5)*0.03,
    '+38160'||lpad((1000000+i)::text,7,'0'), false
FROM generate_series(1,30) i;

-- 200 restorana — svaki peti Premium (hh + city info)
INSERT INTO public.partners (name, type, pin, partner_code, access_token, is_active, is_premium, plan, lat, lng, phone, show_in_city_info)
SELECT
    'TEST Restoran ' || i, 'restaurant', lpad((2000+i)::text,4,'0'), 'TST_REST_'||i,
    replace(gen_random_uuid()::text,'-',''),
    true, (i % 5 = 0), CASE WHEN i % 5 = 0 THEN 'premium' ELSE 'basic' END,
    43.6200 + (random()-0.5)*0.04, 20.8950 + (random()-0.5)*0.04,
    '+38160'||lpad((2000000+i)::text,7,'0'), true
FROM generate_series(1,200) i;

-- 300 apartmana — svaki četvrti Premium
INSERT INTO public.partners (name, type, pin, partner_code, access_token, is_active, is_premium, loyalty_enabled, plan, lat, lng, phone, show_in_city_info)
SELECT
    'TEST Apartman ' || i, 'apartment', lpad((3000+i)::text,4,'0'), 'TST_APT_'||i,
    replace(gen_random_uuid()::text,'-',''),
    true, (i % 4 = 0), (i % 4 = 0), CASE WHEN i % 4 = 0 THEN 'premium' ELSE 'basic' END,
    43.6200 + (random()-0.5)*0.05, 20.8950 + (random()-0.5)*0.05,
    '+38160'||lpad((3000000+i)::text,7,'0'), false
FROM generate_series(1,300) i;

-- ══════════════════════════════════════════════════════════════════
-- 2. PARTNER_CONTENT — po jedan red za svakog test partnera
-- ══════════════════════════════════════════════════════════════════
INSERT INTO public.partner_content (partner_id, wifi_name, wifi_pass, description, category)
SELECT id, 'Test-WiFi-'||partner_code, 'test1234', 'Testni profil za simulaciju opterećenja.',
    CASE type WHEN 'restaurant' THEN 'Restoran' WHEN 'hotel' THEN 'Hotel' ELSE 'Apartman' END
FROM public.partners WHERE partner_code LIKE 'TST_%';

-- ══════════════════════════════════════════════════════════════════
-- 3. HAPPY HOUR — aktivan danas kod ~20% test restorana/hotela
-- ══════════════════════════════════════════════════════════════════
UPDATE public.partners SET hh_active = true, hh_date = CURRENT_DATE,
    hh_start = '17:00', hh_end = '20:00', hh_visibility = 'all'
WHERE partner_code LIKE 'TST_REST_%' AND right(partner_code, 1) IN ('0','5');

UPDATE public.partners SET hh_active = true, hh_date = CURRENT_DATE,
    hh_start = '18:00', hh_end = '19:00', hh_visibility = 'all'
WHERE partner_code LIKE 'TST_HOTEL_%' AND is_premium = true;

-- ══════════════════════════════════════════════════════════════════
-- 4. STAMP LOCATIONS — svaki Premium test-hotel dobija svoju lokaciju
-- ══════════════════════════════════════════════════════════════════
INSERT INTO public.stamp_locations (name, location_code, type, partner_id, lat, lng, is_active)
SELECT 'Pečat — '||name, 'TST_LOC_'||partner_code, 'partner', id, lat, lng, true
FROM public.partners WHERE partner_code LIKE 'TST_HOTEL_%' AND is_premium = true;

-- ══════════════════════════════════════════════════════════════════
-- 5. ACCOMMODATION_LISTINGS — booking ponuda za ~40% premium hotela/apartmana
-- ══════════════════════════════════════════════════════════════════
INSERT INTO public.accommodation_listings (partner_id, title, location_label, description, highlight, guests, bedrooms, bathrooms, price_per_night, amenities, is_active)
SELECT id, name, 'Vrnjačka Banja', 'Testna ponuda za simulaciju booking sistema.', 'Testna oznaka',
    2 + (random()*4)::int, 1 + (random()*3)::int, 1,
    4000 + (random()*8000)::int, ARRAY['wifi','klima'], true
FROM public.partners
WHERE partner_code LIKE 'TST_%' AND type IN ('hotel','apartment') AND is_premium = true
  AND right(partner_code, 1) IN ('1','2','3','4');

-- ══════════════════════════════════════════════════════════════════
-- 6. EVENTS — 15 test događaja u narednih 14 dana
-- ══════════════════════════════════════════════════════════════════
INSERT INTO public.events (title, event_date, location, description)
SELECT 'TEST Događaj '||i, CURRENT_DATE + (i % 14), 'Vrnjačka Banja', 'Testni događaj za simulaciju opterećenja.'
FROM generate_series(1,15) i;

-- ══════════════════════════════════════════════════════════════════
-- 7. GUESTS — 3000 gostiju, raspoređeni na 330 test hotela/apartmana
--    (30 + 300), checkin_date razvučen unazad 0–20 dana
-- ══════════════════════════════════════════════════════════════════
INSERT INTO public.guests (token, accommodation_id, checkin_date, stamp_count, lang)
SELECT
    'TESTGUEST_'||g,
    (SELECT id FROM public.partners WHERE partner_code LIKE 'TST_%' AND type IN ('hotel','apartment')
     OFFSET floor(random()*330) LIMIT 1),
    CURRENT_DATE - (floor(random()*20))::int,
    floor(random()*11)::int,
    (ARRAY['sr','en','de','ru'])[1+floor(random()*4)::int]
FROM generate_series(1,3000) g;

-- ══════════════════════════════════════════════════════════════════
-- 8. STAMPS — pečati za ~1500 od tih gostiju
-- ══════════════════════════════════════════════════════════════════
INSERT INTO public.stamps (guest_id, partner_id, location_id)
SELECT g.id, sl.partner_id, sl.id
FROM public.guests g
JOIN public.stamp_locations sl ON sl.location_code LIKE 'TST_LOC_%'
WHERE g.token LIKE 'TESTGUEST_%' AND random() < 0.5
ORDER BY random()
LIMIT 1500;

-- ══════════════════════════════════════════════════════════════════
-- Gotovo — proveri brojke (očekivano: 530 partnera, 3000 gostiju):
-- ══════════════════════════════════════════════════════════════════
SELECT
  (SELECT count(*) FROM public.partners WHERE partner_code LIKE 'TST_%') AS test_partners,
  (SELECT count(*) FROM public.partners WHERE partner_code LIKE 'TST_HOTEL_%') AS test_hoteli,
  (SELECT count(*) FROM public.partners WHERE partner_code LIKE 'TST_REST_%') AS test_restorani,
  (SELECT count(*) FROM public.partners WHERE partner_code LIKE 'TST_APT_%') AS test_apartmani,
  (SELECT count(*) FROM public.guests WHERE token LIKE 'TESTGUEST_%') AS test_guests,
  (SELECT count(*) FROM public.stamps s JOIN public.guests g ON g.id=s.guest_id WHERE g.token LIKE 'TESTGUEST_%') AS test_stamps,
  (SELECT count(*) FROM public.accommodation_listings al JOIN public.partners p ON p.id=al.partner_id WHERE p.partner_code LIKE 'TST_%') AS test_listings,
  (SELECT count(*) FROM public.events WHERE title LIKE 'TEST Događaj%') AS test_events;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ loadtest_seed_v2.sql
-- ═══════════════════════════════════════════════════════════════════
