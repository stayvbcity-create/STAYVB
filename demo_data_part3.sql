-- ═══════════════════════════════════════════════════════════════════
-- demo_data_part3.sql
-- 1) Uklanja "Nova godina" iz Događaja (na zahtev).
-- 2) Dodaje dva stvarna dešavanja koja realno padaju u narednih 14
--    dana (zato ih "Banja Live" stranica ranije nije prikazivala —
--    ona namerno pokazuje samo dešavanja u tom prozoru, a prethodno
--    uneti festivali su datirani na svoje stvarne termine u
--    julu/avgustu/decembru, van tog opsega). Izvor: zvanični kalendar
--    Turističke organizacije Vrnjačke Banje (vrnjackabanja.co.rs/dogadjaji).
-- ═══════════════════════════════════════════════════════════════════

DELETE FROM public.events WHERE title = 'Vrnjačka bajka — doček Nove godine';

INSERT INTO public.events (title, event_date, location, description)
SELECT '6. ZUM — Međunarodni festival klasične kamerne muzike', '2026-09-24',
    'Zamak kulture Belimarković',
    'Godišnji festival klasične kamerne muzike, nastupi komornih sastava. Traje od 24. do 27. septembra.'
WHERE NOT EXISTS (SELECT 1 FROM public.events WHERE title = '6. ZUM — Međunarodni festival klasične kamerne muzike');

INSERT INTO public.events (title, event_date, location, description)
SELECT 'Prva liga Srbije u šahu — žene i open', '2026-10-04',
    'Vrnjačka Banja',
    'Nacionalno šahovsko takmičenje, ženska i open kategorija. Traje od 4. do 14. oktobra.'
WHERE NOT EXISTS (SELECT 1 FROM public.events WHERE title = 'Prva liga Srbije u šahu — žene i open');

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ demo_data_part3.sql
-- ═══════════════════════════════════════════════════════════════════
