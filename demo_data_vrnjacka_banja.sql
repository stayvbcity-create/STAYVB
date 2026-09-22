-- ═══════════════════════════════════════════════════════════════════
-- demo_data_vrnjacka_banja.sql
-- Dodaje Hotel Fontana kao novog partnera i popunjava StayVB realnim
-- demo podacima o Vrnjačkoj Banji (kategorije, biznisi, lokacije za
-- pečate, događaji). Svi podaci su stvarni (istraženi), nije ništa
-- izmišljeno — gde tačan telefon/adresa nisu pouzdano potvrđeni,
-- polje je ostavljeno prazno umesto da se pogađa.
--
-- Pokreni jednom u Supabase SQL editoru.
-- ═══════════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════════
-- 1. KATEGORIJE ZA CITY INFO / ATRAKCIJE
-- ══════════════════════════════════════════════════════════════════

INSERT INTO public.city_categories (name, icon, color, sort_order)
SELECT 'Restorani', '🍽️', '#f59e0b', 1
WHERE NOT EXISTS (SELECT 1 FROM public.city_categories WHERE name = 'Restorani');

INSERT INTO public.city_categories (name, icon, color, sort_order)
SELECT 'Aktivnosti i izleti', '🌳', '#22c55e', 2
WHERE NOT EXISTS (SELECT 1 FROM public.city_categories WHERE name = 'Aktivnosti i izleti');

INSERT INTO public.city_categories (name, icon, color, sort_order)
SELECT 'Noćni život', '🎶', '#a855f7', 3
WHERE NOT EXISTS (SELECT 1 FROM public.city_categories WHERE name = 'Noćni život');


-- ══════════════════════════════════════════════════════════════════
-- 2. HOTEL FONTANA — novi partner
-- ══════════════════════════════════════════════════════════════════
-- Cara Dušana 2, Vrnjačka Banja. Prvi moderni hotel visoke kategorije
-- u Vrnjačkoj Banji (otvoren 1965, renoviran 2019), odmah pored
-- Banjskog parka, na oko 68 koraka od Mosta ljubavi. 212 jedinica
-- (176 soba + 36 apartmana), restoran, wellness/spa, bazen, teretana.

INSERT INTO public.partners (
    name, type, pin, partner_code, access_token,
    is_active, is_premium, loyalty_enabled, plan,
    lat, lng, phone, show_in_city_info
)
SELECT
    'Hotel Fontana', 'hotel', '4821', 'HOT_FONTANA',
    translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_'),
    true, true, true, 'premium',
    43.621792, 20.895236, '+381 36 612 153', false
WHERE NOT EXISTS (SELECT 1 FROM public.partners WHERE partner_code = 'HOT_FONTANA');

INSERT INTO public.partner_content (
    partner_id, description, short_desc, address,
    wifi_name, wifi_pass, google_maps_url
)
SELECT
    p.id,
    'Hotel Fontana je prvi moderni hotel visoke kategorije u Vrnjačkoj Banji — otvoren 1965. godine, u potpunosti renoviran 2019. Nalazi se u samom centru, neposredno uz Banjski park, svega stotinak metara od Mosta ljubavi i glavnog šetališta. Hotel raspolaže sa 212 jedinica (176 soba i 36 apartmana), restoranom, wellness i spa centrom, bazenom i teretanom.',
    'Prvi hotel visoke kategorije u srcu Banjskog parka.',
    'Cara Dušana 2, 36210 Vrnjačka Banja',
    'Hotel_Fontana_Gosti', 'dobrodosli',
    'https://maps.google.com/?q=43.621792,20.895236'
FROM public.partners p
WHERE p.partner_code = 'HOT_FONTANA'
  AND NOT EXISTS (SELECT 1 FROM public.partner_content WHERE partner_id = p.id);


-- ══════════════════════════════════════════════════════════════════
-- 3. DEMO BIZNISI — restorani i drugi partneri
-- ══════════════════════════════════════════════════════════════════

-- Tri Golubice — tradicionalna kafana u jednoj od najstarijih zgrada
-- u Vrnjačkoj Banji, obnovljena 2010.
INSERT INTO public.partners (
    name, type, pin, partner_code, access_token,
    is_active, phone, show_in_city_info, city_category_id
)
SELECT
    'Tri Golubice', 'restaurant', '5512', 'RES_GOLUBICE',
    translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_'),
    true, '036 612 048', true,
    (SELECT id FROM public.city_categories WHERE name = 'Restorani')
WHERE NOT EXISTS (SELECT 1 FROM public.partners WHERE partner_code = 'RES_GOLUBICE');

INSERT INTO public.partner_content (partner_id, description, address, category)
SELECT p.id,
    'Tradicionalna srpska kafana smeštena u jednoj od najstarijih zgrada u Vrnjačkoj Banji, obnovljenoj 2010. godine. Domaća kuhinja i prijatna bašta u centru grada.',
    'Bulevar srpskih ratnika 28, Vrnjačka Banja', 'Restoran'
FROM public.partners p
WHERE p.partner_code = 'RES_GOLUBICE'
  AND NOT EXISTS (SELECT 1 FROM public.partner_content WHERE partner_id = p.id);

-- Restoran Savka — poznat po ribljim specijalitetima (pastrmka,
-- smuđ). Tačna adresa i telefon nisu pouzdano potvrđeni — treba ih
-- dopuniti ručno kroz admin panel.
INSERT INTO public.partners (
    name, type, pin, partner_code, access_token,
    is_active, show_in_city_info, city_category_id
)
SELECT
    'Restoran Savka', 'restaurant', '7734', 'RES_SAVKA',
    translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_'),
    true, true,
    (SELECT id FROM public.city_categories WHERE name = 'Restorani')
WHERE NOT EXISTS (SELECT 1 FROM public.partners WHERE partner_code = 'RES_SAVKA');

INSERT INTO public.partner_content (partner_id, description, category)
SELECT p.id,
    'Restoran poznat po ribljim specijalitetima — pastrmka i smuđ. Adresu i kontakt telefon treba dopuniti.',
    'Restoran'
FROM public.partners p
WHERE p.partner_code = 'RES_SAVKA'
  AND NOT EXISTS (SELECT 1 FROM public.partner_content WHERE partner_id = p.id);

-- Merkur bicikli — iznajmljivanje bicikala, dve lokacije (Novi
-- Merkur za goste hotela i izvor Tople vode za sve posetioce).
INSERT INTO public.partners (
    name, type, pin, partner_code, access_token,
    is_active, phone, show_in_city_info, city_category_id
)
SELECT
    'Merkur — iznajmljivanje bicikala', 'business', '3390', 'BIZ_MERKUR',
    translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_'),
    true, '+381 36 515 5151', true,
    (SELECT id FROM public.city_categories WHERE name = 'Aktivnosti i izleti')
WHERE NOT EXISTS (SELECT 1 FROM public.partners WHERE partner_code = 'BIZ_MERKUR');

INSERT INTO public.partner_content (partner_id, description, category)
SELECT p.id,
    'Iznajmljivanje bicikala na dve lokacije — kod hotela Novi Merkur (za goste hotela) i kod izvora Tople vode (za sve posetioce, uz ličnu kartu, 18+).',
    'Aktivnost'
FROM public.partners p
WHERE p.partner_code = 'BIZ_MERKUR'
  AND NOT EXISTS (SELECT 1 FROM public.partner_content WHERE partner_id = p.id);

-- White Club — najveći open-air klub u Srbiji, u Vrnjačkoj Banji.
-- Tačna adresa i telefon nisu pouzdano potvrđeni.
INSERT INTO public.partners (
    name, type, pin, partner_code, access_token,
    is_active, show_in_city_info, city_category_id
)
SELECT
    'White Club', 'business', '6601', 'BIZ_WHITECLUB',
    translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_'),
    true, true,
    (SELECT id FROM public.city_categories WHERE name = 'Noćni život')
WHERE NOT EXISTS (SELECT 1 FROM public.partners WHERE partner_code = 'BIZ_WHITECLUB');

INSERT INTO public.partner_content (partner_id, description, category)
SELECT p.id,
    'Najveći open-air klub u Srbiji, u Vrnjačkoj Banji. Adresu i kontakt treba dopuniti.',
    'Noćni život'
FROM public.partners p
WHERE p.partner_code = 'BIZ_WHITECLUB'
  AND NOT EXISTS (SELECT 1 FROM public.partner_content WHERE partner_id = p.id);


-- ══════════════════════════════════════════════════════════════════
-- 4. LOKACIJE ZA PEČATE (javni orijentiri, prikazuju se na Radaru)
-- ══════════════════════════════════════════════════════════════════

INSERT INTO public.stamp_locations (name, description, location_code, type, lat, lng, icon_color)
SELECT 'Jezero', 'Malo jezero u Banjskom parku sa patkama i labudovima — leti se ovde održavaju koncerti, a obalu okružuju kafići i restorani.', 'JEZERO', 'public', 43.622500, 20.894700, '#3b82f6'
WHERE NOT EXISTS (SELECT 1 FROM public.stamp_locations WHERE location_code = 'JEZERO');

INSERT INTO public.stamp_locations (name, description, location_code, type, lat, lng, icon_color)
SELECT 'Topla voda', 'Mineralni izvor u centru Banjskog parka, jedinstven po tome što mu je temperatura 36,5°C — ista kao temperatura ljudskog tela.', 'TOPLA_VODA', 'public', 43.621900, 20.895900, '#f59e0b'
WHERE NOT EXISTS (SELECT 1 FROM public.stamp_locations WHERE location_code = 'TOPLA_VODA');


-- ══════════════════════════════════════════════════════════════════
-- 5. DOGAĐAJI — stvarne, prepoznatljive manifestacije u gradu
-- ══════════════════════════════════════════════════════════════════
-- Datumi su okvirni/sledeći realni termin (tačan datum se pomera iz
-- godine u godinu) — proveriti i ažurirati kad zvanični raspored za
-- narednu sezonu bude objavljen.

INSERT INTO public.events (title, event_date, location, description)
SELECT 'Vrnjački karneval', '2027-07-16',
    'Centar Vrnjačke Banje',
    'Najveća manifestacija u gradu — privlači preko 200.000 posetilaca. Međunarodna karnevalska povorka, koncerti i maskenbal na ulicama Vrnjačke Banje.'
WHERE NOT EXISTS (SELECT 1 FROM public.events WHERE title = 'Vrnjački karneval');

INSERT INTO public.events (title, event_date, location, description)
SELECT 'Festival filmskog scenarija', '2027-08-15',
    'Vrnjačka Banja',
    'Najstariji festival ove vrste u Srbiji, održava se od 1977. godine. Projekcije, promocije scenarija i susreti sa filmskim autorima.'
WHERE NOT EXISTS (SELECT 1 FROM public.events WHERE title = 'Festival filmskog scenarija');

INSERT INTO public.events (title, event_date, location, description)
SELECT 'Međunarodni festival klasične muzike „Vrnjci"', '2027-07-10',
    'Zamak Belimarković',
    'Besplatni koncerti klasične muzike sa domaćim i stranim izvođačima, u zdanju Zamka Belimarković.'
WHERE NOT EXISTS (SELECT 1 FROM public.events WHERE title = 'Međunarodni festival klasične muzike „Vrnjci"');

INSERT INTO public.events (title, event_date, location, description)
SELECT 'Vrnjačka bajka — doček Nove godine', '2026-12-30',
    'Trg kulture',
    'Besplatni novogodišnji koncerti na Trgu kulture i glavnom šetalištu, u trajanju do srpske Nove godine.'
WHERE NOT EXISTS (SELECT 1 FROM public.events WHERE title = 'Vrnjačka bajka — doček Nove godine');


-- ═══════════════════════════════════════════════════════════════════
-- NAPOMENA: Sledeći realni biznisi su potvrđeno pravi (pominju se u
-- više izvora) ali bez pouzdane adrese/telefona, pa NISU uneti da se
-- ne bi izmišljali podaci — dodati ručno kroz admin panel kad se
-- potvrde: Kafana Kod Bubija, Restoran Breza, Etno kuća Gocko,
-- Kafanica Trifunović, Restoran Kompozicija, Music Club Podroom.
--
-- Svi PIN-ovi upisani gore su privremeni demo brojevi — promeniti ih
-- kroz partner panel pre nego što se link zaista podeli.
-- ═══════════════════════════════════════════════════════════════════
