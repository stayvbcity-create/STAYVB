-- ═══════════════════════════════════════════════════════════════════
-- referral_panel.sql — hotel sam podešava "Pozovi prijatelja":
-- uključuje/isključuje, određuje popust i kod, i piše poruku koju
-- njegovi gosti šalju prijateljima (WhatsApp, Viber).
--
-- Do sada je ovo podešavao samo admin. Upis je i dalje ograničen na
-- sopstveni red (politika owner_partners / owner_partner_content).
--
-- Pokreni jednom u Supabase SQL editoru.
-- ═══════════════════════════════════════════════════════════════════

-- Poruka koju hotel piše (ide u sadržaj objekta, kao i ostali tekstovi)
ALTER TABLE public.partner_content
    ADD COLUMN IF NOT EXISTS referral_message text;

-- Hotel sme da menja samo ova polja preporuke na svom redu
GRANT UPDATE (referral_active, referral_discount, referral_code) ON public.partners TO anon;

-- Granice na serveru, jer vrednosti sada unosi hotel, a ne admin.
-- NOT VALID: važi za nove upise, postojeći redovi se ne proveravaju.
ALTER TABLE public.partners DROP CONSTRAINT IF EXISTS referral_discount_range;
ALTER TABLE public.partners ADD CONSTRAINT referral_discount_range
    CHECK (referral_discount IS NULL OR referral_discount BETWEEN 1 AND 50) NOT VALID;

ALTER TABLE public.partners DROP CONSTRAINT IF EXISTS referral_code_format;
ALTER TABLE public.partners ADD CONSTRAINT referral_code_format
    CHECK (referral_code IS NULL OR referral_code ~ '^\S{3,20}$') NOT VALID;

ALTER TABLE public.partner_content DROP CONSTRAINT IF EXISTS referral_message_length;
ALTER TABLE public.partner_content ADD CONSTRAINT referral_message_length
    CHECK (referral_message IS NULL OR char_length(referral_message) <= 500) NOT VALID;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ referral_panel.sql
-- ═══════════════════════════════════════════════════════════════════
