-- 002_common.sql — helpers every later file relies on. Run as processcore_app.
-- ProcessCore schema (rewritten in place 2026-10-08, docs/processcore-design.md D2): the files 002–016 are the
-- application's own; 000, 001 and 020 are run by the provisioning scripts by name.
SET search_path = app, public;

-- updated_at maintenance -----------------------------------------------------
CREATE OR REPLACE FUNCTION app.touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;

-- Immutability guard for ledgers and logs ------------------------------------
CREATE OR REPLACE FUNCTION app.forbid_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% rows are immutable; post a compensating entry instead', TG_TABLE_NAME
        USING ERRCODE = 'integrity_constraint_violation';
END $$;

-- Document numbering ----------------------------------------------------------
-- Keys: lot (the default for a lot; an item class may name its own key — item_classes.lot_number_key), po, receipt,
-- run, packaging_run, shipment, transfer, adjustment, count, production_order, period_report, sales_order,
-- standing_order, order_import. Format tokens: {YY} {YYMMDD} {N:5}. A profile may add keys.
CREATE TABLE IF NOT EXISTS app.number_sequences (
    key          text PRIMARY KEY,
    format       text NOT NULL,
    period_reset text NOT NULL DEFAULT 'never' CHECK (period_reset IN ('never','year','day')),
    period_value text,
    next_value   bigint NOT NULL DEFAULT 1,
    updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION app.next_number(p_key text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    r        app.number_sequences%ROWTYPE;
    period   text;
    n        bigint;
    out_text text;
    pad      int;
BEGIN
    SELECT * INTO r FROM app.number_sequences WHERE key = p_key FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no number sequence for key %', p_key;
    END IF;
    period := CASE r.period_reset
                WHEN 'year' THEN to_char(now(), 'YY')
                WHEN 'day'  THEN to_char(now(), 'YYMMDD')
                ELSE NULL END;
    IF r.period_reset <> 'never' AND r.period_value IS DISTINCT FROM period THEN
        n := 1;
        UPDATE app.number_sequences SET period_value = period, next_value = 2, updated_at = now() WHERE key = p_key;
    ELSE
        n := r.next_value;
        UPDATE app.number_sequences SET next_value = r.next_value + 1, updated_at = now() WHERE key = p_key;
    END IF;
    out_text := replace(r.format, '{YY}', to_char(now(), 'YY'));
    out_text := replace(out_text, '{YYMMDD}', to_char(now(), 'YYMMDD'));
    pad := COALESCE(NULLIF(substring(out_text FROM '\{N:(\d+)\}'), '')::int, 5);
    out_text := regexp_replace(out_text, '\{N:\d+\}', lpad(n::text, pad, '0'));
    RETURN out_text;
END $$;

INSERT INTO app.number_sequences (key, format, period_reset) VALUES
    ('lot',              'L-{YYMMDD}-{N:3}', 'day'),
    ('po',               'PO-{N:5}',         'never'),
    ('receipt',          'GR-{N:5}',         'never'),
    ('run',              'RUN-{N:5}',        'never'),
    ('packaging_run',    'PK-{N:5}',         'never'),
    ('shipment',         'BOL-{N:5}',        'never'),
    ('transfer',         'TR-{N:5}',         'never'),
    ('adjustment',       'ADJ-{N:5}',        'never'),
    ('count',            'CNT-{N:5}',        'never'),
    ('production_order', 'WO-{N:5}',         'never'),
    ('period_report',    'RPT-{N:5}',        'never'),
    ('sales_order',      'SO-{N:5}',         'never'),
    ('standing_order',   'STO-{N:4}',        'never'),
    ('order_import',     'IMP-{N:4}',        'never')
ON CONFLICT (key) DO NOTHING;

-- Generic reference tables (gauge charts, density tables, any profile lookup): one row per (table, key).
CREATE TABLE IF NOT EXISTS app.reference_values (
    table_name text NOT NULL CHECK (table_name ~ '^[a-z][a-z0-9_]{1,49}$'),
    key        text NOT NULL,
    value_num  numeric(18,6),
    value_text text,
    note       text,
    sort_order int NOT NULL DEFAULT 0,
    PRIMARY KEY (table_name, key),
    CHECK (value_num IS NOT NULL OR value_text IS NOT NULL)
);

-- Theoretical weight of a rectangular solid: density (kg/m³) × thickness × width × length (metres). Any unit
-- conversion happens before the call (app.units). Used by the lot and the run for pieces that are not weighed.
CREATE OR REPLACE FUNCTION app.theoretical_weight_kg(p_density_kg_m3 numeric, p_thickness_m numeric, p_width_m numeric, p_length_m numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_density_kg_m3 IS NULL OR p_thickness_m IS NULL OR p_width_m IS NULL OR p_length_m IS NULL THEN NULL
                ELSE round(p_density_kg_m3 * p_thickness_m * p_width_m * p_length_m, 6) END
$$;
