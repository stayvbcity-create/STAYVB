-- ═══════════════════════════════════════════════════════════════════
-- StayVB v2 — Rezervacije smeštaja (premium apartman/hotel partneri)
-- Model: upit/zahtev (partner rucno potvrdjuje, nema live kalendara)
-- Pokreni u Supabase SQL Editor-u
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. TABELA: accommodation_listings ────────────────────────────
-- Jedan oglas po partneru (apartman/hotel, premium)

CREATE TABLE IF NOT EXISTS public.accommodation_listings (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id       UUID NOT NULL UNIQUE REFERENCES public.partners(id),
    title            TEXT,
    location_label   TEXT,
    description      TEXT,
    highlight        TEXT,
    guests           INT NOT NULL DEFAULT 2,
    bedrooms         INT NOT NULL DEFAULT 1,
    bathrooms        INT NOT NULL DEFAULT 1,
    price_per_night  INT NOT NULL DEFAULT 0,
    amenities        TEXT[] NOT NULL DEFAULT '{}',
    photo_urls       TEXT[] NOT NULL DEFAULT '{}',
    is_active        BOOLEAN NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_accommodation_listings_updated_at
    BEFORE UPDATE ON public.accommodation_listings
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

ALTER FUNCTION public.touch_updated_at() SET search_path = public, pg_temp;

-- ── 2. TABELA: accommodation_inquiries ───────────────────────────
-- Upiti/zahtevi gostiju za rezervaciju

CREATE TABLE IF NOT EXISTS public.accommodation_inquiries (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id     UUID NOT NULL REFERENCES public.accommodation_listings(id),
    partner_id     UUID NOT NULL REFERENCES public.partners(id),
    checkin_date   DATE,
    checkout_date  DATE,
    guest_count    INT NOT NULL DEFAULT 1,
    guest_name     TEXT NOT NULL,
    guest_phone    TEXT NOT NULL,
    message        TEXT,
    status         TEXT NOT NULL DEFAULT 'new'
                   CHECK (status IN ('new','contacted','confirmed','declined')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_inquiries_partner ON public.accommodation_inquiries(partner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inquiries_listing ON public.accommodation_inquiries(listing_id);


-- ── 3. RLS ────────────────────────────────────────────────────────

ALTER TABLE public.accommodation_listings   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accommodation_inquiries  ENABLE ROW LEVEL SECURITY;

-- Javno vidljivi oglasi: samo aktivni, samo od aktivnih premium apartman/hotel partnera
CREATE POLICY listings_select_public ON public.accommodation_listings
    FOR SELECT TO anon USING (
        is_active = true AND EXISTS (
            SELECT 1 FROM public.partners p
            WHERE p.id = accommodation_listings.partner_id
              AND p.is_active = true
              AND p.is_premium = true
              AND p.type IN ('apartment','hotel')
        )
    );

-- Partner uredjuje svoj oglas (isti model kao partner_content — bez prave sesije,
-- prihvacen rizik kao i za ostatak partner-self tabela u ovoj aplikaciji)
CREATE POLICY listings_insert_self ON public.accommodation_listings
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY listings_update_self ON public.accommodation_listings
    FOR UPDATE TO anon USING (true) WITH CHECK (true);

CREATE POLICY listings_all_admin ON public.accommodation_listings
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Upiti: gost salje (insert), partner cita/azurira status svojih (accept-risk,
-- isti model kao guests/partner_content), admin sve
CREATE POLICY inquiries_insert_public ON public.accommodation_inquiries
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY inquiries_select_public ON public.accommodation_inquiries
    FOR SELECT TO anon USING (true);
CREATE POLICY inquiries_update_public ON public.accommodation_inquiries
    FOR UPDATE TO anon USING (true) WITH CHECK (true);

CREATE POLICY inquiries_all_admin ON public.accommodation_inquiries
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


-- ── 4. GRANT-ovi ──────────────────────────────────────────────────
-- VAZNO: authenticated rola u ovom projektu nema podrazumevana prava
-- na rucno kreirane tabele (videli smo isti problem kod security_hardening_v2).
-- Bez ovoga admin.html ne bi mogao da moderira oglase/upite.

GRANT SELECT, INSERT, UPDATE, DELETE ON public.accommodation_listings   TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.accommodation_inquiries  TO authenticated;


-- ── 5. STORAGE BUCKET za fotografije smeštaja ───────────────────
-- Javno citljive slike, upload/izmena otvorena kao i ostatak partner-self
-- modela (anon, bez prave sesije — prihvacen rizik, dosledno ostatku app-a)

INSERT INTO storage.buckets (id, name, public)
VALUES ('accommodation-photos', 'accommodation-photos', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY accommodation_photos_public_read ON storage.objects
    FOR SELECT USING (bucket_id = 'accommodation-photos');

CREATE POLICY accommodation_photos_anon_write ON storage.objects
    FOR INSERT TO anon WITH CHECK (bucket_id = 'accommodation-photos');

CREATE POLICY accommodation_photos_anon_update ON storage.objects
    FOR UPDATE TO anon USING (bucket_id = 'accommodation-photos') WITH CHECK (bucket_id = 'accommodation-photos');

CREATE POLICY accommodation_photos_anon_delete ON storage.objects
    FOR DELETE TO anon USING (bucket_id = 'accommodation-photos');

-- Napomena: ako upload iz partner panela i dalje vraca "permission denied" nakon
-- ovoga, proveri Dashboard -> Storage -> accommodation-photos -> Policies rucno,
-- ponekad storage.objects grant-ovi (ne politike, vec GRANT na tabelu) takodje
-- nedostaju za authenticated/anon ulogu u rucno podesenim projektima:
--   GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ accommodation_booking.sql
-- ═══════════════════════════════════════════════════════════════════
