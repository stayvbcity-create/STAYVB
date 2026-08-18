-- ═══════════════════════════════════════════════════════════════════
-- StayVB v2 — Fix #1: authenticated rola nije imala GRANT na tabele
-- Pokreni odmah nakon security_hardening_v2.sql
-- ═══════════════════════════════════════════════════════════════════

GRANT SELECT, INSERT, UPDATE, DELETE ON public.analytics_clicks   TO authenticated;
GRANT SELECT                        ON public.audit_log           TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.billing             TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.bookable_resources  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.bookings            TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.city_categories     TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.events              TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.guest_shares        TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.guests              TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.page_views          TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_billing     TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_content     TO authenticated;
GRANT SELECT, UPDATE, DELETE         ON public.partners            TO authenticated;
GRANT SELECT                        ON public.push_notifications_log TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.push_subscriptions  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.referral_clicks     TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.stamps              TO authenticated;
-- partner_leads i stamp_locations vec imaju ova prava, ne diramo ih.
-- login_attempts i admin_users namerno ostaju bez GRANT-a za authenticated.

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ
-- ═══════════════════════════════════════════════════════════════════
