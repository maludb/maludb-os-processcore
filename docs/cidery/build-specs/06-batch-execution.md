# Build spec: batch execution slice (slice 6)

Built by the **planning-class model** (this is the largest slice and the second exemplar for liquid handling); it is still specified here so the build is substitution, not invention, and so slices 7 to 10 can replicate it. Exemplar to replicate for file layout, list/form/view markup and handler sequence: the **receiving** slice (slice 2).

Schema tables (approved Phase 1, never modify): `app.press_runs`, `app.press_run_inputs`, `app.press_run_outputs`, `app.batches`, `app.batch_lineage`, `app.vessel_occupancies`, `app.stage_events`, `app.consumptions`, `app.batch_transfers`, `app.batch_splits`, `app.batch_split_outputs`, `app.batch_blends`, `app.batch_blend_inputs`, `app.loss_events`, `app.readings`, `app.yeast_harvests`, `app.co_product_dispositions`, `app.lots`, `app.lot_attributes`, `app.inventory_transactions` (insert only), `app.allocations` (release on consumption); read-only: `app.vessels`, `app.items`, `app.stages`, `app.measurement_types`, `app.reason_codes`, `app.products`, `app.recipe_versions`, `app.recipe_stages`, `app.recipe_lines`, `app.production_orders` (status update only), `app.v_vessel_board`, `app.v_lot_balances`, `app.v_batch_costs`, `app.v_batch_stage_yields`, `app.v_press_run_yields`, `app.derive_tax_class`.

Unit rules: volumes entered in gallons, stored in liters (`× 3.785411784`, 3 decimals); weights entered in pounds, stored in kilograms (`× 0.45359237`, 3 decimals); juice Brix entered as is. Fields affected are named `*_gal` / `*_lb` in forms and `*_l` / `*_kg` in tables. Small additions (nutrient, sulfite, enzyme) are entered in the item's base unit or an `item_units` alternate and converted with that unit's `to_base_factor`.

Ledger conventions used by every posting in this slice: one `group_id` per logical event; `idempotency_key` = `{reference_kind}:{reference_id}:{line_no}`; `occurred_at` = the event's timestamp; `actor_id` = current user; `premises_id` and `tax_state` are overwritten by the ledger trigger from the location. Liquid lots and batches are not in the ledger by vessel: a juice lot's ledger location is the vessel's `vessels.location_id` (the cellar), and `vessel_occupancies` says which vessel. Batches themselves have no ledger rows (volume lives in `batches.current_volume_l` and occupancies); ledger rows exist for item lots consumed into or produced from batches.

Interlocks (enforced; the first two by the ledger triggers in 006, the rest in the handlers):
- I1 quarantined, hold, or rejected lots cannot be issued (`txn_type = 'issue'`) — the ledger raises; the handler catches SQLSTATE 23514 and re-renders the form with the message.
- I2 no negative stock unless the location allows it.
- I3 one open occupancy per vessel (`vessel_occupancies_one_open` unique index); the handler checks before insert and renders "vessel {name} holds {occupant}" as a field error.
- I4 vessel capacity: a volume above `vessels.capacity_l` renders a **warning** (not an error) on the form and logs `details.capacity_warning = true`.
- I5 a batch with `status <> 'active'` accepts no events; endpoints return 409 and the view shows no action buttons.

---

## Entity: press run

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| press-runs-list | /press-runs/ | List |
| press-run-add | /press-runs/new | Form (empty) |
| press-run-edit | /press-runs/{id}/edit | Same form, pre-filled; draft only |
| press-run-view | /press-runs/{id} | Detail with yield and Post button |

### List screen
- Columns: number (link, status dot) → `number`; date → `run_on`; press → `vessels.name` via `press_vessel_id` (blank if null); fruit → `fruit_kg_total` in lb; juice → `juice_l_total` in gal; yield → `yield_l_per_kg` shown as gal/ton (`yield_l_per_kg / 3.785411784 * 907.18474`, 0 decimals) and gal/bushel (`× 19.05087954 / 3.785411784`, 2 decimals) as `<small>`; status → dot + badge.
- Search: `number`; sort allowlist: `number`, `run_on`, `status`; default `run_on DESC`; page size 25.
- Row link: press-run-view.

### Form (ids `press-run-form-field-{name}`)
| Field | Input | Required | Validation |
|---|---|---|---|
| run_on | date, default today | yes | — |
| press_vessel | select `vessels` where `kind = 'press'` and active | no | — |
| premises | select `premises` (hidden when one) | yes | — |
| started_at, finished_at | datetime-local | no | finished ≥ started |
| inputs (repeating rows `press-run-form-input-row-{n}`) | lot select (Pattern A fragment `/press-runs/fruit-lot-options.php`: lots of items with `item_class = 'fruit'`, `quality_status = 'released'`, on hand > 0 from `v_lot_balances`, label `lot_number · item · variety · {on hand lb} lb`), qty_lb number | ≥ 1 row | qty_lb > 0 and ≤ on hand (hard: ledger I2) |
| outputs (repeating rows `press-run-form-output-row-{n}`) | kind (juice, pomace), item select (`item_class = 'juice'` for juice; `'co_product'` for pomace), qty (gal for juice, lb for pomace), brix (juice only), vessel select (juice only; `vessels` active, not `press`), location select (pomace only; locations active) | ≥ 1 juice row | qty > 0; juice vessel must be empty (I3) at post time; capacity warning (I4) |
| notes | textarea | no | — |

### View screen
Header card (number, status, date, press, totals in lb and gal, yield gal/ton and gal/bushel, posted by/at); inputs table (`press-run-view-inputs`: lot, item, variety, kg/lb); outputs table (`press-run-view-outputs`: kind, item, lot created (link to lot-view), qty, brix, vessel or location); Post button `press-run-view-post-btn` (draft only), Edit button (draft only).

### Posting (`press-runs/post.php`, one transaction)
1. Lock the run; require `status = 'draft'`, ≥ 1 input and ≥ 1 juice output.
2. For each input: insert `inventory_transactions` (txn_type `issue`, qty `−qty_kg`, item = lot's item, lot, location = the lot's balance location with the largest on hand (query `find_lot_primary_location`), counterparty_kind `press_run`, counterparty_id = run id, reference_kind `press_run`, reference_id = run id, ttb_category `used_in_production`, unit_cost_base = `lots.unit_cost_base`); insert `consumptions` (press_run_id, item_id, lot_id, qty_base = qty_kg, purpose `fruit`, stage_code `press`, ledger_group_id).
3. For each juice output: insert `lots` (lot_number = `app.next_number('lot')`, item, premises, produced_on = run_on, quality_status `released`, source_kind `press_run`, source_id = run id, unit_cost_base = total fruit cost ÷ total juice liters (fruit cost = Σ qty_kg × lot unit cost)); insert `lot_attributes` rows: `brix` (value_num, unit `°Bx`, source `press_run`) when given, `variety` (value_text; the input lots' varieties joined with "/", source `press_run`), `press_run` (value_text = number); insert `inventory_transactions` (txn_type `production_output`, qty `+qty_l`, location = `vessels.location_id` of the output vessel, counterparty_kind `press_run`, reference_kind `press_run`, ttb_category `produced`, unit_cost_base as computed); insert `vessel_occupancies` (vessel, occupant_kind `lot`, occupant_id = new lot, volume_l = qty_l, from_at = finished_at or now); set `press_run_outputs.lot_id`.
4. For each pomace output: insert `lots` (item, produced_on, quality_status `released`, source_kind `press_run`, unit_cost_base 0); `inventory_transactions` (txn_type `production_output`, qty `+qty_kg`, location = the output's location, ttb_category `none`, reference_kind `press_run`); set `press_run_outputs.lot_id`.
5. Update `press_runs`: `fruit_kg_total`, `juice_l_total`, `pomace_kg_total`, `yield_l_per_kg = juice_l_total / fruit_kg_total`, status `posted`, posted_by, posted_at; set `vessels.status = 'in_use'` for each juice vessel.
6. `log_activity('press_run_posted', entity press_run, after = totals and created lot numbers)`.

### Files
- /var/www/html/press-runs/index.php · form.php · view.php · save.php · post.php · delete.php (draft only) · fruit-lot-options.php
- /var/www/app/features/press-runs/queries.php
- /var/www/app/views/press-runs/page.php · partials/table.php · row.php · form.php · view.php · saved.php · fruit-lot-options.php

### Query functions
- find_press_runs(PDO, search='', sort='run_on', page=1): array · count_press_runs(PDO, search=''): int
- find_press_run(PDO, int id): ?array · find_press_run_inputs(PDO, int id): array · find_press_run_outputs(PDO, int id): array
- find_fruit_lot_options(PDO): array · find_lot_primary_location(PDO, int lot_id): ?array
- insert_press_run(PDO, int premises_id, ?int press_vessel_id, string run_on, ?string started_at, ?string finished_at, ?string notes, int created_by): array
- update_press_run(PDO, int id, …same fields): array (draft only)
- replace_press_run_lines(PDO, int id, array inputs, array outputs): void
- post_press_run(PDO, int id, int user_id): array  (steps 2 to 5 above)
- delete_press_run(PDO, int id): bool (draft only)
- insert_ledger_row(PDO, array row): int  (shared helper in /var/www/app/features/inventory/ledger.php from slice 3; reuse, do not duplicate)

### Action manifest entries
- Screens: press-runs-list, press-run-add, press-run-edit, press-run-view.
- Actions: press_run_create / press_run_update (POST /press-runs/save; undo delete_row / restore_prior; draft only) · press_run_post (POST /press-runs/{id}/post; undo reverse: a reversal group that re-issues the juice/pomace lots negatively, closes their occupancies, and credits the fruit lots; status back to draft; no confirm).

### Activity log events
- `screen_entered`; `press_run_created`, `press_run_updated`, `press_run_posted` (after: totals, lot numbers), `press_run_deleted`.

### Status vocabulary
- draft → dark; posted → success; cancelled → danger.

### Out of scope
- Press fractions (wine); multiple presses per run; juice blending at the press (use batch_pitch with several juice lots).

### Open Questions
- (none)

---

## Entity: tank board (read-only screen)

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| tank-board | /tank-board/ | What is in every vessel right now |

- A card grid (`tank-board-grid`, `row g-3`, `col-12 col-md-6 col-xl-4` per vessel card `tank-board-vessel-{vessel_id}`), fed by `app.v_vessel_board` ordered by `vessel_kind, vessel_name`. Each card: vessel name and kind, status badge, fill progress bar (`fill_pct`), occupant label linking to batch-view or lot-view, product name, stage badge, "since" medium date. Empty vessels show `secondary` style.
- Filter in the page header: premises select when more than one; kind select.
- No actions; the whole grid refreshes on `HX-Trigger: batchesChanged` (Pattern D).

### Files
- /var/www/html/tank-board/index.php · /var/www/app/features/tank-board/queries.php · /var/www/app/views/tank-board/page.php · partials/grid.php

### Query functions
- find_tank_board(PDO, ?int premises_id, ?string kind): array

### Action manifest / activity log
- Screen tank-board; `screen_entered`.

### Open Questions
- (none)

---

## Entity: batch

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| batches-list | /batches/ | List |
| batch-add | /batches/new | Pitch form (creates the batch) |
| batch-view | /batches/{id} | Detail with tabs |
| batch-edit | /batches/{id}/edit | Notes and tax class override |

Sub-screens that post events onto a batch, each a dedicated full-container form partial reached from batch-view buttons (ids `batch-view-{action}-btn`): batch-reading-add (/batches/{id}/readings/new), batch-addition-add (/batches/{id}/additions/new), batch-stage-move (/batches/{id}/stage), batch-transfer (/batches/{id}/transfer), batch-split (/batches/{id}/split), batch-blend-add (/batches/blend), batch-loss-add (/batches/{id}/losses/new), batch-dump (/batches/{id}/dump), yeast-harvest-add (/batches/{id}/yeast/new). Each is specified under its own entity below.

### List screen
- Columns: number (link, status dot) → `number`; product → `products.name`; stage → `stages.name` via `current_stage_code`, badge `info`; vessel(s) → open `vessel_occupancies` for the batch joined to `vessels.name`, comma-joined; volume → `current_volume_l` in gal; started → `started_at` medium date; tax class → `COALESCE(tax_class_override, tax_class_derived)` as badge (`hard_cider` success, anything else warning, null secondary); status → badge.
- Search: `number`, `products.name`; sort allowlist: `number`, `started_at`, `status`, `current_stage_code`, `product_name`; default `started_at DESC`; page size 25; status filter default active.
- Row link: batch-view.

### Pitch form (batch-add; ids `batch-form-field-{name}`)
| Field | Input | Required | Validation |
|---|---|---|---|
| product | select active cider products | yes | — |
| recipe_version | select (Pattern A fragment, reuse `/production-orders/recipe-options.php`), default active | no | belongs to product |
| production_order | select `production_orders` with `status = 'released'` for the product, label `number` | no | — |
| vessel | select active vessels, excluding `press`; the vessel where the batch will live | yes | I3 unless the vessel's open occupant is one of the selected juice lots (the batch takes over that vessel) |
| juice lots (repeating `batch-form-juice-row-{n}`) | lot select (Pattern A fragment `/batches/juice-lot-options.php`: lots with `item_class IN ('juice','intermediate')`, released, with an open `vessel_occupancies` row or on hand > 0; label `lot_number · brix · vessel · {gal} gal`), volume_gal | ≥ 1 row | ≤ occupancy volume (or on hand) |
| yeast_lot | select lots of `item_class = 'yeast'` released with on hand > 0 (label `lot_number · strain · gen {generation}`) | yes | — |
| yeast_qty | number in the yeast item's base unit | yes | > 0 |
| started_at | datetime-local default now | yes | — |
| notes | textarea | no | — |
- On save (`batches/save.php` without id; one transaction):
  1. Insert `batches` (number = `app.next_number('batch')`, premises = vessel's premises, product, recipe_version, production_order, origin_kind `pitch`, started_at, current_stage_code `pitch`, status `active`, current_volume_l = Σ juice liters, fruit_share_pct = volume-weighted average of each juice lot's `fruit_share_pct` attribute, defaulting 100 when absent, created_by).
  2. For each juice lot: `inventory_transactions` (txn_type `issue`, qty `−volume_l`, location = the lot's balance location (its vessel's `location_id`), counterparty_kind `batch`, counterparty_id = batch id, reference_kind `batch_consumption`, reference_id = the consumption id, ttb_category `used_in_production`, unit_cost_base = lot cost); `consumptions` (batch_id, item, lot, qty_base = volume_l, purpose `base_juice`, stage_code `pitch`, ledger_group_id); close the lot's `vessel_occupancies` row (`to_at = started_at`) if the whole volume was taken, else reduce `volume_l`.
  3. Yeast: `inventory_transactions` (`issue`, `−yeast_qty`, counterparty `batch`, reference_kind `batch_consumption`, ttb_category `used_in_production`); `consumptions` (purpose `yeast`, stage_code `pitch`).
  4. Insert `vessel_occupancies` (vessel, occupant_kind `batch`, occupant_id = batch, volume_l = current_volume_l, from_at = started_at); set `vessels.status = 'in_use'`.
  5. Insert `stage_events` (stage_code `pitch`, entered_at = started_at, volume_in_l = current_volume_l, actor).
  6. If a production order was given: set `production_orders.status = 'in_progress'`; mark the order's open `allocations` for the consumed items `released_at = now()` up to the consumed quantity.
  7. `log_activity('batch_pitched', entity batch, after = number, product, vessel, juice lots, yeast lot, volume)`.
  8. `HX-Redirect` to batch-view; `HX-Trigger: batchesChanged`.

### View screen (batch-view)
- Header card: number, status, product (link), recipe version (link), production order (link), stage badge, vessel(s), current volume gal, started, fruit share %, tax class (derived vs override shown as "override" `<small>` when set), days in current stage.
- Action buttons in the page header (hidden unless `status = 'active'`): reading, addition, move stage, transfer, split, blend, loss, harvest yeast, release (slice 8 adds it), package (slice 7 adds it), dump (`hx-confirm`), edit.
- Tabs (card-header nav-tabs pattern, ids `batch-view-tab-{name}`): **readings** (table newest first: measurement name, value with unit, taken at, stage, spec result dot pass success/fail danger/none secondary, analyst; above it a simple sparkline is out of scope: render a `table` only), **consumptions** (item, lot link, qty + unit, purpose, stage, when, by), **transfers** (from, to, volume gal, loss gal, when), **losses** (stage, qty gal, reason, TTB category, classification, approval), **lineage** (parents and children from `batch_lineage` with volume and fraction, plus the juice and fruit lots from `app.trace_backward(batch_id)` levels 1 and 2), **cost** (`app.v_batch_costs` row: material, packaging, overhead, total, per liter and per gallon, variance to standard; `app.v_batch_stage_yields` table: stage, in, out, actual loss %, expected loss %).

### Edit form (batch-edit; ids `batch-form-field-{name}`)
- notes (textarea); tax_class_override (select: none, hard_cider, still_wine, artificially_carbonated_wine, sparkling_wine; compliance or owner only; requires `tax_class_override_reason` select from `reason_codes` where `applies_to = 'override'`); on save sets `tax_class_override`, `_reason_code_id`, `_by`, `_at`; `hx-confirm` on the save button when the override changes. Logs `batch_tax_class_overridden` (before/after) or `batch_updated`.

### Files
- /var/www/html/batches/index.php · form.php (pitch) · edit.php · view.php · save.php · juice-lot-options.php · readings/new.php & save.php · additions/new.php & save.php · stage.php (GET form + POST) · transfer.php · split.php · blend.php · losses/new.php & save.php · dump.php · yeast/new.php & save.php
  (implemented as /var/www/html/batches/{readings,additions,losses,yeast}/ subdirectories with `new.php` rendering the form and `save.php` posting; `stage.php`, `transfer.php`, `split.php`, `blend.php`, `dump.php` render on GET and post on POST, per the exemplar's dual-mode pattern)
- /var/www/app/features/batches/queries.php
- /var/www/app/views/batches/page.php · partials/table.php · row.php · form.php · edit.php · view.php · tab-readings.php · tab-consumptions.php · tab-transfers.php · tab-losses.php · tab-lineage.php · tab-cost.php · reading-form.php · addition-form.php · stage-form.php · transfer-form.php · split-form.php · blend-form.php · loss-form.php · dump-form.php · yeast-form.php · saved.php · juice-lot-options.php

### Query functions (batches/queries.php)
- find_batches(PDO, search='', status_filter=['active'], sort='started_at', page=1): array · count_batches(PDO, search='', status_filter=[]): int
- find_batch(PDO, int id): ?array · find_batch_vessels(PDO, int id): array · find_batch_readings(PDO, int id): array · find_batch_consumptions(PDO, int id): array · find_batch_transfers(PDO, int id): array · find_batch_losses(PDO, int id): array · find_batch_lineage(PDO, int id): array · find_batch_cost(PDO, int id): ?array · find_batch_stage_yields(PDO, int id): array
- find_juice_lot_options(PDO): array · find_yeast_lot_options(PDO): array
- pitch_batch(PDO, array input, int user_id): array  (steps 1 to 6 above)
- update_batch(PDO, int id, ?string notes, ?string tax_class_override, ?int reason_code_id, int user_id): array
- recompute_batch_tax_class(PDO, int id): void  (sets `tax_class_derived` = `app.derive_tax_class('cider', latest abv reading, latest co2 reading, fruit_share_pct, products.contains_other_fruit, products.contains_flavoring)`; called after every reading and blend)
- Event functions listed under the entities below live in the same file.

### Action manifest entries
- Screens: batches-list, batch-add, batch-view, batch-edit (+ the event sub-screens below).
- Actions: batch_pitch (POST /batches/save; undo reverse while the batch has no later event: reverse the ledger group, reopen juice occupancies, status `closed` with note "voided"; no confirm; production) · batch_update (POST /batches/{id}/save; restore_prior) · batch_tax_class_override (POST /batches/{id}/tax-class — implemented inside edit save; restore_prior; confirm; compliance).

### Activity log events
- `screen_entered`; `batch_pitched`, `batch_updated`, `batch_tax_class_overridden`, plus the event names under each entity below. Entity type `batch`, label `number`.

### Status vocabulary
- active → info; packaged → success; dumped → danger; closed → secondary. Stage badge always `info`; tax class badge: hard_cider success, other classes warning, unknown secondary.

### Out of scope
- Packaging (slice 7), release (slice 8), fermentation charts (tables only; charts need a plan decision), beer and wine stages.

### Open Questions
- (none)

---

## Entity: reading (on a batch)

### Screen
| Screen id | Canonical URL | Purpose |
|---|---|---|
| batch-reading-add | /batches/{id}/readings/new | Full-container form; prefill `measurement`, `value` from the query string |

### Form (ids `batch-reading-form-field-{name}`)
- measurement (select `measurement_types`, label `name (unit)`; required), value (number; required; within `min_valid..max_valid` of the type), taken_at (datetime-local, default now), stage (select `stages` for cider, default the batch's current stage), method (text), note (textarea).
- Save inserts `readings` (target_kind `batch`, target_id, measurement_type_code, value, taken_at, stage_code, method, is_lab false, analyst_id = user); the 010 trigger sets `spec_id`/`spec_result`; then `recompute_batch_tax_class`. If `spec_result = 'fail'` the saved partial shows a `danger` alert "out of spec: {min}–{max}". Returns the readings tab partial with `HX-Trigger: batchesChanged`.

### Action / log
- batch_reading_record (POST /batches/{id}/readings/save; undo delete_row; production). Event `batch_reading_recorded` (after: measurement, value, spec_result).

### Open Questions
- (none)

---

## Entity: addition (consumption with a purpose)

### Screen
| Screen id | Canonical URL | Purpose |
|---|---|---|
| batch-addition-add | /batches/{id}/additions/new | Form; prefill `item`, `qty`, `purpose` |

### Form (ids `batch-addition-form-field-{name}`)
- item (select items with `item_class IN ('additive','yeast','juice','intermediate')` active; required), lot (Pattern A fragment `/batches/lot-options.php?item_id=`: released lots with on hand > 0, FEFO order; required when the item is lot-controlled; for `consumption_mode = 'backflush'` items the first FEFO lot is preselected), qty (number; required; > 0), unit (select: the item's base unit plus its `item_units`; converts with `to_base_factor`), purpose (select: nutrient, sulfite, enzyme, sweetener, acid, fining, base_juice, other; required), stage (default current), added_at (default now), note.
- Save (one transaction): `inventory_transactions` (`issue`, `−qty_base`, lot's primary location, counterparty `batch`, reference_kind `batch_consumption`, reference_id = consumption id, ttb_category `used_in_production`); `consumptions` (batch_id, item, lot, qty_base, purpose, stage_code, planned_qty_base = matching `recipe_lines` quantity scaled to the batch's starting volume when a line with the same item and stage exists, consumed_at, actor, ledger_group_id); if the item is juice or intermediate, add its liters to `batches.current_volume_l` and the open occupancy's `volume_l`; if purpose is `sweetener` or the item is juice, recompute `fruit_share_pct` (volume-weighted; sugar counts as 0 % fruit on its liters-equivalent only when the item's base unit is L, otherwise ignored) and the tax class. I1 applies (ledger).

### Action / log
- batch_addition_record (POST /batches/{id}/additions/save; undo reverse: reversal ledger row, delete consumption, restore volume). Event `batch_addition_recorded`.

### Open Questions
- (none)

---

## Entity: stage move

### Screen
| Screen id | Canonical URL | Purpose |
|---|---|---|
| batch-stage-move | /batches/{id}/stage | Form; prefill `stage` |

### Form (ids `batch-stage-form-field-{name}`)
- to_stage (select `stages` where `'cider' = ANY(beverage_types)` and `display_order >` current stage's order; required), moved_at (default now), volume_out_gal (number; the volume leaving the previous stage; default current volume; ≤ current volume), note.
- Save: update the open `stage_events` row for the batch (`left_at = moved_at`, `volume_out_l`); insert a new `stage_events` row (stage_code = to_stage, entered_at = moved_at, volume_in_l = volume_out_l); if `volume_out_l < current_volume_l` the difference is recorded as an **expected** loss: insert `loss_events` (target batch, stage = the previous stage, qty_base = difference, unit `L`, reason_code = the stage's default reason: rack → `RACK`, primary → `LEES`, otherwise `RACK`, ttb_category copied from the reason code, reportable true, classification `expected`, no approval); set `batches.current_stage_code`, `current_volume_l = volume_out_l`, update the open occupancy volume. Terminal stages (`stages.is_terminal`) are not selectable here; `package` is reached only through slice 7.

### Action / log
- batch_stage_move (POST /batches/{id}/stage; undo restore_prior: reopen the previous stage event, delete the new one and the generated loss). Event `batch_stage_moved` (before/after stage and volume).

### Open Questions
- (none)

---

## Entity: transfer (vessel to vessel)

### Screen
| Screen id | Canonical URL | Purpose |
|---|---|---|
| batch-transfer | /batches/{id}/transfer | Form; prefill `to_vessel`, `volume_gal`, `loss_gal` |

### Form (ids `batch-transfer-form-field-{name}`)
- from_vessel (select of the batch's open occupancies; required), to_vessel (select active vessels not `press`, excluding from; required; I3; I4 warning), volume_gal (required; ≤ from occupancy volume), loss_gal (default 0; ≥ 0; ≤ volume), transferred_at (default now), note.
- Save (one transaction): insert `batch_transfers`; reduce or close the from occupancy (`volume_l −= volume_l`, `to_at` when it reaches 0; set from vessel `status = 'empty'` when closed); open or increase the to occupancy (occupant batch); if `loss_l > 0` insert `loss_events` (stage = current, reason `RACK`, classification expected, qty = loss_l, ttb_category from the code) and reduce `batches.current_volume_l` by loss_l; set to vessel `status = 'in_use'`.

### Action / log
- batch_transfer (POST /batches/{id}/transfer; undo reverse: inverse transfer with zero loss and deletion of the generated loss). Event `batch_transferred`.

### Open Questions
- (none)

---

## Entity: split

### Screen
| Screen id | Canonical URL | Purpose |
|---|---|---|
| batch-split | /batches/{id}/split | Form |

### Form (ids `batch-split-form-field-{name}`, rows `batch-split-form-output-row-{n}`)
- split_at (default now); outputs: vessel (active, not press; I3 unless it is the source vessel; I4 warning), volume_gal (> 0); Σ volumes ≤ current volume; the remainder, if any, stays in the source batch in its vessel; note.
- Save (one transaction): insert `batch_splits` (source_batch_id, split_at, actor); for each output row: insert a child `batches` row (number = next_number('batch'), same premises, product, recipe_version, production_order; origin_kind `split`; started_at = split_at; current_stage_code = source's; status active; current_volume_l = volume_l; fruit_share_pct = source's; tax_class_derived = source's), insert `batch_split_outputs`, insert `batch_lineage` (child, parent = source, event_kind `split`, event_id = split id, volume_l, fraction = volume_l / source current_volume_l before the split), insert `stage_events` for the child (stage = current, entered_at = split_at, volume_in_l), open `vessel_occupancies` for the child; reduce the source's occupancy and `current_volume_l` by Σ volumes; if the source reaches 0, close its occupancy and set source `status = 'closed'`, `closed_at = split_at`, note "split into {numbers}".

### Action / log
- batch_split (POST /batches/{id}/split; undo reverse only while no child has an event beyond its first stage_event). Event `batch_split` (after: child numbers and volumes).

### Open Questions
- (none)

---

## Entity: blend

### Screen
| Screen id | Canonical URL | Purpose |
|---|---|---|
| batch-blend-add | /batches/blend | Form; prefill `vessel` |

### Form (ids `batch-blend-form-field-{name}`, rows `batch-blend-form-input-row-{n}`)
- inputs: batch (select active batches, label `number · product · {gal} gal`), volume_gal (> 0, ≤ that batch's current volume); ≥ 2 rows; vessel (active, not press; I3 unless it currently holds one of the input batches; I4 warning); product (select; default the product of the largest input); recipe_version (optional); blended_at (default now); note.
- Save (one transaction): insert the result `batches` row (number = next_number('batch'), origin_kind `blend`, started_at = blended_at, current_stage_code `blend`, status active, current_volume_l = Σ input volumes, fruit_share_pct = Σ(volume × input fruit_share) / Σ volume); insert `batch_blends` (result, vessel, volume_out_l, blended_at, actor) and `batch_blend_inputs`; for each input: `batch_lineage` (child = result, parent = input, event_kind `blend`, event_id = blend id, volume_l, fraction = volume_l / Σ volumes); reduce the input's occupancy and `current_volume_l`, close it and set status `closed` when it reaches 0 (note "blended into {number}"); close the input batches' open stage event (`left_at`, `volume_out_l`); insert `stage_events` for the result (stage `blend`, volume_in_l); open the result's occupancy; `recompute_batch_tax_class(result)`.

### Action / log
- batch_blend (POST /batches/blend; undo reverse while the result has no later event). Event `batch_blended` (after: result number, inputs with volumes).

### Open Questions
- (none)

---

## Entity: loss

### Screen
| Screen id | Canonical URL | Purpose |
|---|---|---|
| batch-loss-add | /batches/{id}/losses/new | Form; prefill `qty_gal`, `reason` |

### Form (ids `batch-loss-form-field-{name}`)
- qty_gal (required; > 0; ≤ current volume), reason (select `reason_codes` where `applies_to IN ('loss','dump')` and active; required), stage (default current), occurred_at (default now), note (required when the reason's `classification = 'exceptional'`).
- Save: insert `loss_events` (target_kind batch, target_id, premises, stage_code, qty_base = liters, unit `L`, reason_code_id, ttb_category = `reason_codes.ttb_category`, reportable = ttb_category <> 'none', classification = `reason_codes.classification`, approved_by/at = NULL); reduce `batches.current_volume_l` and the open occupancy by qty. **Approval threshold:** when `reason_codes.requires_approval_above IS NOT NULL` and `qty_base > requires_approval_above` the save still posts but the saved partial shows a `warning` alert "needs approval" and the losses tab shows an Approve button (`batch-view-loss-{id}-approve-btn`, owner or compliance, POST /batches/{id}/losses/{loss}/approve sets approved_by/at). The command bar confirms first in that case (manifest: confirm when exceptional above threshold).

### Action / log
- batch_loss_record (POST /batches/{id}/losses/save; undo reverse: delete the loss event and restore volume). Events `batch_loss_recorded`, `batch_loss_approved`.

### Open Questions
- (none)

---

## Entity: dump

### Screen
| Screen id | Canonical URL | Purpose |
|---|---|---|
| batch-dump | /batches/{id}/dump | Form (destructive; the Save button carries `hx-confirm`) |

### Form (ids `batch-dump-form-field-{name}`)
- reason (select `reason_codes` where `applies_to = 'dump'`; required), note (required), dumped_at (default now).
- Save: insert `loss_events` for the whole `current_volume_l` (classification exceptional, ttb_category from the code, normally `destroyed`); close the batch's open occupancies (`to_at`), set each vessel `status = 'cleaning'`; close the open stage event; set `batches.status = 'dumped'`, `current_volume_l = 0`, `closed_at`; if the batch has a production order with no other active batch, set the order `status = 'complete'`.

### Action / log
- batch_dump (POST /batches/{id}/dump; undo none; confirm yes). Event `batch_dumped`.

### Open Questions
- (none)

---

## Entity: yeast harvest

### Screen
| Screen id | Canonical URL | Purpose |
|---|---|---|
| yeast-harvest-add | /batches/{id}/yeast/new | Form; prefill `volume_l`, `generation` |

### Form (ids `yeast-harvest-form-field-{name}`)
- yeast_item (select items with `item_class = 'yeast'`; default the item of the batch's `purpose = 'yeast'` consumption), generation (int ≥ 1; default the pitched yeast lot's `generation` attribute + 1, else 1), volume_l (number > 0; entered in liters, this is the one liquid field not in gallons: yeast slurry is measured in liters), cell_count, viability_pct, harvested_at (default now), location (select `cold_room`/`freezer` locations), note.
- Save (one transaction): insert `lots` (number = next_number('lot'), item = yeast_item, premises, produced_on, expires_on = produced_on + item shelf_life_days when set, quality_status `released`, unit_cost_base 0, source_kind `yeast_harvest`, source_id = harvest id after insert, so insert `yeast_harvests` first with a placeholder? No: insert `lots` with `source_id = 0`, insert `yeast_harvests` (source_batch_id, lot_id, generation, harvested_at, volume_l, cell_count, viability_pct, actor), then update `lots.source_id` to the harvest id); `lot_attributes`: `strain` (value_text from the pitched lot's `strain` attribute when present), `generation` (value_num), `source_batch` (value_text = batch number), `viability_pct` (value_num) when given; `inventory_transactions` (`production_output`, `+volume_l`, location chosen, counterparty `batch`, reference_kind `yeast_harvest`, ttb_category `none`).

### Action / log
- yeast_harvest_record (POST /batches/{id}/yeast/save; undo reverse: reversal ledger row, lot marked rejected). Event `yeast_harvested` (after: lot number, generation).

### Open Questions
- (none)

---

## Entity: pomace disposition

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| pomace-disposition-add | /dispositions/new | Form; prefill `lot_number`, `destination` |

(No list screen: dispositions appear on lot-view for co-product lots and in the records MCP tool `co_product_dispositions`.)

### Form (ids `pomace-disposition-form-field-{name}`)
- lot (select lots of `item_class = 'co_product'` with on hand > 0, label `lot_number · item · {lb} lb`; required), qty_lb (required; > 0; ≤ on hand), destination (select: compost, farm, sale, waste, other; required), recipient (text), disposed_at (default now), note.
- Save: insert `co_product_dispositions` (lot, qty_base = kg, destination, recipient, disposed_at, actor, ledger_group_id); `inventory_transactions` (txn_type `destruction` for compost/waste, `removal` for farm/sale/other; qty `−kg`; lot's primary location; counterparty_kind `disposal`; reference_kind `co_product_disposition`; ttb_category `none`). Redirect to lot-view of the lot.

### Files
- /var/www/html/dispositions/form.php · save.php · /var/www/app/features/dispositions/queries.php · /var/www/app/views/dispositions/partials/form.php · saved.php

### Query functions
- find_co_product_lot_options(PDO): array · insert_disposition(PDO, int lot_id, float qty_kg, string destination, ?string recipient, string disposed_at, ?string note, int user_id): array

### Action / log
- pomace_disposition_record (POST /dispositions/save; undo reverse). Event `pomace_disposed`.

### Status vocabulary
- none (no states).

### Out of scope
- Revenue from pomace sales; weighbridge integration.

### Open Questions
- (none)
