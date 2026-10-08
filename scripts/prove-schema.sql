-- scripts/prove-schema.sql — the step 2 checks, run by scripts/prove-schema.sh as processcore_app on a freshly
-- provisioned scratch database with the steel profile. Prints one "ok <check>" or "FAIL <check>" line per check and
-- works the plan's §5 example through every table. :keep = 1 leaves the rows in place.
SET search_path = app, public;
SET client_min_messages = warning;

CREATE TEMP TABLE results (n serial, name text, ok boolean);
CREATE FUNCTION pg_temp.chk(p_name text, p_ok boolean) RETURNS void LANGUAGE sql AS
$$ INSERT INTO results (name, ok) VALUES (p_name, COALESCE(p_ok, false)) $$;

-- 1. Structure --------------------------------------------------------------------------------------------------------
SELECT pg_temp.chk('at least 90 tables in app', (SELECT count(*) >= 90 FROM information_schema.tables WHERE table_schema = 'app' AND table_type = 'BASE TABLE'));
SELECT pg_temp.chk('at least 15 views in app',  (SELECT count(*) >= 15 FROM information_schema.views  WHERE table_schema = 'app'));
SELECT pg_temp.chk('table ' || t, to_regclass('app.' || t) IS NOT NULL) FROM unnest(ARRAY[
    'client_settings','sites','units','item_classes','attribute_definitions','item_class_attributes','items','item_attribute_values','item_units',
    'suppliers','supplier_items','locations','reason_codes','equipment_kinds','equipment','attachments','number_sequences','reference_values',
    'purchase_orders','purchase_order_lines','goods_receipts','goods_receipt_lines','lots','lot_attributes','weigh_tickets','certificates','release_decisions',
    'inventory_transactions','inventory_balances','inventory_transfers','inventory_transfer_lines','inventory_adjustments','inventory_adjustment_lines',
    'inventory_counts','inventory_count_lines','operations','measurement_types','products','product_attribute_values','process_specs','process_spec_steps',
    'process_spec_inputs','specs','packaging_configurations','packaging_bom_lines','standard_costs','overhead_rates','production_orders','allocations',
    'runs','run_inputs','run_outputs','run_consumables','consumptions','lot_lineage','loss_events','readings','co_product_dispositions',
    'packaging_runs','packaging_run_inputs','packaging_run_materials','finished_lots','inspections','customers','shipments','shipment_lines',
    'report_line_map','period_reports','period_report_lines','activity_log','order_imports','standing_orders','standing_order_lines','sales_orders',
    'sales_order_lines','packaging_run_order_lines','production_order_packages','demand_forecasts','equipment_reservations',
    'users','auth_identities','mcp_access_tokens','sso_nonces','member_sessions','directory_sync_state','activity_ingest_state','app_rights','app_roles','app_role_rights']) AS t;
SELECT pg_temp.chk('view ' || v, to_regclass('app.' || v) IS NOT NULL) FROM unnest(ARRAY[
    'v_lot_balances','v_item_stock','v_inventory_valuation','v_fifo_stock','v_finished_stock','v_run_yields','v_run_material_costs','v_run_costs',
    'v_product_costs','v_open_po_lines','v_supplier_performance','v_sales_order_lines','v_demand','v_equipment_resources','v_equipment_schedule','mcp_app_roles']) AS v;
SELECT pg_temp.chk('function ' || f, to_regprocedure('app.' || f) IS NOT NULL) FROM unnest(ARRAY[
    'next_number(text)','theoretical_weight_kg(numeric,numeric,numeric,numeric)','rack_sort_key(text)','item_attribute_num(bigint,text)',
    'lot_attributes_fill(bigint,bigint,jsonb,text,bigint)','trace_forward(bigint)','trace_backward(bigint)','heat_where_used(text)',
    'standing_order_occurrences(date,date)','equipment_clashes(bigint,timestamptz,timestamptz,bigint)','equipment_fits(bigint,bigint,bigint)',
    'client_timezone()','log_activity(bigint,text,text,text,text,text,text,text,bigint,text,jsonb,jsonb,jsonb,inet)','activity_ingest_pending(integer)','rebuild_inventory_balances()']) AS f;
SELECT pg_temp.chk('no cider table survives', to_regclass('app.vessels') IS NULL AND to_regclass('app.batches') IS NULL AND to_regclass('app.kegs') IS NULL
                                               AND to_regclass('app.press_runs') IS NULL AND to_regclass('app.ttb_line_map') IS NULL AND to_regclass('app.premises') IS NULL);

-- 2. Seeds: the core's and the steel profile's ----------------------------------------------------------------------------
SELECT pg_temp.chk('19 units, one base per dimension', (SELECT count(*) = 19 FROM app.units) AND (SELECT count(*) = 5 FROM app.units WHERE is_base));
SELECT pg_temp.chk('cwt is 45.359237 kg', (SELECT to_base_factor = 45.359237 FROM app.units WHERE code = 'cwt'));
SELECT pg_temp.chk('7 built-in item classes', (SELECT count(*) = 7 FROM app.item_classes WHERE is_builtin));
SELECT pg_temp.chk('steel classes coil, slit_coil, sheet, blank, scrap', (SELECT count(*) = 5 FROM app.item_classes WHERE code IN ('coil','slit_coil','sheet','blank','scrap')));
SELECT pg_temp.chk('a coil is serialized, catch weight, noun Coil, numbered C-', (SELECT serialized AND catch_weight AND lot_noun = 'Coil' AND lot_number_key = 'coil' FROM app.item_classes WHERE code = 'coil'));
SELECT pg_temp.chk('finished goods are Skids', (SELECT lot_noun = 'Skid' FROM app.item_classes WHERE code = 'finished_good'));
SELECT pg_temp.chk('steel density on the classes', (SELECT density_kg_m3 = 7850 FROM app.item_classes WHERE code = 'sheet'));
SELECT pg_temp.chk('24 attribute definitions', (SELECT count(*) = 24 FROM app.attribute_definitions));
SELECT pg_temp.chk('heat and grade inherit, length and width do not', (SELECT bool_and(inherit) FROM app.attribute_definitions WHERE key IN ('heat','grade','coating'))
                                                                 AND NOT (SELECT bool_or(inherit) FROM app.attribute_definitions WHERE key IN ('length_in','width_in')));
SELECT pg_temp.chk('coating is a choice with G90', (SELECT kind = 'choice' AND 'G90' = ANY(choices) FROM app.attribute_definitions WHERE key = 'coating'));
SELECT pg_temp.chk('the sheet class requires grade, thickness, width, length', (SELECT count(*) = 4 FROM app.item_class_attributes WHERE item_class = 'sheet' AND required));
SELECT pg_temp.chk('7 operations, pack terminal', (SELECT count(*) = 7 FROM app.operations) AND (SELECT is_terminal FROM app.operations WHERE code = 'pack'));
SELECT pg_temp.chk('14 measurement types', (SELECT count(*) = 14 FROM app.measurement_types));
SELECT pg_temp.chk('13 equipment kinds (5 built in + 8 steel)', (SELECT count(*) = 13 FROM app.equipment_kinds));
SELECT pg_temp.chk('16 reason codes (9 built in + 7 steel)', (SELECT count(*) = 16 FROM app.reason_codes));
SELECT pg_temp.chk('TRIM is expected scrap', (SELECT applies_to = 'scrap' AND report_category = 'scrap' AND classification = 'expected' FROM app.reason_codes WHERE code = 'TRIM'));
SELECT pg_temp.chk('gauge table: 16 ga sheet steel = 0.0598 in', (SELECT value_num = 0.0598 FROM app.reference_values WHERE table_name = 'gauge_sheet_steel' AND key = '16'));
SELECT pg_temp.chk('gauge table: 10 ga sheet steel = 0.1345 in', (SELECT value_num = 0.1345 FROM app.reference_values WHERE table_name = 'gauge_sheet_steel' AND key = '10'));
SELECT pg_temp.chk('gauge table: 16 ga galvanized = 0.0635 in', (SELECT value_num = 0.0635 FROM app.reference_values WHERE table_name = 'gauge_galvanized' AND key = '16'));
SELECT pg_temp.chk('density table has carbon steel 7850', (SELECT value_num = 7850 FROM app.reference_values WHERE table_name = 'density_kg_m3' AND key = 'carbon_steel'));
SELECT pg_temp.chk('18 number sequences incl. coil, sheet, skid, scrap', (SELECT count(*) = 18 FROM app.number_sequences));
SELECT pg_temp.chk('21 report lines in three reports', (SELECT count(*) = 21 FROM app.report_line_map) AND (SELECT count(DISTINCT report_code) = 3 FROM app.report_line_map));
SELECT pg_temp.chk('the business row: steel, lb, in', (SELECT profile = 'steel' AND mass_display_unit = 'lb' AND length_display_unit = 'in' FROM app.client_settings WHERE id = 1));
SELECT pg_temp.chk('double booking refused by default', (SELECT settings #>> '{equipment,double_booking}' = 'refuse' FROM app.client_settings WHERE id = 1));
SELECT pg_temp.chk('six dashboard tiles from the profile', (SELECT jsonb_array_length(settings #> '{dashboard,tiles}') = 6 FROM app.client_settings WHERE id = 1));
SELECT pg_temp.chk('the profile is recorded', (SELECT count(*) = 1 FROM app.schema_migrations WHERE file = 'profile:steel'));
SELECT pg_temp.chk('seven OS roles, owner the admin', (SELECT count(*) = 7 FROM app.app_roles) AND (SELECT is_admin FROM app.app_roles WHERE role_key = 'owner'));
SELECT pg_temp.chk('shipping replaced compliance', (SELECT count(*) = 1 FROM app.app_roles WHERE role_key = 'shipping') AND (SELECT count(*) = 0 FROM app.app_roles WHERE role_key = 'compliance'));
SELECT pg_temp.chk('mcp_app_roles gives the owner processcore.admin', (SELECT 'processcore.admin' = ANY(rights) FROM app.mcp_app_roles WHERE role_key = 'owner'));
SELECT pg_temp.chk('mcp_app_roles gives shipping two rights', (SELECT array_length(rights, 1) = 2 FROM app.mcp_app_roles WHERE role_key = 'shipping'));

-- 3. Helpers -----------------------------------------------------------------------------------------------------------------
SELECT pg_temp.chk('next_number(coil) = C-YY-00001', app.next_number('coil') = 'C-' || to_char(now(), 'YY') || '-00001');
SELECT pg_temp.chk('next_number(run) = RUN-00001', app.next_number('run') = 'RUN-00001');
SELECT pg_temp.chk('next_number(shipment) = BOL-00001', app.next_number('shipment') = 'BOL-00001');
UPDATE app.number_sequences SET next_value = 1, period_value = NULL WHERE key IN ('coil','run','shipment');   -- read once above; start the example at 00001
SELECT pg_temp.chk('theoretical weight of a 16 ga 48 x 120 sheet is 44.3 kg (97.7 lb)',
    app.theoretical_weight_kg(7850, 0.0598 * 0.0254, 48 * 0.0254, 120 * 0.0254) BETWEEN 44.2 AND 44.4);
SELECT pg_temp.chk('theoretical weight is NULL when a dimension is missing', app.theoretical_weight_kg(7850, NULL, 1, 1) IS NULL);
SELECT pg_temp.chk('rack_sort_key puts A2 before A10', app.rack_sort_key('A2') < app.rack_sort_key('A10'));
SELECT pg_temp.chk('client_timezone is the business''s', app.client_timezone() = (SELECT timezone FROM app.client_settings WHERE id = 1));

-- 4. The example: people, site, locations, racks ------------------------------------------------------------------------------
INSERT INTO app.users (email, display_name, role, status) VALUES ('prove@processcore.test', 'Prove', 'owner', 'active');
DO $$ BEGIN
    INSERT INTO app.users (email, display_name, role, status) VALUES ('ship@processcore.test', 'Ship', 'shipping', 'active');
    PERFORM pg_temp.chk('a user may hold the shipping role', true);
    BEGIN
        INSERT INTO app.users (email, display_name, role, status) VALUES ('comp@processcore.test', 'Comp', 'compliance', 'active');
        PERFORM pg_temp.chk('the compliance role is gone', false);
    EXCEPTION WHEN check_violation THEN PERFORM pg_temp.chk('the compliance role is gone', true); END;
END $$;
INSERT INTO app.sites (code, name) VALUES ('MAIN', 'Main plant');
INSERT INTO app.locations (site_id, name, kind) SELECT id, 'Receiving dock', 'receiving' FROM app.sites WHERE code = 'MAIN';
INSERT INTO app.locations (site_id, name, kind) SELECT id, 'Coil yard', 'yard' FROM app.sites WHERE code = 'MAIN';
INSERT INTO app.locations (site_id, name, kind) SELECT id, 'Bay B', 'storage' FROM app.sites WHERE code = 'MAIN';
INSERT INTO app.locations (site_id, name, kind) SELECT id, 'Finished goods', 'finished_goods' FROM app.sites WHERE code = 'MAIN';
INSERT INTO app.locations (site_id, name, kind) SELECT id, 'Scrap bin', 'scrap' FROM app.sites WHERE code = 'MAIN';
INSERT INTO app.locations (site_id, name, kind, allow_negative) SELECT id, 'Line side', 'line_side', true FROM app.sites WHERE code = 'MAIN';
INSERT INTO app.locations (site_id, name, kind, parent_location_id, rack_number)
    SELECT s.id, 'x', 'storage', l.id, 'a1' FROM app.sites s JOIN app.locations l ON l.site_id = s.id AND l.name = 'Bay B' WHERE s.code = 'MAIN';
SELECT pg_temp.chk('a rack is named Rack A1 and takes its area''s kind', (SELECT name = 'Rack A1' AND kind = 'storage' FROM app.locations WHERE rack_number = 'A1'));
DO $$ DECLARE v_rack bigint; v_site bigint; BEGIN
    SELECT id INTO v_rack FROM app.locations WHERE rack_number = 'A1'; SELECT site_id INTO v_site FROM app.locations WHERE id = v_rack;
    BEGIN
        INSERT INTO app.locations (site_id, name, kind, parent_location_id, rack_number) VALUES (v_site, 'y', 'storage', v_rack, 'A2');
        PERFORM pg_temp.chk('a rack cannot sit in a rack', false);
    EXCEPTION WHEN check_violation THEN PERFORM pg_temp.chk('a rack cannot sit in a rack', true); END;
END $$;
UPDATE app.locations SET kind = 'yard' WHERE name = 'Bay B';
SELECT pg_temp.chk('an area''s kind change cascades to its racks', (SELECT kind = 'yard' FROM app.locations WHERE rack_number = 'A1'));
UPDATE app.locations SET kind = 'storage' WHERE name = 'Bay B';

-- 5. Items with attributes ----------------------------------------------------------------------------------------------------
INSERT INTO app.items (code, name, item_class, base_unit_code, catch_weight, serialized, costing_method)
    VALUES ('HR-16-48', 'HR coil 16 ga x 48 A1011 CS-B', 'coil', 'kg', true, true, 'actual_lot');
INSERT INTO app.item_attribute_values (item_id, attribute_key, value_num, value_text)
    SELECT id, k, n, t FROM app.items, (VALUES ('grade', NULL::numeric, 'A1011 CS-B'), ('thickness_in', 0.0598, NULL), ('width_in', 48, NULL), ('gauge', NULL, '16'), ('finish', NULL, 'hot_rolled')) v(k, n, t)
     WHERE code = 'HR-16-48';
INSERT INTO app.items (code, name, item_class, base_unit_code, unit_weight_kg)
    VALUES ('SHT-16-48-120', 'Sheet 16 ga x 48 x 120 A1011 CS-B', 'sheet', 'ea', app.theoretical_weight_kg(7850, 0.0598 * 0.0254, 48 * 0.0254, 120 * 0.0254));
INSERT INTO app.item_attribute_values (item_id, attribute_key, value_num, value_text)
    SELECT id, k, n, t FROM app.items, (VALUES ('grade', NULL::numeric, 'A1011 CS-B'), ('thickness_in', 0.0598, NULL), ('width_in', 48, NULL), ('length_in', 120, NULL)) v(k, n, t)
     WHERE code = 'SHT-16-48-120';
INSERT INTO app.items (code, name, item_class, base_unit_code, catch_weight, serialized) VALUES ('HR-16-48-REM', 'HR coil 16 ga x 48 remnant', 'slit_coil', 'kg', true, true);
INSERT INTO app.items (code, name, item_class, base_unit_code, catch_weight, costing_method, standard_cost_per_base) VALUES ('SCRAP-HR', 'Scrap, hot rolled', 'scrap', 'kg', true, 'standard', 0.22);
INSERT INTO app.items (code, name, item_class, base_unit_code, costing_method, standard_cost_per_base, consumption_mode) VALUES ('BAND-34', 'Steel banding 3/4 in', 'consumable', 'm', 'standard', 0.08, 'backflush');
INSERT INTO app.items (code, name, item_class, base_unit_code, costing_method, standard_cost_per_base) VALUES ('SKID-48', 'Skid 48 x 120', 'packaging', 'ea', 'standard', 18.00);
INSERT INTO app.items (code, name, item_class, base_unit_code, units_per_package) VALUES ('FG-SHT-16-48-120', 'Skid of 50 sheets 16 ga x 48 x 120', 'finished_good', 'ea', 50);
SELECT pg_temp.chk('seven items', (SELECT count(*) = 7 FROM app.items));
SELECT pg_temp.chk('item_attribute_num reads the coil''s width 48', app.item_attribute_num((SELECT id FROM app.items WHERE code = 'HR-16-48'), 'width_in') = 48);
SELECT pg_temp.chk('item_attribute_text reads the grade', app.item_attribute_text((SELECT id FROM app.items WHERE code = 'HR-16-48'), 'grade') = 'A1011 CS-B');
SELECT pg_temp.chk('the sheet item weighs 44.3 kg each', (SELECT unit_weight_kg BETWEEN 44.2 AND 44.4 FROM app.items WHERE code = 'SHT-16-48-120'));

-- 6. Supplier, PO, receipt, the coil lot with ticket and MTR --------------------------------------------------------------------
INSERT INTO app.suppliers (name, kind) VALUES ('Lakeside Steel Mill', 'mill');
INSERT INTO app.purchase_orders (number, supplier_id, site_id, status, ordered_on, expected_on)
    SELECT app.next_number('po'), s.id, st.id, 'open', current_date - 14, current_date - 1 FROM app.suppliers s, app.sites st WHERE st.code = 'MAIN';
INSERT INTO app.purchase_order_lines (purchase_order_id, line_no, item_id, qty_ordered, purchase_unit_code, to_base_factor, unit_price, weight_kg_ordered)
    SELECT po.id, 1, i.id, 400, 'cwt', 45.359237, 48.50, 400 * 45.359237 FROM app.purchase_orders po, app.items i WHERE i.code = 'HR-16-48';
SELECT pg_temp.chk('PO line: 400 cwt = 18,143.7 kg base (generated)', (SELECT round(qty_ordered_base, 1) = 18143.7 FROM app.purchase_order_lines LIMIT 1));
SELECT pg_temp.chk('v_open_po_lines shows the line overdue', (SELECT overdue FROM app.v_open_po_lines LIMIT 1));
INSERT INTO app.goods_receipts (number, site_id, supplier_id, purchase_order_id, receiving_location_id, status)
    SELECT app.next_number('receipt'), st.id, s.id, po.id, l.id, 'draft' FROM app.sites st, app.suppliers s, app.purchase_orders po, app.locations l WHERE st.code = 'MAIN' AND l.name = 'Receiving dock';
INSERT INTO app.goods_receipt_lines (goods_receipt_id, line_no, purchase_order_line_id, item_id, qty_received, purchase_unit_code, to_base_factor, qty_base, weight_kg, unit_cost_base, supplier_lot_number, attributes, putaway_location_id)
    SELECT gr.id, 1, pl.id, i.id, 182.4, 'cwt', 45.359237, 8273, 8273, 48.50 / 45.359237, 'LS-77812', '{"heat": "7A1234", "mill": "Lakeside", "country_of_melt": "USA", "mtr_no": "MTR-55120", "coating": "none"}'::jsonb, yard.id
      FROM app.goods_receipts gr, app.purchase_order_lines pl, app.items i, app.locations yard WHERE i.code = 'HR-16-48' AND yard.name = 'Coil yard';
INSERT INTO app.weigh_tickets (goods_receipt_line_id, ticket_number, scale, gross_kg, tare_kg, pieces) SELECT id, 'T-1001', 'Yard scale', 8273 + 1860, 1860, 1 FROM app.goods_receipt_lines;
SELECT pg_temp.chk('the weigh ticket nets 8,273 kg', (SELECT net_kg = 8273 FROM app.weigh_tickets LIMIT 1));
-- "post" the receipt: the lot, its attributes, the ledger row
INSERT INTO app.lots (lot_number, item_id, site_id, supplier_lot_number, supplier_id, received_on, quality_status, unit_cost_base, qty_initial_base, weight_kg, source_kind, source_id)
    SELECT app.next_number('coil'), i.id, st.id, 'LS-77812', s.id, current_date, 'quarantine', 48.50 / 45.359237, 8273, 8273, 'receipt_line', grl.id
      FROM app.items i, app.sites st, app.suppliers s, app.goods_receipt_lines grl WHERE i.code = 'HR-16-48' AND st.code = 'MAIN';
UPDATE app.goods_receipt_lines SET lot_id = (SELECT id FROM app.lots WHERE supplier_lot_number = 'LS-77812');
SELECT pg_temp.chk('the coil lot is numbered C-YY-00001', (SELECT lot_number = 'C-' || to_char(now(), 'YY') || '-00001' FROM app.lots WHERE supplier_lot_number = 'LS-77812'));
SELECT pg_temp.chk('a kg lot''s unit weight is 1 by trigger', (SELECT unit_weight_kg = 1 FROM app.lots WHERE supplier_lot_number = 'LS-77812'));
SELECT app.lot_attributes_fill(l.id, NULL, grl.attributes, 'manual', NULL) FROM app.lots l JOIN app.goods_receipt_lines grl ON grl.lot_id = l.id;
SELECT pg_temp.chk('the coil lot carries the item''s grade, thickness, width (derived)', (SELECT count(*) = 3 FROM app.lot_attributes a JOIN app.lots l ON l.id = a.lot_id
       WHERE l.supplier_lot_number = 'LS-77812' AND a.key IN ('grade','thickness_in','width_in') AND a.source = 'derived'));
SELECT pg_temp.chk('the coil lot carries its heat 7A1234 (explicit)', app.lot_attribute_text((SELECT id FROM app.lots WHERE supplier_lot_number = 'LS-77812'), 'heat') = '7A1234');
SELECT pg_temp.chk('the coil lot''s coating is none, mill Lakeside', app.lot_attribute_text((SELECT id FROM app.lots WHERE supplier_lot_number = 'LS-77812'), 'mill') = 'Lakeside');
INSERT INTO app.certificates (lot_id, kind, number, issuer, heat_number, issued_on, values_json)
    SELECT id, 'mtr', 'MTR-55120', 'Lakeside Steel Mill', '7A1234', current_date - 20, '{"yield_ksi": 41.2, "tensile_ksi": 58.9, "elongation_pct": 31, "chem_c": 0.06, "chem_mn": 0.35}'::jsonb FROM app.lots WHERE supplier_lot_number = 'LS-77812';
SELECT app.lot_attributes_fill(c.lot_id, NULL, c.values_json, 'certificate', NULL) FROM app.certificates c;
SELECT pg_temp.chk('the MTR''s values are on the lot (yield 41.2 ksi, source certificate)', (SELECT value_num = 41.2 AND source = 'certificate' FROM app.lot_attributes WHERE key = 'yield_ksi' LIMIT 1));
INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, unit_cost_base, counterparty_kind, report_category, reference_kind, reference_id, idempotency_key, occurred_at)
    SELECT 'receipt', l.item_id, l.id, yard.id, 0, 8273, l.unit_cost_base, 'supplier', 'received', 'goods_receipt', 1, 'gr-1-line-1', now() FROM app.lots l, app.locations yard WHERE l.supplier_lot_number = 'LS-77812' AND yard.name = 'Coil yard';
SELECT pg_temp.chk('the receipt row took its site from the location', (SELECT site_id = (SELECT id FROM app.sites WHERE code = 'MAIN') FROM app.inventory_transactions WHERE idempotency_key = 'gr-1-line-1'));
SELECT pg_temp.chk('the receipt row''s weight was derived: 8,273 kg', (SELECT weight_kg = 8273 FROM app.inventory_transactions WHERE idempotency_key = 'gr-1-line-1'));
SELECT pg_temp.chk('the balance: 8,273 kg on hand in the yard', (SELECT qty_on_hand = 8273 AND weight_on_hand_kg = 8273 FROM app.inventory_balances b JOIN app.lots l ON l.id = b.lot_id WHERE l.supplier_lot_number = 'LS-77812'));
SELECT pg_temp.chk('v_lot_balances says Coil, in the yard area', (SELECT lot_noun = 'Coil' AND area_name = 'Coil yard' FROM app.v_lot_balances LIMIT 1));
UPDATE app.goods_receipts SET status = 'posted', posted_at = now();
UPDATE app.purchase_order_lines SET qty_received_base = 8273, weight_kg_received = 8273, status = 'partial';

-- 7. Interlocks ---------------------------------------------------------------------------------------------------------------
DO $$ DECLARE v_lot app.lots%ROWTYPE; v_yard bigint; v_line bigint; BEGIN
    SELECT * INTO v_lot FROM app.lots WHERE supplier_lot_number = 'LS-77812';
    SELECT id INTO v_yard FROM app.locations WHERE name = 'Coil yard'; SELECT id INTO v_line FROM app.locations WHERE name = 'Line side';
    BEGIN
        INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, reference_kind, reference_id, idempotency_key, occurred_at)
        VALUES ('issue', v_lot.item_id, v_lot.id, v_yard, 0, -100, 'run_input', 0, 'ilk-1', now());
        PERFORM pg_temp.chk('interlock 1: a quarantined coil cannot be issued', false);
    EXCEPTION WHEN check_violation THEN PERFORM pg_temp.chk('interlock 1: a quarantined coil cannot be issued', true); END;
    -- a quarantined coil may still be moved
    INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, counterparty_kind, counterparty_id, reference_kind, reference_id, idempotency_key, occurred_at)
    VALUES ('transfer_out', v_lot.item_id, v_lot.id, v_yard, 0, -8273, 'location', v_yard, 'transfer', 0, 'tr-0-out', now()),
           ('transfer_in',  v_lot.item_id, v_lot.id, v_yard, 0,  8273, 'location', v_yard, 'transfer', 0, 'tr-0-in', now());
    PERFORM pg_temp.chk('a quarantined coil may be moved (transfer out and back)', (SELECT qty_on_hand = 8273 FROM app.inventory_balances WHERE lot_id = v_lot.id AND location_id = v_yard));
    -- release it
    INSERT INTO app.release_decisions (target_id, from_status, to_status, basis, decided_by) VALUES (v_lot.id, 'quarantine', 'released', 'certificate', 1);
    UPDATE app.lots SET quality_status = 'released' WHERE id = v_lot.id;
    BEGIN
        INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, reference_kind, reference_id, idempotency_key, occurred_at)
        VALUES ('issue', v_lot.item_id, v_lot.id, v_yard, 0, -9000, 'run_input', 0, 'ilk-2', now());
        PERFORM pg_temp.chk('interlock 2: no negative stock in the yard', false);
    EXCEPTION WHEN check_violation THEN PERFORM pg_temp.chk('interlock 2: no negative stock in the yard', true); END;
    INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, reference_kind, reference_id, idempotency_key, occurred_at)
    VALUES ('issue', v_lot.item_id, v_lot.id, v_line, 0, -1, 'run_input', 0, 'ilk-3', now());
    PERFORM pg_temp.chk('a location that allows negative stock goes to -1', (SELECT qty_on_hand = -1 FROM app.inventory_balances WHERE lot_id = v_lot.id AND location_id = v_line));
    INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, reference_kind, reference_id, idempotency_key, occurred_at, reverses_id)
    VALUES ('reversal', v_lot.item_id, v_lot.id, v_line, 0, 1, 'reversal', 0, 'ilk-3-rev', now(), (SELECT id FROM app.inventory_transactions WHERE idempotency_key = 'ilk-3'));
    BEGIN
        UPDATE app.inventory_transactions SET qty_base = 1 WHERE idempotency_key = 'ilk-3';
        PERFORM pg_temp.chk('ledger rows are immutable', false);
    EXCEPTION WHEN integrity_constraint_violation THEN PERFORM pg_temp.chk('ledger rows are immutable', true); END;
    BEGIN
        INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, reference_kind, reference_id, idempotency_key, occurred_at)
        VALUES ('receipt', v_lot.item_id, v_lot.id, v_yard, 0, 1, 'goods_receipt', 1, 'gr-1-line-1', now());
        PERFORM pg_temp.chk('an idempotency key posts once', false);
    EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.chk('an idempotency key posts once', true); END;
END $$;
SELECT app.rebuild_inventory_balances();
SELECT pg_temp.chk('rebuild_inventory_balances reproduces the trigger-kept numbers', (SELECT qty_on_hand = 8273 AND weight_on_hand_kg = 8273 FROM app.inventory_balances b JOIN app.locations l ON l.id = b.location_id WHERE l.name = 'Coil yard'));

-- 8. Product, process spec, specs ---------------------------------------------------------------------------------------------
INSERT INTO app.products (code, name, family, status) VALUES ('P-SHT-16-48-120', 'Sheet 16 ga x 48 x 120 A1011 CS-B', 'cut sheets', 'active');
INSERT INTO app.product_attribute_values (product_id, attribute_key, value_num, value_text)
    SELECT id, k, n, t FROM app.products, (VALUES ('grade', NULL::numeric, 'A1011 CS-B'), ('thickness_in', 0.0598, NULL), ('width_in', 48, NULL), ('length_in', 120, NULL), ('edge', NULL, 'mill')) v(k, n, t);
INSERT INTO app.process_specs (product_id, version_no, status, output_item_id, planned_qty_base)
    SELECT p.id, 1, 'draft', i.id, 170 FROM app.products p, app.items i WHERE i.code = 'SHT-16-48-120';
INSERT INTO app.process_spec_steps (process_spec_id, seq, operation_code, equipment_kind, expected_loss_pct, setup_minutes, minutes_per_base_unit)
    SELECT id, 1, 'cut_to_length', 'cut_to_length_line', 1.5, 20, 0.5 FROM app.process_specs;
INSERT INTO app.process_spec_steps (process_spec_id, seq, operation_code, equipment_kind, expected_loss_pct) SELECT id, 2, 'pack', 'packaging_line', 0 FROM app.process_specs;
INSERT INTO app.process_spec_inputs (process_spec_id, seq, step_seq, item_id, purpose, qty_per_base_unit)
    SELECT ps.id, 1, 1, i.id, 'primary_material', 44.31 / 0.985 FROM app.process_specs ps, app.items i WHERE i.code = 'HR-16-48';
INSERT INTO app.process_spec_inputs (process_spec_id, seq, step_seq, item_id, purpose, qty_per_run, consumption_mode)
    SELECT ps.id, 2, 2, i.id, 'consumable', 24, 'backflush' FROM app.process_specs ps, app.items i WHERE i.code = 'BAND-34';
DO $$ BEGIN
    BEGIN
        INSERT INTO app.process_spec_inputs (process_spec_id, seq, item_id, purpose, qty_per_base_unit, qty_per_run) SELECT id, 9, 1, 'other', 1, 1 FROM app.process_specs;
        PERFORM pg_temp.chk('an input is per unit OR per run, never both', false);
    EXCEPTION WHEN check_violation THEN PERFORM pg_temp.chk('an input is per unit OR per run, never both', true); END;
END $$;
UPDATE app.process_specs SET status = 'active', activated_at = now(), expected_total_loss_pct = 1.5, standard_cost_total = 170 * 44.31 / 0.985 * 1.0693 + 24 * 0.08, standard_cost_per_base = (170 * 44.31 / 0.985 * 1.0693 + 24 * 0.08) / 170;
DO $$ BEGIN
    BEGIN
        INSERT INTO app.process_spec_steps (process_spec_id, seq, operation_code) SELECT id, 3, 'inspect' FROM app.process_specs;
        PERFORM pg_temp.chk('an active spec is immutable', false);
    EXCEPTION WHEN integrity_constraint_violation THEN PERFORM pg_temp.chk('an active spec is immutable', true); END;
    BEGIN
        INSERT INTO app.process_specs (product_id, version_no, status, output_item_id, planned_qty_base) SELECT product_id, 2, 'active', output_item_id, 100 FROM app.process_specs;
        PERFORM pg_temp.chk('one active spec per product', false);
    EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.chk('one active spec per product', true); END;
END $$;
INSERT INTO app.specs (product_id, operation_code, measurement_type_code, min_value, max_value, target_value) SELECT id, 'cut_to_length', 'thickness_in', 0.0568, 0.0628, 0.0598 FROM app.products;
INSERT INTO app.specs (product_id, operation_code, measurement_type_code, min_value, max_value, target_value) SELECT id, 'cut_to_length', 'length_in', 119.875, 120.25, 120 FROM app.products;
INSERT INTO app.specs (product_id, operation_code, measurement_type_code, max_value) SELECT id, 'cut_to_length', 'flatness_iunit', 10 FROM app.products;
SELECT pg_temp.chk('three specs on the product at cut to length', (SELECT count(*) = 3 FROM app.specs));
INSERT INTO app.packaging_configurations (product_id, finished_item_id, name, package_kind, qty_per_package_base, max_weight_kg, default_unit_price, default_price_basis)
    SELECT p.id, i.id, 'Skid of 50', 'skid', 50, 2500, 62.50, 'per_cwt' FROM app.products p, app.items i WHERE i.code = 'FG-SHT-16-48-120';
INSERT INTO app.packaging_bom_lines (configuration_id, item_id, qty_per_package_base) SELECT pc.id, i.id, 1 FROM app.packaging_configurations pc, app.items i WHERE i.code = 'SKID-48';
INSERT INTO app.packaging_bom_lines (configuration_id, item_id, qty_per_package_base) SELECT pc.id, i.id, 8 FROM app.packaging_configurations pc, app.items i WHERE i.code = 'BAND-34';
INSERT INTO app.overhead_rates (site_id, rate_per_kg) SELECT id, 0.03 FROM app.sites WHERE code = 'MAIN';
INSERT INTO app.standard_costs (item_id, cost_per_base) SELECT id, standard_cost_per_base FROM app.items WHERE standard_cost_per_base IS NOT NULL;
SELECT pg_temp.chk('standard costs recorded for the standard-cost items', (SELECT count(*) = 3 FROM app.standard_costs));

-- 9. Equipment, capabilities, the fit --------------------------------------------------------------------------------------------
INSERT INTO app.equipment (site_id, name, kind, rating, capabilities)
    SELECT id, 'CTL-1', 'cut_to_length_line', '60 ft/min, 20,000 lb coils', '{"width_in": {"min": 12, "max": 72}, "thickness_in": {"min": 0.015, "max": 0.25}, "weight_kg": {"max": 20000}}'::jsonb FROM app.sites WHERE code = 'MAIN';
INSERT INTO app.equipment (site_id, name, kind, capabilities)
    SELECT id, 'Slitter 36', 'slitter', '{"width_in": {"max": 36}, "thickness_in": {"max": 0.135}}'::jsonb FROM app.sites WHERE code = 'MAIN';
INSERT INTO app.equipment (site_id, name, kind) SELECT id, 'Pack line', 'packaging_line' FROM app.sites WHERE code = 'MAIN';
SELECT pg_temp.chk('CTL-1 takes the 48 in coil (no warnings)', (SELECT count(*) = 0 FROM app.equipment_fits((SELECT id FROM app.equipment WHERE name = 'CTL-1'), (SELECT id FROM app.items WHERE code = 'HR-16-48'), (SELECT id FROM app.lots WHERE supplier_lot_number = 'LS-77812'))));
SELECT pg_temp.chk('Slitter 36 warns once: width 48 above its maximum of 36', (SELECT count(*) = 1 AND bool_and(attribute_key = 'width_in' AND limit_kind = 'max' AND actual_value = 48) FROM app.equipment_fits((SELECT id FROM app.equipment WHERE name = 'Slitter 36'), (SELECT id FROM app.items WHERE code = 'HR-16-48'), NULL)));
SELECT pg_temp.chk('the fit message is a sentence', (SELECT message LIKE 'Width (in): 48%above Slitter 36%maximum of 36' FROM app.equipment_fits((SELECT id FROM app.equipment WHERE name = 'Slitter 36'), (SELECT id FROM app.items WHERE code = 'HR-16-48'), NULL)));
SELECT pg_temp.chk('v_equipment_resources lists three machines with their kind names', (SELECT count(*) = 3 AND bool_and(kind_name IS NOT NULL) FROM app.v_equipment_resources));

-- 10. The production order and the run (the exemplar) --------------------------------------------------------------------------------
INSERT INTO app.production_orders (number, site_id, product_id, process_spec_id, planned_qty_base, planned_weight_kg, planned_start_on, due_on, status)
    SELECT app.next_number('production_order'), st.id, p.id, ps.id, 170, 170 * 44.31, current_date, current_date + 4, 'released' FROM app.sites st, app.products p, app.process_specs ps WHERE st.code = 'MAIN';
SELECT pg_temp.chk('the production order is WO-00001', (SELECT number = 'WO-00001' FROM app.production_orders));
INSERT INTO app.allocations (production_order_id, item_id, lot_id, qty_base) SELECT po.id, l.item_id, l.id, 8273 FROM app.production_orders po, app.lots l WHERE l.supplier_lot_number = 'LS-77812';
UPDATE app.inventory_balances SET qty_allocated = 8273 WHERE lot_id = (SELECT id FROM app.lots WHERE supplier_lot_number = 'LS-77812') AND location_id = (SELECT id FROM app.locations WHERE name = 'Coil yard');
SELECT pg_temp.chk('v_lot_balances shows 0 available while allocated', (SELECT qty_available = 0 FROM app.v_lot_balances WHERE location_name = 'Coil yard'));
INSERT INTO app.runs (number, site_id, production_order_id, process_spec_step_id, operation_code, equipment_id, status, started_at)
    SELECT app.next_number('run'), st.id, po.id, s.id, 'cut_to_length', e.id, 'in_progress', now() - interval '2 hours'
      FROM app.sites st, app.production_orders po, app.process_spec_steps s, app.equipment e WHERE st.code = 'MAIN' AND s.seq = 1 AND e.name = 'CTL-1';
INSERT INTO app.run_inputs (run_id, seq, lot_id, qty_base, weight_kg, is_primary) SELECT r.id, 1, l.id, 8273, 8273, true FROM app.runs r, app.lots l WHERE l.supplier_lot_number = 'LS-77812';
INSERT INTO app.run_outputs (run_id, seq, kind, item_id, qty_base, weight_kg, location_id, attributes)
    SELECT r.id, 1, 'product', i.id, 170, 7533, b.id, '{"edge": "sheared"}'::jsonb FROM app.runs r, app.items i, app.locations b WHERE i.code = 'SHT-16-48-120' AND b.name = 'Bay B';
INSERT INTO app.run_outputs (run_id, seq, kind, item_id, qty_base, weight_kg, location_id)
    SELECT r.id, 2, 'co_product', i.id, 640, 640, y.id FROM app.runs r, app.items i, app.locations y WHERE i.code = 'HR-16-48-REM' AND y.name = 'Coil yard';
INSERT INTO app.run_outputs (run_id, seq, kind, item_id, qty_base, weight_kg, location_id)
    SELECT r.id, 3, 'scrap', i.id, 100, 100, s.id FROM app.runs r, app.items i, app.locations s WHERE i.code = 'SCRAP-HR' AND s.name = 'Scrap bin';
INSERT INTO app.run_consumables (run_id, item_id, qty_base, mode) SELECT r.id, i.id, 24, 'backflush' FROM app.runs r, app.items i WHERE i.code = 'BAND-34';
DO $$ BEGIN
    BEGIN
        INSERT INTO app.run_inputs (run_id, seq, lot_id, qty_base, is_primary) SELECT id, 2, 1, 1, true FROM app.runs;
        PERFORM pg_temp.chk('one primary input per run', false);
    EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.chk('one primary input per run', true); END;
END $$;
-- a booking for the run, and a clash
INSERT INTO app.equipment_reservations (equipment_id, kind, subject_kind, subject_id, starts_at, ends_at, all_day)
    SELECT e.id, 'run', 'run', r.id, date_trunc('day', now()), date_trunc('day', now()) + interval '1 day', true FROM app.equipment e, app.runs r WHERE e.name = 'CTL-1';
SELECT pg_temp.chk('the run''s booking shows on the schedule with its number and no clash', (SELECT subject_number = 'RUN-00001' AND clash_count = 0 FROM app.v_equipment_schedule));
SELECT pg_temp.chk('equipment_clashes finds the booking for a window today', (SELECT count(*) = 1 FROM app.equipment_clashes((SELECT id FROM app.equipment WHERE name = 'CTL-1'), now(), now() + interval '1 hour', NULL)));
SELECT pg_temp.chk('equipment_clashes finds nothing for next week', (SELECT count(*) = 0 FROM app.equipment_clashes((SELECT id FROM app.equipment WHERE name = 'CTL-1'), now() + interval '7 days', now() + interval '8 days', NULL)));
DO $$ BEGIN
    BEGIN
        INSERT INTO app.equipment_reservations (equipment_id, kind, subject_kind, subject_id, starts_at, ends_at) SELECT id, 'run', 'run', 9999, now(), now() + interval '1 hour' FROM app.equipment WHERE name = 'CTL-1';
        PERFORM pg_temp.chk('a booking for a run that does not exist is refused', false);
    EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.chk('a booking for a run that does not exist is refused', true); END;
    BEGIN
        INSERT INTO app.equipment_reservations (equipment_id, kind, starts_at, ends_at) SELECT id, 'maintenance', now(), now() - interval '1 hour' FROM app.equipment WHERE name = 'CTL-1';
        PERFORM pg_temp.chk('a booking must end after it starts', false);
    EXCEPTION WHEN check_violation THEN PERFORM pg_temp.chk('a booking must end after it starts', true); END;
END $$;
INSERT INTO app.equipment_reservations (equipment_id, kind, starts_at, ends_at, all_day, shared) SELECT id, 'maintenance', date_trunc('day', now()) + interval '18 hours', date_trunc('day', now()) + interval '20 hours', false, true FROM app.equipment WHERE name = 'CTL-1';
SELECT pg_temp.chk('a shared maintenance block over the run counts as its one clash', (SELECT clash_count = 1 FROM app.v_equipment_schedule WHERE subject_kind = 'run'));

-- readings against the specs (the run's product comes from its production order)
INSERT INTO app.readings (target_kind, target_id, measurement_type_code, value, operation_code) SELECT 'run', id, 'thickness_in', 0.0601, 'cut_to_length' FROM app.runs;
INSERT INTO app.readings (target_kind, target_id, measurement_type_code, value, operation_code) SELECT 'run', id, 'length_in', 120.02, 'cut_to_length' FROM app.runs;
INSERT INTO app.readings (target_kind, target_id, measurement_type_code, value, operation_code) SELECT 'run', id, 'flatness_iunit', 14, 'cut_to_length' FROM app.runs;
INSERT INTO app.readings (target_kind, target_id, measurement_type_code, value) SELECT 'run', id, 'camber_in_ft', 0.03 FROM app.runs;
SELECT pg_temp.chk('thickness 0.0601 passes its spec', (SELECT spec_result = 'pass' AND spec_id IS NOT NULL FROM app.readings WHERE measurement_type_code = 'thickness_in'));
SELECT pg_temp.chk('length 120.02 passes its spec', (SELECT spec_result = 'pass' FROM app.readings WHERE measurement_type_code = 'length_in'));
SELECT pg_temp.chk('flatness 14 I-units fails its spec of 10', (SELECT spec_result = 'fail' FROM app.readings WHERE measurement_type_code = 'flatness_iunit'));
SELECT pg_temp.chk('a reading with no spec is none', (SELECT spec_result = 'none' AND spec_id IS NULL FROM app.readings WHERE measurement_type_code = 'camber_in_ft'));

-- "post" the run: the output lots (attributes derived + inherited + explicit), the ledger, lineage, totals
INSERT INTO app.lots (lot_number, item_id, site_id, produced_on, quality_status, unit_cost_base, qty_initial_base, weight_kg, source_kind, source_id)
    SELECT app.next_number(COALESCE(ic.lot_number_key, 'lot')), o.item_id, r.site_id, current_date, 'released',
           CASE o.kind WHEN 'scrap' THEN 0.22 ELSE (8273 * (48.50 / 45.359237)) / NULLIF(7533 + 640, 0) * CASE WHEN i.base_unit_code = 'ea' THEN o.weight_kg / o.qty_base ELSE 1 END END,
           o.qty_base, o.weight_kg, 'run', o.id
      FROM app.run_outputs o JOIN app.runs r ON r.id = o.run_id JOIN app.items i ON i.id = o.item_id JOIN app.item_classes ic ON ic.code = i.item_class ORDER BY o.seq;
UPDATE app.run_outputs o SET lot_id = l.id FROM app.lots l WHERE l.source_kind = 'run' AND l.source_id = o.id;
SELECT pg_temp.chk('three output lots, numbered S-, C-, X- by class', (SELECT count(*) = 3 FROM app.lots WHERE source_kind = 'run')
       AND (SELECT l.lot_number LIKE 'S-%' FROM app.lots l JOIN app.run_outputs o ON o.lot_id = l.id WHERE o.kind = 'product')
       AND (SELECT l.lot_number LIKE 'C-%' FROM app.lots l JOIN app.run_outputs o ON o.lot_id = l.id WHERE o.kind = 'co_product')
       AND (SELECT l.lot_number LIKE 'X-%' FROM app.lots l JOIN app.run_outputs o ON o.lot_id = l.id WHERE o.kind = 'scrap'));
SELECT pg_temp.chk('the sheet lot''s unit weight is 44.3 kg (7,533 / 170)', (SELECT unit_weight_kg BETWEEN 44.2 AND 44.4 FROM app.lots l JOIN app.run_outputs o ON o.lot_id = l.id WHERE o.kind = 'product'));
SELECT app.lot_attributes_fill(o.lot_id, ri.lot_id, o.attributes, 'run', NULL)
  FROM app.run_outputs o JOIN app.run_inputs ri ON ri.run_id = o.run_id AND ri.is_primary;
SELECT pg_temp.chk('the sheet lot inherited the coil''s heat 7A1234', app.lot_attribute_text((SELECT lot_id FROM app.run_outputs WHERE kind = 'product'), 'heat') = '7A1234');
SELECT pg_temp.chk('the sheet lot inherited grade and mill (source inherited)', (SELECT count(*) = 2 FROM app.lot_attributes WHERE lot_id = (SELECT lot_id FROM app.run_outputs WHERE kind = 'product') AND key IN ('grade','mill') AND source = 'inherited'));
SELECT pg_temp.chk('the sheet lot''s length 120 came from its item, not the coil', app.lot_attribute_num((SELECT lot_id FROM app.run_outputs WHERE kind = 'product'), 'length_in') = 120
       AND (SELECT source = 'derived' FROM app.lot_attributes WHERE lot_id = (SELECT lot_id FROM app.run_outputs WHERE kind = 'product') AND key = 'length_in'));
SELECT pg_temp.chk('the sheet lot''s edge is sheared (explicit on the output)', app.lot_attribute_text((SELECT lot_id FROM app.run_outputs WHERE kind = 'product'), 'edge') = 'sheared');
SELECT pg_temp.chk('the MTR''s yield strength flowed down to the sheets', app.lot_attribute_num((SELECT lot_id FROM app.run_outputs WHERE kind = 'product'), 'yield_ksi') = 41.2);
SELECT pg_temp.chk('the remnant coil carries the heat too', app.lot_attribute_text((SELECT lot_id FROM app.run_outputs WHERE kind = 'co_product'), 'heat') = '7A1234');
-- the ledger: input out, outputs in, consumable backflushed
UPDATE app.allocations SET released_at = now(); UPDATE app.inventory_balances SET qty_allocated = 0;
INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, unit_cost_base, counterparty_kind, counterparty_id, report_category, reference_kind, reference_id, idempotency_key, occurred_at)
    SELECT 'issue', l.item_id, l.id, yard.id, 0, -ri.qty_base, l.unit_cost_base, 'run', ri.run_id, 'consumed', 'run_input', ri.id, 'run-1-in-' || ri.id, now()
      FROM app.run_inputs ri JOIN app.lots l ON l.id = ri.lot_id, app.locations yard WHERE yard.name = 'Coil yard';
INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, weight_kg, unit_cost_base, counterparty_kind, counterparty_id, report_category, reference_kind, reference_id, idempotency_key, occurred_at)
    SELECT 'production_output', o.item_id, o.lot_id, o.location_id, 0, o.qty_base, o.weight_kg, l.unit_cost_base, 'run', o.run_id,
           CASE o.kind WHEN 'scrap' THEN 'scrapped' ELSE 'produced' END, 'run_output', o.id, 'run-1-out-' || o.id, now()
      FROM app.run_outputs o JOIN app.lots l ON l.id = o.lot_id;
INSERT INTO app.consumptions (run_id, item_id, lot_id, qty_base, weight_kg, purpose, operation_code)
    SELECT ri.run_id, l.item_id, l.id, ri.qty_base, ri.weight_kg, 'primary_material', 'cut_to_length' FROM app.run_inputs ri JOIN app.lots l ON l.id = ri.lot_id;
-- the banding: an opening lot, then the backflush
INSERT INTO app.lots (lot_number, item_id, site_id, quality_status, unit_cost_base, qty_initial_base, source_kind) SELECT app.next_number('lot'), id, 1, 'released', 0.08, 1000, 'opening' FROM app.items WHERE code = 'BAND-34';
INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, unit_cost_base, reason_code_id, report_category, reference_kind, reference_id, idempotency_key, occurred_at)
    SELECT 'adjustment', l.item_id, l.id, ls.id, 0, 1000, 0.08, rc.id, 'none', 'opening', 0, 'open-band', now() FROM app.lots l, app.locations ls, app.reason_codes rc WHERE l.source_kind = 'opening' AND ls.name = 'Line side' AND rc.code = 'OPENING';
UPDATE app.run_consumables c SET lot_id = l.id FROM app.lots l WHERE l.source_kind = 'opening' AND l.item_id = c.item_id;
INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, counterparty_kind, counterparty_id, report_category, reference_kind, reference_id, idempotency_key, occurred_at)
    SELECT 'issue', c.item_id, c.lot_id, ls.id, 0, -c.qty_base, 'run', c.run_id, 'consumed', 'run_consumable', c.id, 'run-1-cons-' || c.id, now() FROM app.run_consumables c, app.locations ls WHERE ls.name = 'Line side';
INSERT INTO app.consumptions (run_id, item_id, lot_id, qty_base, purpose, operation_code) SELECT run_id, item_id, lot_id, qty_base, 'consumable', 'cut_to_length' FROM app.run_consumables;
SELECT pg_temp.chk('the banding lot''s weight is unknown, so its ledger weight stays 0', (SELECT weight_kg = 0 FROM app.inventory_transactions WHERE idempotency_key LIKE 'run-1-cons-%'));
SELECT pg_temp.chk('the coil is gone from the yard (0 on hand)', (SELECT qty_on_hand = 0 AND weight_on_hand_kg = 0 FROM app.inventory_balances b JOIN app.lots l ON l.id = b.lot_id JOIN app.locations loc ON loc.id = b.location_id WHERE l.supplier_lot_number = 'LS-77812' AND loc.name = 'Coil yard'));
SELECT pg_temp.chk('170 sheets, 7,533 kg in Bay B', (SELECT qty_on_hand = 170 AND weight_on_hand_kg = 7533 FROM app.v_lot_balances WHERE item_code = 'SHT-16-48-120'));
SELECT pg_temp.chk('the remnant coil is back in the yard: 640 kg', (SELECT qty_on_hand = 640 FROM app.v_lot_balances WHERE item_code = 'HR-16-48-REM'));
SELECT pg_temp.chk('100 kg of scrap in the scrap bin', (SELECT weight_on_hand_kg = 100 FROM app.v_lot_balances WHERE item_code = 'SCRAP-HR'));
SELECT pg_temp.chk('976 m of banding left', (SELECT qty_on_hand = 976 FROM app.v_item_stock WHERE code = 'BAND-34'));
SELECT pg_temp.chk('v_item_stock totals the coil item at 0 and the sheets at 170', (SELECT qty_on_hand = 0 FROM app.v_item_stock WHERE code = 'HR-16-48') AND (SELECT qty_on_hand = 170 FROM app.v_item_stock WHERE code = 'SHT-16-48-120'));
SELECT pg_temp.chk('v_inventory_valuation values the sheets at the coil''s cost per kg', (SELECT round(value) = round(7533 * (8273 * (48.50 / 45.359237)) / (7533 + 640)) FROM app.v_inventory_valuation WHERE item_class = 'sheet'));
-- lineage and totals
INSERT INTO app.lot_lineage (child_lot_id, parent_lot_id, event_kind, event_id, weight_kg, fraction)
    SELECT o.lot_id, ri.lot_id, 'run', o.run_id, o.weight_kg, o.weight_kg / ri.weight_kg FROM app.run_outputs o JOIN app.run_inputs ri ON ri.run_id = o.run_id AND ri.is_primary;
SELECT pg_temp.chk('three lineage rows, fractions summing to 1', (SELECT count(*) = 3 AND round(sum(fraction), 4) = 1 FROM app.lot_lineage));
UPDATE app.runs SET status = 'posted', posted_at = now(), finished_at = now(), setup_minutes = 20, run_minutes = 95,
       input_qty_base = 8273, input_weight_kg = 8273, output_qty_base = 170, output_weight_kg = 7533, co_product_weight_kg = 640, scrap_weight_kg = 100,
       loss_weight_kg = 8273 - 7533 - 640 - 100, yield_pct = round(100 * 7533 / 8273.0, 2);
SELECT pg_temp.chk('the run''s loss is 0 kg and its yield 91.06 %', (SELECT loss_weight_kg = 0 AND yield_pct = 91.06 FROM app.runs));
SELECT pg_temp.chk('v_run_yields shows the run on CTL-1 for the product with the step''s 1.5 % expected loss', (SELECT equipment_name = 'CTL-1' AND product_name LIKE 'Sheet 16%' AND expected_loss_pct = 1.5 AND actual_loss_pct = 8.94 FROM app.v_run_yields));
SELECT pg_temp.chk('v_run_costs: material at the coil''s cost, banding at standard, overhead 0.03/kg, scrap credit 22', (SELECT round(material_cost) = round(8273 * 48.50 / 45.359237) AND consumable_cost = 24 * 0.08 AND overhead_cost = 8273 * 0.03 AND scrap_credit = 100 * 0.22 FROM app.v_run_costs));
SELECT pg_temp.chk('v_run_costs: a cost per sheet and per kg', (SELECT cost_per_base_unit > 50 AND cost_per_kg > 1 FROM app.v_run_costs));
SELECT pg_temp.chk('v_product_costs rolls the order up against the spec''s standard', (SELECT total_cost > 0 AND standard_cost_per_base > 0 AND cost_per_base_unit > 0 FROM app.v_product_costs));
UPDATE app.production_orders SET status = 'in_progress';
-- a loss event and the scrap disposition
INSERT INTO app.loss_events (target_kind, target_id, site_id, operation_code, qty_base, unit_code, weight_kg, reason_code_id, report_category, classification)
    SELECT 'run', r.id, r.site_id, 'cut_to_length', 100, 'kg', 100, rc.id, rc.report_category, rc.classification FROM app.runs r, app.reason_codes rc WHERE rc.code = 'ENDS';
SELECT pg_temp.chk('the head-and-tail loss is recorded as expected scrap', (SELECT report_category = 'scrap' AND classification = 'expected' FROM app.loss_events));
INSERT INTO app.customers (name, kind) VALUES ('Great Lakes Fabrication', 'fabricator'), ('Metro Scrap', 'scrap_dealer');
INSERT INTO app.co_product_dispositions (lot_id, qty_base, weight_kg, destination, customer_id, unit_price)
    SELECT o.lot_id, 100, 100, 'scrap_sale', c.id, 0.24 FROM app.run_outputs o, app.customers c WHERE o.kind = 'scrap' AND c.kind = 'scrap_dealer';
INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, counterparty_kind, counterparty_id, report_category, reference_kind, reference_id, idempotency_key, occurred_at)
    SELECT 'scrap_out', l.item_id, l.id, s.id, 0, -100, 'customer', d.customer_id, 'scrapped', 'co_product_disposition', d.id, 'disp-1', now() FROM app.co_product_dispositions d JOIN app.lots l ON l.id = d.lot_id, app.locations s WHERE s.name = 'Scrap bin';
SELECT pg_temp.chk('the scrap bin is empty after the sale', (SELECT count(*) = 0 FROM app.v_lot_balances WHERE item_code = 'SCRAP-HR'));

-- 11. Trace -----------------------------------------------------------------------------------------------------------------------
SELECT pg_temp.chk('trace_forward(coil) lists the sheet lot, the remnant and the scrap', (SELECT count(*) FILTER (WHERE kind = 'lot') = 3 FROM app.trace_forward((SELECT id FROM app.lots WHERE supplier_lot_number = 'LS-77812'))));
SELECT pg_temp.chk('trace_forward carries the fraction and the heat', (SELECT bool_and((detail->>'heat') = '7A1234' AND (detail->>'fraction') IS NOT NULL) FROM app.trace_forward((SELECT id FROM app.lots WHERE supplier_lot_number = 'LS-77812')) WHERE kind = 'lot'));
SELECT pg_temp.chk('trace_backward(sheet lot) reaches the coil with its mill and certificate', (SELECT count(*) = 1 AND bool_and(detail->>'supplier' = 'Lakeside Steel Mill' AND jsonb_array_length(detail->'certificates') = 1 AND detail->>'heat' = '7A1234')
       FROM app.trace_backward((SELECT lot_id FROM app.run_outputs WHERE kind = 'product'))));
SELECT pg_temp.chk('heat_where_used(7A1234) names four lots (coil, sheets, remnant, scrap)', (SELECT count(DISTINCT lot_id) = 4 FROM app.heat_where_used('7a1234')));

-- 12. Packaging into skids ------------------------------------------------------------------------------------------------------------
INSERT INTO app.packaging_runs (number, site_id, packaging_configuration_id, production_order_id, equipment_id, output_location_id, status)
    SELECT app.next_number('packaging_run'), st.id, pc.id, po.id, e.id, fg.id, 'draft' FROM app.sites st, app.packaging_configurations pc, app.production_orders po, app.equipment e, app.locations fg WHERE st.code = 'MAIN' AND e.name = 'Pack line' AND fg.name = 'Finished goods';
INSERT INTO app.packaging_run_inputs (packaging_run_id, lot_id, qty_base, weight_kg) SELECT pr.id, o.lot_id, 150, 150 * 44.31 FROM app.packaging_runs pr, app.run_outputs o WHERE o.kind = 'product';
INSERT INTO app.packaging_run_materials (packaging_run_id, item_id, qty_base, mode) SELECT pr.id, i.id, 3, 'backflush' FROM app.packaging_runs pr, app.items i WHERE i.code = 'SKID-48';
-- "post": one finished lot of 3 skids
INSERT INTO app.lots (lot_number, item_id, site_id, produced_on, quality_status, unit_cost_base, qty_initial_base, weight_kg, source_kind, source_id)
    SELECT app.next_number('skid'), i.id, pr.site_id, current_date, 'quarantine', 50 * 44.31 * 1.07 + 18, 3, 150 * 44.31, 'packaging_run', pr.id FROM app.items i, app.packaging_runs pr WHERE i.code = 'FG-SHT-16-48-120';
INSERT INTO app.finished_lots (lot_id, packaging_run_id, packaging_configuration_id, product_id, production_order_id, packaged_on, packages, qty_per_package_base, package_weight_kg, heat_numbers)
    SELECT l.id, pr.id, pr.packaging_configuration_id, pc.product_id, pr.production_order_id, current_date, 3, 50, 50 * 44.31, ARRAY['7A1234'] FROM app.lots l, app.packaging_runs pr JOIN app.packaging_configurations pc ON pc.id = pr.packaging_configuration_id WHERE l.source_kind = 'packaging_run';
SELECT pg_temp.chk('the finished lot is a Skid lot numbered K-', (SELECT lot_number LIKE 'K-%' AND unit_weight_kg BETWEEN 2215 AND 2216 FROM app.lots WHERE source_kind = 'packaging_run'));
SELECT app.lot_attributes_fill(l.id, pi.lot_id, '{}'::jsonb, 'packaging_run', NULL) FROM app.lots l, app.packaging_run_inputs pi WHERE l.source_kind = 'packaging_run';
SELECT pg_temp.chk('the skids inherited the heat through packaging', app.lot_attribute_text((SELECT id FROM app.lots WHERE source_kind = 'packaging_run'), 'heat') = '7A1234');
INSERT INTO app.lot_lineage (child_lot_id, parent_lot_id, event_kind, event_id, weight_kg, fraction) SELECT l.id, pi.lot_id, 'packaging_run', pi.packaging_run_id, pi.weight_kg, 150 / 170.0 FROM app.lots l, app.packaging_run_inputs pi WHERE l.source_kind = 'packaging_run';
INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, counterparty_kind, counterparty_id, report_category, reference_kind, reference_id, idempotency_key, occurred_at)
    SELECT 'issue', l.item_id, l.id, b.id, 0, -150, 'packaging_run', pi.packaging_run_id, 'packaged', 'packaging_run', pi.packaging_run_id, 'pk-1-in', now() FROM app.packaging_run_inputs pi JOIN app.lots l ON l.id = pi.lot_id, app.locations b WHERE b.name = 'Bay B';
INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, unit_cost_base, counterparty_kind, counterparty_id, report_category, reference_kind, reference_id, idempotency_key, occurred_at)
    SELECT 'packaging_output', l.item_id, l.id, pr.output_location_id, 0, 3, l.unit_cost_base, 'packaging_run', pr.id, 'packaged', 'packaging_run', pr.id, 'pk-1-out', now() FROM app.lots l JOIN app.packaging_runs pr ON pr.id = l.source_id WHERE l.source_kind = 'packaging_run';
UPDATE app.packaging_runs SET status = 'posted', posted_at = now(), input_qty_base = 150, input_weight_kg = 150 * 44.31, packages_out = 3, output_weight_kg = 150 * 44.31;
SELECT pg_temp.chk('20 sheets stay in Bay B, 3 skids stand in finished goods', (SELECT qty_on_hand = 20 FROM app.v_lot_balances WHERE item_code = 'SHT-16-48-120') AND (SELECT qty_on_hand = 3 FROM app.v_lot_balances WHERE item_code = 'FG-SHT-16-48-120'));
SELECT pg_temp.chk('the skids'' ledger weight is 3 × 2,215.5 kg', (SELECT weight_kg BETWEEN 6646 AND 6647 FROM app.inventory_transactions WHERE idempotency_key = 'pk-1-out'));
SELECT pg_temp.chk('v_finished_stock: 3 skids of the product with heat 7A1234, not yet released', (SELECT units_on_hand = 3 AND '7A1234' = ANY(heat_numbers) AND product_name LIKE 'Sheet 16%' FROM app.v_finished_stock));
SELECT pg_temp.chk('v_fifo_stock ranks nothing unreleased', (SELECT fifo_rank IS NULL FROM app.v_fifo_stock WHERE item_code = 'FG-SHT-16-48-120'));
INSERT INTO app.inspections (target_kind, target_id, kind, verdict, attributes) SELECT 'lot', id, 'final', 'pass', '{"surface": "clean", "banding": "tight"}'::jsonb FROM app.lots WHERE source_kind = 'packaging_run';
INSERT INTO app.release_decisions (target_id, from_status, to_status, basis, decided_by) SELECT id, 'quarantine', 'released', 'inspection', 1 FROM app.lots WHERE source_kind = 'packaging_run';
UPDATE app.lots SET quality_status = 'released' WHERE source_kind = 'packaging_run';
SELECT pg_temp.chk('once released the skids rank first in FIFO', (SELECT fifo_rank = 1 FROM app.v_fifo_stock WHERE item_code = 'FG-SHT-16-48-120'));

-- 13. The customer order, the price basis, the shipment ------------------------------------------------------------------------------------
INSERT INTO app.sales_orders (number, customer_id, site_id, status, requested_on, customer_reference)
    SELECT app.next_number('sales_order'), c.id, st.id, 'confirmed', current_date + 3, 'GLF-PO-8841' FROM app.customers c, app.sites st WHERE c.kind = 'fabricator' AND st.code = 'MAIN';
INSERT INTO app.sales_order_lines (sales_order_id, line_no, product_id, packaging_configuration_id, qty_ordered, weight_kg_ordered, package_qty_base, unit_price, price_basis)
    SELECT so.id, 1, p.id, pc.id, 150, 150 * 44.31, 50, 62.50, 'per_cwt' FROM app.sales_orders so, app.products p, app.packaging_configurations pc;
INSERT INTO app.sales_order_lines (sales_order_id, line_no, product_id, qty_ordered, unit_price, price_basis) SELECT so.id, 2, p.id, 20, 97.00, 'per_unit' FROM app.sales_orders so, app.products p;
SELECT pg_temp.chk('a per-cwt line totals weight / 45.359237 × price = 9,158.86', (SELECT line_total = round((150 * 44.31 / 45.359237 * 62.50)::numeric, 2) FROM app.sales_order_lines WHERE line_no = 1));
SELECT pg_temp.chk('a per-unit line totals qty × price = 1,940', (SELECT line_total = 1940.00 FROM app.sales_order_lines WHERE line_no = 2));
SELECT pg_temp.chk('v_sales_order_lines: line 1 open for 150, in production via the order', (SELECT qty_open = 150 AND qty_shipped = 0 FROM app.v_sales_order_lines WHERE line_no = 1));
UPDATE app.production_orders SET sales_order_line_id = (SELECT id FROM app.sales_order_lines WHERE line_no = 1);
SELECT pg_temp.chk('v_sales_order_lines sees the production order''s 170 behind line 1', (SELECT qty_in_production = 170 FROM app.v_sales_order_lines WHERE line_no = 1));
INSERT INTO app.shipments (number, site_id, direction, customer_id, carrier, trailer, from_location_id, status, sales_order_id, packages, total_weight_kg)
    SELECT app.next_number('shipment'), st.id, 'out', so.customer_id, 'Lakeshore Freight', 'TRL-4471', fg.id, 'draft', so.id, 3, 150 * 44.31 FROM app.sites st, app.sales_orders so, app.locations fg WHERE st.code = 'MAIN' AND fg.name = 'Finished goods';
INSERT INTO app.shipment_lines (shipment_id, lot_id, qty_base, product_qty_base, weight_kg, sales_order_line_id)
    SELECT s.id, l.id, 3, 150, 150 * 44.31, ol.id FROM app.shipments s, app.lots l, app.sales_order_lines ol WHERE l.source_kind = 'packaging_run' AND ol.line_no = 1;
SELECT pg_temp.chk('the shipment is BOL-00001', (SELECT number = 'BOL-00001' FROM app.shipments));
INSERT INTO app.inventory_transactions (txn_type, item_id, lot_id, location_id, site_id, qty_base, counterparty_kind, counterparty_id, report_category, reference_kind, reference_id, idempotency_key, occurred_at)
    SELECT 'shipment', l.item_id, l.id, s.from_location_id, 0, -3, 'customer', s.customer_id, 'shipped', 'shipment', s.id, 'bol-1', now() FROM app.shipment_lines sl JOIN app.lots l ON l.id = sl.lot_id JOIN app.shipments s ON s.id = sl.shipment_id;
UPDATE app.shipments SET status = 'posted', posted_at = now();
SELECT pg_temp.chk('finished goods are empty after the truck left', (SELECT count(*) = 0 FROM app.v_finished_stock));
SELECT pg_temp.chk('v_sales_order_lines: 150 pieces shipped on line 1, 0 open, 6,646.5 kg', (SELECT qty_shipped = 150 AND qty_open = 0 AND weight_kg_shipped BETWEEN 6646 AND 6647 FROM app.v_sales_order_lines WHERE line_no = 1));
SELECT pg_temp.chk('trace_forward(coil) now ends at the shipment', (SELECT count(*) = 1 AND bool_and(label = 'BOL-00001') FROM app.trace_forward((SELECT id FROM app.lots WHERE supplier_lot_number = 'LS-77812')) WHERE kind = 'shipment'));
SELECT pg_temp.chk('heat_where_used(7A1234) names the shipment', (SELECT count(*) = 1 FROM app.heat_where_used('7A1234') WHERE shipment_number = 'BOL-00001'));
-- a standing order and the demand view
INSERT INTO app.standing_orders (number, customer_id, site_id, frequency, weekday, starts_on) SELECT app.next_number('standing_order'), c.id, st.id, 'weekly', 1, current_date - 7 FROM app.customers c, app.sites st WHERE c.kind = 'fabricator' AND st.code = 'MAIN';
INSERT INTO app.standing_order_lines (standing_order_id, line_no, product_id, qty_ordered, unit_price, price_basis) SELECT s.id, 1, p.id, 50, 62.50, 'per_cwt' FROM app.standing_orders s, app.products p;
SELECT pg_temp.chk('a weekly standing order occurs 4 times in the next 4 weeks', (SELECT count(*) = 4 FROM app.standing_order_occurrences(current_date, current_date + 27)));
SELECT pg_temp.chk('v_demand has firm (line 2) and standing rows', (SELECT count(*) FILTER (WHERE demand_type = 'firm') = 1 AND count(*) FILTER (WHERE demand_type = 'standing') BETWEEN 25 AND 27 FROM app.v_demand));
INSERT INTO app.demand_forecasts (product_id, week_start, qty, method) SELECT id, date_trunc('week', current_date)::date + 7, 500, 'manual' FROM app.products;
SELECT pg_temp.chk('a forecast is reduced by the standing demand of its week', (SELECT qty = 450 FROM app.v_demand WHERE demand_type = 'forecast'));

-- 14. Period reports, activity, misc ---------------------------------------------------------------------------------------------------
INSERT INTO app.period_reports (number, site_id, report_code, period_start, period_end, status) SELECT app.next_number('period_report'), id, 'yield_scrap', date_trunc('month', current_date)::date, (date_trunc('month', current_date) + interval '1 month - 1 day')::date, 'draft' FROM app.sites WHERE code = 'MAIN';
INSERT INTO app.period_report_lines (report_id, section, line_code, label, group_key, value, unit) SELECT r.id, m.section, m.line_code, m.label, '', 0, 'kg' FROM app.period_reports r, app.report_line_map m WHERE m.report_code = 'yield_scrap';
SELECT pg_temp.chk('a yield and scrap report has its 8 lines', (SELECT count(*) = 8 FROM app.period_report_lines));
DO $$ BEGIN
    BEGIN
        INSERT INTO app.period_reports (number, site_id, report_code, period_start, period_end) SELECT 'RPT-dup', site_id, report_code, period_start, period_end FROM app.period_reports;
        PERFORM pg_temp.chk('one report per site, code and period', false);
    EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.chk('one report per site, code and period', true); END;
END $$;
SELECT app.log_activity(1, 'user/1 Prove', 'screen', NULL, NULL, 'run_posted', 'run-view', 'run', 1, 'RUN-00001', NULL, '{"yield_pct": 91.06}'::jsonb, '{}'::jsonb, NULL);
SELECT pg_temp.chk('log_activity writes a row', (SELECT count(*) = 1 FROM app.activity_log WHERE action = 'run_posted'));
DO $$ BEGIN
    BEGIN
        DELETE FROM app.activity_log;
        PERFORM pg_temp.chk('the activity log cannot be deleted from', false);
    EXCEPTION WHEN integrity_constraint_violation THEN PERFORM pg_temp.chk('the activity log cannot be deleted from', true); END;
END $$;
SELECT pg_temp.chk('v_supplier_performance counts the mill''s one receipt', (SELECT receipts = 1 FROM app.v_supplier_performance));
INSERT INTO app.inventory_transfers (number, from_location_id, to_location_id) SELECT app.next_number('transfer'), a.id, b.id FROM app.locations a, app.locations b WHERE a.name = 'Bay B' AND b.name = 'Coil yard';
INSERT INTO app.inventory_adjustments (number, location_id, reason_code_id) SELECT app.next_number('adjustment'), l.id, rc.id FROM app.locations l, app.reason_codes rc WHERE l.name = 'Bay B' AND rc.code = 'RUST';
INSERT INTO app.inventory_counts (number, location_id) SELECT app.next_number('count'), id FROM app.locations WHERE name = 'Coil yard';
SELECT pg_temp.chk('a transfer, an adjustment and a count can be opened (TR-, ADJ-, CNT-)', (SELECT number = 'TR-00001' FROM app.inventory_transfers) AND (SELECT number = 'ADJ-00001' FROM app.inventory_adjustments) AND (SELECT number = 'CNT-00001' FROM app.inventory_counts));
DO $$ BEGIN
    BEGIN
        INSERT INTO app.item_classes (code, name, kind) VALUES ('Bad Code', 'x', 'material');
        PERFORM pg_temp.chk('an item class code must be lower snake case', false);
    EXCEPTION WHEN check_violation THEN PERFORM pg_temp.chk('an item class code must be lower snake case', true); END;
    BEGIN
        DELETE FROM app.item_classes WHERE code = 'finished_good';
        PERFORM pg_temp.chk('a built-in item class cannot be deleted', false);
    EXCEPTION WHEN integrity_constraint_violation THEN PERFORM pg_temp.chk('a built-in item class cannot be deleted', true); END;
    BEGIN
        INSERT INTO app.attribute_definitions (key, name, kind) VALUES ('bad_choice', 'x', 'choice');
        PERFORM pg_temp.chk('a choice attribute needs its choices', false);
    EXCEPTION WHEN check_violation THEN PERFORM pg_temp.chk('a choice attribute needs its choices', true); END;
    DELETE FROM app.item_classes WHERE code = 'blank';
    PERFORM pg_temp.chk('a profile''s class may be deleted by the business', (SELECT count(*) = 0 FROM app.item_classes WHERE code = 'blank'));
END $$;

-- Results ------------------------------------------------------------------------------------------------------------------------
SELECT CASE WHEN ok THEN 'ok ' ELSE 'FAIL ' END || name FROM results ORDER BY n;
SELECT 'ok ' || count(*) FILTER (WHERE ok) || ' checks passed, ' || count(*) FILTER (WHERE NOT ok) || ' failed' FROM results;
\if :keep
\else
    -- the example rows go; the schema and the seeds stay (the ledger is immutable, so the tables are truncated)
    TRUNCATE app.inventory_transactions, app.inventory_balances, app.lot_lineage, app.consumptions, app.loss_events, app.readings, app.inspections,
             app.co_product_dispositions, app.shipment_lines, app.shipments, app.finished_lots, app.packaging_run_inputs, app.packaging_run_materials,
             app.packaging_runs, app.run_inputs, app.run_outputs, app.run_consumables, app.equipment_reservations, app.runs, app.allocations,
             app.production_order_packages, app.production_orders, app.sales_order_lines, app.sales_orders, app.standing_order_lines, app.standing_orders,
             app.demand_forecasts, app.period_report_lines, app.period_reports, app.release_decisions, app.certificates, app.lot_attributes,
             app.weigh_tickets, app.goods_receipt_lines, app.goods_receipts, app.lots, app.purchase_order_lines, app.purchase_orders,
             app.specs, app.packaging_bom_lines, app.packaging_configurations, app.process_spec_inputs, app.process_spec_steps, app.process_specs,
             app.product_attribute_values, app.products, app.standard_costs, app.overhead_rates, app.item_attribute_values, app.supplier_items, app.items,
             app.suppliers, app.customers, app.equipment, app.inventory_transfer_lines, app.inventory_transfers, app.inventory_adjustment_lines,
             app.inventory_adjustments, app.inventory_count_lines, app.inventory_counts, app.locations, app.sites, app.activity_log, app.users RESTART IDENTITY CASCADE;
    UPDATE app.number_sequences SET next_value = 1, period_value = NULL;
    INSERT INTO app.item_classes (code, name, kind, purchasable, process_input, catch_weight, serialized, lot_noun, lot_noun_plural, lot_number_key, density_kg_m3, display_order)
        VALUES ('blank', 'Blank', 'material', false, true, false, false, 'Lot', 'Lots', 'sheet', 7850, 14) ON CONFLICT (code) DO NOTHING;
\endif
