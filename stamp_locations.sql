-- ═══════════════════════════════════════════════════════════════════
-- StayVB v2 — Stamp lokacije nadogradnja
-- Pokreni nakon security.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. NOVA TABELA: stamp_locations ─────────────────────────────
-- Sve lokacije koje daju pečat:
--   type = 'partner'  → restoran, hotel, atrakcija (već u partners tabeli)
--   type = 'public'   → vidikovac, fontana, park... (admin unosi)

CREATE TABLE IF NOT EXISTS stamp_locations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Identitet
    name            TEXT NOT NULL,          -- npr. "Vidikovac Goč"
    description     TEXT,                   -- kratki opis za gosta
    location_code   TEXT UNIQUE NOT NULL,   -- kratki kod za QR (npr. LOC_VIDOVAC)

    -- Tip
    type            TEXT NOT NULL DEFAULT 'public'
                    CHECK (type IN ('public', 'partner')),
    partner_id      UUID REFERENCES partners(id) ON DELETE CASCADE,
    -- partner_id je NULL za public lokacije, popunjen za partner lokacije

    -- Radar prikaz
    lat             NUMERIC(10, 7) NOT NULL,
    lng             NUMERIC(10, 7) NOT NULL,
    show_on_radar   BOOLEAN DEFAULT true,   -- admin on/off toggle

    -- Status
    is_active       BOOLEAN DEFAULT true,   -- daje pečate on/off

    -- Ikonica na radaru
    -- 'partner' tip dobija standardnu ikonu po tipu partnera
    -- 'public' tip dobija posebnu stamp ikonu (ciodom/strelica)
    icon_color      TEXT DEFAULT '#f59e0b', -- hex boja ikonice na radaru

    -- Meta
    sort_order      INT DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stamp_loc_active  ON stamp_locations(is_active);
CREATE INDEX IF NOT EXISTS idx_stamp_loc_radar   ON stamp_locations(show_on_radar, is_active);
CREATE INDEX IF NOT EXISTS idx_stamp_loc_code    ON stamp_locations(location_code);
CREATE INDEX IF NOT EXISTS idx_stamp_loc_partner ON stamp_locations(partner_id);

-- RLS
ALTER TABLE stamp_locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "stamp_loc_public_read" ON stamp_locations
    FOR SELECT USING (is_active = true);

CREATE POLICY "stamp_loc_write" ON stamp_locations
    FOR ALL USING (true);

-- Trigger updated_at
CREATE TRIGGER trg_stamp_loc_updated
    BEFORE UPDATE ON stamp_locations
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();


-- ── 2. AŽURIRAJ stamps TABELU ────────────────────────────────────
-- Umesto partner_id, stamps sada referencira stamp_locations
-- Migracioni korak: kreiraj stamp_location red za svaki postojeći partner
-- koji ima loyalty_enabled = true

-- Dodaj location_id kolonu
ALTER TABLE stamps
    ADD COLUMN IF NOT EXISTS location_id UUID REFERENCES stamp_locations(id) ON DELETE CASCADE;

-- Stara partner_id kolona ostaje privremeno za migraciju
-- Nakon migracije može se ukloniti

-- Novi unique constraint: gost + lokacija (1 pečat po lokaciji)
ALTER TABLE stamps
    DROP CONSTRAINT IF EXISTS uq_stamp_guest_partner;

ALTER TABLE stamps
    ADD CONSTRAINT uq_stamp_guest_location
    UNIQUE(guest_id, location_id);


-- ── 3. AUTOMATSKI KREIRAJ stamp_locations ZA POSTOJEĆE PARTNERE ─
-- Za sve partnere sa loyalty_enabled = true

INSERT INTO stamp_locations (
    name, description, location_code, type,
    partner_id, lat, lng, show_on_radar, is_active, icon_color
)
SELECT
    p.name,
    pc.short_desc,
    'LOC_' || p.partner_code,
    'partner',
    p.id,
    COALESCE(p.lat, 43.6208),
    COALESCE(p.lng, 20.8973),
    true,
    true,
    CASE p.type
        WHEN 'restaurant'  THEN '#f59e0b'
        WHEN 'hotel'       THEN '#3b82f6'
        WHEN 'attraction'  THEN '#10b981'
        WHEN 'business'    THEN '#8b5cf6'
        ELSE '#f59e0b'
    END
FROM partners p
LEFT JOIN partner_content pc ON pc.partner_id = p.id
WHERE p.loyalty_enabled = true
ON CONFLICT (location_code) DO NOTHING;


-- ── 4. SEED: JAVNE STAMP LOKACIJE (Vrnjačka Banja) ──────────────

INSERT INTO stamp_locations (
    name, description, location_code, type,
    lat, lng, show_on_radar, is_active, icon_color, sort_order
) VALUES

('Vidikovac Goč',
 'Panoramski pogled na Vrnjačku Banju sa vrha Goča',
 'LOC_VIDOVAC', 'public',
 43.6380, 20.8870, true, true, '#f59e0b', 1),

('Stara česma — izvor',
 'Istorijski izvor mineralne vode u centru Banje',
 'LOC_CESMA', 'public',
 43.6198, 20.8962, true, true, '#f59e0b', 2),

('Fontana na šetalištu',
 'Centralna fontana na glavnom šetalištu',
 'LOC_FONTANA', 'public',
 43.6205, 20.8968, true, true, '#f59e0b', 3),

('Park Vladimira Rolović',
 'Gradski park u centru Vrnjačke Banje',
 'LOC_PARK', 'public',
 43.6210, 20.8975, true, true, '#f59e0b', 4),

('Teniski tereni VB',
 'Sportski centar sa teniskim terenima',
 'LOC_TENIS', 'public',
 43.6188, 20.8945, true, true, '#f59e0b', 5);


-- ── 5. AŽURIRANA FUNKCIJA: get_stamp_locations_for_radar ─────────
-- Vraća sve aktivne stamp lokacije za prikaz na radaru
-- Uključuje: koordinate, ime, tip, boju ikonice

CREATE OR REPLACE FUNCTION get_radar_stamps()
RETURNS TABLE (
    id              UUID,
    name            TEXT,
    description     TEXT,
    location_code   TEXT,
    type            TEXT,
    lat             NUMERIC,
    lng             NUMERIC,
    icon_color      TEXT,
    partner_type    TEXT,   -- za partner lokacije (restaurant/hotel/...)
    is_active       BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sl.id,
        sl.name,
        sl.description,
        sl.location_code,
        sl.type,
        sl.lat,
        sl.lng,
        sl.icon_color,
        p.type AS partner_type,
        sl.is_active
    FROM stamp_locations sl
    LEFT JOIN partners p ON p.id = sl.partner_id
    WHERE sl.show_on_radar = true
      AND sl.is_active = true
    ORDER BY sl.sort_order, sl.name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ── 6. AŽURIRANI stamp trigger ────────────────────────────────────
-- Sada koristi location_id umesto partner_id za brojanje

CREATE OR REPLACE FUNCTION update_stamp_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE guests SET stamp_count = stamp_count + 1 WHERE id = NEW.guest_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE guests SET stamp_count = GREATEST(0, stamp_count - 1) WHERE id = OLD.guest_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- ── 7. VERIFIKACIJA ──────────────────────────────────────────────
/*
SELECT type, COUNT(*), SUM(CASE WHEN is_active THEN 1 ELSE 0 END) as active
FROM stamp_locations
GROUP BY type;

SELECT * FROM get_radar_stamps();
*/

-- ═══════════════════════════════════════════════════════════════════
-- KRAJ stamp_locations.sql
-- ═══════════════════════════════════════════════════════════════════
