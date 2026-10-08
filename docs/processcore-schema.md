# ProcessCore — the schema (step 2 of the build order, written in place 2026-10-08)

Plan: [processcore-design.md](processcore-design.md) §3 (concept by concept), §4 (the steel profile), §5 (the run),
D2 (rewritten in place), D4 (pieces and weight), D5 (attributes), D6 (capabilities), D7 (reports), D9 (price basis).
The files are `db/002–016` plus `db/020_grants.sql` and `db/profiles/steel/seed.sql`; `db/README.md` lists them.
Proof: `scripts/prove-schema.sh` — drops and rebuilds `processcore_dev` from the files through
`deploy/os-provision.sh`, then runs `scripts/prove-schema.sql` as the application role and a few statements as the
two read roles: **283 checks, all green** (structure, seeds, helpers, the worked steel example of the plan's §5 end to
end, the interlocks, trace, costing, the price basis, demand, reports, the read roles' grants).

## 1. The shape

```
sites ─┬─ locations (areas; racks inside them, one level)        reason_codes     equipment_kinds ─ equipment (capabilities)
       │                                                                         attribute_definitions ─ item_class_attributes
item_classes (lot noun, serialized, catch weight, density) ─ items ─ item_attribute_values
suppliers ─ supplier_items                                                     products ─ product_attribute_values
purchase_orders ─ lines ─ goods_receipts ─ lines ─ weigh_tickets                        └ process_specs ─ steps, inputs
                                        └─ lots ─ lot_attributes, certificates, release_decisions       └ specs (per operation)
inventory_transactions (qty + weight) ─ inventory_balances          transfers, adjustments, counts   packaging_configurations ─ bom
production_orders ─ allocations ─ runs ─ run_inputs, run_outputs, run_consumables ─ consumptions, readings, loss_events
                                        └─ lot_lineage (child ← parent, event, fraction)      co_product_dispositions
packaging_runs ─ inputs, materials ─ finished_lots (packages, heats)
customers ─ shipments ─ shipment_lines                       report_line_map ─ period_reports ─ lines
sales_orders ─ lines (price basis) ─ standing_orders, order_imports, demand_forecasts, production_order_packages
equipment_reservations (one machine, one window, a run or a block)
activity_log; users (seven roles), mcp_access_tokens; the OS kit (sso_nonces, member_sessions, directory_sync_state, app_roles…)
```

93 tables, 16 views. Every document numbers itself through `app.next_number()`; every state-changing table has
`created_at`/`updated_at` with the touch trigger; the ledger and the activity log are immutable.

## 2. The rules the schema enforces

- **A lot is one received or produced quantity of an item** with a `source_kind`/`source_id` (receipt line, run output,
  packaging run, adjustment, opening, split), a quality status, a unit cost, and **its weight** (`weight_kg`) and
  **weight per base unit** (`unit_weight_kg`: 1 when the base unit is kg, else the ticket's or the theoretical weight
  per piece — the trigger `lots_default_unit_weight` fills it).
- **The ledger** (`inventory_transactions`): one signed row per (item, lot, location) in the item's base unit, with
  `weight_kg` beside it (derived from the lot's unit weight when not given), the site snapshotted from the location,
  a `report_category` for the period reports, a `reference_kind`/`reference_id` to its document and an idempotency
  key. Balances (`qty_on_hand`, `weight_on_hand_kg`, `qty_allocated`) are kept by trigger and recomputable.
  **Interlock 1:** nothing unreleased is issued, packaged or shipped (moving it is fine). **Interlock 2:** no negative
  stock unless the location allows it. No tax state: that was the cidery's.
- **Attributes (D5):** `attribute_definitions` is the dictionary (kind, unit, choices, where it applies, `inherit`,
  `in_code`); `item_class_attributes` says which a class carries and requires; values sit on items, products and lots.
  `app.lot_attributes_fill(lot, parent_lot, explicit, source, by)` writes a lot's attributes in three layers: the
  item's values (source `derived`), then the parent lot's inheritable ones (`inherited` — heat, grade, coating, mill,
  the MTR's mechanicals), then explicit values (`manual`, `certificate`, `run`, …). Later layers win. This is how a
  cut sheet carries its coil's heat and its own length.
- **The run (D3, the exemplar):** `runs` is one operation on one machine in one sitting; `run_inputs` (one primary),
  `run_outputs` (product, co_product, scrap, rework — the lot is created at post, from the output item's class
  sequence, with `lot_attributes_fill` from the primary input), `run_consumables` (explicit or backflushed). Posting
  writes `consumptions`, the ledger (issue the inputs, production_output the outputs, scrap as `scrapped`),
  `lot_lineage` (child ← parent, `fraction` by weight) and the run's totals (`input_weight_kg`, `output_weight_kg`,
  `co_product_weight_kg`, `scrap_weight_kg`, `loss_weight_kg`, `yield_pct`). The handler does this in step 4; the
  proof does it in SQL today.
- **Process specs** are the generic recipe: immutable once active (the guard refuses a step or input change), one
  active per product, `output_item_id` and `planned_qty_base`, steps with an operation, an equipment kind, an
  expected loss and a time, inputs per base unit of output or per run.
- **Specs and readings:** a spec is per product per operation per measurement type; `readings_evaluate_spec` grades
  a run's reading against its production order's product (and a finished lot's against its product).
- **Equipment (D6):** kinds are data; `capabilities` is JSON keyed by attribute key with `min`/`max` (`weight_kg` is
  the lot's weight); `app.equipment_fits(equipment, item, lot)` answers one warning per limit exceeded. Reservations
  are one machine × one window for a run (production order, run, packaging run) or a block; `equipment_clashes()` and
  `v_equipment_schedule` as the cidery had them; the double-booking switch is `settings.equipment.double_booking`,
  `refuse` by the column default.
- **Packaging:** a packaging run takes lots of a product through a packaging configuration (pieces per package, max
  weight, the materials BOM) into a finished lot (`finished_lots`: packages, pieces per package, package weight,
  `heat_numbers[]`, the product, the production order); lineage records it.
- **Shipping (D8):** `shipments` is the bill of lading (direction out, or in for a return; carrier, trailer, status
  draft → posted → reversed), `shipment_lines` a lot × quantity × weight with `product_qty_base` (pieces of the
  product, so an order line in pieces is satisfied by skids) and the order line.
- **Orders (D9):** a line is a product × quantity × weight × optional package × price with `price_basis` (per_unit,
  per_kg, per_lb, per_cwt, per_package); `line_total` is generated from the basis. `v_sales_order_lines` says what
  shipped, what is in packaging and in production, what is open; `v_demand` merges firm, standing and forecast.
- **Reports (D7):** `report_line_map` derives a report's lines from the ledger (`report_category`), losses
  (`classification`), shipments (`direction`), balances and runs by a JSON match; three generic reports are seeded
  (`production`, `yield_scrap`, `shipments`); `period_reports` and `period_report_lines` hold a generated period,
  split by `group_key` (an item class or a product family).
- **Trace:** `trace_forward(lot)` walks `lot_lineage` down to the shipments; `trace_backward(lot)` walks up to the
  received lots with their supplier and certificates; `heat_where_used(heat)` is the recall question.
- **Costing (D11):** `v_run_costs` = material at lot cost + consumables at standard + overhead per kg of input (per
  site) − scrap credit at the scrap item's standard; `v_product_costs` rolls an order's posted runs up against the
  spec's standard. Valuation by class and site at lot or standard cost.
- **Profiles (D12):** everything an industry names is a row: units (all seeded in the core), item classes with lot
  nouns and sequences, the attribute dictionary, operations, measurement types, equipment kinds, reason codes,
  reference tables (`reference_values`: gauge charts, densities), number formats, display units, dashboard tiles.
  `db/profiles/steel/seed.sql` is applied once by `deploy/os-provision.sh` (`PROCESS_PROFILE`, default `steel`,
  recorded as `profile:steel`) and by `deploy/provision-client.sh`. The core seeds only the built-in classes, the
  built-in reason codes and equipment kinds, and the three reports.

## 3. The steel seed, in numbers

| | |
|---|---|
| Item classes | `coil` (serialized, catch weight, Coil, `C-YY-NNNNN`), `slit_coil`, `sheet` (`S-`), `blank`, `scrap` (`X-`); finished goods are Skids (`K-`); density 7,850 kg/m³ |
| Attributes | 24: grade, spec, thickness_in, gauge, width_in, length_in, coating (choice), finish (choice), heat, mill, country_of_melt, mtr_no, piw, yield_ksi, tensile_ksi, elongation_pct, hardness_hrb, chem_c/mn/p/s/si, edge, pieces_per_package — heat, grade, coating, finish, mill and the mechanicals inherit; width and length do not |
| Operations | slit, cut_to_length, shear, blank, level, pack (terminal), inspect |
| Measurement types | 14: thickness, width, length, flatness (I-unit), camber, crown, squareness, burr, hardness, yield, tensile, elongation, coating weight, weight |
| Equipment kinds | slitter, cut_to_length_line, shear, leveler, blanking_press, laser, plasma, saw (+ the built-in packaging_line, scale, crane, forklift, other) |
| Reason codes | TRIM, ENDS, SETUP (expected scrap), OFFGAUGE, SURFACE, CAMBER (exceptional), RUST (damage) (+ the nine built in) |
| Reference tables | `gauge_sheet_steel` (3–30 ga, 16 ga = 0.0598 in, 10 ga = 0.1345 in), `gauge_galvanized` (8–30 ga, 16 ga = 0.0635 in), `density_kg_m3` |
| Display | lb, in, ft²; six dashboard tiles |

## 4. What the proof works through (scripts/prove-schema.sql)

A mill, a 400 cwt purchase order, a receipt of one 8,273 kg coil with a weigh ticket (gross 10,133, tare 1,860) and
an MTR (heat 7A1234, yield 41.2 ksi) whose values land on the lot; the receipt posts to the yard; the quarantined coil
cannot be issued but can be moved; released on the certificate; the negative-stock interlock, an allow-negative
location, a reversal, immutability, idempotency, the rebuild. A product "Sheet 16 ga × 48 × 120 A1011 CS-B" with a
two-step process spec (cut to length on a cut-to-length line at 1.5 % expected loss, then pack), activated and
immutable, three specs. Two machines with capabilities: CTL-1 takes the 48 in coil, Slitter 36 warns. A production
order WO-00001 and the run RUN-00001 on CTL-1: the coil in, 170 sheets (7,533 kg), a 640 kg remnant coil and 100 kg of
scrap out, banding backflushed; readings graded (thickness and length pass, flatness fails); the output lots numbered
S-, C-, X- by class, the sheets inheriting heat, grade, mill and the MTR's yield while taking their length from the
item and their sheared edge from the run; lineage fractions summing to 1; yield 91.06 %; the cost views; a booking
on the schedule and a shared maintenance block as its one clash. The head-and-tail loss, the scrap sold to a dealer.
Trace forward from the coil, backward from the sheets to the mill and the MTR, the heat's four lots. Packaging 150
sheets into 3 skids (finished lot K-, heats inherited, 2,215.5 kg each), FIFO rank only once released. A customer
order with a per-cwt line (150 pieces, 6,646.5 kg, $62.50/cwt = $9,158.86) and a per-unit line; BOL-00001 of the
three skids posts; the order line shows 150 shipped and 0 open; the trace ends at the shipment. A weekly standing
order with 4 occurrences in 4 weeks; the demand view's firm, standing and forecast rows (the forecast reduced by the
standing demand of its week). A yield-and-scrap period report with its 8 lines. The read roles see the views and
functions and never the auth material.
