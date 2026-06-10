-- ═══════════════════════════════════════════════════════════════════
-- StayVB v2 — Seed podaci za testiranje
-- Pokreni NAKON schema.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. PARTNERI ─────────────────────────────────────────────────────

INSERT INTO partners (id, name, type, pin, partner_code, is_active, is_premium, loyalty_enabled, has_booking, hh_active, lat, lng, phone, whatsapp) VALUES

-- Apartman FREE
('a1000000-0000-0000-0000-000000000001',
 'Apartman Sunce', 'apartment', '1111', 'APT_SUNCE',
 true, false, false, false, false,
 43.6208, 20.8973, '+381641234001', '+381641234001'),

-- Apartman PREMIUM
('a1000000-0000-0000-0000-000000000002',
 'Vila Marković', 'apartment', '2222', 'APT_MARKO',
 true, true, false, false, false,
 43.6215, 20.8980, '+381641234002', '+381641234002'),

-- Hotel
('a1000000-0000-0000-0000-000000000003',
 'Hotel Fontana', 'hotel', '3333', 'HOT_FONTANA',
 true, true, true, false, false,
 43.6220, 20.8955, '+381641234003', '+381641234003'),

-- Restoran (sa HH)
('a1000000-0000-0000-0000-000000000004',
 'Restoran Vrnjak', 'restaurant', '4444', 'REST_VRNJAK',
 true, true, true, false, true,
 43.6200, 20.8960, '+381641234004', '+381641234004'),

-- Restoran (bez HH trenutno)
('a1000000-0000-0000-0000-000000000005',
 'Kafana Stara Česma', 'restaurant', '5555', 'REST_CESMA',
 true, true, true, false, false,
 43.6195, 20.8970, '+381641234005', '+381641234005'),

-- Mali biznis
('a1000000-0000-0000-0000-000000000006',
 'Kozmetički salon Lana', 'business', '6666', 'BIZ_LANA',
 true, true, false, false, false,
 43.6205, 20.8965, '+381641234006', '+381641234006'),

-- Atrakcija SA bookingom
('a1000000-0000-0000-0000-000000000007',
 'Avantura Park VB', 'attraction', '7777', 'ATR_AVAN',
 true, true, true, true, false,
 43.6188, 20.8950, '+381641234007', '+381641234007'),

-- Atrakcija BEZ bookinga
('a1000000-0000-0000-0000-000000000008',
 'Gradski Bazen', 'attraction', '8888', 'ATR_BAZEN',
 true, true, true, false, false,
 43.6230, 20.8990, '+381641234008', '+381641234008');


-- ── 2. PARTNER CONTENT ──────────────────────────────────────────────

INSERT INTO partner_content (partner_id, short_desc, description, wifi_name, wifi_pass, house_rules, service_prices, extra_offer, google_maps_url, instagram_reel_url, share_gift_text, share_campaign_active, hh_info, current_offer, working_hours, category) VALUES

-- Apartman Sunce (FREE)
('a1000000-0000-0000-0000-000000000001',
 'Udoban apartman u centru Banje',
 'Apartman Sunce nudi sve što vam treba za odmor u Vrnjačkoj Banji.',
 'Sunce_WiFi', 'sunce2024',
 NULL, NULL, NULL, NULL, NULL, NULL, false,
 NULL, NULL, NULL, NULL),

-- Vila Marković (PREMIUM)
('a1000000-0000-0000-0000-000000000002',
 'Luksuzna vila sa bazenom i vrtom',
 'Vila Marković je premium smeštaj sa sopstvenim bazenom, roštiljem i predivnim vrtom. Idealna za porodice i grupe.',
 'VilaMarkovic_5G', 'markovic2024!',
 '• Tišina od 22:00 do 08:00' || chr(10) ||
 '• Zabranjeno pušenje u zatvorenom prostoru' || chr(10) ||
 '• Kućni ljubimci uz prethodnu najavu' || chr(10) ||
 '• Check-out do 11:00h',
 'Doručak u sobu: 600 RSD' || chr(10) ||
 'Transfer aerodrom: 4500 RSD' || chr(10) ||
 'Rent-a-car: od 3500 RSD/dan' || chr(10) ||
 'Masaža (dolazak): 2500 RSD/h',
 '🎁 Kao naš gost dobijate: besplatan doručak prvog jutra, bocu lokalnog vina i popust 15% u Restoranu Vrnjak!',
 'https://maps.google.com/?q=Vila+Markovic+Vrnjacka+Banja',
 'https://www.instagram.com/reel/example123',
 'čaša lokalnog vina i džem od šumskog voća',
 true,
 NULL, NULL, NULL, NULL),

-- Hotel Fontana
('a1000000-0000-0000-0000-000000000003',
 '4* hotel u srcu Vrnjačke Banje',
 'Hotel Fontana je moderan četvorozvezdični hotel sa spa centrom, restoranom i konferencijskim salama. Savršen za odmor i poslovne goste.',
 'Fontana_Hotel', 'fontana2024',
 '• Check-in od 14:00h' || chr(10) ||
 '• Check-out do 12:00h' || chr(10) ||
 '• Spa centar radi 07:00–22:00',
 'Room service: 08:00–22:00' || chr(10) ||
 'Spa tretmani: od 2000 RSD' || chr(10) ||
 'Parking: besplatan',
 '✨ VIP gosti hotela imaju besplatan pristup spa centru i 20% popust u restoranu tokom boravka!',
 'https://maps.google.com/?q=Hotel+Fontana+Vrnjacka+Banja',
 NULL, NULL, false,
 NULL, NULL, 'Non-stop', NULL),

-- Restoran Vrnjak (sa HH)
('a1000000-0000-0000-0000-000000000004',
 'Tradicionalna srpska kuhinja uz reku',
 'Restoran Vrnjak nudi autentičnu srpsku kuhinju sa svežim lokalnim namirnicama. Specijal kuće: jagnjetina ispod sača i domaći roštilj.',
 NULL, NULL, NULL, NULL, NULL,
 'https://maps.google.com/?q=Restoran+Vrnjak+Vrnjacka+Banja',
 NULL, NULL, false,
 '🍺 Happy Hour ponuda: 2 piva po ceni 1! Sva domaća pića -30%. Uz svako piće — čašica šljivovice gratis.',
 NULL, '10:00–24:00', 'srpska kuhinja'),

-- Kafana Stara Česma
('a1000000-0000-0000-0000-000000000005',
 'Tradicionalna kafana u starom delu varoši',
 'Stara Česma je kafana sa tradicijom dužom od 50 godina. Domaća jela, živa muzika vikendom i prijatna atmosfera.',
 NULL, NULL, NULL, NULL, NULL,
 'https://maps.google.com/?q=Kafana+Stara+Cesma+Vrnjacka+Banja',
 NULL, NULL, false,
 NULL, NULL, '08:00–01:00', 'srpska kuhinja'),

-- Kozmetički salon Lana
('a1000000-0000-0000-0000-000000000006',
 'Profesionalna kozmetika i masaže',
 'Salon Lana nudi kompletne kozmetičke usluge: tretmane lica, manikir, pedikir i relaks masaže. Rezervišite termin unapred.',
 NULL, NULL, NULL, NULL, NULL,
 'https://maps.google.com/?q=Kozmeticki+salon+Lana+Vrnjacka+Banja',
 NULL, NULL, false,
 NULL,
 '💅 Ovaj mesec: Manikir + Pedikir = 2200 RSD (uštedite 500 RSD). Rezervacija obavezna!',
 'Pon–Sub 09:00–20:00', 'kozmetika'),

-- Avantura Park VB (sa bookingom)
('a1000000-0000-0000-0000-000000000007',
 'Kvadovi, paintball i zip-line avantura',
 'Avantura Park VB nudi uzbudljive outdoor aktivnosti za sve uzraste. Kvadovi, paintball, zip-line i terenska vozila — sve na jednom mestu!',
 NULL, NULL, NULL, NULL, NULL,
 'https://maps.google.com/?q=Avantura+Park+Vrnjacka+Banja',
 NULL, NULL, false,
 NULL, NULL, 'Svaki dan 09:00–19:00', 'outdoor'),

-- Gradski Bazen (bez bookinga)
('a1000000-0000-0000-0000-000000000008',
 'Olimpijski bazen i dečija zona',
 'Gradski Bazen Vrnjačke Banje ima olimpijski bazen, dečiju zonu sa toboganimana i kafić. Sezonski rad jun–septembar.',
 NULL, NULL, NULL, NULL, NULL,
 'https://maps.google.com/?q=Gradski+Bazen+Vrnjacka+Banja',
 NULL, NULL, false,
 NULL, NULL, '09:00–20:00 (Jun–Sep)', 'sport');


-- ── 3. RESURSI ZA BOOKING (Avantura Park) ───────────────────────────

INSERT INTO bookable_resources (partner_id, name, description, total_qty, duration_min, slot_start, slot_end, slot_interval_min, price_rsd, is_active, sort_order) VALUES

('a1000000-0000-0000-0000-000000000007',
 'Kvadovi', 'ATV quad vozila za terenska avantura tura',
 5, 60, '09:00', '18:00', 60, 2500, true, 1),

('a1000000-0000-0000-0000-000000000007',
 'Paintball', 'Paintball bitka — 2 tima, 50 metaka po igraču',
 12, 60, '10:00', '17:00', 60, 1800, true, 2),

('a1000000-0000-0000-0000-000000000007',
 'Zip-line', 'Zip-line staza kroz šumu, 400m',
 1, 30, '09:00', '18:00', 30, 1200, true, 3),

('a1000000-0000-0000-0000-000000000007',
 'Terenska vozila', 'Off-road buggy vozila za 2 osobe',
 3, 90, '09:00', '17:00', 90, 3500, true, 4);


-- ── 4. HH PODACI ZA RESTORAN VRNJAK ─────────────────────────────────

UPDATE partners
SET
    hh_active = true,
    hh_date   = CURRENT_DATE,
    hh_start  = '17:00',
    hh_end    = '19:00'
WHERE id = 'a1000000-0000-0000-0000-000000000004';


-- ── 5. EVENTI ────────────────────────────────────────────────────────

INSERT INTO events (partner_id, title, event_date, event_time, location, description, is_active) VALUES

-- Gradski događaj (partner_id = NULL)
(NULL,
 'Letnji festival folklora',
 CURRENT_DATE + 2,
 '19:00',
 'Centralni park Vrnjačke Banje',
 'Folklorni nastupi ansambala iz cele Srbije. Slobodan ulaz.',
 true),

(NULL,
 'Manifestacija vina i sira',
 CURRENT_DATE + 5,
 '11:00',
 'Šetališta Vrnjačke Banje',
 'Degustacija lokalnih vina i sireva. Ulaz 500 RSD.',
 true),

-- Event od hotela
('a1000000-0000-0000-0000-000000000003',
 'Večera uz live džez',
 CURRENT_DATE + 1,
 '20:00',
 'Restoran Hotel Fontana',
 'Specijalna večera uz live džez muziku. Rezervacija obavezna. Cena po osobi 3500 RSD.',
 true),

-- Event od kafane
('a1000000-0000-0000-0000-000000000005',
 'Živa muzika — vikend večer',
 CURRENT_DATE,
 '21:00',
 'Kafana Stara Česma',
 'Srpska narodna muzika sa bendom. Ulaz slobodan.',
 true);


-- ── 6. TEST GOST ─────────────────────────────────────────────────────

INSERT INTO guests (id, token, accommodation_id, checkin_date, stamp_count) VALUES
('b2000000-0000-0000-0000-000000000001',
 'test-guest-token-001',
 'a1000000-0000-0000-0000-000000000002',
 CURRENT_DATE,
 3);

-- Test pečati za tog gosta
INSERT INTO stamps (guest_id, partner_id) VALUES
('b2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000004'),
('b2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000007'),
('b2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000008');


-- ── 7. TEST REZERVACIJA ──────────────────────────────────────────────

-- Uzimamo id resursa za Kvadove
INSERT INTO bookings (resource_id, guest_id, booking_date, slot_time, qty, guest_name, guest_phone, status)
SELECT
    r.id,
    'b2000000-0000-0000-0000-000000000001',
    CURRENT_DATE + 1,
    '10:00',
    2,
    'Marko Petrović',
    '+381641234999',
    'confirmed'
FROM bookable_resources r
WHERE r.partner_id = 'a1000000-0000-0000-0000-000000000007'
  AND r.name = 'Kvadovi'
LIMIT 1;


-- ═══════════════════════════════════════════════════════════════════
-- VERIFIKACIJA — pokreni da provjeriš da je sve ok
-- ═══════════════════════════════════════════════════════════════════
/*
SELECT type, COUNT(*) FROM partners GROUP BY type ORDER BY type;
SELECT name, total_qty, price_rsd FROM bookable_resources ORDER BY sort_order;
SELECT title, event_date FROM events ORDER BY event_date;
SELECT name, stamp_count FROM guests;
SELECT * FROM get_free_slots(
    (SELECT id FROM bookable_resources WHERE name = 'Kvadovi' LIMIT 1),
    CURRENT_DATE + 1,
    1
);
*/

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ SEED.SQL
-- Nastavi sa lang-init.js i zatim HTML fajlovima
-- ═══════════════════════════════════════════════════════════════════
