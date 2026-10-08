-- 022_tank_view.sql — the Tank view (Inventory): vessels arranged as they stand on the floor. Run as processcore_app.
-- A vessel remembers its place on the board in grid units (20 px each in the screen); NULL = not yet placed, the
-- screen lays those out after the placed ones. v_vessel_board gains the position and the juice lot's item name,
-- appended last so dependent readers keep working.
SET search_path = app, public;

ALTER TABLE app.vessels
    ADD COLUMN IF NOT EXISTS board_x integer CHECK (board_x IS NULL OR (board_x >= 0 AND board_x <= 400)),
    ADD COLUMN IF NOT EXISTS board_y integer CHECK (board_y IS NULL OR (board_y >= 0 AND board_y <= 400));

CREATE OR REPLACE VIEW app.v_vessel_board AS
SELECT v.id AS vessel_id, v.name AS vessel_name, v.kind AS vessel_kind, v.capacity_l, v.status AS vessel_status, v.premises_id,
       o.occupant_kind, o.occupant_id, o.volume_l, o.from_at AS occupied_since,
       CASE WHEN o.occupant_kind = 'batch' THEN b.number WHEN o.occupant_kind = 'lot' THEN l.lot_number END AS occupant_label,
       b.current_stage_code, b.product_id, p.name AS product_name,
       round(100 * o.volume_l / v.capacity_l, 1) AS fill_pct,
       v.board_x, v.board_y,
       li.name AS lot_item_name,
       v.location_id
  FROM app.vessels v
  LEFT JOIN app.vessel_occupancies o ON o.vessel_id = v.id AND o.to_at IS NULL
  LEFT JOIN app.batches b ON o.occupant_kind = 'batch' AND b.id = o.occupant_id
  LEFT JOIN app.lots l ON o.occupant_kind = 'lot' AND l.id = o.occupant_id
  LEFT JOIN app.items li ON li.id = l.item_id
  LEFT JOIN app.products p ON p.id = b.product_id
 WHERE v.active;
