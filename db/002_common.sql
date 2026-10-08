-- 002_common.sql — helpers every later file relies on. Run as processcore_app.
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
-- Keys: lot, batch, po, receipt, press_run, packaging_run, removal, transfer,
-- adjustment, count, production_order. Format tokens: {YY} {YYMMDD} {N:5}.
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
    ('batch',            'B-{YY}-{N:3}',     'year'),
    ('po',               'PO-{N:5}',         'never'),
    ('receipt',          'GR-{N:5}',         'never'),
    ('press_run',        'PR-{N:5}',         'never'),
    ('packaging_run',    'PK-{N:5}',         'never'),
    ('removal',          'RM-{N:5}',         'never'),
    ('transfer',         'TR-{N:5}',         'never'),
    ('adjustment',       'ADJ-{N:5}',        'never'),
    ('count',            'CNT-{N:5}',        'never'),
    ('production_order', 'WO-{N:5}',         'never'),
    ('period_report',    'RPT-{N:5}',        'never')
ON CONFLICT (key) DO NOTHING;
