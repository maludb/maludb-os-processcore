-- Seed for scripts/prove-equipment-schedule.sh, run as processcore_app on the scratch copy BEFORE db/023.
-- Three vessels and four production orders whose vessel plans overlap two by two, one cancelled; the plan is
-- copied aside (app.prove_before) so the migration can be checked row for row.
SET search_path = app, public;

INSERT INTO app.locations (premises_id, name, kind, tax_state)
SELECT p.id, 'PROVE cellar', 'cellar', 'bonded' FROM app.premises p ORDER BY p.id LIMIT 1;

INSERT INTO app.vessels (premises_id, location_id, name, kind, capacity_l)
SELECT l.premises_id, l.id, v.name, v.kind, v.cap FROM app.locations l,
       (VALUES ('PROVE FV-A', 'fermenter', 2000), ('PROVE FV-B', 'fermenter', 2000), ('PROVE BT-C', 'brite', 1500)) AS v(name, kind, cap)
 WHERE l.name = 'PROVE cellar';

INSERT INTO app.products (code, name, status) VALUES ('PROVE-DRY', 'PROVE Dry', 'active');
INSERT INTO app.recipe_versions (product_id, version_no, status, target_batch_volume_l)
SELECT id, 1, 'active', 1800 FROM app.products WHERE code = 'PROVE-DRY';

INSERT INTO app.production_orders (number, premises_id, product_id, recipe_version_id, planned_volume_l, planned_pitch_on, status)
SELECT o.number, l.premises_id, p.id, rv.id, 1800, o.pitch, o.status
  FROM app.locations l, app.products p JOIN app.recipe_versions rv ON rv.product_id = p.id,
       (VALUES ('PROVE-WO-A', DATE '2026-11-02', 'planned'), ('PROVE-WO-B', DATE '2026-11-10', 'released'),
               ('PROVE-WO-C', DATE '2026-11-01', 'cancelled'), ('PROVE-WO-D', DATE '2026-12-01', 'planned')) AS o(number, pitch, status)
 WHERE l.name = 'PROVE cellar' AND p.code = 'PROVE-DRY';

-- A and B overlap on FV-A (live orders → the switch must start on, both rows shared); C is cancelled and overlaps A
-- (must not count); D is alone on FV-B after A's maturation there ends (no overlap).
INSERT INTO app.production_order_vessels (production_order_id, vessel_id, role, planned_from, planned_to)
SELECT o.id, v.id, r.role, r.f, r.t
  FROM (VALUES ('PROVE-WO-A', 'PROVE FV-A', 'primary',    DATE '2026-11-02', DATE '2026-11-16'),
               ('PROVE-WO-A', 'PROVE FV-B', 'maturation', DATE '2026-11-17', DATE '2026-11-30'),
               ('PROVE-WO-B', 'PROVE FV-A', 'primary',    DATE '2026-11-10', DATE '2026-11-20'),
               ('PROVE-WO-C', 'PROVE FV-A', 'primary',    DATE '2026-11-01', DATE '2026-11-05'),
               ('PROVE-WO-D', 'PROVE FV-B', 'primary',    DATE '2026-12-01', DATE '2026-12-14')) AS r(o, v, role, f, t)
  JOIN app.production_orders o ON o.number = r.o
  JOIN app.vessels v ON v.name = r.v;

CREATE TABLE app.prove_before AS
SELECT pv.production_order_id, pv.vessel_id, pv.role, pv.planned_from, pv.planned_to, o.status
  FROM app.production_order_vessels pv JOIN app.production_orders o ON o.id = pv.production_order_id;
