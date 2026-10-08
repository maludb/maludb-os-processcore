# ProcessCore — plan (a generic processing ERP, forked from Cidery; steel processing the default profile)

**Date:** 2026-10-08
**Status:** APPROVED 2026-10-08 — the owner took every recommendation of section 12 (D1–D19); section 16 records it.
The build order of section 13 is under way; `docs/processcore-progress.md` is the record step by step. Before step 1 this
repository was a verbatim fork of `maludb-os-cidery` at its commit `adf4733` (equipment scheduling, 2026-10-08), history
kept, pushed to `github.com/maludb/maludb-os-processcore` (private) and cloned at `/srv/apps/processcore`. When the
answers are in, step 1 of section 13 begins; the design doc with the schema files follows the cidery's own pattern
(plan → design + `db/` → progress), proven on a scratch database before a screen is written.

**The ask (2026-10-08):** create a new Business OS application, ProcessCore, in a new repository `maludb-os-processcore`:
a base manufacturing application with the same process flow as `maludb-os-cidery` that can easily be the base for
manufacturing ERP applications; the processes modelled in the default version are steel processing — for example the
cutting and processing of rolled steel into cut sheets. Start by forking the cidery, then plan the changes.

## 1. Goal

One application that knows **converting processes** and nothing of any one industry: material arrives as lots, is
transformed by **runs** on **equipment** into other lots (products, co-products, scrap), is packed, released by quality
and shipped — every quantity on the inventory ledger, every lot traceable to what it came from, every question
answerable by an agent, every action a tool. What makes it steel, cider, paper or lumber is a **profile**: seed data,
vocabulary and skills. The default profile is a steel service center: master coils in, slit coils, cut sheets and blanks
out, scrap sold by weight, certificates following the heat.

## 2. What ProcessCore is, and is not

- **Is:** the base for process and converting manufacturers that buy material in bulk and cut, slit, shear, level,
  blank, portion or pack it to order — steel and aluminium service centers (the default), paper and board converters,
  plastics film, lumber, textiles, food portioning. The cidery's flow, with its beverage layers removed:
  receive → lots on the ledger → production orders → runs on equipment → packaging → quality release → shipments,
  plus customer orders, planning, costing, equipment scheduling, trace, the two MCP servers, the expert agent.
- **Is not:** an assembly MRP (no multi-level bills of material, no routings across sub-assemblies — a run has inputs
  and outputs, and a process spec is a short sequence of runs); a finance system (no books: the General Ledger reads it
  through K7); the cidery (continuous fermentation in vessels, TTB, tax classes, kegs stay there — section 3 says what
  goes and D3 asks).
- **The rule that makes it a base:** *industry is data, not code.* The PHP, the MCP servers and the manifest know
  items, item classes, lots, operations, process specs, runs, equipment, orders and shipments. No file says "coil". The
  word "Coil" appears because the steel profile names the `coil` item class and gives it the lot noun "Coil".

## 3. The cidery, concept by concept — keep, generalize, remove

| Cidery | Where | ProcessCore | Why |
|---|---|---|---|
| `client_settings` (display units volume/mass/fruit) | db/004 | **Keep.** Display units become mass, length, area, count; `fruit_display_unit` goes; `settings.profile` names the profile | Every profile needs display units; fruit was cider's |
| `premises` (a TTB permit: kind, form, filing, tax point, CBMA tier) | db/004 | **`sites`** — a plant or yard: name, code, timezone, address; the permit columns go | A site is the generic of a bonded premises |
| `locations` (kind, `tax_state`) | db/004, db/015 racks | **Keep**; kinds `yard, bay, rack, dock, line_side, finished_goods, shipping, scrap, outside`; `tax_state` goes; racks (db/015: areas, rack numbers, the rack board) stay — coil saddles and sheet racks are racks | Stock lives somewhere; bonded/tax-paid was cider's |
| `units` (volume, mass, count) | db/004 | **Keep + length (base m: mm, in, ft), area (base m²: ft²), mass + cwt and metric tonne**; `bushel` goes to the beverage profile | Steel is sold per cwt and sized in inches |
| `items`, `item_classes` (db/017 made classes data) | db/004, db/017 | **Keep.** `ttb_material_category` goes; `catch_weight` stays (a coil's weight is the ticket's); + `serialized` (one lot = one unit) on the class; + `lot_noun` on the class ("Coil", "Skid", "Bundle"); + **dimensional attributes** (D5) | Classes are already data — the profile seeds them |
| `item_units`, `suppliers`, `supplier_items` | db/004 | **Keep**; supplier kinds `mill, distributor, processor, packaging, services, other` | — |
| `reason_codes` (`ttb_category`) | db/004 | **Keep**; `ttb_category` → `report_category` (`none, expected_scrap, exceptional_scrap, damage, count, correction, other`); seeded by the profile | The report category is generic; the TTB words were not |
| `attachments` | db/004 | **Keep**; kinds `certificate, weigh_ticket, drawing, photo, spreadsheet, bol, packing_list, other` | — |
| purchase orders, receipts, lots, `lot_attributes` | db/005 | **Keep verbatim.** A receipt line is one coil = one lot; the profile names the attribute keys (`heat`, `grade`, `spec`, `thickness_in`, `width_in`, `length_in`, `coating`, `mill`, `country_of_melt`, `yield_ksi`, `tensile_ksi`, `elongation_pct`, `c`, `mn`, `p`, `s`, `si`, …) | The receiving exemplar is already generic |
| `weigh_tags` (gross, tare, net, bin count, variety, orchard, block, brix) | db/005 | **`weigh_tickets`**: ticket number, scale, gross, tare, net, weighed at/by; the fruit columns become lot attributes | Every scale ticket is gross − tare |
| `certificates_of_analysis` | db/005 | **`certificates`**: kind `mtr, coa, conformance, other`, issuer, number, heat, issued on, parsed values JSON → lot attributes; the file an attachment | The mill test report is the certificate of analysis of steel |
| `release_decisions` | db/005 | **Keep**; basis `certificate, inspection, readings, override, other`; `target_kind` `lot` only | — |
| the ledger: `inventory_transactions`, balances, interlocks, transfers, adjustments, counts | db/006 | **Keep.** `tax_state`, `ttb_category` and the tax-state interlock go; `counterparty_kind` and `reference_kind` say `run` where they said `press_run`/`batch_*`/`yeast_harvest`; + `weight_kg` beside `qty_base` on transactions, balances, lots and run lines (D4) | Metals count pieces and weigh everything |
| `products` (beverage type, tax class, ABV, fruit share, flavoring) | db/007 | **Keep** as the spec that can be made: code, name, `family`, status, notes; + product attributes (D5); the beverage columns go | A product is a specification |
| `stages` (press, pitch, primary, …, `beverage_types[]`) | db/007 | **`operations`**: code, name, kind `convert, pack, inspect`, display order; seeded by the profile (steel: `slit, cut_to_length, shear, blank, level, pack, inspect`) | A stage was an operation with a cider name |
| `recipe_versions`, `recipe_stages`, `recipe_lines` | db/007 | **`process_specs`** (product, version, status, planned output per run, change note, activation — same immutability guard), **`process_spec_steps`** (seq, operation, equipment kind, expected yield loss %, setup minutes, rate per base unit, instructions), **`process_spec_inputs`** (seq, item, qty per base unit of output or per run, purpose `primary_material, consumable, packaging`, explicit/backflush) | The recipe was a routing with ingredients |
| `measurement_types`, `specs` (per product per stage) | db/007 | **Keep**; per product per **operation**; seeded by the profile (thickness, width, length, flatness I-units, camber, crown, hardness HRB, yield ksi, tensile ksi, elongation %, coating weight oz/ft², squareness, burr) | — |
| `packaging_configurations` (keg/can/bottle, fill volume), `packaging_bom_lines` | db/007 | **Keep**: package kind `skid, bundle, coil, pallet, crate, box, other`, `qty_per_package_base`, `max_weight_kg`, the materials BOM (skids, banding, paper, wrap) | A skid spec is a packaging configuration |
| `standard_costs`, `overhead_rates` (per L per premises) | db/007 | **Keep**; overhead per kg per site (D11) | — |
| `product_approvals` (formula, COLA) | db/007 | **Remove** (customer specifications and PPAP are Extended) | TTB only |
| `production_orders` (`planned_volume_l`, pitch/package dates) | db/008 | **Keep**: `planned_qty_base`, `planned_weight_kg`, `planned_start_on`, `planned_finish_on`, `due_on`, `priority`; the link to the customer order line stays (`production_order_packages`, db/016) | — |
| `production_order_vessels` (a view since db/023) | db/008, db/023 | **Remove** (bookings are `equipment_reservations`) | — |
| `allocations` | db/008 | **Keep** | — |
| `batches`, `batch_lineage`, `stage_events`, `batch_transfers`, `batch_splits`, `batch_blends`, `vessel_occupancies`, `yeast_harvests` | db/008 | **Remove from the core** (D3). The unit of execution is the run | A batch is a continuous quantity living in a vessel for weeks: beverage, dairy, chemicals — the cidery keeps it |
| `press_runs`, `press_run_inputs`, `press_run_outputs` | db/008 | **`runs`** — THE EXEMPLAR (section 5): number, site, production order (nullable: stock processing), operation, process spec step, equipment, status `draft, in_progress, posted, cancelled`, started/finished, totals in and out (base and kg), yield; **`run_inputs`** (lot, qty, weight); **`run_outputs`** (kind `product, co_product, scrap, rework`, item, lot created at post, qty, weight, location, attributes written to the new lot); **`run_consumables`** (item, lot, qty, explicit/backflush) | The press run is the generic shape: lots in, lots out, a yield |
| `consumptions` | db/008 | **Keep** with `run_id` (the ledger side of inputs and consumables) | — |
| `loss_events`, `readings`, `co_product_dispositions` | db/008 | **Keep**: targets `run, lot, equipment`; losses in the item's unit; dispositions `scrap_sale, recycle, waste, rework, return_to_stock, other` | — |
| `lot_lineage` (new) | — | **New**: child lot ← parent lot, run, fraction by weight — written at post; `trace_forward`/`trace_backward` run on it | Heat inheritance: every slit coil and sheet carries its parent's heat |
| `tax_class_rules`, `derive_tax_class` | db/009 | **Remove** | — |
| `packaging_runs`, materials, `finished_lots` (batch, ABV, CO₂, fruit share, tax class) | db/009 | **Keep**: a packaging run takes lots (run outputs or stock) through a packaging configuration into finished lots; `finished_lots` carries the run, pieces, `unit_weight_kg`, `heat_numbers[]` for the packing list; the beverage columns go | — |
| `kegs`, `keg_movements` | db/009 | **Extended as `containers`** (D10) | Returnable racks and cradles exist, not in v1 |
| `sensory_records` | db/010 | **`inspections`**: visual/dimensional inspection of a lot or run with a verdict and typed attributes JSON | A sensory panel is an inspection |
| `customers` (kind, default destination, permit) | db/011 | **Keep**: kinds `oem, fabricator, distributor, contractor, scrap_dealer, other`; ship-to address | — |
| `removals`, `removal_lines` (destination kinds, tax) | db/011 | **`shipments`**, **`shipment_lines`**: BOL number, carrier, trailer, ship-from location, customer, direction out/in (a return), status `draft, posted, reversed, cancelled`, lines = finished lot × pieces × weight × customer order line; a printable packing list and BOL (D8) | A removal is a shipment without the tax |
| `ttb_line_map`, `period_reports`, `period_report_lines` | db/011, db/014 | **Keep the mechanism as `report_line_map` + `period_reports`** (D7): a report is lines derived from the ledger, losses and shipments by a match rule; the profile seeds "Production", "Yield and scrap", "Shipments" per site per month; the TTB forms go | The derivation engine is good; the forms were cider's |
| costing views, trace functions | db/012 | **Keep**, rewritten over runs and `lot_lineage` (`v_run_yields`, `v_run_costs`, `v_product_costs`) | — |
| `activity_log`, auth, `mcp_access_tokens`, OS adoption (SSO, directory sync, app roles) | db/003, db/013, db/021 | **Keep**; roles renamed (section 8) | — |
| customer orders, standing orders, imports, forecasts, `v_demand` | db/016 | **Keep**: a line is a product × pieces × weight × due date × price with a **price basis** (D9) | — |
| tank view | db/022 | **Remove** | — |
| `equipment`, `equipment_reservations`, the schedule, the switch | db/023 | **Keep**; `v_equipment_resources` is equipment only; kinds `slitter, cut_to_length_line, shear, leveler, blanking_press, laser, plasma, saw, crane, forklift, scale, packaging_line, other`; + **`equipment_capabilities`** (D6) | The newest cidery feature is already generic |

What this leaves is a schema of roughly 60 tables (the cidery's 70 less the beverage layers plus runs, lineage,
attributes, capabilities and shipments), in **new numbered files written in place** (D2).

## 4. The steel profile (the default)

What a steel service center does, in the words the profile seeds. (Grounding: the vendor literature agrees that the
two facts a steel ERP must get right are **heat inheritance** — a slit or cut child carries the parent's heat and grade
and its certificate can be reprinted from the child — and the **weight balance** of every operation, input against
output with the trim and ends as scrap at a recovery value; sequence-cast coils can carry two heats.)

- **Material:** master coils from mills — hot-rolled, pickled and oiled, cold-rolled, galvanized, galvannealed,
  aluminized, stainless — by **heat** with a **mill test report** (chemistry, yield, tensile, elongation, coating). A
  coil is one lot: tag number, mill coil id, heat, grade and spec (ASTM A1011 CS-B, A1008, A653 G90 …), thickness,
  width, scale weight. Stored in the yard on saddles, by location.
- **Operations:** **slit** (one coil → several narrower coils, the mults, plus edge trim scrap), **cut to length**
  (coil → sheets of a length, stacked on skids, head and tail scrap), **shear** and **blank** (sheet → smaller sheets or
  blanks), **level** (flatten; usually a step on the cut-to-length line), **pack** (skid, banding, paper, wrap),
  **inspect**. Laser and plasma cutting come later on the same shape.
- **Quantities:** everything weighs; sheets and blanks are also counted. Theoretical weight from the dimensions
  (steel 7.85 g/cm³ — 0.2836 lb/in³; the Manufacturers' Standard Gauge for sheet steel is defined from
  41.82 lb/ft² per inch of thickness; galvanized gauges add the coating) against the scale weight; a coil's
  **PIW** (pounds per inch of width). Prices per cwt (100 lb) or per piece.
- **Quality:** the MTR's values on the lot; dimensional readings at the machine (thickness, width, length, flatness,
  camber, squareness, burr); a release decision before shipping; non-conformance = a hold with a reason.
- **Shipping:** a bill of lading per truck, a packing list per skid with heat numbers, certificates travelling with
  the load; scrap sold by weight to a dealer.

The seed (`db/profiles/steel/seed.sql`): the display units (lb, in, ft², ea) and number formats; item classes
`coil` (material, catch weight, serialized, lot noun Coil), `slit_coil` (intermediate, serialized), `sheet`, `blank`,
`consumable` (knives, oil, blades), `packaging` (skids, banding, paper, wrap), `scrap` (co-product, lot noun Scrap bin),
`finished_good` (packed, lot noun Skid); the attribute dictionary per class (coil: heat, grade, spec, thickness,
width, coating, mill, country of melt; sheet/blank: + length; finished good: pieces per skid); the operations;
the measurement types; the equipment kinds; the reason codes (`TRIM` edge trim expected, `ENDS` head and tail
expected, `SETUP` setup scrap expected, `OFFGAUGE`, `SURFACE`, `DAMAGE`, `COUNT`, `CORRECT`, `SHORT`, `OPENING`,
`SPECOVR`); the gauge table (`gauge_tables`: family `sheet_steel` and `galvanized`, gauge → inches, verified against
a supplier chart in step 5 — the two figures confirmed today are 10 ga = 0.1345 in and 18 ga = 0.0478 in); the three
period reports; the dashboard tiles (coils in the yard by weight, runs today, orders due this week, scrap this month,
the release queue).

## 5. The run — the exemplar

```
production order  WO-00012   product "Sheet 16 ga × 48 × 120 A1011 CS-B", 400 pieces, due Friday
  process spec    v2         step 1 cut_to_length on a cut-to-length line, expected loss 1.5 %, 20 min setup
                             step 2 pack to "Skid 48×120, 50 pieces", banding + paper
run  RUN-00031  cut_to_length on CTL-1   coil C-26-0144 (heat 7A1234, 0.0598 × 48, 18,240 lb) in
                outputs: 400 sheets 48×120 (item SHT-16-48-120) → lot S-26-0097, 16,590 lb, to bay B2
                         1 coil remnant (slit_coil/coil, 1,420 lb) → lot C-26-0144-R, back to the yard
                         scrap ends 230 lb → scrap lot, to the scrap location
                readings: thickness 0.0601, length 120.02, flatness 4 I-units — against the product's specs
                yield 99.0 % by weight; lot_lineage: S-26-0097 ← C-26-0144 (0.91), C-26-0144-R ← C-26-0144 (0.08)
packaging run   PK-00020  lot S-26-0097 → 8 skids (finished lots F-26-0210 … 0217), heat 7A1234 on each
release         quality releases the finished lots on the MTR and the readings
shipment        BOL-00055 to the customer, 8 skids, 16,590 lb, packing list with heats, certificate attached
```

The run is the slice every later slice copies: a document with lines (draft → in progress → posted), the ledger posting
at post (inputs out, outputs in, consumables out, losses), new lots with attributes derived from the inputs and the
process spec (a sheet inherits the coil's heat, grade, thickness and width; its length is the step's), lineage, the
readings against specs, the yield, the equipment booking it consumes, the activity events, the records tools
(`run_find`, `production_runs_today`, `run_yield`, `trace_forward`) and the actions (`run_create`, `run_start`,
`run_add_input`, `run_add_output`, `run_reading_record`, `run_post`, `run_cancel`).

## 6. Profiles — how an industry is added, and how a fork is made

- A **profile** is `db/profiles/<name>/seed.sql` (units, display units, number formats, item classes with their
  attribute dictionaries and lot nouns, operations, measurement types, equipment kinds, reason codes, report line
  maps, dashboard tiles) + `skills/<name>-*` (the vocabulary and the day's routines for the expert) + a paragraph in
  `os/expert.md` chosen by the profile. `PROCESS_PROFILE` in `config/.env` (installer `env.optional`, default `steel`);
  `deploy/os-provision.sh` applies the profile once and records it in `app.schema_migrations` as `profile:<name>`.
  A second profile (aluminium, paper, lumber) is a seed and skills — no PHP.
- A **fork** (`maludb-os-<key>`, its own catalog key, the way this repository was made from the cidery) is for an
  industry that needs its own tables or screens. The rule for forks: the core's `db/001–0NN` are never edited, the fork
  appends its files and its features, so a core fix merges forward. ProcessCore itself is the first proof of the rule
  the other way round: it is the cidery with the beverage layer taken off and the generic layer named.

## 7. Agents

- **ProcessCore Expert** (the application's expert, the command bar, `assistant.agent = expert`): answers what is in
  the yard, what ran today, what is short, what is ready to ship, what a run yielded, where a heat went; acts on request
  (a run, a receipt, a booking, a shipment); pauses for approval on deletions and on finalizing a period report.
- **Shift Planner** (D13): a 06:30 note to `#production` or the owner's inbox — today's runs and bookings by machine,
  orders due this week against finished stock, coils below reorder, runs left in progress overnight, out-of-spec
  readings since yesterday. Read tools only.

## 8. Roles

`viewer`, `receiving` (vendors, purchase orders, receipts, lots, transfers, counts), `production` (products, process
specs, equipment, production orders, runs, packaging), `quality` (readings, inspections, specs, certificates, releases),
`shipping` (customers' shipments, bills of lading, returns, scrap dispositions), `sales` (customers, orders, standing
orders, planning), `owner` (everything, users, settings, tokens). Rights: `records.read`, `purchasing.write`,
`production.write`, `quality.write`, `shipping.write`, `sales.write`, `processcore.admin`. The cidery's `compliance`
role becomes `shipping`.

## 9. Screens

The nxl look, 375 px, no modals, the cidery's URL conventions. The navigation after the change:

| Group | Items | Change from the cidery |
|---|---|---|
| Overview | Dashboard, Ask me anything, Activity | tiles from the profile |
| Purchasing | Purchase orders, Vendors | — |
| Receiving | Receipts, Lots (the lot noun in the list: Coils), Projected | weigh ticket and certificate on the receipt line |
| Inventory | Materials, Finished goods, Movements, Reorder, Rack board, Transfers, Adjustments, Counts | Tank view goes; weight beside quantity everywhere |
| Products | Products and process specs, Packaging configurations, Standard costs | Approvals go |
| Production | Production orders, Equipment schedule, **Runs** | Press runs, Tank board, Batches go |
| Packaging | Packaging runs, Finished goods | Kegs go |
| Quality | Readings, Inspections, Certificates, Release queue | Lab → Readings; Sensory → Inspections; Certificates new |
| Reports | Yields, Run costs, Valuation, Period reports, Order history | Juice yield, Batch costs, TTB reports replaced |
| Sales | Customer orders, Packaging queue, Standing orders, Import orders | — |
| Planning | Projections, Suggested production, Suggested purchases, Forecast | — |
| Shipping | Customers, **Shipments**, Scrap dispositions, Trace | was Compliance: Removals → Shipments |
| Setup | Sites, Locations, Equipment, Items, Item classes, Attributes, Units, Reason codes, Users, Organization, AI access tokens | Premises → Sites; Vessels go; Attributes new |

About 110 screens and 115 actions, from the cidery's 123 screens: the batch, vessel, keg, TTB and tank screens
(about 35) go; runs, certificates, inspections, shipments, attributes, capabilities and period reports (about 22) come.

## 10. The tool surface and the manifest — the deltas

Records MCP (the cidery's 50 tools → about 48): `production_tank_board`, `production_batches_in_progress`,
`batch_readings`, `batch_genealogy`, `keg_fleet`, `compliance_*`, `find_batch`, `find_vessel`, `find_keg`,
`find_press_run` go; `production_runs_today`, `run_yield`, `run_find`, `find_run`, `find_shipment`, `find_certificate`,
`heat_where_used` (every lot and shipment a heat reached), `equipment_fits` (what a machine can take), `period_report`,
`cost_run`, `cost_product` come; `trace_forward`/`trace_backward` run over `lot_lineage`; every quantity tool returns
`weight` beside `qty`. Activity MCP: unchanged (6). Actions MCP (49 → about 50): the batch, vessel, keg and removal
actions go; `run_*` (7), `shipment_create/add_line/post/reverse`, `certificate_record`, `inspection_record`,
`scrap_disposition_post`, `period_report_finalize` come. Approvals: `customer_delete`, `item_class_delete`,
`supplier_delete`, `period_report_finalize`. K7 shares for the siblings: `shipments_by_period` and
`inventory_valuation` (the ledger, G3), `open_orders` (Help Desk HD4, Spaces S2), `finished_stock_available`
(Inventory I1 — a service center that also sells from stock).

## 11. Names, ports, the kernel

| | |
|---|---|
| Catalog key, name, DNS label | `processcore`, "ProcessCore", `processcore.<domain>` (D1) |
| Repository, clone | `github.com/maludb/maludb-os-processcore` (private, D16), `/srv/apps/processcore` |
| Database, roles | `<tenant>_processcore`; `processcore_app`, `processcore_records_ro`, `processcore_activity_ro` |
| Ports | 8189 (Apache internal), 8839 (records MCP), 8840 (activity MCP) — the next free after Inventory's 8188/8837/8838; scratch `processcore_dev` (D19) |
| Kernel | **K29** the catalog row (`db/174`): category `manufacturing` — the category check and `APPLICATION_CATEGORIES` widened as db/172 did for `inventory`; business area Operations; `kind = 'ours'`; on request, not a default |
| Systemd units, vhost | `processcore-records-mcp`, `processcore-activity-mcp`, `processcore-activity-ingest(.timer)`, `processcore-directory-sync(.timer)`; `deploy/apache-processcore.conf` |
| Expert, Planner | hired by `bin/hire_application_agent.php --app processcore --agent expert|planner` |

## 12. Owner decisions (recommendation first)

| # | Question | Recommendation | Alternative |
|---|---|---|---|
| D1 | The names | Catalog key `processcore`, display name "ProcessCore", DNS label `processcore`, the business sees "ProcessCore" in the launcher; the profile name never appears in a URL | DNS label `process` (shorter); or the installation names the application after its profile ("Steel") |
| D2 | How the schema changes | **Rewrite `db/001–0NN` in place** as ProcessCore's own clean schema (the cidery's history stays in git; this application has never been installed anywhere, so there is nothing to migrate) | Append migrations that drop and rename the cidery's tables — a base product would start with 23 files of cider and ten undoing them |
| D3 | The batch | **Remove the continuous batch** (batches, stage events, vessel occupancy, splits, blends, yeast) from the core; the run is the unit of execution — short (a coil slit in an hour) or long (a kiln charge), it has inputs, outputs, readings and a booking | Keep batches as a "continuous run" mode behind a profile flag — every screen and tool would carry two shapes for an industry the core does not ship |
| D4 | Dual quantities | **Pieces and weight everywhere:** `qty_base` in the item's unit plus `weight_kg` on lots, ledger rows, balances, run lines, order lines and shipment lines; the item class says which is primary for display; theoretical weight computed from attributes when no ticket | Weight only through the existing catch-weight flag — sheets would be counted nowhere |
| D5 | Dimensions and grades | **Typed attribute definitions per item class** (`attribute_definitions`: key, name, kind num/text/choice, unit, required, on lot/on item/on product) with values on items, products and lots; the profile seeds the dictionary; a product's code can be composed from them ("SHT-16-48-120") | Fixed columns `thickness`, `width`, `length`, `grade` on items — right for steel, wrong for the base |
| D6 | Equipment capabilities | **A capabilities set per machine** (`equipment_capabilities`: max width, thickness min/max, max coil weight, max length, materials) checked when a run or booking names a machine — **a warning, never a stop** (the cidery's interlock rule: hard stops only on quarantine and negative stock) | No capabilities — the planner is told nothing |
| D7 | Compliance | **Certificates + heat flow-down + period reports over the generic line map**; the TTB forms, tax classes and bonded state go | Drop period reports too — then a monthly production and scrap statement is a spreadsheet |
| D8 | Shipping documents | **Printable bill of lading and packing list** (HTML print views, heats and weights per skid, the certificate attachments listed) — the cidery has no PDFs and neither does this | None in v1 |
| D9 | Price basis on order lines | **`per_cwt`, `per_lb`, `per_kg`, `per_piece`** on the line, the extended price computed from the shipped weight or pieces | Per piece only |
| D10 | Kegs | **Extended as `containers`** (returnable racks, cradles, totes: serial, state, holder, deposit) — the keg tables generalized and kept out of v1 | Delete them |
| D11 | Costing | **As the cidery:** actual lot cost per kg for material, standard cost for consumables and packaging, overhead per kg per site; scrap credited at its recovery value; variance to the process spec | Overhead per machine-hour (Extended on the same ledger) |
| D12 | Profiles | **Seed + skills + `PROCESS_PROFILE`**, `steel` the default, applied once by `os-provision.sh`; forks for industries that need screens (section 6) | One hard-coded industry per repository |
| D13 | Agents | **Expert + Shift Planner** (06:30 note, read tools only) | Expert only |
| D14 | Roles | The seven of section 8 | Keep the cidery's seven with `compliance` |
| D15 | Ports and category | 8189/8839/8840; category `manufacturing` (K29 widens the check) | Category `other` |
| D16 | Repository visibility | **Private** (made so today, like the owner's recent products); flipping to public is one command once the cidery words are gone | Public like the cidery |
| D17 | Standalone mode | **Keep the cidery's two ways to run** (`OS_ENABLED` unset: own login, TOTP, Google, the standalone assistant and actions servers, `provision-client.sh`) — the base may be sold standalone like every `htmx-php-builder` product | OS-only: delete the standalone login, the assistant and `provision-client.sh` — smaller, but the base loses a door |
| D18 | Division of labour | **The planning model** does steps 1–5 of section 13 (through the run exemplar and the steel seed); **Sonnet 5.5 workers** steps 6–8 one slice each from a build spec; the planning model Phase 4 review and the handoff | All by the planning model |
| D19 | Where the schema is proven | A scratch database `processcore_dev` on this host (the cidery's `cidery_dev` pattern), provisioned by `deploy/os-provision.sh`, never the live cluster's tenant databases; the live apply is the owner's | — |

## 13. Build order

Each step ends with a proof script in `scripts/`, a commit on `main`, and a line in `docs/processcore-progress.md`.

0. **The fork** — done 2026-10-08: repository, clone, this plan.
1. **The rename sweep.** `cidery` → `processcore` in `maludb-os.json`, `deploy/` (units, vhost, provision), `services/`
   (server names, roles, env keys `CIDERY_*` → `PROCESSCORE_*`), `config/`, `scripts/`, `bin/`, `skills/`, `os/expert.md`,
   `README.md`, `CLAUDE.md`; database roles; ports. Nothing of the domain changes. Proof: `os-provision.sh` on
   `processcore_dev`, the shell under `php -S`, both MCP servers start and answer `app_roles`, `app_install.php plan`
   reads the manifest clean.
2. **The schema, in place (D2).** `db/001–0NN` rewritten per section 3: the generic core with runs, lineage,
   attributes, weights, certificates, shipments, capabilities, report line maps; `db/profiles/steel/seed.sql`;
   `020_grants.sql` and `021_os_adoption.sql` re-numbered at the end. Design doc `docs/processcore-schema.md`.
   Proof: provisioned from empty, every table and view counted, the ledger interlocks, the lineage trace, the
   theoretical weight function, the gauge table — the cidery's `prove-equipment-schedule.sh` style, 150+ checks.
3. **The cut.** The batch, vessel, keg, TTB, tax and tank code removed: features, views, handlers, tools, actions,
   manifest rows, skills paragraphs; the navigation of section 9; the roles of section 8. Proof: the shell and every
   surviving screen render as owner, production and viewer; the manifest builder and the registry builder run clean.
4. **Runs — the exemplar (section 5).** Schema already in; screens, handlers, activity events, the records tools,
   the actions with undo, the booking link, the yield views; `docs/build-specs/runs.md` the exemplar spec. Proof: the
   worked example of section 5 end to end over HTTP on `processcore_dev`.
5. **The steel profile and the lot.** Attributes on items, products and lots (D5); weigh tickets and certificates on
   the receipt line; the lot view with its heat, dimensions, certificate and lineage; theoretical weight; the profile
   seed applied by provisioning; the dashboard tiles. Proof: a coil received with a ticket and an MTR, cut in step 4's
   run, the sheet lot showing its inherited heat.
   — **the handoff point (D18)** —
6. **Packaging, shipping, quality** (workers, one slice each): packaging runs over lots; finished lots with heats;
   shipments with the BOL and packing list (D8); certificates and inspections; the release queue; scrap dispositions.
7. **Equipment capabilities, orders and costing** (workers): capabilities and the fit warning (D6); order lines with
   weight and the price basis (D9); the cost views; period reports over the line map (D7); the reports group.
8. **The expert, the skills, the surfaces** (workers, then the planning model's review): `os/expert.md`,
   `skills/processcore-basics`, `processcore-receiving-day`, `processcore-month-end`, `steel-processing`; the Shift
   Planner's job description and duty; `docs/04` and `docs/05` rewritten; both registries rebuilt; `maludb-os.json`
   agents, grants, approvals, shares.
9. **Install (the owner's).** K29 in the kernel; `bin/app_install.php plan` then `apply`; DNS/TLS; the hires; the
   grants; the end-to-end proof of section 5 on the live install.

Size: the cidery's Phase 3 was ten slices; this is a rename, a schema rewrite, a cut, two slices by the planning
model and three by workers — smaller than a new application because 70 % of the code survives unchanged.

## 14. What does not change

The `htmx-php-builder` stack and its three governing skills; the OS adoption (`app/os.php`, `/sso`, the directory
sync, `app_roles`, JSON mode, the kernel's actions server reaching the handlers); the ledger's shape and interlocks;
receipts, lots, transfers, adjustments, counts, racks; customer orders, standing orders, imports, projections; the
equipment schedule and its double-booking switch; the activity log and the two MCP servers' contracts; the proof
discipline.

## 15. Later, in no fixed order

Containers (D10); overhead per machine-hour; cutting optimization (which coils to slit for a set of orders — the
service-center software's hard problem, a records tool over the open orders and the yard); blanket orders with
releases; customer specifications and PPAP; EN 10204 3.1/3.2 certificate templates and reprints from a child lot;
mixed-heat coils (two heats on one lot — `lot_attributes` already admits a list); laser and plasma operations with
nesting; a mill EDI feed; a second profile (aluminium, then paper or lumber) to prove section 6.

## 16. The owner's answers (2026-10-08 — rules, not questions)

The owner accepted every recommendation of section 12: D1 the names `processcore` / "ProcessCore" / `processcore.<domain>`;
D2 the schema rewritten in place; D3 the batch removed from the core, the run the unit of execution; D4 pieces and weight
everywhere; D5 typed attribute definitions per item class; D6 equipment capabilities as warnings; D7 certificates, heat
flow-down and period reports over the line map; D8 printable BOL and packing list; D9 the price basis on order lines;
D10 kegs Extended as containers; D11 the cidery's costing; D12 profiles as seed + skills + `PROCESS_PROFILE`, steel the
default, forks for screens; D13 the expert + the Shift Planner; D14 the seven roles; D15 ports 8189/8839/8840 and the
`manufacturing` category (K29); D16 private; D17 the two ways to run kept; D18 the planning model through step 5, Sonnet
workers for 6–8; D19 proven on `processcore_dev`, never live.

## 17. State

- 2026-10-08: the fork (repository, clone, push) and this plan; approved the same day, every recommendation. Kernel:
  the CLAUDE.md and README entries written the same day; K29 not built. The build order starts with step 1 the same day
  (`docs/processcore-progress.md`).
