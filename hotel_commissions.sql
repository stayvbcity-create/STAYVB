-- ═══════════════════════════════════════════════════════════════════
-- hotel_commissions.sql — proširenje sistema provizija i na PREMIUM
-- HOTELE (ne samo apartmane). Gost hotela rezerviše aktivnost u
-- atrakcije.html, atrakcija realizuje rezervaciju, a triger upisuje
-- proviziju hotelu — isti tok i ista pravila kao za apartmane.
--
-- Tabela apartment_commissions, trigger i grantovi ostaju isti; menja
-- se samo uslov u funkciji create_apartment_commission().
--
-- Pokreni jednom u Supabase SQL editoru.
-- ═══════════════════════════════════════════════════════════════════

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
    v_acc_type text;
    v_acc_premium boolean;
    v_amount integer;
BEGIN
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

    SELECT type, is_premium INTO v_acc_type, v_acc_premium
    FROM public.partners WHERE id = NEW.accommodation_id;
    IF NOT FOUND OR v_acc_type NOT IN ('apartment','hotel') OR NOT COALESCE(v_acc_premium, false) THEN
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

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ hotel_commissions.sql
-- ═══════════════════════════════════════════════════════════════════
