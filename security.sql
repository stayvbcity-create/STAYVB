-- ═══════════════════════════════════════════════════════════════════
-- StayVB v2 — Bezbednosna nadogradnja
-- Pokreni NAKON schema.sql i seed.sql
-- ═══════════════════════════════════════════════════════════════════


-- ── 1. DODAJ access_token KOLONU NA partners ─────────────────────
-- Svaki partner dobija jedinstven URL token koji se generiše u god modu
-- Format: partner.html?t=TOKEN

ALTER TABLE partners
    ADD COLUMN IF NOT EXISTS access_token TEXT UNIQUE;

-- Generiši tokene za sve postojeće partnere
UPDATE partners
SET access_token = encode(gen_random_bytes(18), 'base64url')
WHERE access_token IS NULL;

-- Zabrani NULL u budućnosti
ALTER TABLE partners
    ALTER COLUMN access_token SET NOT NULL;

-- Indeks za brzo traženje po tokenu
CREATE UNIQUE INDEX IF NOT EXISTS idx_partners_token
    ON partners(access_token);


-- ── 2. TABELA: login_attempts ────────────────────────────────────
-- Prati neuspešne PIN pokušaje — brute force zaštita

CREATE TABLE IF NOT EXISTS login_attempts (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    access_token TEXT NOT NULL,
    ip_hint     TEXT,               -- prvih 12 znakova IP (ne čuvamo celu)
    success     BOOLEAN DEFAULT false,
    attempted_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_attempts_token
    ON login_attempts(access_token, attempted_at);

-- RLS
ALTER TABLE login_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "attempts_insert" ON login_attempts
    FOR INSERT WITH CHECK (true);

-- Samo SECURITY DEFINER funkcije mogu čitati
CREATE POLICY "attempts_no_read" ON login_attempts
    FOR SELECT USING (false);


-- ── 3. TABELA: audit_log ─────────────────────────────────────────
-- Beleži sve admin akcije (ko je šta promenio)

CREATE TABLE IF NOT EXISTS audit_log (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    action      TEXT NOT NULL,      -- 'partner_created', 'pin_changed', 'token_regenerated'...
    target_id   UUID,               -- ID partnera/gosta na koga se odnosi
    target_name TEXT,
    details     JSONB,              -- stara/nova vrednost
    performed_by TEXT DEFAULT 'admin',
    performed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_target ON audit_log(target_id);
CREATE INDEX IF NOT EXISTS idx_audit_time   ON audit_log(performed_at DESC);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "audit_insert" ON audit_log
    FOR INSERT WITH CHECK (true);

CREATE POLICY "audit_read" ON audit_log
    FOR SELECT USING (true);


-- ── 4. AŽURIRANA partner_login FUNKCIJA ──────────────────────────
-- Sada proverava I access_token I pin
-- Blokira ako ima 5+ neuspešnih pokušaja u poslednjih 15 minuta
-- Dodaje pg_sleep da uspori brute force

CREATE OR REPLACE FUNCTION partner_login(
    p_token TEXT,
    p_pin   TEXT
)
RETURNS TABLE (
    id              UUID,
    name            TEXT,
    type            TEXT,
    is_premium      BOOLEAN,
    is_active       BOOLEAN,
    loyalty_enabled BOOLEAN,
    has_booking     BOOLEAN,
    hh_active       BOOLEAN,
    hh_date         DATE,
    hh_start        TIME,
    hh_end          TIME,
    partner_code    TEXT,
    lat             NUMERIC,
    lng             NUMERIC,
    phone           TEXT,
    whatsapp        TEXT,
    login_ok        BOOLEAN,
    error_msg       TEXT
) AS $$
DECLARE
    v_attempts  INT;
    v_partner   partners%ROWTYPE;
BEGIN
    -- Provjeri broj neuspješnih pokušaja u posjednjih 15 min
    SELECT COUNT(*) INTO v_attempts
    FROM login_attempts
    WHERE access_token = p_token
      AND success = false
      AND attempted_at > NOW() - INTERVAL '15 minutes';

    -- Blokada nakon 5 neuspješnih pokušaja
    IF v_attempts >= 5 THEN
        PERFORM pg_sleep(2);  -- kazna: 2 sekunde čekanja
        RETURN QUERY SELECT
            NULL::UUID, NULL::TEXT, NULL::TEXT,
            NULL::BOOLEAN, NULL::BOOLEAN, NULL::BOOLEAN,
            NULL::BOOLEAN, NULL::BOOLEAN, NULL::DATE,
            NULL::TIME, NULL::TIME, NULL::TEXT,
            NULL::NUMERIC, NULL::NUMERIC, NULL::TEXT, NULL::TEXT,
            false, 'Previše pokušaja. Sačekajte 15 minuta.'::TEXT;
        RETURN;
    END IF;

    -- Nađi partnera po tokenu
    SELECT * INTO v_partner
    FROM partners
    WHERE access_token = p_token
      AND is_active = true;

    IF NOT FOUND THEN
        -- Ubaci neuspješan pokušaj
        INSERT INTO login_attempts(access_token, success)
        VALUES (p_token, false);
        PERFORM pg_sleep(0.5);
        RETURN QUERY SELECT
            NULL::UUID, NULL::TEXT, NULL::TEXT,
            NULL::BOOLEAN, NULL::BOOLEAN, NULL::BOOLEAN,
            NULL::BOOLEAN, NULL::BOOLEAN, NULL::DATE,
            NULL::TIME, NULL::TIME, NULL::TEXT,
            NULL::NUMERIC, NULL::NUMERIC, NULL::TEXT, NULL::TEXT,
            false, 'Nevažeći link.'::TEXT;
        RETURN;
    END IF;

    -- Provjeri PIN
    IF v_partner.pin != p_pin THEN
        INSERT INTO login_attempts(access_token, success)
        VALUES (p_token, false);
        PERFORM pg_sleep(0.5);  -- usporavanje brute force
        RETURN QUERY SELECT
            NULL::UUID, NULL::TEXT, NULL::TEXT,
            NULL::BOOLEAN, NULL::BOOLEAN, NULL::BOOLEAN,
            NULL::BOOLEAN, NULL::BOOLEAN, NULL::DATE,
            NULL::TIME, NULL::TIME, NULL::TEXT,
            NULL::NUMERIC, NULL::NUMERIC, NULL::TEXT, NULL::TEXT,
            false,
            ('Pogrešan PIN. Još ' || (5 - v_attempts - 1)::TEXT ||
             ' pokušaja pre blokade.')::TEXT;
        RETURN;
    END IF;

    -- Uspješan login — obriši stare pokušaje i vrati podatke
    DELETE FROM login_attempts
    WHERE access_token = p_token;

    INSERT INTO login_attempts(access_token, success)
    VALUES (p_token, true);

    RETURN QUERY SELECT
        v_partner.id, v_partner.name, v_partner.type,
        v_partner.is_premium, v_partner.is_active,
        v_partner.loyalty_enabled, v_partner.has_booking,
        v_partner.hh_active, v_partner.hh_date,
        v_partner.hh_start, v_partner.hh_end,
        v_partner.partner_code, v_partner.lat, v_partner.lng,
        v_partner.phone, v_partner.whatsapp,
        true, 'OK'::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ── 5. FUNKCIJA: regenerate_partner_token ────────────────────────
-- Admin poziva kada treba da izda novi URL za partnera

CREATE OR REPLACE FUNCTION regenerate_partner_token(p_partner_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_new_token TEXT;
    v_name      TEXT;
BEGIN
    v_new_token := encode(gen_random_bytes(18), 'base64url');

    UPDATE partners
    SET access_token = v_new_token
    WHERE id = p_partner_id
    RETURNING name INTO v_name;

    -- Audit log
    INSERT INTO audit_log(action, target_id, target_name, details)
    VALUES (
        'token_regenerated',
        p_partner_id,
        v_name,
        jsonb_build_object('new_token_prefix', LEFT(v_new_token, 6) || '...')
    );

    RETURN v_new_token;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ── 6. FUNKCIJA: admin_create_partner ────────────────────────────
-- Kreira novog partnera i odmah generiše token
-- Poziva se samo iz admin panela

CREATE OR REPLACE FUNCTION admin_create_partner(
    p_name          TEXT,
    p_type          TEXT,
    p_pin           TEXT,
    p_partner_code  TEXT,
    p_phone         TEXT DEFAULT NULL,
    p_lat           NUMERIC DEFAULT NULL,
    p_lng           NUMERIC DEFAULT NULL
)
RETURNS TABLE(
    partner_id      UUID,
    access_token    TEXT,
    partner_url     TEXT
) AS $$
DECLARE
    v_id        UUID;
    v_token     TEXT;
BEGIN
    v_token := encode(gen_random_bytes(18), 'base64url');

    INSERT INTO partners(name, type, pin, partner_code, access_token, phone, lat, lng)
    VALUES (p_name, p_type, p_pin, p_partner_code, v_token, p_phone, p_lat, p_lng)
    RETURNING id INTO v_id;

    -- Kreira prazan sadržaj
    INSERT INTO partner_content(partner_id) VALUES (v_id);

    -- Audit log
    INSERT INTO audit_log(action, target_id, target_name, details)
    VALUES (
        'partner_created',
        v_id,
        p_name,
        jsonb_build_object('type', p_type, 'code', p_partner_code)
    );

    RETURN QUERY SELECT
        v_id,
        v_token,
        ('partner.html?t=' || v_token)::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ── 7. FUNKCIJA: admin_change_pin ────────────────────────────────
-- Admin menja PIN partneru, beleži u audit log

CREATE OR REPLACE FUNCTION admin_change_pin(
    p_partner_id    UUID,
    p_new_pin       TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    v_name TEXT;
BEGIN
    UPDATE partners
    SET pin = p_new_pin
    WHERE id = p_partner_id
    RETURNING name INTO v_name;

    IF NOT FOUND THEN RETURN false; END IF;

    INSERT INTO audit_log(action, target_id, target_name, details)
    VALUES (
        'pin_changed',
        p_partner_id,
        v_name,
        jsonb_build_object('changed_at', NOW())
    );

    -- Obriši stare login pokušaje (fresh start)
    DELETE FROM login_attempts la
    USING partners p
    WHERE p.id = p_partner_id
      AND la.access_token = p.access_token;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ── 8. CLEANUP JOB ───────────────────────────────────────────────
-- Briše stare login pokušaje (starije od 1h) i stare analytics (30 dana)
-- Supabase ne podržava pg_cron na free planu — pozivati ručno ili iz app-a

CREATE OR REPLACE FUNCTION cleanup_old_data()
RETURNS void AS $$
BEGIN
    DELETE FROM login_attempts WHERE attempted_at < NOW() - INTERVAL '1 hour';
    DELETE FROM analytics_clicks WHERE created_at < NOW() - INTERVAL '30 days';
    DELETE FROM audit_log WHERE performed_at < NOW() - INTERVAL '90 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ── 9. AŽURIRAJ RLS NA partners ──────────────────────────────────
-- Sakrij pin i access_token iz javnih SELECT upita

DROP POLICY IF EXISTS "partners_public_read" ON partners;
DROP POLICY IF EXISTS "partners_no_pin_leak" ON partners;

-- Gosti i partneri mogu čitati sve OSIM pin i access_token
-- To se rešava na app nivou — nikad ne selektuj pin i access_token u JS kodu
-- RLS ne može blokirati pojedine kolone, ali funkcije SECURITY DEFINER mogu
CREATE POLICY "partners_read" ON partners
    FOR SELECT USING (is_active = true);

-- Admin može čitati sve (uključujući neaktivne)
-- Admin bypass se radi kroz SECURITY DEFINER funkcije


-- ── 10. AŽURIRAJ seed - dodaj tokene za test partnere ─────────────
-- (tokeni su već generisani u koraku 1, ali dodajemo readable primere za dev)

-- Provjeri da li su tokeni generisani
SELECT id, name, type, LEFT(access_token, 12) || '...' AS token_preview
FROM partners
ORDER BY type, name;


-- ═══════════════════════════════════════════════════════════════════
-- KRAJ security.sql
-- ═══════════════════════════════════════════════════════════════════
