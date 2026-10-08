-- 010_quality.sql — inspections and the spec evaluation of readings. Specs live in 007, readings in 008,
-- certificates and release decisions in 005.
SET search_path = app, public;

-- An inspection: visual, dimensional or final, of a lot or a run, with a verdict and typed findings.
CREATE TABLE app.inspections (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    target_kind    text NOT NULL CHECK (target_kind IN ('lot','run')),
    target_id      bigint NOT NULL,
    kind           text NOT NULL DEFAULT 'visual' CHECK (kind IN ('receiving','in_process','final','visual','dimensional','other')),
    inspected_on   date NOT NULL DEFAULT current_date,
    inspector_id   bigint REFERENCES app.users(id),
    inspector_name text,
    sample_code    text,
    verdict        text NOT NULL CHECK (verdict IN ('pass','fail','hold')),
    attributes     jsonb NOT NULL DEFAULT '{}'::jsonb,           -- {"surface": "clean", "edge": "smooth"}
    defects        jsonb NOT NULL DEFAULT '[]'::jsonb,           -- [{"defect":"scratch","severity":2}]
    comment        text,
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX inspections_target_idx ON app.inspections (target_kind, target_id, inspected_on DESC);

-- Evaluate a reading against the active spec for its product and operation. A run's product is its production
-- order's; a finished lot's product is on the finished lot; other lots have no spec.
CREATE OR REPLACE FUNCTION app.evaluate_reading_spec() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_spec app.specs%ROWTYPE; v_product bigint; v_op text;
BEGIN
    IF NEW.target_kind = 'run' THEN
        SELECT po.product_id, r.operation_code INTO v_product, v_op
          FROM app.runs r LEFT JOIN app.production_orders po ON po.id = r.production_order_id WHERE r.id = NEW.target_id;
        v_op := COALESCE(NEW.operation_code, v_op);
    ELSIF NEW.target_kind = 'lot' THEN
        SELECT fl.product_id INTO v_product FROM app.finished_lots fl WHERE fl.lot_id = NEW.target_id;
        v_op := NEW.operation_code;
    END IF;
    IF v_product IS NULL OR v_op IS NULL THEN RETURN NEW; END IF;
    SELECT * INTO v_spec FROM app.specs
     WHERE product_id = v_product AND operation_code = v_op AND measurement_type_code = NEW.measurement_type_code AND active;
    IF NOT FOUND THEN RETURN NEW; END IF;
    NEW.spec_id := v_spec.id;
    NEW.spec_result := CASE
        WHEN (v_spec.min_value IS NOT NULL AND NEW.value < v_spec.min_value)
          OR (v_spec.max_value IS NOT NULL AND NEW.value > v_spec.max_value) THEN 'fail'
        ELSE 'pass' END;
    RETURN NEW;
END $$;
CREATE TRIGGER readings_evaluate_spec BEFORE INSERT ON app.readings
    FOR EACH ROW EXECUTE FUNCTION app.evaluate_reading_spec();
