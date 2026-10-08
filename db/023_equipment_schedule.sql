-- 023_equipment_schedule.sql — equipment scheduling (docs/cidery/15-equipment-schedule-plan.md, approved 2026-10-08, all the
-- recommendations; design docs/cidery/16-equipment-schedule-design.md). Run as processcore_app.
--
-- Equipment that holds no liquid sits beside the vessels; one table of bookings holds every reservation of either
-- (the production order's vessel plan moves into it and app.production_order_vessels becomes a view of the same shape);
-- a booking is a window of time — all day by default — for a run (production order, batch, press run, packaging run)
-- or a block (cleaning, maintenance, hold); whether two bookings may overlap is the organization's setting
-- settings.equipment.double_booking, not the table's: refuse (default) or allow.
SET search_path = app, public;

-- 0. The business's time zone, for turning a booking's instants into its calendar days ----------------------------
CREATE OR REPLACE FUNCTION app.client_timezone() RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT COALESCE((SELECT timezone FROM app.client_settings WHERE id = 1), 'UTC')
$$;

-- 1. Equipment: what a run needs that holds nothing (a press is a vessel of kind press, not equipment) ----------------
CREATE TABLE app.equipment (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    premises_id bigint NOT NULL REFERENCES app.premises(id),
    location_id bigint REFERENCES app.locations(id),           -- the cellar or packaging area it stands in, when known
    name        text NOT NULL,
    kind        text NOT NULL CHECK (kind IN ('mill','pump','filter','chiller','carbonator','canning_line','bottling_line',
                                              'keg_line','keg_washer','labeler','other')),
    status      text NOT NULL DEFAULT 'available' CHECK (status IN ('available','cleaning','out_of_service')),
    rating      text,                                          -- "120 cans/min", "4,000 L/h": words, not a number
    notes       text,
    active      boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (premises_id, name)
);
CREATE TRIGGER equipment_touch BEFORE UPDATE ON app.equipment FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- 2. Reservations: one resource, one window, for a run or a block ---------------------------------------------------
CREATE TABLE app.equipment_reservations (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resource_kind text NOT NULL CHECK (resource_kind IN ('vessel','equipment')),
    resource_id   bigint NOT NULL,                             -- app.vessels.id or app.equipment.id (checked by trigger)
    kind          text NOT NULL DEFAULT 'run' CHECK (kind IN ('run','cleaning','maintenance','hold')),
    subject_kind  text CHECK (subject_kind IN ('production_order','batch','press_run','packaging_run')),
    subject_id    bigint,                                      -- the run, when kind = run (checked by trigger)
    role          text NOT NULL DEFAULT 'other' CHECK (role IN ('primary','maturation','brite','blend',   -- vessels, as before
                                                                 'press','mill','transfer','filter','carbonate','package','other')),
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
    CONSTRAINT equipment_reservations_window      CHECK (ends_at > starts_at),
    CONSTRAINT equipment_reservations_run_subject CHECK ((kind = 'run') = (subject_kind IS NOT NULL)),
    CONSTRAINT equipment_reservations_subject_pair CHECK ((subject_kind IS NULL) = (subject_id IS NULL)),
    CONSTRAINT equipment_reservations_cancelled   CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL))
);
CREATE TRIGGER equipment_reservations_touch BEFORE UPDATE ON app.equipment_reservations FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
-- The clash query and the schedule window read this (btree_gist is in, with maludb_core).
CREATE INDEX equipment_reservations_window_idx ON app.equipment_reservations
    USING gist (resource_kind, resource_id, tstzrange(starts_at, ends_at)) WHERE status = 'booked';
CREATE INDEX equipment_reservations_subject_idx ON app.equipment_reservations (subject_kind, subject_id) WHERE status = 'booked';

-- The resource and the run must exist; a polymorphic pair cannot say so with a foreign key.
CREATE OR REPLACE FUNCTION app.equipment_reservations_check_refs() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.resource_kind = 'vessel' AND NOT EXISTS (SELECT 1 FROM app.vessels WHERE id = NEW.resource_id) THEN
        RAISE EXCEPTION 'The vessel does not exist.' USING ERRCODE = 'foreign_key_violation';
    ELSIF NEW.resource_kind = 'equipment' AND NOT EXISTS (SELECT 1 FROM app.equipment WHERE id = NEW.resource_id) THEN
        RAISE EXCEPTION 'The equipment does not exist.' USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF NEW.subject_kind IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM app.production_orders WHERE NEW.subject_kind = 'production_order' AND id = NEW.subject_id
        UNION ALL SELECT 1 FROM app.batches        WHERE NEW.subject_kind = 'batch'            AND id = NEW.subject_id
        UNION ALL SELECT 1 FROM app.press_runs     WHERE NEW.subject_kind = 'press_run'        AND id = NEW.subject_id
        UNION ALL SELECT 1 FROM app.packaging_runs WHERE NEW.subject_kind = 'packaging_run'    AND id = NEW.subject_id) THEN
        RAISE EXCEPTION 'The run this reservation is for does not exist.' USING ERRCODE = 'foreign_key_violation';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER equipment_reservations_check_refs BEFORE INSERT OR UPDATE OF resource_kind, resource_id, subject_kind, subject_id
    ON app.equipment_reservations FOR EACH ROW EXECUTE FUNCTION app.equipment_reservations_check_refs();

-- 3. The vessel plan moves in: every row of production_order_vessels becomes an all-day vessel booking of its order.
--    Rows of cancelled orders arrive cancelled (D10 going forward: cancelling an order cancels its bookings).
INSERT INTO app.equipment_reservations
       (resource_kind, resource_id, kind, subject_kind, subject_id, role, starts_at, ends_at, all_day, status, cancelled_at, created_by, created_at)
SELECT 'vessel', pv.vessel_id, 'run', 'production_order', pv.production_order_id, pv.role,
       pv.planned_from::timestamp AT TIME ZONE app.client_timezone(),
       (pv.planned_to + 1)::timestamp AT TIME ZONE app.client_timezone(),
       true,
       CASE WHEN o.status = 'cancelled' THEN 'cancelled' ELSE 'booked' END,
       CASE WHEN o.status = 'cancelled' THEN o.updated_at END,
       o.created_by, o.created_at
  FROM app.production_order_vessels pv
  JOIN app.production_orders o ON o.id = pv.production_order_id
 ORDER BY pv.id;

DROP TABLE app.production_order_vessels;

-- The old name lives on as a view of the same six columns over booked vessel bookings of production orders, so
-- find_production_order_vessels, find_vessel_conflicts, find_calendar_rows and the records MCP keep working.
CREATE VIEW app.production_order_vessels AS
SELECT r.id,
       r.subject_id  AS production_order_id,
       r.resource_id AS vessel_id,
       r.role,
       (r.starts_at AT TIME ZONE app.client_timezone())::date                       AS planned_from,
       ((r.ends_at - interval '1 second') AT TIME ZONE app.client_timezone())::date AS planned_to
  FROM app.equipment_reservations r
 WHERE r.resource_kind = 'vessel' AND r.kind = 'run' AND r.subject_kind = 'production_order' AND r.status = 'booked';

-- 4. Every resource as one list: vessels first (by kind, then name), equipment after ----------------------------------
CREATE VIEW app.v_equipment_resources AS
SELECT 'vessel'::text AS resource_kind, v.id AS resource_id, v.name, v.kind, v.premises_id, v.location_id, v.status, v.capacity_l, v.active,
       CASE v.kind WHEN 'fermenter' THEN 1 WHEN 'tank' THEN 2 WHEN 'brite' THEN 3 WHEN 'tote' THEN 4 WHEN 'ibc' THEN 5 WHEN 'barrel' THEN 6 WHEN 'press' THEN 7 ELSE 8 END AS sort_group
  FROM app.vessels v
UNION ALL
SELECT 'equipment', e.id, e.name, e.kind, e.premises_id, e.location_id, e.status, NULL::numeric(14,3), e.active,
       CASE e.kind WHEN 'mill' THEN 11 WHEN 'pump' THEN 12 WHEN 'filter' THEN 13 WHEN 'chiller' THEN 14 WHEN 'carbonator' THEN 15
                   WHEN 'canning_line' THEN 16 WHEN 'bottling_line' THEN 17 WHEN 'keg_line' THEN 18 WHEN 'keg_washer' THEN 19 WHEN 'labeler' THEN 20 ELSE 21 END
  FROM app.equipment e;

-- 5. The schedule: every booked reservation with its resource, its run and how many other bookings it overlaps -------
CREATE VIEW app.v_equipment_schedule AS
SELECT r.id, r.resource_kind, r.resource_id, res.name AS resource_name, res.kind AS resource_type, res.premises_id, res.capacity_l,
       res.status AS resource_status,
       r.kind, r.subject_kind, r.subject_id,
       CASE r.subject_kind WHEN 'production_order' THEN po.number WHEN 'batch' THEN b.number
                           WHEN 'press_run' THEN pr.number WHEN 'packaging_run' THEN pk.number END AS subject_number,
       CASE r.subject_kind WHEN 'production_order' THEN pop.name WHEN 'batch' THEN bp.name
                           WHEN 'press_run' THEN 'Press run' WHEN 'packaging_run' THEN pc.name END AS subject_label,
       CASE r.subject_kind WHEN 'production_order' THEN po.status WHEN 'batch' THEN b.status
                           WHEN 'press_run' THEN pr.status WHEN 'packaging_run' THEN pk.status END AS subject_status,
       r.role, r.starts_at, r.ends_at, r.all_day, r.shared, r.status, r.notes, r.created_by, r.created_at,
       (r.starts_at AT TIME ZONE app.client_timezone())::date                       AS local_from,
       ((r.ends_at - interval '1 second') AT TIME ZONE app.client_timezone())::date AS local_to,
       (SELECT count(*) FROM app.equipment_reservations o
         WHERE o.status = 'booked' AND o.id <> r.id AND o.resource_kind = r.resource_kind AND o.resource_id = r.resource_id
           AND tstzrange(o.starts_at, o.ends_at) && tstzrange(r.starts_at, r.ends_at)) AS clash_count
  FROM app.equipment_reservations r
  JOIN app.v_equipment_resources res ON res.resource_kind = r.resource_kind AND res.resource_id = r.resource_id
  LEFT JOIN app.production_orders po ON r.subject_kind = 'production_order' AND po.id = r.subject_id
  LEFT JOIN app.products pop ON pop.id = po.product_id
  LEFT JOIN app.batches b ON r.subject_kind = 'batch' AND b.id = r.subject_id
  LEFT JOIN app.products bp ON bp.id = b.product_id
  LEFT JOIN app.press_runs pr ON r.subject_kind = 'press_run' AND pr.id = r.subject_id
  LEFT JOIN app.packaging_runs pk ON r.subject_kind = 'packaging_run' AND pk.id = r.subject_id
  LEFT JOIN app.packaging_configurations pc ON pc.id = pk.packaging_configuration_id
 WHERE r.status = 'booked';

-- 6. The clashes of a window on a resource: what the handler lists, what the form shows, what the tool answers --------
CREATE OR REPLACE FUNCTION app.equipment_clashes(p_resource_kind text, p_resource_id bigint, p_starts timestamptz, p_ends timestamptz,
                                                 p_exclude_id bigint DEFAULT NULL)
RETURNS TABLE (reservation_id bigint, kind text, subject_kind text, subject_id bigint, subject_number text, subject_label text,
               subject_status text, role text, starts_at timestamptz, ends_at timestamptz, all_day boolean, shared boolean,
               local_from date, local_to date)
LANGUAGE sql STABLE AS $$
    SELECT s.id, s.kind, s.subject_kind, s.subject_id, s.subject_number, s.subject_label, s.subject_status, s.role,
           s.starts_at, s.ends_at, s.all_day, s.shared, s.local_from, s.local_to
      FROM app.v_equipment_schedule s
     WHERE s.resource_kind = p_resource_kind AND s.resource_id = p_resource_id
       AND tstzrange(s.starts_at, s.ends_at) && tstzrange(p_starts, p_ends)
       AND (p_exclude_id IS NULL OR s.id <> p_exclude_id)
       AND s.subject_status IS DISTINCT FROM 'cancelled'
     ORDER BY s.starts_at, s.id
$$;

-- 7. The policy. Off (refuse) for everyone — unless overlapping vessel plans of live orders already exist, which the
--    old rule allowed with a warning: then the switch starts on and those bookings are marked shared, so nothing
--    already planned becomes a booking that cannot be saved.
WITH overlapping AS (
    SELECT DISTINCT a.id
      FROM app.production_order_vessels a
      JOIN app.production_orders oa ON oa.id = a.production_order_id AND oa.status IN ('planned','released','in_progress')
      JOIN app.production_order_vessels b ON b.vessel_id = a.vessel_id AND b.production_order_id <> a.production_order_id
      JOIN app.production_orders ob ON ob.id = b.production_order_id AND ob.status IN ('planned','released','in_progress')
     WHERE daterange(a.planned_from, a.planned_to, '[]') && daterange(b.planned_from, b.planned_to, '[]')
), marked AS (
    UPDATE app.equipment_reservations r SET shared = true FROM overlapping o WHERE r.id = o.id RETURNING r.id
)
UPDATE app.client_settings
   SET settings = settings || jsonb_build_object('equipment', jsonb_build_object('double_booking',
                  CASE WHEN EXISTS (SELECT 1 FROM marked) THEN 'allow' ELSE 'refuse' END))
 WHERE id = 1 AND NOT (settings ? 'equipment');
