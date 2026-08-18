-- ═══════════════════════════════════════════════════════════════════
-- StayVB v2 — Bezbednosna nadogradnja #2 (RLS + admin auth + funkcije)
-- Pokreni NAKON pregleda. Testiraj na staging/branch pre produkcije ako je moguce.
--
-- PRE POKRETANJA:
--   1. Kreiraj Supabase Auth korisnika za marko.predolac85@gmail.com
--      (Dashboard -> Authentication -> Users -> Add User -> Auto Confirm User)
--   2. Dashboard -> Authentication -> Sign In / Providers -> Email ->
--      iskljuci "Allow new users to sign up" (da niko ne moze da napravi
--      sopstveni authenticated nalog i zaobidje is_admin() proveru)
-- ═══════════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════════
-- 1. ADMIN IDENTITET — admin_users tabela + is_admin() helper
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.admin_users (
    email TEXT PRIMARY KEY
);

REVOKE ALL ON public.admin_users FROM anon, authenticated;
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;
-- Namerno bez ijedne RLS politike: niko (anon/authenticated) ne moze
-- direktno da cita/pise ovu tabelu. Samo is_admin() (SECURITY DEFINER)
-- moze da je cita, jer se izvrsava sa pravima vlasnika.

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.admin_users
        WHERE email = (auth.jwt() ->> 'email')
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated;

INSERT INTO public.admin_users(email) VALUES ('marko.predolac85@gmail.com')
ON CONFLICT (email) DO NOTHING;


-- ══════════════════════════════════════════════════════════════════
-- 2. OPASNE / MRTVE FUNKCIJE — ukloni ili zakljucaj
-- ══════════════════════════════════════════════════════════════════

-- partner_login(p_pin text) — jednoargumentna varijanta, KRITICNO:
-- trazi partnera po PIN-u kroz CELU tabelu, bez tokena, bez limita
-- pokusaja, bez logovanja. Aplikacija je nikad ne poziva (config.js
-- poziva samo partner_login(p_token, p_pin)). Brisanje je bezbedno.
DROP FUNCTION IF EXISTS public.partner_login(text);

-- admin_change_pin i cleanup_old_data nisu pozvane ni sa jedne
-- stranice, ali su SECURITY DEFINER i trenutno izvrsive od anon role.
-- Zakljucavamo ih ispod (odeljak 4) umesto brisanja, za slucaj da se
-- koriste rucno iz SQL editora.


-- ══════════════════════════════════════════════════════════════════
-- 3. ADMIN FUNKCIJE — dodaj is_admin() proveru + fiksiraj search_path
--    (definicije kopirane 1:1 iz zive baze, samo dodata provera na vrhu)
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_change_pin(p_partner_id uuid, p_new_pin text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_name TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'access denied' USING ERRCODE = '42501';
    END IF;

    UPDATE partners
    SET pin = p_new_pin
    WHERE id = p_partner_id
    RETURNING name INTO v_name;

    IF NOT FOUND THEN RETURN false; END IF;

    INSERT INTO audit_log(action, target_id, target_name, details)
    VALUES ('pin_changed', p_partner_id, v_name, jsonb_build_object('changed_at', NOW()));

    DELETE FROM login_attempts la
    USING partners p
    WHERE p.id = p_partner_id
      AND la.access_token = p.access_token;

    RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_create_partner(
    p_name text, p_type text, p_pin text, p_plan text DEFAULT 'basic'::text,
    p_partner_code text DEFAULT NULL::text, p_phone text DEFAULT NULL::text,
    p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric
)
RETURNS TABLE(partner_id uuid, partner_code text, access_token text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_id    UUID;
    v_token TEXT;
    v_code  TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'access denied' USING ERRCODE = '42501';
    END IF;

    v_token := translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_');
    v_code  := COALESCE(p_partner_code,
                   upper(substr(p_type,1,3)) || '_' ||
                   upper(substr(regexp_replace(p_name,'[^a-zA-Z0-9]','','g'),1,5)) || '_' ||
                   floor(random()*900+100)::TEXT);
    INSERT INTO partners(name, type, pin, partner_code, access_token, phone, lat, lng, plan)
    VALUES (p_name, p_type, p_pin, v_code, v_token, p_phone, p_lat, p_lng, p_plan)
    RETURNING id INTO v_id;
    INSERT INTO partner_content(partner_id) VALUES (v_id) ON CONFLICT DO NOTHING;
    INSERT INTO audit_log(action, target_id, target_name, details)
    VALUES ('partner_created', v_id, p_name,
            jsonb_build_object('type',p_type,'code',v_code,'plan',p_plan));
    RETURN QUERY SELECT v_id, v_code, v_token;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cleanup_old_data()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'access denied' USING ERRCODE = '42501';
    END IF;

    DELETE FROM login_attempts WHERE attempted_at < NOW() - INTERVAL '1 hour';
    DELETE FROM analytics_clicks WHERE created_at < NOW() - INTERVAL '30 days';
    DELETE FROM audit_log WHERE performed_at < NOW() - INTERVAL '90 days';
END;
$function$;

CREATE OR REPLACE FUNCTION public.generate_monthly_billing(p_month text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_month TEXT := COALESCE(p_month, to_char(NOW(), 'YYYY-MM'));
    v_count INTEGER := 0;
    v_partner RECORD;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'access denied' USING ERRCODE = '42501';
    END IF;

    FOR v_partner IN SELECT id, monthly_price FROM partners WHERE is_active = true
    LOOP
        INSERT INTO partner_billing (partner_id, month_year, status, amount_rsd, due_date)
        VALUES (v_partner.id, v_month, 'pending', COALESCE(v_partner.monthly_price,0),
                (to_date(v_month,'YYYY-MM') + INTERVAL '1 month' - INTERVAL '1 day')::DATE)
        ON CONFLICT (partner_id, month_year) DO NOTHING;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_system_stats()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE v_month TEXT := to_char(NOW(), 'YYYY-MM');
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'access denied' USING ERRCODE = '42501';
    END IF;

    RETURN (SELECT json_build_object(
        'total_partners',   (SELECT COUNT(*) FROM partners WHERE is_active = true),
        'premium_partners', (SELECT COUNT(*) FROM partners WHERE is_active = true AND is_premium = true),
        'partners_paid',    (SELECT COUNT(*) FROM partner_billing WHERE month_year = v_month AND status = 'paid'),
        'partners_pending', (SELECT COUNT(*) FROM partners WHERE is_active = true
                              AND id NOT IN (SELECT partner_id FROM partner_billing WHERE month_year = v_month AND status = 'paid')),
        'revenue_month',    (SELECT COALESCE(SUM(amount_rsd),0) FROM partner_billing WHERE month_year = v_month AND status = 'paid'),
        'revenue_pending',  (SELECT COALESCE(SUM(monthly_price),0) FROM partners WHERE is_active = true
                              AND id NOT IN (SELECT partner_id FROM partner_billing WHERE month_year = v_month AND status = 'paid')),
        'total_guests',     (SELECT COUNT(*) FROM guests),
        'guests_today',     (SELECT COUNT(*) FROM guests WHERE DATE(created_at) = CURRENT_DATE),
        'total_stamps',     (SELECT COUNT(*) FROM stamps),
        'hh_today',         (SELECT COUNT(*) FROM partners WHERE is_active = true AND hh_active = true AND hh_date = CURRENT_DATE),
        'pending_rewards',  (SELECT COUNT(*) FROM guests WHERE reward_claimed = true AND reward_status = 'pending'),
        'total_bookings',   (SELECT COUNT(*) FROM bookings),
        'top_partners',     (SELECT json_agg(t) FROM (
                                SELECT p.name, COUNT(a.id) AS scans
                                FROM partners p
                                LEFT JOIN analytics_clicks a ON a.partner_id = p.id
                                    AND a.created_at > NOW() - INTERVAL '30 days'
                                WHERE p.is_active = true
                                GROUP BY p.id, p.name
                                ORDER BY scans DESC LIMIT 5
                             ) t)
    ));
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_payment(p_partner_id uuid, p_month text, p_paid boolean)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_price INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'access denied' USING ERRCODE = '42501';
    END IF;

    SELECT monthly_price INTO v_price FROM partners WHERE id = p_partner_id;
    IF NOT FOUND THEN RETURN false; END IF;

    IF p_paid THEN
        INSERT INTO partner_billing (partner_id, month_year, status, amount_rsd, paid_at)
        VALUES (p_partner_id, p_month, 'paid', COALESCE(v_price,0), NOW())
        ON CONFLICT (partner_id, month_year)
        DO UPDATE SET status = 'paid', paid_at = NOW(), amount_rsd = COALESCE(v_price,0);
    ELSE
        INSERT INTO partner_billing (partner_id, month_year, status, amount_rsd)
        VALUES (p_partner_id, p_month, 'pending', COALESCE(v_price,0))
        ON CONFLICT (partner_id, month_year)
        DO UPDATE SET status = 'pending', paid_at = NULL;
    END IF;

    RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.regenerate_partner_token(p_partner_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_new_token TEXT;
    v_name      TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'access denied' USING ERRCODE = '42501';
    END IF;

    v_new_token := translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_');

    UPDATE partners
    SET access_token = v_new_token
    WHERE id = p_partner_id
    RETURNING name INTO v_name;

    INSERT INTO audit_log(action, target_id, target_name, details)
    VALUES ('token_regenerated', p_partner_id, v_name,
            jsonb_build_object('new_token_prefix', LEFT(v_new_token, 6) || '...'));

    RETURN v_new_token;
END;
$function$;


-- ══════════════════════════════════════════════════════════════════
-- 4. IZVRSNA PRAVA NA FUNKCIJAMA
-- ══════════════════════════════════════════════════════════════════

-- Admin-only: iskljuci anon potpuno (is_admin() provera unutar funkcije
-- je glavna brana, ovo je dodatni sloj koji spreci i sam pokusaj poziva)
REVOKE EXECUTE ON FUNCTION public.admin_change_pin(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_create_partner(text,text,text,text,text,text,numeric,numeric) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cleanup_old_data() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.generate_monthly_billing(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_system_stats() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.mark_payment(uuid, text, boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.regenerate_partner_token(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.admin_change_pin(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_partner(text,text,text,text,text,text,numeric,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_old_data() TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_monthly_billing(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_system_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_payment(uuid, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.regenerate_partner_token(uuid) TO authenticated;

-- next_partner_code — orfanska funkcija, niko je ne poziva. Zakljucaj potpuno.
REVOKE EXECUTE ON FUNCTION public.next_partner_code() FROM PUBLIC, anon, authenticated;

-- Javne funkcije — samo fiksiraj search_path, izvrsna prava ostaju ista
ALTER FUNCTION public.partner_login(text, text) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_radar_stamps() SET search_path = public, pg_temp;
ALTER FUNCTION public.get_free_slots(uuid, date, integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.touch_updated_at() SET search_path = public, pg_temp;
ALTER FUNCTION public.update_stamp_count() SET search_path = public, pg_temp;


-- ══════════════════════════════════════════════════════════════════
-- 5. OCISTI STARE (DUPLIRANE, NEAKTIVNE) RLS POLITIKE
-- ══════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS ac_read ON public.analytics_clicks;
DROP POLICY IF EXISTS ac_write ON public.analytics_clicks;
DROP POLICY IF EXISTS analytics_insert ON public.analytics_clicks;
DROP POLICY IF EXISTS analytics_read ON public.analytics_clicks;
DROP POLICY IF EXISTS anon_read_analytics ON public.analytics_clicks;

DROP POLICY IF EXISTS anon_read_audit ON public.audit_log;
DROP POLICY IF EXISTS audit_insert ON public.audit_log;
DROP POLICY IF EXISTS audit_read ON public.audit_log;

DROP POLICY IF EXISTS anon_read_billing ON public.billing;
DROP POLICY IF EXISTS billing_insert ON public.billing;
DROP POLICY IF EXISTS billing_read ON public.billing;
DROP POLICY IF EXISTS billing_write ON public.billing;

DROP POLICY IF EXISTS br_read ON public.bookable_resources;
DROP POLICY IF EXISTS br_write ON public.bookable_resources;
DROP POLICY IF EXISTS resources_public_read ON public.bookable_resources;
DROP POLICY IF EXISTS resources_write ON public.bookable_resources;

DROP POLICY IF EXISTS anon_read_bookings ON public.bookings;
DROP POLICY IF EXISTS bookings_public ON public.bookings;
DROP POLICY IF EXISTS bookings_read ON public.bookings;
DROP POLICY IF EXISTS bookings_write ON public.bookings;

DROP POLICY IF EXISTS cc_read ON public.city_categories;
DROP POLICY IF EXISTS cc_write ON public.city_categories;
DROP POLICY IF EXISTS city_cat_read ON public.city_categories;
DROP POLICY IF EXISTS city_cat_write ON public.city_categories;

DROP POLICY IF EXISTS anon_read_events ON public.events;
DROP POLICY IF EXISTS events_public_read ON public.events;
DROP POLICY IF EXISTS events_read ON public.events;
DROP POLICY IF EXISTS events_write ON public.events;

DROP POLICY IF EXISTS gs_read ON public.guest_shares;
DROP POLICY IF EXISTS gs_write ON public.guest_shares;
DROP POLICY IF EXISTS guest_shares_insert ON public.guest_shares;
DROP POLICY IF EXISTS guest_shares_read ON public.guest_shares;

DROP POLICY IF EXISTS anon_read_guests ON public.guests;
DROP POLICY IF EXISTS guests_public_insert ON public.guests;
DROP POLICY IF EXISTS guests_public_read ON public.guests;
DROP POLICY IF EXISTS guests_public_update ON public.guests;
DROP POLICY IF EXISTS guests_read ON public.guests;
DROP POLICY IF EXISTS guests_write ON public.guests;

DROP POLICY IF EXISTS attempts_insert_only ON public.login_attempts;

DROP POLICY IF EXISTS pv_insert ON public.page_views;
DROP POLICY IF EXISTS pv_read ON public.page_views;

DROP POLICY IF EXISTS billing_all ON public.partner_billing;
DROP POLICY IF EXISTS pb_read ON public.partner_billing;
DROP POLICY IF EXISTS pb_write ON public.partner_billing;

DROP POLICY IF EXISTS anon_read_content ON public.partner_content;
DROP POLICY IF EXISTS content_read ON public.partner_content;
DROP POLICY IF EXISTS pc_read ON public.partner_content;
DROP POLICY IF EXISTS pc_write ON public.partner_content;
DROP POLICY IF EXISTS pcontent_public_read ON public.partner_content;
DROP POLICY IF EXISTS pcontent_public_write ON public.partner_content;

DROP POLICY IF EXISTS leads_insert_anon ON public.partner_leads;
DROP POLICY IF EXISTS leads_read_all ON public.partner_leads;
DROP POLICY IF EXISTS leads_update_all ON public.partner_leads;
DROP POLICY IF EXISTS pl_read ON public.partner_leads;
DROP POLICY IF EXISTS pl_update ON public.partner_leads;
DROP POLICY IF EXISTS pl_write ON public.partner_leads;

DROP POLICY IF EXISTS anon_read_partners ON public.partners;
DROP POLICY IF EXISTS partners_read ON public.partners;
DROP POLICY IF EXISTS partners_update_all ON public.partners;
DROP POLICY IF EXISTS partners_write ON public.partners;

DROP POLICY IF EXISTS push_read ON public.push_subscriptions;
DROP POLICY IF EXISTS push_write ON public.push_subscriptions;

DROP POLICY IF EXISTS rc_read ON public.referral_clicks;
DROP POLICY IF EXISTS rc_write ON public.referral_clicks;
DROP POLICY IF EXISTS ref_insert ON public.referral_clicks;
DROP POLICY IF EXISTS ref_read ON public.referral_clicks;

DROP POLICY IF EXISTS anon_read_stamps ON public.stamp_locations;
DROP POLICY IF EXISTS sl_read ON public.stamp_locations;
DROP POLICY IF EXISTS sl_write ON public.stamp_locations;
DROP POLICY IF EXISTS stamp_locations_admin_write ON public.stamp_locations;
DROP POLICY IF EXISTS stamp_locations_all ON public.stamp_locations;
DROP POLICY IF EXISTS stamp_locations_public_read ON public.stamp_locations;

DROP POLICY IF EXISTS stamps_public ON public.stamps;
DROP POLICY IF EXISTS stamps_read ON public.stamps;
DROP POLICY IF EXISTS stamps_write ON public.stamps;


-- ══════════════════════════════════════════════════════════════════
-- 6. UKLJUCI RLS NA SVE TABELE
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.partners            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_content     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guests              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stamps              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookable_resources  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analytics_clicks    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_attempts      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stamp_locations     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_billing     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.city_categories     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_clicks     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guest_shares        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_leads       ENABLE ROW LEVEL SECURITY;
-- push_subscriptions, push_notifications_log, page_views already had RLS on


-- ══════════════════════════════════════════════════════════════════
-- 7. NOVE RLS POLITIKE (po tabeli, prema stvarnom koriscenju u kodu)
-- ══════════════════════════════════════════════════════════════════

-- ── partners ──────────────────────────────────────────────────────
CREATE POLICY partners_select_public ON public.partners
    FOR SELECT TO anon USING (is_active = true);
CREATE POLICY partners_select_admin ON public.partners
    FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY partners_update_self ON public.partners
    FOR UPDATE TO anon USING (is_active = true) WITH CHECK (is_active = true);
CREATE POLICY partners_update_admin ON public.partners
    FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY partners_delete_admin ON public.partners
    FOR DELETE TO authenticated USING (public.is_admin());
-- Nema INSERT politike: partneri se kreiraju samo kroz admin_create_partner()
-- (SECURITY DEFINER, zaobilazi RLS), sto je jedini nacin kreiranja u kodu.

-- Sakrij pin/access_token od anon uloge na nivou kolona (RLS ne moze
-- da filtrira kolone, samo redove)
REVOKE SELECT ON public.partners FROM anon;
GRANT SELECT (
    id, name, type, partner_code, is_active, is_premium, loyalty_enabled,
    has_booking, hh_active, hh_date, hh_start, hh_end, lat, lng, phone,
    whatsapp, created_at, updated_at, plan, city_category_id,
    show_in_city_info, referral_active, referral_discount, referral_code,
    hh_visibility, google_review_url, hide_competitors
) ON public.partners TO anon;

-- Anon sme da menja SAMO polja koja partner panel stvarno menja
-- (happy-hour i booking toggle) — ne is_premium, monthly_price, pin...
REVOKE UPDATE ON public.partners FROM anon;
GRANT UPDATE (hh_active, hh_date, hh_start, hh_end, hh_visibility, has_booking)
    ON public.partners TO anon;

-- ── partner_content ──────────────────────────────────────────────
CREATE POLICY partner_content_select_public ON public.partner_content
    FOR SELECT TO anon USING (
        EXISTS (SELECT 1 FROM public.partners p WHERE p.id = partner_content.partner_id AND p.is_active = true)
    );
CREATE POLICY partner_content_select_admin ON public.partner_content
    FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY partner_content_insert_self ON public.partner_content
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY partner_content_update_self ON public.partner_content
    FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY partner_content_all_admin ON public.partner_content
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── guests ────────────────────────────────────────────────────────
CREATE POLICY guests_select_public ON public.guests
    FOR SELECT TO anon USING (true);
CREATE POLICY guests_insert_public ON public.guests
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY guests_update_public ON public.guests
    FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY guests_all_admin ON public.guests
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── stamps ────────────────────────────────────────────────────────
CREATE POLICY stamps_select_public ON public.stamps
    FOR SELECT TO anon USING (true);
CREATE POLICY stamps_insert_public ON public.stamps
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY stamps_all_admin ON public.stamps
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── events ────────────────────────────────────────────────────────
CREATE POLICY events_select_public ON public.events
    FOR SELECT TO anon USING (true);
CREATE POLICY events_insert_public ON public.events
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY events_all_admin ON public.events
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── billing ───────────────────────────────────────────────────────
CREATE POLICY billing_select_public ON public.billing
    FOR SELECT TO anon USING (true);
CREATE POLICY billing_insert_public ON public.billing
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY billing_all_admin ON public.billing
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── bookable_resources ───────────────────────────────────────────
CREATE POLICY resources_select_public ON public.bookable_resources
    FOR SELECT TO anon USING (true);
CREATE POLICY resources_insert_public ON public.bookable_resources
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY resources_update_public ON public.bookable_resources
    FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY resources_all_admin ON public.bookable_resources
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── bookings ──────────────────────────────────────────────────────
CREATE POLICY bookings_select_public ON public.bookings
    FOR SELECT TO anon USING (true);
CREATE POLICY bookings_insert_public ON public.bookings
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY bookings_all_admin ON public.bookings
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── analytics_clicks ─────────────────────────────────────────────
CREATE POLICY analytics_select_public ON public.analytics_clicks
    FOR SELECT TO anon USING (true);
CREATE POLICY analytics_insert_public ON public.analytics_clicks
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY analytics_all_admin ON public.analytics_clicks
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── referral_clicks ──────────────────────────────────────────────
CREATE POLICY referral_select_public ON public.referral_clicks
    FOR SELECT TO anon USING (true);
CREATE POLICY referral_insert_public ON public.referral_clicks
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY referral_all_admin ON public.referral_clicks
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── city_categories ──────────────────────────────────────────────
CREATE POLICY city_categories_select_public ON public.city_categories
    FOR SELECT TO anon USING (true);
CREATE POLICY city_categories_all_admin ON public.city_categories
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── stamp_locations ──────────────────────────────────────────────
CREATE POLICY stamp_locations_select_public ON public.stamp_locations
    FOR SELECT TO anon USING (is_active = true);
CREATE POLICY stamp_locations_all_admin ON public.stamp_locations
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── guest_shares (samo insert, niko ne cita direktno) ───────────
CREATE POLICY guest_shares_insert_public ON public.guest_shares
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY guest_shares_all_admin ON public.guest_shares
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── push_subscriptions (samo insert; ne dozvoljavamo citanje tudjih
--    push kljuceva) ─────────────────────────────────────────────
DROP POLICY IF EXISTS push_subscriptions_insert_public ON public.push_subscriptions;
DROP POLICY IF EXISTS push_subscriptions_all_admin ON public.push_subscriptions;
CREATE POLICY push_subscriptions_insert_public ON public.push_subscriptions
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY push_subscriptions_all_admin ON public.push_subscriptions
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── partner_leads (samo insert za goste; citanje/izmena samo admin) ─
CREATE POLICY partner_leads_insert_public ON public.partner_leads
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY partner_leads_all_admin ON public.partner_leads
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── page_views (samo insert za sve; citanje samo admin) ─────────
DROP POLICY IF EXISTS page_views_insert_public ON public.page_views;
DROP POLICY IF EXISTS page_views_all_admin ON public.page_views;
CREATE POLICY page_views_insert_public ON public.page_views
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY page_views_all_admin ON public.page_views
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── partner_billing (u potpunosti admin-only, partner.html je ne
--    koristi nikad) ────────────────────────────────────────────
CREATE POLICY partner_billing_all_admin ON public.partner_billing
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
-- Nema anon politike uopste — anon nema NIKAKAV pristup ovoj tabeli.

-- ── login_attempts (potpuno zakljucano — samo SECURITY DEFINER
--    funkcije je diraju, aplikacija je nikad direktno ne cita/pise) ─
-- Nema nijedne politike — RLS ukljucen bez politika = pun deny za sve.

-- ── audit_log (isto — samo funkcije pisu; admin sme da cita) ────
CREATE POLICY audit_log_select_admin ON public.audit_log
    FOR SELECT TO authenticated USING (public.is_admin());
-- Nema INSERT/UPDATE/DELETE politike za anon/authenticated — samo
-- SECURITY DEFINER funkcije pisu (zaobilaze RLS).

-- ── push_notifications_log (vec RLS on bez politika — dodaj samo
--    citanje za admin radi vidljivosti) ──────────────────────────
DROP POLICY IF EXISTS push_log_select_admin ON public.push_notifications_log;
CREATE POLICY push_log_select_admin ON public.push_notifications_log
    FOR SELECT TO authenticated USING (public.is_admin());


-- ══════════════════════════════════════════════════════════════════
-- 8. VIEW-OVI
-- ══════════════════════════════════════════════════════════════════

-- newsletter_subscribers: niko je ne koristi u app kodu (proverено),
-- pa je bezbedno prebaciti u security_invoker rezim i zakljucati za anon.
ALTER VIEW public.newsletter_subscribers SET (security_invoker = true);
REVOKE ALL ON public.newsletter_subscribers FROM anon;
GRANT SELECT ON public.newsletter_subscribers TO authenticated;

-- partners_public: NAMERNO ostaje SECURITY DEFINER (bez security_invoker).
-- Razlog: view svesno bira samo bezbedne kolone (bez pin/access_token)
-- i vec filtrira is_active=true, a koriste je 3 javne stranice
-- (happy-hour.html, landing.html, radar.html) koje ocekuju i
-- monthly_price/payment_status polja. Prebacivanje u invoker rezim bi
-- ili polomilo te stranice ili zahtevalo da se ta polja otvore i na
-- samoj partners tabeli za anon (sto je losiji kompromis). Ovo je
-- svesno zadrzano stanje, ne previd — Supabase advisor ce i dalje
-- prijavljivati ovaj view kao "security definer view".


-- ═══════════════════════════════════════════════════════════════════
-- KRAJ security_hardening_v2.sql
-- ═══════════════════════════════════════════════════════════════════
