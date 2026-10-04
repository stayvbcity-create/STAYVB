-- ═══════════════════════════════════════════════════════════════════
-- extension_no_commission.sql — u produženju boravka nema provizije.
--
-- Atrakcija je u toj ponudi već dala sniženu cenu, pa bi provizija na to
-- bila dupla naplata. Pravilo je: hotel zadržava noć, atrakcija zadržava
-- aktivnost. Za sve ostale rezervacije provizija radi kao do sada.
--
-- Pokreni jednom u Supabase SQL editoru (posle stay_extension.sql).
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
    IF NEW.redeemed_at IS NULL OR OLD.redeemed_at IS NOT NULL THEN RETURN NEW; END IF;
    IF NEW.accommodation_id IS NULL THEN RETURN NEW; END IF;

    -- Rezervacija nastala iz produženja boravka: bez provizije
    IF EXISTS (SELECT 1 FROM public.stay_extension_offers WHERE booking_id = NEW.id) THEN
        RETURN NEW;
    END IF;

    SELECT price_rsd, partner_id INTO v_resource_price, v_attraction_id
    FROM public.bookable_resources WHERE id = NEW.resource_id;
    IF NOT FOUND THEN RETURN NEW; END IF;

    -- cena sa rezervacije ima prednost (sniženi termin)
    v_resource_price := COALESCE(NEW.unit_price_rsd, v_resource_price, 0);

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

    v_amount := ROUND(v_resource_price * NEW.qty * v_pct / 100.0);
    IF v_amount <= 0 THEN RETURN NEW; END IF;

    INSERT INTO public.apartment_commissions
        (booking_id, apartment_partner_id, attraction_partner_id, amount_rsd, commission_pct_applied)
    VALUES (NEW.id, NEW.accommodation_id, v_attraction_id, v_amount, v_pct)
    ON CONFLICT (booking_id) DO NOTHING;

    RETURN NEW;
END;
$$;

-- Pregled ponuda za vlasnika sada vraća i ID rezervacije, da panel može
-- da označi koje rezervacije su nastale iz produženja
CREATE OR REPLACE FUNCTION public.owner_extension_offers(p_access_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id uuid;
    v_rows jsonb;
BEGIN
    SELECT id INTO v_id FROM public.partners
    WHERE access_token = p_access_token AND is_active = true AND type IN ('hotel','apartment');
    IF v_id IS NULL THEN RETURN '[]'::jsonb; END IF;

    SELECT jsonb_agg(x ORDER BY x.created_at DESC) INTO v_rows FROM (
        SELECT o.id, o.status, o.night_price, o.guest_name, o.guest_phone,
               o.stay_checkout_date::text AS checkout_date, o.activity_qty,
               o.activity_price, o.created_at, o.expires_at, o.booking_id,
               r.name AS resource_name, p.name AS attraction_name
        FROM public.stay_extension_offers o
        LEFT JOIN public.bookable_resources r ON r.id = o.resource_id
        LEFT JOIN public.partners p ON p.id = r.partner_id
        WHERE o.accommodation_id = v_id
          AND o.created_at > now() - interval '30 days'
    ) x;
    RETURN COALESCE(v_rows, '[]'::jsonb);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ extension_no_commission.sql
-- ═══════════════════════════════════════════════════════════════════
