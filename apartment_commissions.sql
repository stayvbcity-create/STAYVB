-- ═══════════════════════════════════════════════════════════════════
-- apartment_commissions.sql — provizija za Premium apartmane od
-- rezervacija aktivnosti koje naprave njihovi gosti.
--
-- Tok: gost rezerviše aktivnost u atrakcije.html -> dobija QR kod za
-- tu rezervaciju -> atrakcija skenira kod kad gost dođe/plati ->
-- bookings.redeemed_at se postavlja -> TRIGER (ne klijent!) proverava
-- uslove i sam upisuje red u apartment_commissions. Iznos se ne moze
-- lazirati sa klijenta jer samo triger (SECURITY DEFINER) pise u tu
-- tabelu.
--
-- Pokreni jednom u Supabase SQL editoru.
-- ═══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- 1. NOVE KOLONE
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.bookings
    ADD COLUMN IF NOT EXISTS accommodation_id uuid REFERENCES public.partners(id),
    ADD COLUMN IF NOT EXISTS redeemed_at timestamptz;

ALTER TABLE public.partners
    ADD COLUMN IF NOT EXISTS commission_sharing_active boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS apartment_commission_pct integer;

-- ══════════════════════════════════════════════════════════════════
-- 2. TABELA ZA KNJIŽENJE PROVIZIJE
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.apartment_commissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id uuid NOT NULL REFERENCES public.bookings(id),
    apartment_partner_id uuid NOT NULL REFERENCES public.partners(id),
    attraction_partner_id uuid NOT NULL REFERENCES public.partners(id),
    amount_rsd integer NOT NULL,
    commission_pct_applied integer NOT NULL,
    attraction_paid_confirmed boolean NOT NULL DEFAULT false,
    apartment_paid_confirmed boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    paid_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_apartment_commissions_booking
    ON public.apartment_commissions(booking_id);
CREATE INDEX IF NOT EXISTS idx_apartment_commissions_apartment
    ON public.apartment_commissions(apartment_partner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_apartment_commissions_attraction
    ON public.apartment_commissions(attraction_partner_id, created_at DESC);

-- ══════════════════════════════════════════════════════════════════
-- 3. TRIGER — upisuje proviziju kad se rezervacija realizuje
--    (redeemed_at prelazi iz NULL u vreme). SECURITY DEFINER znaci da
--    radi sa pravima vlasnika tabele, ne klijenta koji je pokrenuo
--    UPDATE — pa anon ne mora (i ne sme) da ima direktan INSERT na
--    apartment_commissions.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_apartment_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource_price integer;
    v_attraction_id uuid;
    v_sharing_active boolean;
    v_pct integer;
    v_apt_type text;
    v_apt_premium boolean;
    v_amount integer;
BEGIN
    -- Samo kad redeemed_at PRVI PUT postaje postavljen
    IF NEW.redeemed_at IS NULL OR OLD.redeemed_at IS NOT NULL THEN
        RETURN NEW;
    END IF;
    IF NEW.accommodation_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT price_rsd, partner_id INTO v_resource_price, v_attraction_id
    FROM public.bookable_resources WHERE id = NEW.resource_id;
    IF NOT FOUND THEN RETURN NEW; END IF;

    SELECT commission_sharing_active, apartment_commission_pct
    INTO v_sharing_active, v_pct
    FROM public.partners WHERE id = v_attraction_id;
    IF NOT FOUND OR NOT COALESCE(v_sharing_active, false) OR COALESCE(v_pct, 0) <= 0 THEN
        RETURN NEW;
    END IF;

    SELECT type, is_premium INTO v_apt_type, v_apt_premium
    FROM public.partners WHERE id = NEW.accommodation_id;
    IF NOT FOUND OR v_apt_type <> 'apartment' OR NOT COALESCE(v_apt_premium, false) THEN
        RETURN NEW;
    END IF;

    v_amount := ROUND(COALESCE(v_resource_price, 0) * NEW.qty * v_pct / 100.0);
    IF v_amount <= 0 THEN RETURN NEW; END IF;

    INSERT INTO public.apartment_commissions
        (booking_id, apartment_partner_id, attraction_partner_id, amount_rsd, commission_pct_applied)
    VALUES (NEW.id, NEW.accommodation_id, v_attraction_id, v_amount, v_pct)
    ON CONFLICT (booking_id) DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_apartment_commission ON public.bookings;
CREATE TRIGGER trg_create_apartment_commission
    AFTER UPDATE ON public.bookings
    FOR EACH ROW EXECUTE FUNCTION public.create_apartment_commission();

-- ══════════════════════════════════════════════════════════════════
-- 4. TRIGER — "Isplaćeno" tek kad OBE strane potvrde
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.mark_commission_paid()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.attraction_paid_confirmed AND NEW.apartment_paid_confirmed THEN
        IF NEW.paid_at IS NULL THEN NEW.paid_at := now(); END IF;
    ELSE
        NEW.paid_at := NULL;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mark_commission_paid ON public.apartment_commissions;
CREATE TRIGGER trg_mark_commission_paid
    BEFORE UPDATE ON public.apartment_commissions
    FOR EACH ROW EXECUTE FUNCTION public.mark_commission_paid();

-- ══════════════════════════════════════════════════════════════════
-- 5. RLS + GRANTOVI (isti obrazac kao ostatak projekta)
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.apartment_commissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS apartment_commissions_select_public ON public.apartment_commissions;
DROP POLICY IF EXISTS apartment_commissions_update_public ON public.apartment_commissions;
DROP POLICY IF EXISTS apartment_commissions_all_admin ON public.apartment_commissions;

-- Anon SME da cita (oba partnera treba da vide svoju stranu) i da
-- menja SAMO svoje "placeno" polje (vidi napomenu ispod) — ne sme da
-- pravi nove redove direktno, to radi iskljucivo gornji triger.
CREATE POLICY apartment_commissions_select_public ON public.apartment_commissions
    FOR SELECT TO anon USING (true);
CREATE POLICY apartment_commissions_update_public ON public.apartment_commissions
    FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY apartment_commissions_all_admin ON public.apartment_commissions
    FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

GRANT SELECT, UPDATE (attraction_paid_confirmed, apartment_paid_confirmed) ON public.apartment_commissions TO anon;
GRANT ALL ON public.apartment_commissions TO authenticated;
-- Namerno NEMA GRANT INSERT za anon — jedini nacin da se red pojavi
-- je triger (SECURITY DEFINER) iznad.

-- Dozvoli anon da upise nove kolone na bookings/partners koje su mu
-- vec dostupne za ostala polja (isti obrazac kao postojeci grantovi).
GRANT UPDATE (accommodation_id, redeemed_at) ON public.bookings TO anon;
GRANT INSERT (accommodation_id) ON public.bookings TO anon;
GRANT UPDATE (commission_sharing_active, apartment_commission_pct) ON public.partners TO anon;
GRANT SELECT (commission_sharing_active, apartment_commission_pct) ON public.partners TO anon;

-- NAPOMENA o bezbednosti "placeno" potvrde: isto kao svuda u ovom
-- projektu (partner.html nema Supabase Auth sesiju, vec token u URL-u),
-- RLS ovde ne moze da razlikuje "ovo je zahtev bas tog apartmana" od
-- "ovo je zahtev bas te atrakcije" — oslanjamo se na to da svaki panel
-- menja samo red koji sam prikazuje (isti nivo poverenja kao i sve
-- ostalo u partner.html, npr. cancelBooking).

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ apartment_commissions.sql
-- ═══════════════════════════════════════════════════════════════════
