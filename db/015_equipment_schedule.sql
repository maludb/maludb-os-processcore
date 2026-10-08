-- 015_equipment_schedule.sql — equipment scheduling (the cidery's db/023 made generic): one table of bookings, each
-- a window of time on one machine — all day by default — for a run (production order, run, packaging run) or a block
-- (setup, maintenance, hold); whether two bookings may overlap is the organization's setting
-- settings.equipment.double_booking: refuse (default) or allow. Equipment itself is in 004; capabilities (D6) are
-- compared with an item's attributes by app.equipment_fits(), a warning never a stop.
SET search_path = app, public;

-- The business's time zone, for turning a booking's instants into its calendar days.
CREATE OR REPLACE FUNCTION app.client_timezone() RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT COALESCE((SELECT timezone FROM app.client_settings WHERE id = 1), 'UTC')
$$;

CREATE TABLE app.equipment_reservations (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    equipment_id  bigint NOT NULL REFERENCES app.equipment(id),
    kind          text NOT NULL DEFAULT 'run' CHECK (kind IN ('run','setup','maintenance','hold')),
    subject_kind  text CHECK (subject_kind IN ('production_order','run','packaging_run')),
    subject_id    bigint,                                      -- the run, when kind = run (checked by trigger)
    role          text NOT NULL DEFAULT 'primary' CHECK (role IN ('primary','secondary','setup','other')),
    starts_at     timestamptz NOT NULL,
    ends_at       timestamptz NOT NULL,                        -- exclusive: an all-day booking ends at 00:00 after its last day
    all_day       boolean NOT NULL DEFAULT true,
    shared        boolean NOT NULL DEFAULT false,              -- saved over a clash under the allow policy
    status        text NOT NULL DEFAULT 'booked' CHECK (status IN ('booked','cancelled')),
    notes         text,
    created_by    bigint REFERENCES app.users(id),
    cancelled_by  bigint REFERENCES app.users(id),
    cancelled_at  timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT equipment_reservations_window       CHECK (ends_at > starts_at),
    CONSTRAINT equipment_reservations_run_subject  CHECK ((kind = 'run') = (subject_kind IS NOT NULL)),
    CONSTRAINT equipment_reservations_subject_pair CHECK ((subject_kind IS NULL) = (subject_id IS NULL)),
    CONSTRAINT equipment_reservations_cancelled    CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL))
);
CREATE TRIGGER equipment_reservations_touch BEFORE UPDATE ON app.equipment_reservations FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE INDEX equipment_reservations_window_idx ON app.equipment_reservations
    USING gist (equipment_id, tstzrange(starts_at, ends_at)) WHERE status = 'booked';
CREATE INDEX equipment_reservations_subject_idx ON app.equipment_reservations (subject_kind, subject_id) WHERE status = 'booked';

-- The run must exist; a polymorphic pair cannot say so with a foreign key.
CREATE OR REPLACE FUNCTION app.equipment_reservations_check_refs() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.subject_kind IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM app.production_orders WHERE NEW.subject_kind = 'production_order' AND id = NEW.subject_id
        UNION ALL SELECT 1 FROM app.runs           WHERE NEW.subject_kind = 'run'              AND id = NEW.subject_id
        UNION ALL SELECT 1 FROM app.packaging_runs WHERE NEW.subject_kind = 'packaging_run'    AND id = NEW.subject_id) THEN
        RAISE EXCEPTION 'The run this reservation is for does not exist.' USING ERRCODE = 'foreign_key_violation';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER equipment_reservations_check_refs BEFORE INSERT OR UPDATE OF subject_kind, subject_id
    ON app.equipment_reservations FOR EACH ROW EXECUTE FUNCTION app.equipment_reservations_check_refs();

-- Every resource as one list (equipment only; the name is kept for the schedule's readers).
CREATE VIEW app.v_equipment_resources AS
SELECT e.id AS equipment_id, e.name, e.kind, k.name AS kind_name, e.site_id, e.location_id, e.status, e.rating, e.capabilities, e.active,
       k.display_order AS sort_group
  FROM app.equipment e JOIN app.equipment_kinds k ON k.code = e.kind;

-- The schedule: every booked reservation with its machine, its run and how many other bookings it overlaps.
CREATE VIEW app.v_equipment_schedule AS
SELECT r.id, r.equipment_id, res.name AS resource_name, res.kind AS resource_type, res.site_id, res.status AS resource_status,
       r.kind, r.subject_kind, r.subject_id,
       CASE r.subject_kind WHEN 'production_order' THEN po.number WHEN 'run' THEN rn.number WHEN 'packaging_run' THEN pk.number END AS subject_number,
       CASE r.subject_kind WHEN 'production_order' THEN pop.name WHEN 'run' THEN op.name WHEN 'packaging_run' THEN pc.name END AS subject_label,
       CASE r.subject_kind WHEN 'production_order' THEN po.status WHEN 'run' THEN rn.status WHEN 'packaging_run' THEN pk.status END AS subject_status,
       r.role, r.starts_at, r.ends_at, r.all_day, r.shared, r.status, r.notes, r.created_by, r.created_at,
       (r.starts_at AT TIME ZONE app.client_timezone())::date                       AS local_from,
       ((r.ends_at - interval '1 second') AT TIME ZONE app.client_timezone())::date AS local_to,
       (SELECT count(*) FROM app.equipment_reservations o
         WHERE o.status = 'booked' AND o.id <> r.id AND o.equipment_id = r.equipment_id
           AND tstzrange(o.starts_at, o.ends_at) && tstzrange(r.starts_at, r.ends_at)) AS clash_count
  FROM app.equipment_reservations r
  JOIN app.v_equipment_resources res ON res.equipment_id = r.equipment_id
  LEFT JOIN app.production_orders po ON r.subject_kind = 'production_order' AND po.id = r.subject_id
  LEFT JOIN app.products pop ON pop.id = po.product_id
  LEFT JOIN app.runs rn ON r.subject_kind = 'run' AND rn.id = r.subject_id
  LEFT JOIN app.operations op ON op.code = rn.operation_code
  LEFT JOIN app.packaging_runs pk ON r.subject_kind = 'packaging_run' AND pk.id = r.subject_id
  LEFT JOIN app.packaging_configurations pc ON pc.id = pk.packaging_configuration_id
 WHERE r.status = 'booked';

-- The clashes of a window on a machine: what the handler lists, what the form shows, what the tool answers.
CREATE OR REPLACE FUNCTION app.equipment_clashes(p_equipment_id bigint, p_starts timestamptz, p_ends timestamptz, p_exclude_id bigint DEFAULT NULL)
RETURNS TABLE (reservation_id bigint, kind text, subject_kind text, subject_id bigint, subject_number text, subject_label text,
               subject_status text, role text, starts_at timestamptz, ends_at timestamptz, all_day boolean, shared boolean,
               local_from date, local_to date)
LANGUAGE sql STABLE AS $$
    SELECT s.id, s.kind, s.subject_kind, s.subject_id, s.subject_number, s.subject_label, s.subject_status, s.role,
           s.starts_at, s.ends_at, s.all_day, s.shared, s.local_from, s.local_to
      FROM app.v_equipment_schedule s
     WHERE s.equipment_id = p_equipment_id
       AND tstzrange(s.starts_at, s.ends_at) && tstzrange(p_starts, p_ends)
       AND (p_exclude_id IS NULL OR s.id <> p_exclude_id)
       AND s.subject_status IS DISTINCT FROM 'cancelled'
     ORDER BY s.starts_at, s.id
$$;

-- Does this machine take this material? Each capability key is an attribute key with min and/or max (weight_kg is
-- the lot's weight; otherwise the item's attribute, or the lot's own when it has one). Answers the warnings, one
-- per limit exceeded, empty when it fits or when nothing is known.
CREATE OR REPLACE FUNCTION app.equipment_fits(p_equipment_id bigint, p_item_id bigint, p_lot_id bigint DEFAULT NULL)
RETURNS TABLE (attribute_key text, limit_kind text, limit_value numeric, actual_value numeric, message text)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_caps jsonb; v_key text; v_lim jsonb; v_actual numeric; v_name text; v_eq text;
BEGIN
    SELECT capabilities, name INTO v_caps, v_eq FROM app.equipment WHERE id = p_equipment_id;
    IF v_caps IS NULL THEN RETURN; END IF;
    FOR v_key, v_lim IN SELECT * FROM jsonb_each(v_caps) LOOP
        IF v_key = 'weight_kg' THEN
            SELECT weight_kg INTO v_actual FROM app.lots WHERE id = p_lot_id;
            v_name := 'weight (kg)';
        ELSE
            v_actual := COALESCE(CASE WHEN p_lot_id IS NOT NULL THEN app.lot_attribute_num(p_lot_id, v_key) END,
                                 app.item_attribute_num(p_item_id, v_key));
            SELECT COALESCE(d.name, v_key) || COALESCE(' (' || d.unit_code || ')', '') INTO v_name FROM app.attribute_definitions d WHERE d.key = v_key;
            v_name := COALESCE(v_name, v_key);
        END IF;
        IF v_actual IS NULL OR jsonb_typeof(v_lim) <> 'object' THEN CONTINUE; END IF;
        IF v_lim ? 'min' AND v_actual < (v_lim->>'min')::numeric THEN
            attribute_key := v_key; limit_kind := 'min'; limit_value := (v_lim->>'min')::numeric; actual_value := v_actual;
            message := format('%s: %s is below %s''s minimum of %s', v_name, v_actual, v_eq, limit_value);
            RETURN NEXT;
        END IF;
        IF v_lim ? 'max' AND v_actual > (v_lim->>'max')::numeric THEN
            attribute_key := v_key; limit_kind := 'max'; limit_value := (v_lim->>'max')::numeric; actual_value := v_actual;
            message := format('%s: %s is above %s''s maximum of %s', v_name, v_actual, v_eq, limit_value);
            RETURN NEXT;
        END IF;
    END LOOP;
END $$;

-- The policy settings.equipment.double_booking is 'refuse' by the column default (004) until the organization turns sharing on.
