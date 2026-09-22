-- ═══════════════════════════════════════════════════════════════════
-- demo_data_part2.sql
-- NASTAVAK demo_data_vrnjacka_banja.sql — POKRENI TEK POSLE NJEGA,
-- jer se ovde referenciraju partner_code vrednosti koje on kreira
-- (HOT_FONTANA, RES_GOLUBICE, RES_SAVKA, BIZ_MERKUR, BIZ_WHITECLUB).
--
-- Dodaje: 1) realne atrakcije (akva park, zoo vrt, vidikovac,
-- avantura park), 2) Happy Hour demo ponude za postojeće partnere —
-- pošto sistem dozvoljava samo JEDAN aktivan termin po partneru,
-- raspoređeno je po jedan partner dnevno kroz narednih 5 dana,
-- 3) popunjen profil Hotela Fontana (kućni red, pogodnosti, servisi).
-- ═══════════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════════
-- 1. ATRAKCIJE — stvarne, istražene na netu
-- ══════════════════════════════════════════════════════════════════

-- Aqua Park Raj
INSERT INTO public.partners (
    name, type, pin, partner_code, access_token,
    is_active, phone, show_in_city_info, city_category_id
)
SELECT
    'Aqua Park Raj', 'attraction', '2201', 'ATR_AQUAPARK',
    translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_'),
    true, '+381 64 846 0665', true,
    (SELECT id FROM public.city_categories WHERE name = 'Aktivnosti i izleti')
WHERE NOT EXISTS (SELECT 1 FROM public.partners WHERE partner_code = 'ATR_AQUAPARK');

INSERT INTO public.partner_content (partner_id, description, address, category, working_hours)
SELECT p.id,
    'Akva park na 3,5 hektara sa bazenima i toboganima za decu i odrasle. Ležaljke i suncobrani uključeni u cenu ulaznice, uz restoran i Pool Bar.',
    'Olimpijska 29a, 36210 Vrnjačka Banja', 'Atrakcija', 'Svaki dan 10–18h (sezonski, letnji period)'
FROM public.partners p
WHERE p.partner_code = 'ATR_AQUAPARK'
  AND NOT EXISTS (SELECT 1 FROM public.partner_content WHERE partner_id = p.id);

-- Zoo vrt Vrnjci
INSERT INTO public.partners (
    name, type, pin, partner_code, access_token,
    is_active, phone, show_in_city_info, city_category_id
)
SELECT
    'Zoo vrt Vrnjci', 'attraction', '1206', 'ATR_ZOOVRNJCI',
    translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_'),
    true, '064 64 161 61', true,
    (SELECT id FROM public.city_categories WHERE name = 'Aktivnosti i izleti')
WHERE NOT EXISTS (SELECT 1 FROM public.partners WHERE partner_code = 'ATR_ZOOVRNJCI');

INSERT INTO public.partner_content (partner_id, description, address, category)
SELECT p.id,
    'Zoološki vrt na 3,5 hektara sa preko 120 vrsta životinja, nastao iz privatne kolekcije ptica osnovane 2006. godine. Suvenirnica, dečije igralište, dva jezera i staze za šetnju.',
    'Moravska dolina 1/a, 36217 Vrnjci (oko 4 km od centra Vrnjačke Banje)', 'Atrakcija'
FROM public.partners p
WHERE p.partner_code = 'ATR_ZOOVRNJCI'
  AND NOT EXISTS (SELECT 1 FROM public.partner_content WHERE partner_id = p.id);

-- Stakleni vidikovac — besplatan javni orijentir, bez telefona/koordinata
INSERT INTO public.partners (
    name, type, pin, partner_code, access_token,
    is_active, show_in_city_info, city_category_id
)
SELECT
    'Stakleni vidikovac', 'attraction', '2404', 'ATR_VIDIKOVAC',
    translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_'),
    true, true,
    (SELECT id FROM public.city_categories WHERE name = 'Aktivnosti i izleti')
WHERE NOT EXISTS (SELECT 1 FROM public.partners WHERE partner_code = 'ATR_VIDIKOVAC');

INSERT INTO public.partner_content (partner_id, description, address, category)
SELECT p.id,
    'Prvi stakleni vidikovac u Srbiji, 24 metra iznad Šetališta. Pogled na platо biblioteke, izvor Tople vode, reku Vrnjačku i Centralni park. Besplatan ulaz.',
    'Crkveno brdo, iznad Šetališta, iznad spomenika „Muza sa feniksom"', 'Atrakcija'
FROM public.partners p
WHERE p.partner_code = 'ATR_VIDIKOVAC'
  AND NOT EXISTS (SELECT 1 FROM public.partner_content WHERE partner_id = p.id);

-- Avantura park (poligon sa preprekama + zip-line)
INSERT INTO public.partners (
    name, type, pin, partner_code, access_token,
    is_active, phone, show_in_city_info, city_category_id
)
SELECT
    'Avantura park', 'attraction', '0915', 'ATR_AVANTURA',
    translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_'),
    true, '036 611 105', true,
    (SELECT id FROM public.city_categories WHERE name = 'Aktivnosti i izleti')
WHERE NOT EXISTS (SELECT 1 FROM public.partners WHERE partner_code = 'ATR_AVANTURA');

INSERT INTO public.partner_content (partner_id, description, address, category)
SELECT p.id,
    '9 prepreka za ravnotežu i spretnost plus zip-line za najmlađe (minimalna visina 115 cm). Sertifikovani instruktori. Isti organizator vodi i ATV ture, streličarstvo i planinarenje na Goču.',
    'Gradski park, kod Muzičkog paviljona, Vrnjačka Banja', 'Atrakcija'
FROM public.partners p
WHERE p.partner_code = 'ATR_AVANTURA'
  AND NOT EXISTS (SELECT 1 FROM public.partner_content WHERE partner_id = p.id);


-- ══════════════════════════════════════════════════════════════════
-- 2. HAPPY HOUR — demo ponude za postojeće partnere
-- ══════════════════════════════════════════════════════════════════
-- Sistem drži samo JEDAN aktivan HH termin po partneru (hh_date je
-- jedno polje, ne raspored) — zato je raspoređeno po jedan partner
-- dnevno kroz narednih 5 dana, umesto svi odjednom na 7 dana.
-- Ponude su demo/izmišljen sadržaj (kako i treba za promotivni tekst),
-- za razliku od imena/adresa biznisa gore koji su stvarni.

UPDATE public.partners SET hh_active = true, hh_date = CURRENT_DATE,
    hh_start = '17:00', hh_end = '19:00', hh_visibility = 'all'
WHERE partner_code = 'RES_GOLUBICE';
UPDATE public.partner_content SET hh_info = '20% popusta na sva pića uz svaku porudžbinu jela.'
WHERE partner_id = (SELECT id FROM public.partners WHERE partner_code = 'RES_GOLUBICE');

UPDATE public.partners SET hh_active = true, hh_date = CURRENT_DATE + 1,
    hh_start = '18:00', hh_end = '20:00', hh_visibility = 'all'
WHERE partner_code = 'RES_SAVKA';
UPDATE public.partner_content SET hh_info = 'Happy hour na riblje specijalitete — pastrmka i smuđ po sniženoj ceni.'
WHERE partner_id = (SELECT id FROM public.partners WHERE partner_code = 'RES_SAVKA');

UPDATE public.partners SET hh_active = true, hh_date = CURRENT_DATE + 2,
    hh_start = '18:00', hh_end = '19:00', hh_visibility = 'all'
WHERE partner_code = 'HOT_FONTANA';
UPDATE public.partner_content SET hh_info = '20% popusta na koktele u hotelskom baru, za goste hotela i grada.'
WHERE partner_id = (SELECT id FROM public.partners WHERE partner_code = 'HOT_FONTANA');

UPDATE public.partners SET hh_active = true, hh_date = CURRENT_DATE + 3,
    hh_start = '12:00', hh_end = '14:00', hh_visibility = 'all'
WHERE partner_code = 'BIZ_MERKUR';
UPDATE public.partner_content SET hh_info = '30% popusta na iznajmljivanje bicikala u periodu 12–14h.'
WHERE partner_id = (SELECT id FROM public.partners WHERE partner_code = 'BIZ_MERKUR');

UPDATE public.partners SET hh_active = true, hh_date = CURRENT_DATE + 4,
    hh_start = '22:00', hh_end = '23:00', hh_visibility = 'all'
WHERE partner_code = 'BIZ_WHITECLUB';
UPDATE public.partner_content SET hh_info = '2+1 na koktele od 22h do 23h.'
WHERE partner_id = (SELECT id FROM public.partners WHERE partner_code = 'BIZ_WHITECLUB');


-- ══════════════════════════════════════════════════════════════════
-- 3. PROFIL HOTELA FONTANA — kućni red, pogodnosti, servisi
-- ══════════════════════════════════════════════════════════════════
-- Standardni sadržaj za hotel ove kategorije — potvrđene činjenice
-- (pet-friendly, punjačka stanica, wellness/spa/bazen/teretana) su iz
-- ranijeg istraživanja; vreme prijave/odjave je uobičajen standard.
-- Ovo je startni tekst — hotel treba da ga pregleda i prilagodi.

UPDATE public.partner_content SET
    house_rules = 'Prijava (check-in): od 14:00č. Odjava (check-out): do 11:00č. Doručak je uključen u cenu boravka i služi se u hotelskom restoranu. Kućni ljubimci su dobrodošli uz prethodnu najavu, bez doplate. Pušenje je dozvoljeno isključivo na za to predviđenim mestima.',
    extra_offer = 'Gosti hotela imaju besplatan pristup wellness i spa centru, bazenu i teretani. Na raspolaganju je punjačka stanica za električna vozila.',
    service_prices = 'Servis u sobi, usluga pranja veša, iznajmljivanje bicikala (u saradnji sa Merkur biciklima) i organizacija izleta/transfera — sve uz najavu na recepciji.'
WHERE partner_id = (SELECT id FROM public.partners WHERE partner_code = 'HOT_FONTANA');


-- ═══════════════════════════════════════════════════════════════════
-- KRAJ demo_data_part2.sql
-- ═══════════════════════════════════════════════════════════════════
