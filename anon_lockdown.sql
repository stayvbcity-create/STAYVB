-- ═══════════════════════════════════════════════════════════════════
-- anon_lockdown.sql — javni (anon) ključ više ne sme da menja tuđe
-- podatke. Upis u tabele panela partnera dozvoljen je samo kad zaglavlje
-- x-partner-token odgovara partneru čiji se red menja.
--
-- Čitanje (SELECT) ostaje isto kao pre. Gostinski upisi (rezervacija,
-- gost, analitika, prijave...) ostaju netaknuti.
--
-- Pokreni jednom u Supabase SQL editoru (sve odjednom).
-- ═══════════════════════════════════════════════════════════════════

-- 1. Pomoćne funkcije: token iz zaglavlja i provera vlasništva
CREATE OR REPLACE FUNCTION public.current_partner_token()
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT coalesce(nullif(current_setting('request.headers', true), '')::json->>'x-partner-token', '')
$$;

CREATE OR REPLACE FUNCTION public.owns_partner(p_partner_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.partners p
        WHERE p.id = p_partner_id
          AND p.access_token = public.current_partner_token()
          AND p.access_token <> ''
    )
$$;

GRANT EXECUTE ON FUNCTION public.current_partner_token() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.owns_partner(uuid) TO anon, authenticated;

-- 2. Ukloni sve postojeće anon/public upisne politike na tabelama panela.
--    Ako je politika bila ALL (sadrži i SELECT), prvo sačuvaj njen SELECT deo.
--    Gostinski INSERT na bookings i accommodation_inquiries se NE dira.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT schemaname, tablename, policyname, cmd, roles, qual
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('partners','partner_content','bookable_resources','events',
                            'accommodation_listings','accommodation_inquiries','billing',
                            'bookings','apartment_commissions')
          AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
          AND (roles && ARRAY['anon','public']::name[])
          AND NOT (cmd = 'INSERT' AND tablename IN ('bookings','accommodation_inquiries'))
    LOOP
        IF r.cmd = 'ALL' AND r.qual IS NOT NULL THEN
            EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', r.policyname || '_read', r.schemaname, r.tablename);
            EXECUTE format('CREATE POLICY %I ON %I.%I FOR SELECT TO anon, authenticated USING (%s)',
                           r.policyname || '_read', r.schemaname, r.tablename, r.qual);
        END IF;
        EXECUTE format('DROP POLICY %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
    END LOOP;
END $$;

-- 3. RLS uključen na svim tabelama; ako RLS nije bio uključen, sačuvaj čitanje
DO $
DECLARE
    t text;
    had_rls boolean;
BEGIN
    FOREACH t IN ARRAY ARRAY['partners','partner_content','bookable_resources','events',
                             'accommodation_listings','accommodation_inquiries','billing',
                             'bookings','apartment_commissions'] LOOP
        SELECT relrowsecurity INTO had_rls FROM pg_class WHERE oid = format('public.%I', t)::regclass;
        IF NOT had_rls THEN
            EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_read_all', t);
            EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO anon, authenticated USING (true)',
                           t || '_read_all', t);
        END IF;
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    END LOOP;
END $$;

-- 4. Admin (authenticated, is_admin) zadržava punu kontrolu
DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['partners','partner_content','bookable_resources','events',
                             'accommodation_listings','accommodation_inquiries','billing',
                             'bookings','apartment_commissions'] LOOP
        EXECUTE format('DROP POLICY IF EXISTS lockdown_admin_all ON public.%I', t);
        EXECUTE format('CREATE POLICY lockdown_admin_all ON public.%I FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())', t);
    END LOOP;
END $$;

-- 5. Grantovi: anon više nema pravo na upis osim gde je panelu potrebno,
--    i to uvek uz RLS proveru vlasništva iz koraka 6
REVOKE INSERT, UPDATE, DELETE ON public.partners, public.partner_content, public.bookable_resources,
    public.events, public.accommodation_listings, public.accommodation_inquiries, public.billing,
    public.bookings, public.apartment_commissions FROM anon;
GRANT INSERT ON public.accommodation_inquiries TO anon;
GRANT INSERT ON public.bookings TO anon;
GRANT UPDATE (hh_active, hh_date, hh_start, hh_end, hh_visibility, has_booking,
              commission_sharing_active, apartment_commission_pct) ON public.partners TO anon;
GRANT INSERT, UPDATE ON public.partner_content TO anon;
GRANT INSERT, UPDATE ON public.bookable_resources TO anon;
GRANT INSERT, DELETE ON public.events TO anon;
GRANT INSERT, UPDATE ON public.accommodation_listings TO anon;
GRANT INSERT ON public.billing TO anon;
GRANT UPDATE (status) ON public.bookings TO anon;
GRANT UPDATE (attraction_paid_confirmed, apartment_paid_confirmed) ON public.apartment_commissions TO anon;
GRANT UPDATE (status) ON public.accommodation_inquiries TO anon;

-- 6. Vlasnički uslovi (anon, samo uz x-partner-token)
DROP POLICY IF EXISTS owner_partners ON public.partners;
CREATE POLICY owner_partners ON public.partners FOR UPDATE TO anon
    USING (public.owns_partner(id)) WITH CHECK (public.owns_partner(id));

DROP POLICY IF EXISTS owner_partner_content ON public.partner_content;
CREATE POLICY owner_partner_content ON public.partner_content FOR ALL TO anon
    USING (public.owns_partner(partner_id)) WITH CHECK (public.owns_partner(partner_id));

DROP POLICY IF EXISTS owner_bookable_resources ON public.bookable_resources;
CREATE POLICY owner_bookable_resources ON public.bookable_resources FOR ALL TO anon
    USING (public.owns_partner(partner_id)) WITH CHECK (public.owns_partner(partner_id));

DROP POLICY IF EXISTS owner_events ON public.events;
CREATE POLICY owner_events ON public.events FOR ALL TO anon
    USING (public.owns_partner(partner_id)) WITH CHECK (public.owns_partner(partner_id));

DROP POLICY IF EXISTS owner_accommodation_listings ON public.accommodation_listings;
CREATE POLICY owner_accommodation_listings ON public.accommodation_listings FOR ALL TO anon
    USING (public.owns_partner(partner_id)) WITH CHECK (public.owns_partner(partner_id));

DROP POLICY IF EXISTS owner_accommodation_inquiries ON public.accommodation_inquiries;
CREATE POLICY owner_accommodation_inquiries ON public.accommodation_inquiries FOR UPDATE TO anon
    USING (public.owns_partner(partner_id)) WITH CHECK (public.owns_partner(partner_id));

DROP POLICY IF EXISTS owner_billing ON public.billing;
CREATE POLICY owner_billing ON public.billing FOR INSERT TO anon
    WITH CHECK (public.owns_partner(partner_id));

DROP POLICY IF EXISTS owner_bookings ON public.bookings;
CREATE POLICY owner_bookings ON public.bookings FOR UPDATE TO anon
    USING (EXISTS (SELECT 1 FROM public.bookable_resources r
                   WHERE r.id = bookings.resource_id AND public.owns_partner(r.partner_id)))
    WITH CHECK (EXISTS (SELECT 1 FROM public.bookable_resources r
                        WHERE r.id = bookings.resource_id AND public.owns_partner(r.partner_id)));

DROP POLICY IF EXISTS owner_apartment_commissions ON public.apartment_commissions;
CREATE POLICY owner_apartment_commissions ON public.apartment_commissions FOR UPDATE TO anon
    USING (public.owns_partner(apartment_partner_id) OR public.owns_partner(attraction_partner_id))
    WITH CHECK (public.owns_partner(apartment_partner_id) OR public.owns_partner(attraction_partner_id));

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ anon_lockdown.sql
-- ═══════════════════════════════════════════════════════════════════
