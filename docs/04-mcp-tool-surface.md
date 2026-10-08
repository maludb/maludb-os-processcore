# MCP tool surface (Phase 1)

**Date:** 2026-10-01
**Status:** Phase 1 deliverable for approval, alongside the schema in `db/` and [05-action-manifest.md](05-action-manifest.md).
**Contract:** every record question R1 to R54 and activity question A1 to A12 in [03-phase0-plan.md](03-phase0-plan.md) has a named tool here. A question with no tool is unfinished design.

Two client-facing read servers per client, per the mcp-servers skill. Python + FastMCP, streamable HTTP, stateless JSON, bearer tokens from `app.mcp_access_tokens`, read-only database roles from `db/020_grants.sql`. The localhost-only actions server is specified in the action manifest.

| Server | Name | Role | Backing |
|---|---|---|---|
| Records | `processcore_records_mcp` | `processcore_records_ro` | `app.*` tables, views in `db/012_costing_views.sql`, `app.trace_forward`, `app.trace_backward` |
| Activity | `processcore_activity_mcp` | `processcore_activity_ro` | `app.activity_log`, the `memory` schema facades (`maludb_episode`, `maludb_memory_search`, `maludb_episode_get`, `text_search`) |

Endpoints: `https://{client}.{domain}/mcp/records` and `/mcp/activity` (domain pending, see 03 section 6 item 8).

## Conventions

- Tool names are `snake_case`, verb first, prefixed by area (`receiving_`, `inventory_`, `recipe_`, `production_`, `batch_`, `packaging_`, `keg_`, `quality_`, `cost_`, `compliance_`, `trace_`, `activity_`).
- Every tool: `readOnlyHint: true`, `openWorldHint: false`, Pydantic input with `extra="forbid"`, `limit` (1 to 200, default 50) and `offset` where a list can be long.
- Entity resolution: tools accept human labels (`lot_number`, `batch_number`, `item` name or code, `product` name, `vessel` name, `supplier` name) and resolve them server side with `ILIKE` and trigram similarity; ambiguity returns the candidates. Ids are accepted where the caller already has them.
- Units: quantities are returned in base units with the item's `base_unit_code`, plus a `display` object converted to the client's display units from `app.client_settings`. Volumes in liters and gallons; masses in kilograms and pounds; fruit also in tons and bushels.
- Dates: `date_from` and `date_to` are inclusive ISO dates; defaults are the current period.
- Every call is logged to `app.activity_log` with `source = 'mcp'` and `actor_label = 'mcp/token:{name}'` (this is question A12).
- Errors are actionable sentences, never stack traces.

## Records server: tools by question

### Receiving and purchasing

| Tool | Answers | Input | Returns | Backing |
|---|---|---|---|---|
| `receiving_open_orders` | R1, R5 | `date_from?`, `date_to?`, `supplier?`, `overdue_only=false` | PO lines outstanding with expected date, supplier, item, quantity | `app.v_open_po_lines` |
| `receiving_receipt_vs_order` | R2 | `receipt_number` or `po_number` | Each line: ordered, received, discrepancy kind and note | `goods_receipt_lines` join `purchase_order_lines` |
| `receiving_receipt_lots` | R3 | `receipt_number` | Lots created, supplier lot numbers, whether a CoA is attached and which values were captured | `goods_receipt_lines`, `lots`, `certificates_of_analysis`, `lot_attributes` |
| `receiving_lot_status` | R4 | `lot_number` | Quality status, last release decision, who and when, basis | `lots`, `release_decisions` |
| `receiving_price_history` | R6 | `item`, `date_from?`, `date_to?`, `group_by=month` | Unit cost per base and display unit over time, by supplier; for fruit also per pound and per ton | `goods_receipt_lines`, `goods_receipts`, `weigh_tags` |
| `receiving_supplier_performance` | R7 | `supplier?`, `date_from?`, `date_to?` | Receipts, late receipts, short and damaged lines per supplier | `app.v_supplier_performance` |
| `receiving_fruit_intake` | R8 | `season_year?`, `variety?`, `orchard?` | Net kg and lb by variety and orchard, Brix at receipt, lot numbers | `weigh_tags`, `goods_receipt_lines`, `lots` |

### Inventory

| Tool | Answers | Input | Returns | Backing |
|---|---|---|---|---|
| `inventory_on_hand` | R9 | `item?`, `item_class?`, `location?`, `lot_number?`, `include_zero=false` | On hand, allocated, available by item, lot, location with quality status and expiry | `app.v_lot_balances` |
| `inventory_rack_stock` | R9 | `rack?`, `area?`, `product?`, `item?`, `item_class?`, `released_only=false` | What is on each rack: lot, batch, stock date, use-by, quality, on hand and available, and `fifo_rank` (1 = pick next) | `app.v_fifo_stock` |
| `inventory_available_after_orders` | R10 | `item?` | On hand, allocated by open production orders, net available | `app.v_item_stock`, `allocations` |
| `inventory_pick_order` | R11 | `item`, `qty_base?`, `expiring_within_days?` | Lots in FEFO order (expiry, then received date), released only, with on hand | `app.v_lot_balances`, `lots` |
| `inventory_below_reorder` | R12 | `item_class?` | Items under reorder point with on hand, on order, shortfall | `app.v_item_stock` |
| `inventory_adjustments` | R14 | `date_from?`, `date_to?`, `location?`, `reason?` | Posted adjustments with reason, lines, actor | `inventory_adjustments`, lines, `inventory_transactions` |
| `inventory_last_count` | R15 | `location` | Last count: when, who, variance per line, resulting corrections | `inventory_counts`, `inventory_count_lines` |
| `inventory_slow_movers` | R17 | `months=6`, `item_class?` | Items with stock and no issue or removal in the window | `inventory_transactions`, `app.v_item_stock` |
| `inventory_movements` | R14, R17 (long tail) | `item?`, `lot_number?`, `location?`, `txn_type?`, `date_from?`, `date_to?` | The ledger rows matching, newest first | `inventory_transactions` |

### Recipes and products

| Tool | Answers | Input | Returns | Backing |
|---|---|---|---|---|
| `recipe_current` | R18 | `product`, `batch_volume_l?` | Active version with stages, expected losses, lines scaled to the requested volume | `recipe_versions`, `recipe_stages`, `recipe_lines` |
| `recipe_diff` | R19 | `product`, `from_version`, `to_version` | Added, removed, changed lines and stages, change notes, who activated and when | `recipe_versions` and children |
| `recipe_batches_made` | R20 | `product`, `version?` | Batches per recipe version with status and dates | `batches` |
| `recipe_can_make` | R21 | `product`, `batch_volume_l` | Each line: required, available (released stock), shortfall | `recipe_lines`, `app.v_item_stock` |
| `recipe_standard_cost` | R22 | `product`, `batch_volume_l?` | Line costs at standard or last lot cost, overhead, total, per liter | `recipe_lines`, `items`, `overhead_rates` |
| `product_approvals_needed` | R50 | `status?` | Products whose formula or label approval is required, submitted, expired | `product_approvals`, `products` |
| `product_find` | helper | `query` | Products matching with codes, status, active recipe version | `products` |

### Production and batches

| Tool | Answers | Input | Returns | Backing |
|---|---|---|---|---|
| `production_tank_board` | R23 | `premises?`, `vessel?` | Every vessel: occupant (juice lot or batch), volume, fill percent, stage, since when | `app.v_vessel_board` |
| `production_batches_in_progress` | R24 | `product?`, `stage?` | Active batches with stage, volume, planned package date, days in stage | `batches`, `stage_events`, `production_orders` |
| `production_press_runs` | R25 | `date_from?`, `date_to?` | Press runs with fruit in, juice out, pomace, yield per ton and bushel | `press_runs`, `app.v_press_run_yields` |
| `production_orders_by_status` | R26 | `status?` | Orders with product, planned volume, dates, vessels, the equipment plan (every booking with its days, shared mark and overlaps), allocations, batches | `production_orders` and children, `app.v_equipment_schedule` |
| `production_order_shortages` | R13 | `order_number?` | Per open order: required lines vs available vs on order | `production_orders`, `recipe_lines`, `app.v_item_stock` |
| `equipment_schedule` | E1 | `vessel?` or `equipment?`, `kind?`, `premises?`, `date_from?`, `date_to?`, `order?` or `batch?` | What is booked on which tank, press, line or equipment, when and for which run; each booking's role, days, times, shared mark and overlaps | `app.v_equipment_schedule` (db/023) |
| `equipment_free` | E2 | `kind`, `days`, `min_capacity_l?`/`min_capacity_gal?`, `premises?`, `date_from?`, `date_to?` | Every resource of the kind with its free windows of at least `days`, earliest first | `app.v_equipment_resources`, `app.v_equipment_schedule` |
| `find_equipment` / `find_press_run` / `find_reservation` | helper | `q` | Resolvers: equipment by name; press runs by number; a booking by its resource or run (or `id:`) | `equipment`, `press_runs`, `app.v_equipment_schedule` |
| `batch_find` | helper | `query` | Batches matching by number or product | `batches` |
| `batch_consumptions` | R27, R28 | `batch_number`, `purpose?`, `stage?` | Lots consumed with quantity, purpose, stage, when, by whom | `consumptions`, `lots` |
| `batch_blends` | R29 | `batch_number` | Blend events in and out with volumes and fractions | `batch_blends`, `batch_blend_inputs`, `batch_lineage` |
| `batch_genealogy` | R30 | `batch_number` or `vessel` | Parents and children recursively with volumes, plus fruit and juice lots at the root | `batch_lineage`, `app.trace_backward` |
| `batch_readings` | R31, R41, R43 | `batch_number` or `lot_number`, `measurement?`, `date_from?`, `date_to?` | Readings in time order with spec result; the fermentation curve is `measurement=sg` or `brix` | `readings`, `specs` |
| `batch_losses` | R33 | `batch_number`, `stage?` | Loss events with reason, category, classification, approval | `loss_events` |
| `batch_stage_history` | R23, R32 | `batch_number` | Stage events with volumes in and out | `stage_events` |
| `co_product_dispositions` | R52 | `date_from?`, `date_to?` | Pomace lots and where they went | `co_product_dispositions` |

### Packaging, finished goods, kegs

| Tool | Answers | Input | Returns | Backing |
|---|---|---|---|---|
| `packaging_run_losses` | R35 | `run_number?`, `last_n=5` | Volume in, units out, volume out, loss liters and percent vs expected | `packaging_runs`, `packaging_configurations` |
| `packaging_finished_stock` | R36 | `product?`, `package_kind?`, `location?` | Finished lots on hand and available by product and package, tax class, best before | `app.v_finished_stock` |
| `packaging_material_needs` | R37 | `date_to?` | For planned orders near packaging: BOM quantities needed vs on hand | `production_orders`, `packaging_configurations`, `packaging_bom_lines`, `app.v_item_stock` |
| `packaging_lots_for_batch` | R38 | `batch_number` or `lot_number` | Finished lots from a batch, or the batch behind a finished lot | `finished_lots` |
| `packaging_tax_class_check` | R49 | `lot_number` or `batch_number` | ABV, CO2, fruit share, other fruit and flavoring flags, derived class, override if any, margin to each limit | `finished_lots`, `batches`, `app.derive_tax_class` |
| `keg_fleet` | R39 | `state?`, `customer?`, `older_than_days?` | Kegs by state and holder with days since moved; summary counts | `app.v_keg_fleet` |
| `keg_history` | R39 | `serial` | Movements for one keg | `keg_movements` |

### Quality

| Tool | Answers | Input | Returns | Backing |
|---|---|---|---|---|
| `quality_out_of_spec` | R41 | `batch_number?`, `days=30` | Readings that failed spec, with the spec range | `readings`, `specs` |
| `quality_release_queue` | R42 | — | Batches and lots awaiting release, with latest readings and sensory | `batches`, `lots`, `readings`, `sensory_records` |
| `quality_release_history` | R42 | `batch_number` or `lot_number` | Release decisions: who, when, basis, override | `release_decisions` |
| `quality_sensory` | R44 | `batch_number`, `date_from?` | Sensory records with verdicts, attributes, faults | `sensory_records` |

### Costing and finance

| Tool | Answers | Input | Returns | Backing |
|---|---|---|---|---|
| `cost_batch` | R45, R40 | `batch_number` | Material, packaging, overhead, total, per liter, variance to standard, cost per keg and per case by package | `app.v_batch_costs`, `finished_lots` |
| `cost_inventory_valuation` | R16, R46 | `as_of?`, `group_by=item_class|tax_state|location` | Quantity and value by group | `app.v_inventory_valuation` (as-of uses the ledger) |
| `cost_stage_yields` | R32 | `batch_number` or `product` with `last_n` | Per-stage actual vs expected loss | `app.v_batch_stage_yields` |
| `cost_juice_yield_by_variety` | R34 | `season_year?`, `variety?` | Gallons per ton and per bushel by variety, press run count | `app.v_press_run_yields` |

### Compliance and traceability

| Tool | Answers | Input | Returns | Backing |
|---|---|---|---|---|
| `compliance_period_summary` | R47 | `premises?`, `period_start`, `period_end` | Produced, bottled, removed tax paid, removed in bond, losses, by tax class, in gallons, with the line codes | `ttb_line_map`, `inventory_transactions`, `loss_events`, `removals` |
| `compliance_bulk_vs_bottled` | R48 | `premises?`, `as_of?` | Gallons in bulk and packaged by tax class | `vessel_occupancies`, `batches`, `app.v_finished_stock` |
| `compliance_removals` | R51 | `destination_kind?`, `customer?`, `date_from?`, `date_to?` | Removals with lots, units, gallons, tax | `removals`, `removal_lines` |
| `compliance_report` | R47 | `report_number` or `premises` + `period` | A generated report's lines and totals, with source ids for drill-down | `period_reports`, `period_report_lines` |
| `trace_forward` | R53 | `lot_number` | Batches, finished lots, removals and customers downstream | `app.trace_forward` |
| `trace_backward` | R54 | `lot_number` (finished) or `batch_number` | Parent batches, ingredient lots, fruit lots, suppliers upstream | `app.trace_backward` |

### Long tail

| Tool | Input | Rules |
|---|---|---|
| `records_search` | `sql` (one SELECT), `limit<=200` | Parsed and rejected unless a single `SELECT` or `WITH ... SELECT`; no semicolons; runs under `processcore_records_ro` with `statement_timeout = 15s` and the row cap; description embeds a schema summary generated from `information_schema` at startup (tables, columns, the views). Auth tables are not readable by the role, so they never appear. |

## Activity server: tools by question

The activity server reads `app.activity_log` directly for precise timelines and the `memory` schema for search and replay. Episode payloads hold the full activity row, so either path answers.

| Tool | Answers | Input | Returns | Backing |
|---|---|---|---|---|
| `activity_record_history` | A1, A5, A10 | `entity_type`, `entity_id` or label, `date_from?`, `date_to?` | Every event on the record in order: actor, action, before and after, screen, source | `activity_log` |
| `activity_actor_timeline` | A2, A4, A7 | `actor` (name or id), `date_from?`, `date_to?`, `screen?` | What one person did, in order, including screens entered | `activity_log` |
| `activity_who_did` | A1, A3, A5, A6, A8 | `action` (e.g. `receipt_posted`, `lot_released`, `production_order_created`, `po_approved`, `count_approved`), `entity_label?`, `date_from?` | Who performed the action on what and when, with the preceding screen trail per session | `activity_log` |
| `activity_before_and_after` | A4, A2 | `activity_id` or (`actor`, `at`), `window_minutes=30` | The events around one event in the same session | `activity_log` |
| `activity_elapsed` | A6, A8 | `start_action`, `end_action`, `entity_type`, `entity_id?` | Time between two actions per entity (PO created to approved; count started to approved) | `activity_log` |
| `activity_screen_usage` | A7 | `date_from?`, `date_to?`, `group_by=actor|screen|hour` | Screen entries aggregated | `activity_log` |
| `activity_untouched` | A9 | `entity_type`, `screen`, `since_days=365` | Entities with no screen entry since the date | `activity_log` against `app` entity tables |
| `activity_day_replay` | A10 | `date`, `entity_type?`, `entity_id?` | Every event that day touching the entity, in order, with payloads | `activity_log`, `maludb_episode_get` |
| `activity_assistant_actions` | A11 | `actor?`, `date_from?` | Actions with `source in (command_bar, ama)` and whether an `action_undone` followed | `activity_log` |
| `activity_mcp_usage` | A12 | `date_from?`, `token?` | MCP tool calls by token with the tool and arguments summary | `activity_log` where `source = 'mcp'` |
| `activity_search` | long tail | `query` text, or `subject?` and `verb?`, `date_from?`, `date_to?` | Full-text and subject-verb search over episodes, newest first | `memory.text_search`, `memory.maludb_memory_search`, `memory.maludb_episode` |
| `activity_sql` | long tail | `sql` (one SELECT) | Same guard as `records_search`, over `app.activity_log` and the `memory` views only | role-limited |

## Evaluation set

The sixty-six questions in 03 sections 3.1 and 3.2, phrased as a person would type them, each paired with the tool expected to answer it. Phase 4 runs the set with MCP Inspector and the AMA agent; a miss is a tool or description bug, not a question bug.
