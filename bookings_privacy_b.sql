-- ═══════════════════════════════════════════════════════════════════
-- bookings_privacy_b.sql — KORAK 2 (pokreni TEK POSLE deploy-a novog koda).
--
-- Zatvara javno čitanje rezervacija i provizija i direktan upis rezervacija
-- preko anon ključa. Posle ovoga anon ključ vidi samo ono što su funkcije
-- iz koraka 1 i ono što je vlasnik (sa svojim tokenom) dobio.
-- ═══════════════════════════════════════════════════════════════════

-- Ukloni sve anon SELECT politike na bookings i apartment_commissions,
-- osim vlasničkih (owner_*) koje je korak 1 dodao.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('bookings', 'apartment_commissions')
          AND cmd IN ('SELECT', 'ALL')
          AND (roles && ARRAY['anon', 'public']::name[])
          AND policyname NOT LIKE 'owner\_%'
    LOOP
        EXECUTE format('DROP POLICY %I ON public.%I', r.policyname, r.tablename);
    END LOOP;
END $$;

-- Gost više ne upisuje rezervacije direktno (ide kroz create_guest_booking)
REVOKE INSERT ON public.bookings FROM anon;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ bookings_privacy_b.sql
-- ═══════════════════════════════════════════════════════════════════
