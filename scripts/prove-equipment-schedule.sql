-- Checks for db/023_equipment_schedule.sql, run by scripts/prove-equipment-schedule.sh after the seed and the migration.
-- Each check is one row in prove_results; the script's exit status is the number of failures.
SET search_path = app, public;
CREATE TEMP TABLE prove_results (n serial, name text, ok boolean);
CREATE OR REPLACE FUNCTION pg_temp.check(p_name text, p_ok boolean) RETURNS void LANGUAGE sql SECURITY DEFINER AS
    $$ INSERT INTO prove_results (name, ok) VALUES (p_name, COALESCE(p_ok, false)) $$;
\pset tuples_only on
\pset format unaligned
CREATE OR REPLACE FUNCTION pg_temp.fails(p_name text, p_sql text, p_sqlstate text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    EXECUTE p_sql;
    PERFORM pg_temp.check(p_name, false);
EXCEPTION WHEN others THEN
    PERFORM pg_temp.check(p_name, SQLSTATE = p_sqlstate);
END $$;

-- 1. The old table is a view now, with the same six columns ---------------------------------------------------------
SELECT pg_temp.check('production_order_vessels is a view',
    (SELECT relkind FROM pg_class WHERE oid = 'app.production_order_vessels'::regclass) = 'v');
SELECT pg_temp.check('the view has the old six columns in order',
    (SELECT array_agg(attname::text ORDER BY attnum) FROM pg_attribute WHERE attrelid = 'app.production_order_vessels'::regclass AND attnum > 0)
      = ARRAY['id','production_order_id','vessel_id','role','planned_from','planned_to']);

-- 2. Row for row: every plan of a live order is back with the same dates; the cancelled order's plan is not ---------
SELECT pg_temp.check('live plans migrate row for row (same order, vessel, role, from, to)',
    NOT EXISTS (SELECT production_order_id, vessel_id, role, planned_from, planned_to FROM app.prove_before WHERE status <> 'cancelled'
                EXCEPT SELECT production_order_id, vessel_id, role, planned_from, planned_to FROM app.production_order_vessels)
    AND NOT EXISTS (SELECT production_order_id, vessel_id, role, planned_from, planned_to FROM app.production_order_vessels
                    EXCEPT SELECT production_order_id, vessel_id, role, planned_from, planned_to FROM app.prove_before WHERE status <> 'cancelled'));
SELECT pg_temp.check('the view holds 4 rows (5 seeded, 1 of a cancelled order)', (SELECT count(*) FROM app.production_order_vessels) = 4);
SELECT pg_temp.check('the cancelled order''s row arrived cancelled, with cancelled_at',
    (SELECT count(*) FROM app.equipment_reservations r JOIN app.production_orders o ON o.id = r.subject_id
      WHERE r.subject_kind = 'production_order' AND o.number = 'PROVE-WO-C' AND r.status = 'cancelled' AND r.cancelled_at IS NOT NULL) = 1);
SELECT pg_temp.check('migrated bookings are all-day vessel runs with the order as subject',
    (SELECT bool_and(resource_kind = 'vessel' AND kind = 'run' AND subject_kind = 'production_order' AND all_day) FROM app.equipment_reservations));
SELECT pg_temp.check('an all-day booking starts at local midnight and ends at local midnight after its last day',
    (SELECT bool_and((starts_at AT TIME ZONE app.client_timezone())::time = '00:00' AND (ends_at AT TIME ZONE app.client_timezone())::time = '00:00'
                     AND ends_at - starts_at >= interval '1 day') FROM app.equipment_reservations));

-- 3. The policy and the shared marks -------------------------------------------------------------------------------
SELECT pg_temp.check('overlapping live plans existed, so the switch starts on (allow)',
    (SELECT settings #>> '{equipment,double_booking}' FROM app.client_settings WHERE id = 1) = 'allow');
SELECT pg_temp.check('the two overlapping rows (A and B on FV-A) are marked shared, the other three are not',
    (SELECT array_agg(o.number || '/' || v.name ORDER BY o.number) FROM app.equipment_reservations r JOIN app.production_orders o ON o.id = r.subject_id
       JOIN app.vessels v ON v.id = r.resource_id WHERE r.shared) = ARRAY['PROVE-WO-A/PROVE FV-A', 'PROVE-WO-B/PROVE FV-A']);

-- 4. The readers' SQL still runs against the view ------------------------------------------------------------------
SELECT pg_temp.check('find_vessel_conflicts'' plan query: A overlaps B and not the cancelled C',
    (SELECT array_agg(o.number ORDER BY o.number)
       FROM app.production_order_vessels pv
       JOIN app.production_order_vessels other ON other.vessel_id = pv.vessel_id AND other.production_order_id <> pv.production_order_id
       JOIN app.production_orders o ON o.id = other.production_order_id AND o.status IN ('planned', 'released', 'in_progress')
      WHERE pv.production_order_id = (SELECT id FROM app.production_orders WHERE number = 'PROVE-WO-A')
        AND daterange(pv.planned_from, pv.planned_to, '[]') && daterange(other.planned_from, other.planned_to, '[]')) = ARRAY['PROVE-WO-B']);
SELECT pg_temp.check('find_calendar_rows'' window query returns the November plans of live orders',
    (SELECT count(*) FROM app.production_order_vessels pv JOIN app.production_orders o ON o.id = pv.production_order_id
      WHERE o.status IN ('planned', 'released', 'in_progress')
        AND daterange(pv.planned_from, pv.planned_to, '[]') && daterange(DATE '2026-11-01', DATE '2026-11-30', '[]')) = 3);
SELECT pg_temp.check('the records MCP''s vessels aggregate reads the view',
    (SELECT jsonb_array_length((SELECT jsonb_agg(jsonb_build_object('vessel', v.name, 'role', pov.role, 'from', pov.planned_from, 'to', pov.planned_to) ORDER BY pov.planned_from)
          FROM app.production_order_vessels pov JOIN app.vessels v ON v.id = pov.vessel_id
         WHERE pov.production_order_id = (SELECT id FROM app.production_orders WHERE number = 'PROVE-WO-A')))) = 2);

-- 5. The clash function --------------------------------------------------------------------------------------------
SELECT pg_temp.check('a day inside both A and B on FV-A clashes with both',
    (SELECT array_agg(subject_number ORDER BY subject_number) FROM app.equipment_clashes('vessel', (SELECT id FROM app.vessels WHERE name = 'PROVE FV-A'),
        TIMESTAMP '2026-11-12 00:00' AT TIME ZONE app.client_timezone(), TIMESTAMP '2026-11-13 00:00' AT TIME ZONE app.client_timezone()))
      = ARRAY['PROVE-WO-A', 'PROVE-WO-B']);
SELECT pg_temp.check('excluding A''s own booking leaves B',
    (SELECT array_agg(subject_number) FROM app.equipment_clashes('vessel', (SELECT id FROM app.vessels WHERE name = 'PROVE FV-A'),
        TIMESTAMP '2026-11-12 00:00' AT TIME ZONE app.client_timezone(), TIMESTAMP '2026-11-13 00:00' AT TIME ZONE app.client_timezone(),
        (SELECT r.id FROM app.equipment_reservations r JOIN app.production_orders o ON o.id = r.subject_id WHERE o.number = 'PROVE-WO-A' AND r.resource_id = (SELECT id FROM app.vessels WHERE name = 'PROVE FV-A'))))
      = ARRAY['PROVE-WO-B']);
SELECT pg_temp.check('the cancelled order''s window (Nov 1) clashes with nothing but A',
    (SELECT array_agg(subject_number) FROM app.equipment_clashes('vessel', (SELECT id FROM app.vessels WHERE name = 'PROVE FV-A'),
        TIMESTAMP '2026-11-02 00:00' AT TIME ZONE app.client_timezone(), TIMESTAMP '2026-11-03 00:00' AT TIME ZONE app.client_timezone())) = ARRAY['PROVE-WO-A']);
SELECT pg_temp.check('a window after every booking is free',
    (SELECT count(*) FROM app.equipment_clashes('vessel', (SELECT id FROM app.vessels WHERE name = 'PROVE FV-A'),
        TIMESTAMP '2026-11-21 00:00' AT TIME ZONE app.client_timezone(), TIMESTAMP '2026-11-28 00:00' AT TIME ZONE app.client_timezone())) = 0);
SELECT pg_temp.check('the window is half-open: a booking starting the day another ends does not clash',
    (SELECT count(*) FROM app.equipment_clashes('vessel', (SELECT id FROM app.vessels WHERE name = 'PROVE FV-B'),
        TIMESTAMP '2026-12-01 00:00' AT TIME ZONE app.client_timezone(), TIMESTAMP '2026-12-02 00:00' AT TIME ZONE app.client_timezone(),
        (SELECT r.id FROM app.equipment_reservations r JOIN app.production_orders o ON o.id = r.subject_id WHERE o.number = 'PROVE-WO-D'))) = 0);

-- 6. Equipment, timed bookings and blocks ---------------------------------------------------------------------------
INSERT INTO app.equipment (premises_id, name, kind, rating) SELECT premises_id, 'PROVE canning line', 'canning_line', '120 cans/min' FROM app.locations WHERE name = 'PROVE cellar';
SELECT pg_temp.check('v_equipment_resources lists vessels before equipment, equipment with no capacity',
    (SELECT array_agg(resource_kind ORDER BY sort_group, name) FROM app.v_equipment_resources WHERE name LIKE 'PROVE %') = ARRAY['vessel','vessel','vessel','equipment']
    AND (SELECT capacity_l IS NULL FROM app.v_equipment_resources WHERE name = 'PROVE canning line'));
-- two timed runs on the line the same day, morning and afternoon, for a batch and an order
INSERT INTO app.batches (number, premises_id, product_id)
SELECT 'PROVE-B-1', l.premises_id, p.id FROM app.locations l, app.products p WHERE l.name = 'PROVE cellar' AND p.code = 'PROVE-DRY';
INSERT INTO app.equipment_reservations (resource_kind, resource_id, kind, subject_kind, subject_id, role, starts_at, ends_at, all_day)
SELECT 'equipment', e.id, 'run', 'batch', b.id, 'package',
       TIMESTAMP '2026-11-18 08:00' AT TIME ZONE app.client_timezone(), TIMESTAMP '2026-11-18 12:00' AT TIME ZONE app.client_timezone(), false
  FROM app.equipment e, app.batches b WHERE e.name = 'PROVE canning line' AND b.number = 'PROVE-B-1';
INSERT INTO app.equipment_reservations (resource_kind, resource_id, kind, subject_kind, subject_id, role, starts_at, ends_at, all_day)
SELECT 'equipment', e.id, 'run', 'production_order', o.id, 'package',
       TIMESTAMP '2026-11-18 13:00' AT TIME ZONE app.client_timezone(), TIMESTAMP '2026-11-18 17:00' AT TIME ZONE app.client_timezone(), false
  FROM app.equipment e, app.production_orders o WHERE e.name = 'PROVE canning line' AND o.number = 'PROVE-WO-A';
SELECT pg_temp.check('two timed runs on one line, morning and afternoon, do not clash',
    (SELECT bool_and(clash_count = 0) FROM app.v_equipment_schedule WHERE resource_name = 'PROVE canning line'));
SELECT pg_temp.check('a run across lunch clashes with both',
    (SELECT count(*) FROM app.equipment_clashes('equipment', (SELECT id FROM app.equipment WHERE name = 'PROVE canning line'),
        TIMESTAMP '2026-11-18 11:00' AT TIME ZONE app.client_timezone(), TIMESTAMP '2026-11-18 14:00' AT TIME ZONE app.client_timezone())) = 2);
SELECT pg_temp.check('the schedule names the batch and its product, and the local day of a timed booking',
    (SELECT subject_number = 'PROVE-B-1' AND subject_label = 'PROVE Dry' AND local_from = DATE '2026-11-18' AND local_to = DATE '2026-11-18'
       FROM app.v_equipment_schedule WHERE subject_kind = 'batch'));
INSERT INTO app.equipment_reservations (resource_kind, resource_id, kind, role, starts_at, ends_at, notes)
SELECT 'equipment', id, 'cleaning', 'other', TIMESTAMP '2026-11-19 00:00' AT TIME ZONE app.client_timezone(), TIMESTAMP '2026-11-20 00:00' AT TIME ZONE app.client_timezone(), 'CIP'
  FROM app.equipment WHERE name = 'PROVE canning line';
SELECT pg_temp.check('a cleaning block has no subject and appears on the schedule',
    (SELECT subject_kind IS NULL AND subject_number IS NULL AND kind = 'cleaning' FROM app.v_equipment_schedule WHERE notes = 'CIP'));
SELECT pg_temp.check('the clash function sees the block too',
    (SELECT kind FROM app.equipment_clashes('equipment', (SELECT id FROM app.equipment WHERE name = 'PROVE canning line'),
        TIMESTAMP '2026-11-19 09:00' AT TIME ZONE app.client_timezone(), TIMESTAMP '2026-11-19 10:00' AT TIME ZONE app.client_timezone())) = 'cleaning');

-- 7. The rules the table enforces -------------------------------------------------------------------------------
SELECT pg_temp.fails('a run without a subject is refused',
    $$INSERT INTO app.equipment_reservations (resource_kind, resource_id, kind, starts_at, ends_at) VALUES ('vessel', (SELECT id FROM app.vessels WHERE name = 'PROVE BT-C'), 'run', now(), now() + interval '1 day')$$, '23514');
SELECT pg_temp.fails('a block with a subject is refused',
    $$INSERT INTO app.equipment_reservations (resource_kind, resource_id, kind, subject_kind, subject_id, starts_at, ends_at) VALUES ('vessel', (SELECT id FROM app.vessels WHERE name = 'PROVE BT-C'), 'hold', 'batch', (SELECT id FROM app.batches WHERE number = 'PROVE-B-1'), now(), now() + interval '1 day')$$, '23514');
SELECT pg_temp.fails('an empty or backwards window is refused',
    $$INSERT INTO app.equipment_reservations (resource_kind, resource_id, kind, starts_at, ends_at) VALUES ('vessel', (SELECT id FROM app.vessels WHERE name = 'PROVE BT-C'), 'hold', now(), now())$$, '23514');
SELECT pg_temp.fails('a vessel that does not exist is refused',
    $$INSERT INTO app.equipment_reservations (resource_kind, resource_id, kind, starts_at, ends_at) VALUES ('vessel', 999999999, 'hold', now(), now() + interval '1 day')$$, '23503');
SELECT pg_temp.fails('equipment that does not exist is refused',
    $$INSERT INTO app.equipment_reservations (resource_kind, resource_id, kind, starts_at, ends_at) VALUES ('equipment', 999999999, 'hold', now(), now() + interval '1 day')$$, '23503');
SELECT pg_temp.fails('a run whose subject does not exist is refused',
    $$INSERT INTO app.equipment_reservations (resource_kind, resource_id, kind, subject_kind, subject_id, starts_at, ends_at) VALUES ('vessel', (SELECT id FROM app.vessels WHERE name = 'PROVE BT-C'), 'run', 'press_run', 999999999, now(), now() + interval '1 day')$$, '23503');
SELECT pg_temp.fails('cancelled without cancelled_at is refused',
    $$UPDATE app.equipment_reservations SET status = 'cancelled' WHERE notes = 'CIP'$$, '23514');
SELECT pg_temp.fails('an unknown equipment kind is refused',
    $$INSERT INTO app.equipment (premises_id, name, kind) SELECT premises_id, 'PROVE press', 'press' FROM app.locations WHERE name = 'PROVE cellar'$$, '23514');
SELECT pg_temp.fails('two pieces of equipment with one name on one premises are refused',
    $$INSERT INTO app.equipment (premises_id, name, kind) SELECT premises_id, 'PROVE canning line', 'labeler' FROM app.locations WHERE name = 'PROVE cellar'$$, '23505');

-- 8. Cancelling takes a booking off the schedule and out of the view and the clashes --------------------------------
UPDATE app.equipment_reservations SET status = 'cancelled', cancelled_at = now()
 WHERE subject_kind = 'production_order' AND subject_id = (SELECT id FROM app.production_orders WHERE number = 'PROVE-WO-B');
SELECT pg_temp.check('a cancelled booking leaves the view, the schedule and the clashes',
    (SELECT count(*) FROM app.production_order_vessels pv JOIN app.production_orders o ON o.id = pv.production_order_id WHERE o.number = 'PROVE-WO-B') = 0
    AND (SELECT count(*) FROM app.v_equipment_schedule WHERE subject_number = 'PROVE-WO-B') = 0
    AND (SELECT array_agg(subject_number) FROM app.equipment_clashes('vessel', (SELECT id FROM app.vessels WHERE name = 'PROVE FV-A'),
        TIMESTAMP '2026-11-12 00:00' AT TIME ZONE app.client_timezone(), TIMESTAMP '2026-11-13 00:00' AT TIME ZONE app.client_timezone())) = ARRAY['PROVE-WO-A']);
UPDATE app.equipment_reservations SET notes = 'CIP, acid' WHERE notes = 'CIP';
SELECT pg_temp.check('the touch trigger moves updated_at', (SELECT updated_at > created_at FROM app.equipment_reservations WHERE notes = 'CIP, acid'));

-- 9. Grants: the records reader sees the views and the function and cannot write; the app role writes -------------
SET ROLE processcore_records_ro;
SELECT pg_temp.check('records reader reads v_equipment_schedule', (SELECT count(*) FROM app.v_equipment_schedule) >= 4);
SELECT pg_temp.check('records reader reads v_equipment_resources and equipment', (SELECT count(*) FROM app.v_equipment_resources) >= 4 AND (SELECT count(*) FROM app.equipment) = 1);
SELECT pg_temp.check('records reader calls equipment_clashes and client_timezone',
    (SELECT count(*) FROM app.equipment_clashes('equipment', (SELECT id FROM app.equipment WHERE name = 'PROVE canning line'),
        TIMESTAMP '2026-11-18 11:00' AT TIME ZONE app.client_timezone(), TIMESTAMP '2026-11-18 14:00' AT TIME ZONE app.client_timezone())) = 2);
-- (not through pg_temp.fails: that helper is SECURITY DEFINER and would insert as postgres)
DO $$ BEGIN
    INSERT INTO app.equipment_reservations (resource_kind, resource_id, kind, starts_at, ends_at) VALUES ('vessel', 1, 'hold', now(), now() + interval '1 day');
    PERFORM pg_temp.check('records reader cannot insert a reservation', false);
EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.check('records reader cannot insert a reservation', true);
END $$;
RESET ROLE;

-- 10. A fresh install: the switch is refuse when nothing overlaps ----------------------------------------------------
-- Re-derive on this data with the overlap gone (B cancelled): the same statement with the guard removed must say refuse.
SELECT pg_temp.check('with no live overlap the derivation says refuse',
    (SELECT CASE WHEN EXISTS (
        SELECT 1 FROM app.production_order_vessels a
          JOIN app.production_orders oa ON oa.id = a.production_order_id AND oa.status IN ('planned','released','in_progress')
          JOIN app.production_order_vessels b ON b.vessel_id = a.vessel_id AND b.production_order_id <> a.production_order_id
          JOIN app.production_orders ob ON ob.id = b.production_order_id AND ob.status IN ('planned','released','in_progress')
         WHERE daterange(a.planned_from, a.planned_to, '[]') && daterange(b.planned_from, b.planned_to, '[]')) THEN 'allow' ELSE 'refuse' END) = 'refuse');

\pset tuples_only off
\pset format aligned
-- Report ---------------------------------------------------------------------------------------------------------
SELECT CASE WHEN ok THEN 'ok   ' ELSE 'FAIL ' END || name AS result FROM prove_results ORDER BY n;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM prove_results;
DO $$ DECLARE n int; BEGIN SELECT count(*) INTO n FROM prove_results WHERE NOT ok; IF n > 0 THEN RAISE EXCEPTION '% check(s) failed', n; END IF; END $$;
