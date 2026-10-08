-- 012_views.sql — derived views for stock, yield, cost, valuation, status, and the trace functions over lot lineage.
-- Views are the contract for the report screens and for the records MCP server.
SET search_path = app, public;

-- Lot balances with item, location, area and rack, the on-hand/available answer, in quantity and weight.
CREATE OR REPLACE VIEW app.v_lot_balances AS
SELECT b.item_id, i.code AS item_code, i.name AS item_name, i.item_class, ic.lot_noun, i.base_unit_code,
       b.lot_id, l.lot_number, l.quality_status, l.expires_on, l.received_on, l.produced_on, l.unit_cost_base, l.unit_weight_kg,
       l.supplier_lot_number,
       b.location_id, loc.name AS location_name, loc.kind AS location_kind, loc.site_id,
       COALESCE(loc.parent_location_id, loc.id) AS area_location_id,
       COALESCE(area.name, loc.name) AS area_name,
       loc.rack_number,
       b.qty_on_hand, b.qty_allocated, (b.qty_on_hand - b.qty_allocated) AS qty_available,
       b.weight_on_hand_kg,
       (b.qty_on_hand * l.unit_cost_base) AS value_at_lot_cost
  FROM app.inventory_balances b
  JOIN app.items i ON i.id = b.item_id
  JOIN app.item_classes ic ON ic.code = i.item_class
  JOIN app.lots l ON l.id = b.lot_id
  JOIN app.locations loc ON loc.id = b.location_id
  LEFT JOIN app.locations area ON area.id = loc.parent_location_id
 WHERE b.qty_on_hand <> 0 OR b.qty_allocated <> 0;

-- Item totals across lots and locations, with reorder status.
CREATE OR REPLACE VIEW app.v_item_stock AS
SELECT i.id AS item_id, i.code, i.name, i.item_class, i.base_unit_code,
       COALESCE(sum(b.qty_on_hand), 0) AS qty_on_hand,
       COALESCE(sum(b.weight_on_hand_kg), 0) AS weight_on_hand_kg,
       COALESCE(sum(b.qty_allocated), 0) AS qty_allocated,
       COALESCE(sum(b.qty_on_hand - b.qty_allocated), 0) AS qty_available,
       COALESCE((SELECT sum(pl.qty_ordered_base - pl.qty_received_base) FROM app.purchase_order_lines pl
                  JOIN app.purchase_orders po ON po.id = pl.purchase_order_id
                 WHERE pl.item_id = i.id AND pl.status IN ('open','partial') AND po.status IN ('open','partial')), 0) AS qty_on_order,
       i.reorder_point_base, i.min_qty_base, i.max_qty_base,
       (i.reorder_point_base IS NOT NULL AND COALESCE(sum(b.qty_on_hand - b.qty_allocated), 0) < i.reorder_point_base) AS below_reorder_point
  FROM app.items i
  LEFT JOIN app.inventory_balances b ON b.item_id = i.id
 WHERE i.active
 GROUP BY i.id;

-- Inventory valuation by class and site (lot cost for actual-lot items, standard otherwise).
CREATE OR REPLACE VIEW app.v_inventory_valuation AS
SELECT i.item_class, loc.site_id, i.base_unit_code,
       sum(b.qty_on_hand) AS qty_on_hand,
       sum(b.weight_on_hand_kg) AS weight_on_hand_kg,
       sum(b.qty_on_hand * CASE WHEN i.costing_method = 'standard'
                                THEN COALESCE(i.standard_cost_per_base, 0) ELSE l.unit_cost_base END) AS value
  FROM app.inventory_balances b
  JOIN app.items i ON i.id = b.item_id
  JOIN app.lots l ON l.id = b.lot_id
  JOIN app.locations loc ON loc.id = b.location_id
 WHERE b.qty_on_hand <> 0
 GROUP BY 1,2,3;

-- Every positive balance with its area, rack and age, for the rack board and FIFO picking. fifo_rank orders the
-- released stock of one item across the racks and areas of a site, oldest first. Unreleased lots have no rank.
CREATE OR REPLACE VIEW app.v_fifo_stock AS
SELECT vb.site_id, vb.area_location_id, vb.area_name, vb.location_id, vb.location_name, vb.rack_number,
       app.rack_sort_key(vb.rack_number) AS rack_sort,
       vb.item_id, vb.item_code, vb.item_name, vb.item_class, vb.lot_noun, vb.base_unit_code,
       vb.lot_id, vb.lot_number, vb.quality_status, vb.supplier_lot_number,
       fl.product_id, p.name AS product_name, pc.name AS package_name, pc.package_kind,
       COALESCE(fl.packaged_on, vb.produced_on, vb.received_on) AS stock_date,
       COALESCE(fl.best_before_on, vb.expires_on) AS use_by,
       vb.qty_on_hand, vb.qty_allocated, vb.qty_available, vb.weight_on_hand_kg,
       CASE WHEN vb.quality_status = 'released' THEN
           dense_rank() OVER (PARTITION BY vb.site_id, vb.item_id, (vb.quality_status = 'released')
                              ORDER BY COALESCE(fl.packaged_on, vb.produced_on, vb.received_on) NULLS LAST, vb.lot_number)
       END AS fifo_rank
  FROM app.v_lot_balances vb
  LEFT JOIN app.finished_lots fl ON fl.lot_id = vb.lot_id
  LEFT JOIN app.products p ON p.id = fl.product_id
  LEFT JOIN app.packaging_configurations pc ON pc.id = fl.packaging_configuration_id
 WHERE vb.qty_on_hand > 0;

-- Finished goods ready to ship, by product and package.
CREATE OR REPLACE VIEW app.v_finished_stock AS
SELECT fl.lot_id, l.lot_number, fl.product_id, p.name AS product_name, pc.id AS packaging_configuration_id,
       pc.name AS package_name, pc.package_kind, fl.packaged_on, fl.packages, fl.qty_per_package_base, fl.package_weight_kg,
       fl.heat_numbers, fl.best_before_on, fl.production_order_id,
       vb.location_id, vb.location_name, vb.area_location_id, vb.area_name, vb.rack_number, vb.site_id,
       vb.qty_on_hand AS units_on_hand, vb.qty_available AS units_available, vb.weight_on_hand_kg, fl.unit_cost
  FROM app.finished_lots fl
  JOIN app.lots l ON l.id = fl.lot_id
  JOIN app.products p ON p.id = fl.product_id
  JOIN app.packaging_configurations pc ON pc.id = fl.packaging_configuration_id
  JOIN app.v_lot_balances vb ON vb.lot_id = fl.lot_id;

-- Run yields: what went in, what came out, by weight, against the step's expected loss.
CREATE OR REPLACE VIEW app.v_run_yields AS
SELECT r.id AS run_id, r.number, r.site_id, r.run_on, r.status, r.operation_code, o.name AS operation_name,
       r.equipment_id, e.name AS equipment_name, r.production_order_id, po.number AS order_number, po.product_id, p.name AS product_name,
       r.input_qty_base, r.input_weight_kg, r.output_qty_base, r.output_weight_kg, r.co_product_weight_kg, r.scrap_weight_kg, r.loss_weight_kg,
       r.yield_pct,
       CASE WHEN r.input_weight_kg > 0 THEN round(100 * (r.input_weight_kg - COALESCE(r.output_weight_kg, 0)) / r.input_weight_kg, 2) END AS actual_loss_pct,
       st.expected_loss_pct,
       r.setup_minutes, r.run_minutes
  FROM app.runs r
  JOIN app.operations o ON o.code = r.operation_code
  LEFT JOIN app.equipment e ON e.id = r.equipment_id
  LEFT JOIN app.production_orders po ON po.id = r.production_order_id
  LEFT JOIN app.products p ON p.id = po.product_id
  LEFT JOIN app.process_spec_steps st ON st.id = r.process_spec_step_id;

-- Material cost per run (inputs and consumables at lot cost).
CREATE OR REPLACE VIEW app.v_run_material_costs AS
SELECT c.run_id, c.item_id, i.name AS item_name, i.item_class, c.lot_id, l.lot_number, c.purpose,
       c.qty_base, c.weight_kg, i.base_unit_code, l.unit_cost_base,
       (c.qty_base * CASE WHEN i.costing_method = 'standard' THEN COALESCE(i.standard_cost_per_base, l.unit_cost_base) ELSE l.unit_cost_base END) AS cost
  FROM app.consumptions c
  JOIN app.items i ON i.id = c.item_id
  JOIN app.lots l ON l.id = c.lot_id;

-- Run cost roll-up (D11): material at lot cost, consumables at standard, overhead per kg of input, less the scrap
-- credit at the scrap item's standard cost; the output's cost per base unit and per kg.
CREATE OR REPLACE VIEW app.v_run_costs AS
WITH mat AS (
    SELECT run_id,
           sum(cost) FILTER (WHERE purpose IN ('primary_material','material')) AS material_cost,
           sum(cost) FILTER (WHERE purpose NOT IN ('primary_material','material')) AS consumable_cost
      FROM app.v_run_material_costs GROUP BY run_id
), scrap AS (
    SELECT ro.run_id, sum(COALESCE(ro.weight_kg, 0) * COALESCE(i.standard_cost_per_base, 0)) AS scrap_credit
      FROM app.run_outputs ro JOIN app.items i ON i.id = ro.item_id
     WHERE ro.kind = 'scrap' GROUP BY ro.run_id
), oh AS (
    SELECT r.id AS run_id,
           (SELECT rate_per_kg FROM app.overhead_rates o WHERE o.site_id = r.site_id AND o.effective_from <= r.run_on
             ORDER BY o.effective_from DESC LIMIT 1) AS rate_per_kg
      FROM app.runs r
)
SELECT r.id AS run_id, r.number, r.status, r.production_order_id, r.operation_code,
       COALESCE(mat.material_cost, 0) AS material_cost,
       COALESCE(mat.consumable_cost, 0) AS consumable_cost,
       COALESCE(r.input_weight_kg, 0) * COALESCE(oh.rate_per_kg, 0) AS overhead_cost,
       COALESCE(scrap.scrap_credit, 0) AS scrap_credit,
       COALESCE(mat.material_cost, 0) + COALESCE(mat.consumable_cost, 0)
         + COALESCE(r.input_weight_kg, 0) * COALESCE(oh.rate_per_kg, 0) - COALESCE(scrap.scrap_credit, 0) AS total_cost,
       r.output_qty_base, r.output_weight_kg,
       CASE WHEN COALESCE(r.output_qty_base, 0) > 0
            THEN (COALESCE(mat.material_cost, 0) + COALESCE(mat.consumable_cost, 0)
                  + COALESCE(r.input_weight_kg, 0) * COALESCE(oh.rate_per_kg, 0) - COALESCE(scrap.scrap_credit, 0)) / r.output_qty_base END AS cost_per_base_unit,
       CASE WHEN COALESCE(r.output_weight_kg, 0) > 0
            THEN (COALESCE(mat.material_cost, 0) + COALESCE(mat.consumable_cost, 0)
                  + COALESCE(r.input_weight_kg, 0) * COALESCE(oh.rate_per_kg, 0) - COALESCE(scrap.scrap_credit, 0)) / r.output_weight_kg END AS cost_per_kg
  FROM app.runs r
  LEFT JOIN mat ON mat.run_id = r.id
  LEFT JOIN scrap ON scrap.run_id = r.id
  LEFT JOIN oh ON oh.run_id = r.id;

-- Product costs from posted runs of production orders: the average and the variance to the spec's standard.
CREATE OR REPLACE VIEW app.v_product_costs AS
SELECT po.product_id, p.name AS product_name, po.id AS production_order_id, po.number AS order_number, po.process_spec_id,
       sum(rc.total_cost) AS total_cost,
       sum(rc.output_qty_base) FILTER (WHERE r.process_spec_step_id IS NULL OR r.process_spec_step_id = (
           SELECT id FROM app.process_spec_steps s WHERE s.process_spec_id = po.process_spec_id ORDER BY seq DESC LIMIT 1)) AS output_qty_base,
       ps.standard_cost_per_base,
       CASE WHEN sum(rc.output_qty_base) > 0 THEN sum(rc.total_cost) / sum(rc.output_qty_base) END AS cost_per_base_unit
  FROM app.production_orders po
  JOIN app.products p ON p.id = po.product_id
  JOIN app.process_specs ps ON ps.id = po.process_spec_id
  JOIN app.runs r ON r.production_order_id = po.id AND r.status = 'posted'
  JOIN app.v_run_costs rc ON rc.run_id = r.id
 GROUP BY po.product_id, p.name, po.id, po.number, po.process_spec_id, ps.standard_cost_per_base;

-- Purchase order lines still open, for "what is arriving" and "what is overdue".
CREATE OR REPLACE VIEW app.v_open_po_lines AS
SELECT po.id AS purchase_order_id, po.number, po.supplier_id, s.name AS supplier_name, po.status AS po_status, po.site_id,
       pl.id AS line_id, pl.line_no, pl.item_id, i.name AS item_name, i.base_unit_code,
       pl.qty_ordered, pl.purchase_unit_code, pl.qty_ordered_base, pl.qty_received_base, pl.weight_kg_ordered, pl.weight_kg_received,
       (pl.qty_ordered_base - pl.qty_received_base) AS qty_outstanding_base,
       COALESCE(pl.expected_on, po.expected_on) AS expected_on,
       (COALESCE(pl.expected_on, po.expected_on) < current_date) AS overdue
  FROM app.purchase_order_lines pl
  JOIN app.purchase_orders po ON po.id = pl.purchase_order_id
  JOIN app.suppliers s ON s.id = po.supplier_id
  JOIN app.items i ON i.id = pl.item_id
 WHERE pl.status IN ('open','partial') AND po.status IN ('open','partial');

-- Supplier performance: late and short deliveries.
CREATE OR REPLACE VIEW app.v_supplier_performance AS
SELECT s.id AS supplier_id, s.name,
       count(DISTINCT gr.id) AS receipts,
       count(DISTINCT gr.id) FILTER (WHERE gr.received_at::date > COALESCE(pl.expected_on, po.expected_on)) AS late_receipts,
       count(DISTINCT grl.id) FILTER (WHERE grl.discrepancy_kind = 'short') AS short_lines,
       count(DISTINCT grl.id) FILTER (WHERE grl.discrepancy_kind = 'damaged') AS damaged_lines
  FROM app.suppliers s
  LEFT JOIN app.goods_receipts gr ON gr.supplier_id = s.id AND gr.status = 'posted'
  LEFT JOIN app.goods_receipt_lines grl ON grl.goods_receipt_id = gr.id
  LEFT JOIN app.purchase_order_lines pl ON pl.id = grl.purchase_order_line_id
  LEFT JOIN app.purchase_orders po ON po.id = pl.purchase_order_id
 GROUP BY s.id;

-- Forward trace: everything downstream of a lot — its children through lineage, then the shipments they left on.
CREATE OR REPLACE FUNCTION app.trace_forward(p_lot_id bigint)
RETURNS TABLE (level int, kind text, id bigint, label text, detail jsonb)
LANGUAGE sql STABLE AS $$
WITH RECURSIVE down AS (
    SELECT p_lot_id AS lot_id, 0 AS lvl, NULL::text AS event_kind, NULL::bigint AS event_id, NULL::numeric AS fraction
    UNION
    SELECT ll.child_lot_id, d.lvl + 1, ll.event_kind, ll.event_id, ll.fraction
      FROM app.lot_lineage ll JOIN down d ON ll.parent_lot_id = d.lot_id
)
SELECT d.lvl, CASE WHEN fl.lot_id IS NOT NULL THEN 'finished_lot' ELSE 'lot' END, l.id, l.lot_number,
       jsonb_build_object('item', i.name, 'item_class', i.item_class, 'status', l.quality_status, 'weight_kg', l.weight_kg,
                          'event_kind', d.event_kind, 'event_id', d.event_id, 'fraction', d.fraction,
                          'heat', app.lot_attribute_text(l.id, 'heat'))
  FROM down d JOIN app.lots l ON l.id = d.lot_id JOIN app.items i ON i.id = l.item_id LEFT JOIN app.finished_lots fl ON fl.lot_id = l.id
 WHERE d.lvl > 0
UNION ALL
SELECT d.lvl + 1, 'shipment', s.id, s.number,
       jsonb_build_object('customer_id', s.customer_id, 'direction', s.direction, 'shipped_at', s.shipped_at, 'qty', sl.qty_base, 'weight_kg', sl.weight_kg, 'lot', l.lot_number)
  FROM down d JOIN app.lots l ON l.id = d.lot_id
  JOIN app.shipment_lines sl ON sl.lot_id = d.lot_id JOIN app.shipments s ON s.id = sl.shipment_id AND s.status IN ('posted','reversed');
$$;

-- Backward trace: everything upstream of a lot — its parents through lineage, each with its supplier, receipt and
-- certificate when it was received.
CREATE OR REPLACE FUNCTION app.trace_backward(p_lot_id bigint)
RETURNS TABLE (level int, kind text, id bigint, label text, detail jsonb)
LANGUAGE sql STABLE AS $$
WITH RECURSIVE up AS (
    SELECT p_lot_id AS lot_id, 0 AS lvl, NULL::text AS event_kind, NULL::bigint AS event_id, NULL::numeric AS fraction
    UNION
    SELECT ll.parent_lot_id, u.lvl + 1, ll.event_kind, ll.event_id, ll.fraction
      FROM app.lot_lineage ll JOIN up u ON ll.child_lot_id = u.lot_id
)
SELECT u.lvl, 'lot', l.id, l.lot_number,
       jsonb_build_object('item', i.name, 'item_class', i.item_class, 'status', l.quality_status, 'weight_kg', l.weight_kg,
                          'supplier_lot', l.supplier_lot_number, 'supplier', s.name, 'source_kind', l.source_kind,
                          'event_kind', u.event_kind, 'event_id', u.event_id, 'fraction', u.fraction,
                          'heat', app.lot_attribute_text(l.id, 'heat'),
                          'certificates', (SELECT jsonb_agg(jsonb_build_object('id', c.id, 'kind', c.kind, 'number', c.number, 'heat', c.heat_number))
                                             FROM app.certificates c WHERE c.lot_id = l.id))
  FROM up u JOIN app.lots l ON l.id = u.lot_id JOIN app.items i ON i.id = l.item_id LEFT JOIN app.suppliers s ON s.id = l.supplier_id
 WHERE u.lvl > 0;
$$;

-- Every lot that carries a heat, and the shipments it left on: the recall question.
CREATE OR REPLACE FUNCTION app.heat_where_used(p_heat text)
RETURNS TABLE (lot_id bigint, lot_number text, item_name text, item_class text, quality_status text, weight_kg numeric,
               shipment_id bigint, shipment_number text, customer_id bigint, shipped_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT l.id, l.lot_number, i.name, i.item_class, l.quality_status, l.weight_kg,
           s.id, s.number, s.customer_id, s.shipped_at
      FROM app.lot_attributes a
      JOIN app.lots l ON l.id = a.lot_id
      JOIN app.items i ON i.id = l.item_id
      LEFT JOIN app.shipment_lines sl ON sl.lot_id = l.id
      LEFT JOIN app.shipments s ON s.id = sl.shipment_id AND s.status IN ('posted','reversed')
     WHERE a.key = 'heat' AND upper(COALESCE(a.value_text, a.value_num::text)) = upper(p_heat)
     ORDER BY l.id, s.shipped_at
$$;
