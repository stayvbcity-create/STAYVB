-- ═══════════════════════════════════════════════════════════════════
-- guest_feedback.sql — "Review gate" pre Google recenzije.
--
-- Gost pre odlaska na Google prvo odgovori kako mu je bio boravak.
-- Ako je pozitivan (odlično/dobro) - saljemo ga na pravi Google
-- review link. Ako je negativan (moglo bolje/lose) - NE saljemo ga
-- na Google, vec prikupljamo kratak upitnik i cuvamo ovde, da
-- partner/hotel to vidi i moze da reaguje direktno prema gostu.
--
-- Isti RLS obrazac kao accommodation_inquiries/stamps u ovom
-- projektu: anon cita/pise slobodno (partner.html filtrira po
-- svom partner_id u kodu), admin ima pun pristup.
-- Pokreni jednom u Supabase SQL editoru.
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.guest_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id uuid REFERENCES public.partners(id),
    guest_token text,
    sentiment text NOT NULL CHECK (sentiment IN ('great','good','meh','bad')),
    issues text[] DEFAULT '{}',
    message text,
    contact_phone text,
    sent_to_google boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_guest_feedback_partner ON public.guest_feedback(partner_id, created_at DESC);

ALTER TABLE public.guest_feedback ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS guest_feedback_insert_public ON public.guest_feedback;
DROP POLICY IF EXISTS guest_feedback_select_public ON public.guest_feedback;
DROP POLICY IF EXISTS guest_feedback_all_admin ON public.guest_feedback;

CREATE POLICY guest_feedback_insert_public ON public.guest_feedback
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY guest_feedback_select_public ON public.guest_feedback
    FOR SELECT TO anon USING (true);
CREATE POLICY guest_feedback_all_admin ON public.guest_feedback
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

GRANT SELECT, INSERT ON public.guest_feedback TO anon;
GRANT ALL ON public.guest_feedback TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ guest_feedback.sql
-- ═══════════════════════════════════════════════════════════════════
