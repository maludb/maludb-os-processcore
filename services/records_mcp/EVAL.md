# Records MCP server evaluation (R1 to R54)

Run on 2026-10-01 against `processcore_dev` through Apache (`http://127.0.0.1/mcp/records`, systemd unit `processcore-records-mcp`) with
`.venv/bin/python -m records_mcp.test_client http://127.0.0.1/mcp/records --suite` (83 calls, 83 behaved as expected; all 57 tools
called). Arguments are sent as `{"params": {...}}`. The dev data was entered in one day, so nearly every record is dated
2026-10-01 (some readings 2026-10-02), and some timestamps are later than the clock at test time.

| # | Question | Tool and arguments | Real result (one line) |
|---|---|---|---|
| R1 | What is arriving this week, and against which PO? | `receiving_open_orders {date_from: 2026-09-28, date_to: 2026-10-04}` | PO-00001 (Hill Orchard), expected 2026-10-03: 100 lb Golden Russet and 10 bushels (419.9 lb) McIntosh still outstanding. |
| R2 | Did the delivery match the order? Short, over, damaged? | `receiving_receipt_vs_order {receipt_number: GR-00001}` (or `{po_number: PO-00001}`) | GR-00001: 7,900 of 8,000 lb Golden Russet and 30 of 40 bu McIntosh received, no discrepancy flagged. Both PO lines are still partial. |
| R3 | What lots came in on that delivery, and do we have the certificate? | `receiving_receipt_lots {receipt_number: GR-00002}` | Lallemand delivery: lots L-261001-006/007/008 (yeast, Fermaid K, KMS), all released. No CoA on file for any of the three. |
| R4 | Is this lot released or in quarantine? | `receiving_lot_status {lot_number: L-261001-002}` | McIntosh lot is released (259 lb on hand). Ed Honour put it on hold ("smells off") and then undid that at 11:02, after an earlier hold and release. |
| R5 | Which open orders are overdue? | `receiving_open_orders {overdue_only: true}` | None: the only open PO is due 2026-10-03. |
| R6 | What did we pay per pound for apples this season versus last? | `receiving_price_history {item_class: fruit, group_by: year}` | 2026: Golden Russet $0.35/lb ($700/ton), McIntosh $0.333/lb ($14/bushel). There is no earlier season on record to compare. |
| R7 | Which supplier delivers late or short most often? | `receiving_supplier_performance {}` | Four suppliers with one receipt each; 0 late receipts and 0 short or damaged lines. Nobody stands out. |
| R8 | Pounds of each variety this harvest, from which orchards, at what Brix? | `receiving_fruit_intake {season_year: 2026}` | 9,160 lb (4.58 tons) in total: Golden Russet 7,900 lb (10 bins, 14.2 Bx) and McIntosh 1,260 lb (12.1 Bx), both from Hill Orchard. |
| R9 | How much of X is on hand, by lot and location? | `inventory_on_hand {item: JCE-APL}` (any item, class, location or lot) | Purchased apple juice: none on hand (all consumed). Called without a filter it lists every lot and location with totals. |
| R9 | Where is X stored, what is on rack N, which lot goes first? | `inventory_rack_stock {product: Hill Dry Cider, released_only: true}` | Rows by item oldest first with area, rack number (none = loose in the area), lot, batch and `fifo_rank`; L-261001-019 (B-26-004) is rank 1 for the 16 oz can case. |
| R10 | How much is available after what the next batches need? | `inventory_available_after_orders {}` | Short after WO-00004 (allocated) and WO-00005 (planned): juice -2,839 L (-750 gal), EC-1118 -0.6 kg, Fermaid K -0.47 kg. |
| R11 | Which lots first? Which are expiring? | `inventory_pick_order {item: EC-1118, qty: 0.6, unit: kg}`; `{expiring_within_days: 365}` | Pick 0.4 kg from L-261001-006, leaving 0.2 kg short. Expiring: yeast slurry L-261001-010 in 14 days, cans L-261001-012 in 243 days. |
| R12 | What is below reorder point? | `inventory_below_reorder {}` | Nothing. Only 1 of 13 active items has a reorder point set (APL-GOLD, which is above it). |
| R13 | What do scheduled orders need that we do not have? | `production_order_shortages {}` | Across WO-00004 and WO-00005: 750 gal juice, 0.6 kg EC-1118 and 0.47 kg Fermaid K short. Nothing is on order. |
| R14 | What adjustments this month and why? | `inventory_adjustments {date_from: 2026-10-01, date_to: 2026-10-31}`; `inventory_movements {txn_type: adjustment}` | 6 adjustments: OPENING balances for EC-1118 (ADJ-00004/5 posted, -6.5 kg net) and a DAMAGE adjustment of 20 lb McIntosh. The rest are cancelled. |
| R15 | When was the cold room last counted, and the variance? | `inventory_last_count {location: Cold room}` | Only CNT-00002 (cycle count, started 2026-10-01 by Ed Honour), and it was cancelled: 3 lines, yeast slurry variance -0.0002 L, nothing posted. |
| R16 | What is inventory worth, by category, as of a date? | `cost_inventory_valuation {group_by: item_class}` (`as_of` optional) | Ledger stock $2,423.92 (fruit $2,046, packaging $125, finished goods $104.79, additives $74.80, yeast $73) plus $582.82 bulk cider in vessels, $3,006.74 in total. |
| R17 | Which items have not moved in six months? | `inventory_slow_movers {months: 6}` | None: nothing has been in stock for 6 months yet. |
| R18 | Current recipe for X at what batch size? | `recipe_current {product: Hill Dry Cider, batch_volume_gal: 300}` | v2 (active): 7 stages, expected loss 8.23%. At 300 gal: 300 gal juice, 0.5 kg EC-1118, 0.82 kg Fermaid K, 0.136 kg KMS. |
| R19 | What changed between versions, and why? | `recipe_diff {product: DRY}` | v1 to v2: KMS 0.2 to 0.136 kg (-32%), Fermaid K per L +36.1%. Note: "More nutrient, less SO2". Activated by Ed Honour. |
| R20 | Which batches were made with version N? | `recipe_batches_made {product: DRY, version: 2}` | v2: B-26-001 and B-26-006 (active), B-26-002 and B-26-003 (split children, closed). B-26-004 and B-26-005 have no recipe version. |
| R21 | Can we make X at this volume with what is on hand? | `recipe_can_make {product: DRY, batch_volume_gal: 200}` | No: short 200 gal juice and 0.1 kg EC-1118. Fermaid K and KMS are covered. |
| R22 | Standard cost of a batch of X? | `recipe_standard_cost {product: DRY}` | 500 gal batch: materials $2,038.77 (last lot cost, since there are no standards for these items) plus overhead $250 = $2,288.77, or $4.58/gal. The activation snapshot is $340. |
| R23 | What is in every vessel, since when, at what stage? | `production_tank_board {}`; `batch_stage_history {batch_number: B-26-001}` | FV-2: B-26-004 (41.7 gal, blend). Tank-3: B-26-006 (10.9 gal, package). Tote-1: B-26-001 (83 gal, rack). FV-1 is cleaning; Press-1 is empty. |
| R24 | Which batches are in progress and when ready? | `production_batches_in_progress {}` | 3 active: B-26-006 package, B-26-004 blend, B-26-001 rack (v2, ready estimate from recipe stage days). Each comes with its latest reading. |
| R25 | What was pressed this week, yield per ton and bushel? | `production_press_runs {date_from: 2026-09-28, date_to: 2026-10-04}` | PR-00001: 3,000 lb in, 200 gal out. PR-00002: 300 lb in, 20 gal out. Both 133.3 gal/ton and 2.8 gal/bushel; 1,000 lb pomace. |
| R26 | Which production orders are released but not started? | `production_orders_by_status {status: released, not_started_only: true}` | WO-00004: 450 gal of Hill Dry Cider v2, pitch 2026-10-05 in FV-1, 4 open allocations. |
| R27 | What was consumed in batch B, by lot? | `batch_consumptions {batch_number: B-26-001}` | 200 gal juice L-261001-004, 0.5 kg EC-1118 L-261001-006, 0.4 kg Fermaid K L-261001-007. All at pitch. |
| R28 | What was added after fermentation? | `batch_consumptions {batch_number: B-26-004, after_stage: primary}` | One addition: 0.03 kg Fermaid K (L-261001-007) at the blend stage. |
| R29 | Which batches were blended, in what proportion? | `batch_blends {batch_number: B-26-004}`; `batch_blends {}` | B-26-004 = B-26-002 (227.1 L, 54.55%) + B-26-003 (189.3 L, 45.45%), 110 gal in FV-2. |
| R30 | Full genealogy of what is in tank 7? | `batch_genealogy {vessel: Tank-3}` (or `batch_number`) | Tank-3 holds B-26-006: no parents, made from Valley Juice Co juice L-261001-014 and yeast slurry L-261001-015. For B-26-004 it walks blend, split and B-26-001 back to fruit lots. |
| R31 | Fermentation curve for batch B? | `batch_readings {batch_number: B-26-001, measurement: brix}` | One Brix reading: 2.0 at primary (2026-10-01 12:00), which fails the spec (max 0). There is no SG series yet. |
| R32 | Yield at each stage vs the recipe? | `cost_stage_yields {product: DRY, last_n: 5}` (or `batch_number`) | B-26-001 primary: 2.5% actual vs 3% expected. Rack: B-26-002 0% vs 2%. Averages are given per stage. |
| R33 | Where did batch B lose volume, and why? | `batch_losses {batch_number: B-26-001}` | 7 gal in total: LEES 5 gal at primary and RACK 2 gal (the FV-1 to Tote-1 transfer). |
| R34 | Juice per ton by variety this season? | `cost_juice_yield_by_variety {season_year: 2026}` | Golden Russet 133.3 gal/ton (2 runs, 1.15 tons); McIntosh 133.3 gal/ton (1 run, 0.5 tons). |
| R35 | Packaging loss on the last canning run? | `packaging_run_losses {package_kind: can, last_n: 1}` | PK-00007 (B-26-004): 15.2 gal in, 120 cans and 15.0 gal out, 0.2 gal lost (1.31% vs 2% expected). |
| R36 | How many cases and kegs of X are ready to sell? | `packaging_finished_stock {product: DRY}` | 54 cans (2.25 cases of 24) and 3 half-barrel kegs (46.5 gal), all bonded in Packaged goods. |
| R37 | What packaging materials do next week's runs need? | `packaging_material_needs {}` | B-26-006 (10.9 gal at package): if canned, 85 cans and 85 ends, with 500 of each available. Too little to fill a keg. |
| R38 | Finished lots from batch B? Which batch is in this can? | `packaging_lots_for_batch {batch_number: B-26-004}`; `{lot_number: L-261001-019}` | B-26-004 gave L-261001-009 (rejected, run cancelled), L-261001-018 (3 kegs) and L-261001-019 (120 cans). The can lot L-261001-019 is from B-26-004. |
| R39 | Where are the kegs, how many out, for how long? | `keg_fleet {}`; `keg_history {serial: KEG-0003}` | 4 kegs; 1 out (KEG-0003 at Green Mountain Distributors, rented). KEG-0003 history: clean, fill, ship, return, ship (RM-00006). |
| R40 | Cost of a keg or case of X from batch B? | `cost_batch {batch_number: B-26-004}` | Recorded unit cost: $9.90 per case of 24 cans and $7.75 per keg. The estimate including liquid inherited from parents is $15.67 per keg. |
| R41 | Last reading on batch B? Anything out of spec? | `batch_readings {batch_number: B-26-006}`; `quality_out_of_spec {days: 30}` | B-26-006's last reading: ABV 6.5%, which passes (spec 6 to 7). Out of spec: B-26-004 pH 4.2 (spec 3.2 to 3.8) and B-26-001 Brix 2.0 (max 0), neither re-tested since. |
| R42 | Which batches await release? Who released B, on what basis? | `quality_release_queue {}`; `quality_release_history {batch_number: B-26-006}` | Queue: B-26-004 (blend stage, 1 failing reading), no lots. B-26-006 was last released by Ed Honour (basis "other") after a hold. |
| R43 | SO2 history of lot or batch W? | `batch_readings {lot_number: L-261001-001, measurement: so2}` | "so2" matches free and total SO2. One reading: free SO2 30 mg/L on 2026-10-01. |
| R44 | What did the sensory panel say about batch B? | `quality_sensory {lot_number: L-261001-002}` (or `batch_number`) | 2 records, both pass (Ed Honour, Guest); no attributes or faults recorded. The only sensory data is on this lot. |
| R45 | What did batch B cost against standard? | `cost_batch {batch_number: B-26-001}` | $1,239.33 ($1,139.33 materials + $100 overhead) on 200 gal ($6.20/gal). Standard at that volume is $136, so variance is +$1,103.33. |
| R46 | Value of bonded versus tax-paid inventory? | `cost_inventory_valuation {group_by: tax_state}` | Bonded $2,423.92 in the ledger plus $582.82 bulk cider (bonded). Tax-paid $0. |
| R47 | Gallons produced, removed tax paid, in bond, lost this period? | `compliance_period_summary {period: 2026-10}`; `compliance_report {report_number: RPT-00003}` | October: produced 246.4 gal, bottled 109.6, removed tax paid 94.0 (taproom included), in bond 1.25, exported 0.5, returned 73.3, lost 33.8. Tax $15.46. RPT-00003 is the draft Q4 report. |
| R48 | Gallons in bulk versus packaged, by tax class? | `compliance_bulk_vs_bottled {}` | Bulk 135.6 gal (hard cider 10.9, still wine 124.7); packaged 53.25 gal hard cider (bonded); 20 gal juice not yet fermented. |
| R49 | Is this cider still inside the hard-cider class? | `packaging_tax_class_check {lot_number: L-261001-019}` (or `batch_number`) | Yes: ABV 6.5 (2.0 under the 8.5 limit), CO2 0.5 (0.14 under 0.64), fruit 100% (50 over the minimum). For batch B-26-006 the CO2 reading is missing, so it derives still wine. |
| R50 | Which products need a formula or label approval? | `product_approvals_needed {}` | Hill Dry Cider: label for the 16 oz can is required (not yet submitted). Formula TTB-F-123 expires 2026-11-15 (in 45 days). |
| R51 | What did we remove to the taproom last month? | `compliance_removals {destination_kind: taproom_transfer, date_from, date_to}` | October: RM-00002, 24 cans (3.0 gal) of L-261001-019, tax $0.49, since reversed by RM-00003. |
| R52 | Where did the pomace go? | `co_product_dispositions {}` | From PR-00001's pomace lot L-261001-005: 600 lb to the farm (Hill Farm) and 100 lb to compost; 300 lb still in the cold room. |
| R53 | Supplier lot L is bad: which batches, packages, customers? | `trace_forward {lot_number: L-261001-001}` (supplier lot numbers also resolve, e.g. LAL-77) | Golden Russet lot: 5 batches, 3 finished lots (56 units on hand), 10 removals, 2 customers (Green Mountain Distributors, North Bonded Winery). LAL-77 reached nothing. |
| R54 | A customer returns a bad can: which batch, ingredient lots, other packages? | `trace_backward {lot_number: L-261001-019}` | Can lot is from B-26-004, via B-26-002/003 and then B-26-001. Inputs: juice L-261001-004, yeast, Fermaid K (Lallemand), fruit L-261001-001/002 (Hill Orchard). Other packages: L-261001-018 (2 kegs on hand) and L-261001-009. |

## Also exercised

| Tool | Arguments | Result |
|---|---|---|
| `product_find` | `{query: dry}` | Hill Dry Cider, active v2, 6 batches, 2 packages. |
| `batch_find` | `{status: active}` | B-26-004, B-26-001, B-26-006 with vessels. |
| `records_search` | item class lot counts; `SELECT id, display_name, role FROM app.users` | 7 classes (finished_good 5 lots ...); 2 users. |
| ambiguity | `inventory_on_hand {item: apple}`, `receiving_lot_status {lot_number: 261001}` | `ambiguous: true` with candidate lists (4 items, 10 lots). |
| refusals | DELETE, UPDATE, `SELECT 1; DROP`, `WITH x AS (DELETE ...)`, `password_hash`, `mcp_access_tokens` | All refused with an actionable message (guard or role privilege). |
| errors | unknown lot, unknown argument, `limit: 500`, ingredient lot in `packaging_lots_for_batch` | is_error results with actionable sentences. |
| auth | no token, wrong token, activity-scope token | HTTP 401 `invalid_token`, direct and through Apache. |

## Gaps and caveats

- No question is unanswered. Several answers are empty or thin only because the dev data has nothing to show: R5, R7, R12, R17, a one-point R31 curve and R44 sensory data only on a lot.
- R37: production orders do not record a packaging configuration, so material needs are shown per configuration as "if all packaged as". A `packaging_configuration_id` on production orders would make this exact.
- R40 and R45: `app.v_batch_costs` counts only a batch's own consumptions, so split and blend children look cheap (B-26-004 shows $56.20). `cost_batch` adds `inherited_from_parents` and a per-liter figure that includes them; folding that into the view is a schema decision for the coordinator.
- R47: `compliance_period_summary` derives the figures live, using the same sources as the PHP report generator but a simpler rollup. The filed figures come from `compliance_report`.

## Customer orders and planning (2026-10-02)

| Q | Tool call | Result against the dev data |
|---|---|---|
| O1 | `orders_find {status: null, limit: 3}` | SO-00002 (Green Mountain, history, 6 half barrels, $960) first, by due date; `has_more` true. |
| O2 | `order_status {order: "HT-1001"}` | Resolves the customer reference to SO-00001 (closed, 73 units, $129.60) with lines, runs and shipments. |
| O3 | `orders_history {group_by: "month", 2026}` | 2026-06: 1 order, 6 units, $960; 2026-10: 1 order, 73 units, $129.60. |
| O4 | `standing_orders_find {include_paused: true}` | STO-0001 (every week on Friday) and STO-0002 (every month on day 15), both paused, with lines. |
| O5 to O7 | `purchase_projection {weeks: 6}`, `production_projection {level: "all"}` | Juice short 1,892.7 L this week (1,250 gal suggested, about $5,625) for planned production; bulk supply lists B-26-004, B-26-006, B-26-001 and the unstarted production orders. |
| Prices | the same calls with `X-ProcessCore-Show-Prices: 0` | `unit_price`, `order_value`, `approx_cost` absent. |

Live assistant turns (sales user): the AMA question "what do we need to buy in the next 4 weeks" answered from `purchase_projection` (driven by planned production); the dictated "the hill taproom wants three half barrels next friday, their PO is TAP-77" created and confirmed SO-00013; "undo that" cancelled it. As a production user, a question about order values was answered in units with the values withheld.
