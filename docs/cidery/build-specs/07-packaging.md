# Build spec: packaging slice (slice 7)

Exemplar to replicate: receiving slice (slice 2, `goods_receipts` / `lots`, built by the planning-class model).
Model class: worker. Build each entity exactly like the exemplar, applying this spec. If anything is ambiguous, conflicting, or missing, STOP, record the exact question under Open Questions, and escalate.

Schema tables (never modify): `app.packaging_runs`, `app.packaging_run_materials`, `app.finished_lots`, `app.lots`, `app.lot_attributes`, `app.kegs`, `app.keg_movements`, `app.tax_class_rules`, `app.inventory_transactions`, `app.vessel_occupancies`, `app.loss_events`, `app.batches`, `app.packaging_configurations`, `app.packaging_bom_lines`. Views: `app.v_finished_stock`, `app.v_keg_fleet`, `app.v_lot_balances`. Functions: `app.derive_tax_class`, `app.next_number('packaging_run')`, `app.next_number('lot')`.

Units: volumes are entered in gallons and stored in liters (`volume_in_l`, `volume_out_l`, `loss_l`, `fill_volume_l`, `unit_volume_l`, `size_l`); convert with 3.785411784 in the controller (`gal_to_l()` / `l_to_gal()` helpers from the shell). CO2 is entered and stored in g/100 mL. ABV in percent.

---

## Entity: packaging run

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| packaging-runs-list | /packaging-runs/ | List per the canonical table pattern |
| packaging-run-add | /packaging-runs/new | Full-container form (empty); prefill `batch`, `package` |
| packaging-run-edit | /packaging-runs/{id}/edit | Same form, pre-filled (draft only; posted runs redirect to view) |
| packaging-run-view | /packaging-runs/{id} | Detail: header, materials, loss vs expected, finished lot, tax class; Post button |

### List screen
- Columns, in order: number → `number` (row link, status dot); batch → `batches.number` with product name as `<small>`; package → `packaging_configurations.name`; run date → `run_on` (medium date); volume in → `volume_in_l` shown in gal (1 decimal); units out → `units_out`; loss → `loss_l` in gal with percent `<small>`; status → `status` badge; actions → Edit (draft) or View.
- Search matches: `number`, batch number, product name; sort allowlist: `run_on`, `number`, `status`; page size: 25.
- Row link target: packaging-run-view.
- Filter (query param `status`): draft, posted, all (default all except cancelled).

### Form
Fields, in order (ids `packaging-run-form-field-{name}`):
- batch | select (active batches, label `number — product — vessel`) | required | must be `status = 'active'` and `current_stage_code in ('carbonate','package','maturation','blend','back_sweeten')` | `packaging-run-form-field-batch-id`
- packaging_configuration | select (configs active for the batch's product; reloaded on batch change via Pattern A `/packaging-runs/options.php?batch_id=`) | required | | `-packaging-configuration-id`
- run_on | date | required | default today | `-run-on`
- source_vessel | select (vessels currently occupied by the batch, from `vessel_occupancies` where `occupant_kind='batch' and to_at is null`) | required | | `-source-vessel-id`
- output_location | select (locations kind `packaged_goods`, same premises) | required | | `-output-location-id`
- volume_in_gal | number step 0.1 | required | > 0 and ≤ occupancy volume | `-volume-in-gal`
- units_out | integer | required on post | > 0 | `-units-out`
- abv_at_packaging | number step 0.01 | required on post | 0–25 | `-abv-at-packaging`
- co2_g_100ml | number step 0.001 | required on post | 0–2 | `-co2-g-100ml`
- started_at, finished_at | datetime-local | optional | finished ≥ started | `-started-at`, `-finished-at`
- notes | textarea | optional | | `-notes`
- Materials tab (`packaging-run-form-tab-materials`): one row per `packaging_bom_lines` of the configuration, prefilled `qty_base = qty_per_unit_base × units_out`; columns item, mode (`items.consumption_mode`), qty, lot (select of released lots with stock, required when mode = explicit; blank for backflush, resolved FEFO at post). Rows editable; ids `packaging-run-form-material-{item_id}-qty`, `-lot-id`.
- Derived readback (readonly, recomputed on change): volume out = units_out × fill_volume_l; loss = volume_in − volume_out; loss % vs `expected_loss_pct`; derived tax class via `app.derive_tax_class(product.beverage_type, abv, co2, batch.fruit_share_pct, product.contains_other_fruit, product.contains_flavoring)`.

### Files (exactly these)
- /var/www/html/packaging-runs/index.php · form.php · view.php · save.php · post.php · delete.php · options.php
- /var/www/app/features/packaging-runs/queries.php
- /var/www/app/views/packaging-runs/page.php · partials/table.php · row.php · form.php · view.php · materials.php · saved.php

### Query functions (signatures fixed)
- find_packaging_runs(PDO, search='', status='', sort='run_on', page=1): array
- find_packaging_run(PDO, int id): ?array  (joins batch number, product, configuration, finished lot)
- find_packaging_run_materials(PDO, int id): array
- find_bom_for_configuration(PDO, int configuration_id): array
- find_batch_vessels(PDO, int batch_id): array
- insert_packaging_run(PDO, int premises_id, int batch_id, int configuration_id, ?int source_vessel_id, int output_location_id, string run_on, ?float volume_in_l, ?int units_out, ?float abv, ?float co2, ?string started_at, ?string finished_at, ?string notes, int created_by): array
- update_packaging_run(PDO, int id, ...same explicit fields): array
- replace_packaging_run_materials(PDO, int id, array lines): void
- post_packaging_run(PDO, int id, int actor_id): array — inside one transaction, in this order: (1) `UPDATE batches SET current_volume_l = current_volume_l - volume_in_l`; (2) insert `lots` row (`lot_number = app.next_number('lot')`, `item_id = configuration.finished_item_id`, `premises_id`, `produced_on = run_on`, `quality_status = 'released'`, `unit_cost_base` = liquid cost per unit from `v_batch_costs.liquid_cost_per_l × unit_volume_l` + packaging standard cost per unit, `source_kind = 'packaging_run'`, `source_id = id`); (3) insert `finished_lots` (`units_packaged = units_out`, `unit_volume_l = fill_volume_l`, `abv`, `co2_g_100ml`, `fruit_share_pct` from batch, `tax_class` from `app.derive_tax_class`, `tax_class_source = 'derived'`, `best_before_on = run_on + items.shelf_life_days`, `label_approval_id` = approved label approval for product + configuration if any); (4) insert `lot_attributes` abv, co2_g_100ml, fruit_share_pct, tax_class (source `packaging_run`); (5) for each material: resolve backflush lots FEFO from `v_lot_balances` (released, qty_available ≥ qty), then `inventory_transactions` row `txn_type = 'issue'`, `qty_base` negative, `counterparty_kind = 'packaging_run'`, `counterparty_id = id`, `ttb_category = 'none'`, `reference_kind = 'packaging_run'`, `reference_id = id`, `idempotency_key = 'pkg:{id}:mat:{material_id}'`; (6) `inventory_transactions` row `txn_type = 'packaging_output'`, `qty_base = units_out`, `location_id = output_location_id`, `unit_cost_base` = lot unit cost, `counterparty_kind = 'batch'`, `ttb_category = 'bottled'`, `idempotency_key = 'pkg:{id}:out'`; (7) if `loss_l > 0`: `loss_events` row (`target_kind = 'batch'`, `stage_code = 'package'`, `qty_base = loss_l`, reason code `PKG`, `ttb_category = 'inventory_loss'`, `classification = 'expected'` when loss % ≤ expected_loss_pct else `'exceptional'`); (8) `stage_events` row stage `package` with `volume_in_l`, `volume_out_l`; (9) if the source vessel occupancy volume − volume_in_l ≤ 0: set `vessel_occupancies.to_at = now()`, `vessels.status = 'empty'`, and if batch `current_volume_l ≤ 0` set `batches.status = 'packaged'`, `current_stage_code = 'package'`; else reduce occupancy `volume_l`; (10) set `packaging_runs` `status = 'posted'`, `volume_out_l`, `loss_l`, `posted_by`, `posted_at`. All ledger writes share one `group_id`.
- Release gate (decided 2026-10-01): before step (1), `post_packaging_run` looks for the batch's latest `release_decisions` row (`target_kind = 'batch'`) with `to_status = 'released'` dated after the batch's current stage entry. If none exists and `app.client_settings.settings->>'require_batch_release'` is `'true'`, abort with "batch B-26-003 has not been released for packaging". If the setting is absent or `'false'` (the state until slice 8 ships), post anyway and record `details.release_missing = true` on the `packaging_run_posted` activity row. Slice 8 sets the setting to `'true'` on deploy.
- delete_packaging_run(PDO, int id): bool — draft only.

### Action manifest entries
- Screens: the four above.
- Actions: `packaging_run_create` / `packaging_run_update` → `POST /packaging-runs/save` (params batch, package, run_on, volume_in_gal, units_out, co2, abv, materials[]; undo delete_row / restore_prior, draft only); `packaging_run_post` → `POST /packaging-runs/{id}/post` (undo: reverse — posts reversal ledger rows for every row in the group, marks finished lot `quality_status = 'rejected'`, reopens occupancy; confirm no).

### Activity log events
- `screen_entered` for each screen; `packaging_run_created`, `packaging_run_updated`, `packaging_run_posted` (after = {finished_lot, units_out, loss_l, tax_class}), `packaging_run_deleted`.

### Status vocabulary mapping
- draft → dark; posted → success; cancelled → danger.

### Out of scope for this slice
- Bottle-conditioned or still cider; package-level CO2 readings; printing labels or GS1 barcodes; costing beyond copying `v_batch_costs.liquid_cost_per_l`; editing a posted run (reversal only).

### Open Questions
- (none)

---

## Entity: finished lot

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| finished-lots-list | /finished-lots/ | List over `app.v_finished_stock` |
| finished-lot-view | /finished-lots/{id} | Detail: batch, package, balances by location, tax class check, removals, kegs; override control |

No add or edit form: finished lots are created by posting a packaging run. `{id}` is `finished_lots.lot_id`.

### List screen
- Columns, in order: lot → `lot_number` (row link, dot by `tax_state`: bonded info, tax_paid success); product → `product_name` with `package_name` `<small>`; batch → `batch_number`; packaged → `packaged_on`; on hand → `units_on_hand` with `units_available` `<small>`; volume → `volume_on_hand_l` in gal; tax class → `tax_class` badge; location → `location_name`; actions → View.
- Search matches: `lot_number`, `product_name`, `batch_number`; sort allowlist: `packaged_on`, `lot_number`, `product_name`; page size: 25.
- Filters: `product_id`, `package_kind`, `location_id`.
- Row link target: finished-lot-view.

### Form
- Tax class override only, rendered inline on the view (Pattern C, replaces `#finished-lot-view-tax-class-card`): tax_class | select (hard_cider, still_wine, artificially_carbonated_wine, sparkling_wine) | required | `finished-lot-view-field-tax-class`; reason_code | select (`reason_codes` where `applies_to = 'override'`, default `TAXOVR`) | required | `-reason-code-id`; note | text | optional. Submit carries `hx-confirm`.
- Tax class check panel shows abv, co2_g_100ml, fruit_share_pct, product flags, the derived class from `app.derive_tax_class`, and the margin to each hard-cider limit (0.64 g/100 mL, 8.5 % ABV, 50 % fruit share).

### Files (exactly these)
- /var/www/html/finished-lots/index.php · view.php · tax-class.php
- /var/www/app/features/finished-lots/queries.php
- /var/www/app/views/finished-lots/page.php · partials/table.php · row.php · view.php · tax-class-card.php

### Query functions (signatures fixed)
- find_finished_lots(PDO, search='', filters=[], sort='packaged_on', page=1): array
- find_finished_lot(PDO, int lot_id): ?array
- find_finished_lot_balances(PDO, int lot_id): array
- find_finished_lot_removals(PDO, int lot_id): array
- find_finished_lot_kegs(PDO, int lot_id): array
- derive_finished_lot_tax_class(PDO, int lot_id): ?string
- override_finished_lot_tax_class(PDO, int lot_id, string tax_class, int reason_code_id, int actor_id): array — sets `tax_class`, `tax_class_source = 'override'`, `tax_class_override_reason_code_id`, `tax_class_override_by`; upserts `lot_attributes` key `tax_class`.

### Action manifest entries
- Screens: the two above.
- Actions: `finished_lot_tax_class_override` → `POST /finished-lots/{id}/tax-class` (undo restore_prior; confirm yes; role compliance).

### Activity log events
- `screen_entered`; `finished_lot_tax_class_overridden` (before/after tax_class and source).

### Status vocabulary mapping
- Tax state dot: bonded → info, tax_paid → success. Tax class badge: hard_cider → success, others → warning.

### Out of scope for this slice
- Allocations to customers; best-before alerts; label printing.

### Open Questions
- (none)

---

## Entity: keg

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| kegs-list | /kegs/ | Fleet list over `app.v_keg_fleet` with state summary tiles |
| keg-add | /kegs/new | Register a keg; prefill `serial`, `size` |
| keg-edit | /kegs/{id}/edit | Same form, pre-filled |
| keg-view | /kegs/{id} | Detail with movement history and the state-change buttons |
| keg-return | /kegs/return | Textarea of serials, one per line, optional customer; returns all |

### List screen
- Columns, in order: serial → `serial` (row link, dot by state); size → `size_l` in gal; state → `state` badge; contents → `lot_number`; holder → `holder_name`; days → `days_since_moved`; fills → `fill_count`; actions → Edit, View.
- Search matches: `serial`, `lot_number`, `holder_name`; sort allowlist: `serial`, `state`, `last_moved_at`, `days_since_moved`; page size: 50.
- Filters: `state`, `customer_id`, `older_than_days`.
- Row link target: keg-view.

### Form (add / edit)
- serial | text | required | unique | `keg-form-field-serial`
- size_gal | number step 0.01 | required | > 0; stored in `size_l` | `-size-gal`
- ownership | select owned, rented, customer_owned | required | `-ownership`
- deposit_amount | number step 0.01 | required | ≥ 0 | `-deposit-amount`
- notes | textarea | optional | `-notes`
- Register also creates a `keg_movements` row event `found`? No: registration writes no movement; `kegs.state` defaults `empty`, `current_holder_kind = 'location'`, `current_holder_id` = the first `packaged_goods` location of the premises.

### State transitions (buttons on keg-view, each `hx-post`, Pattern C replacing `#keg-view-state-card`)
| Action | Allowed from | Sets | Movement row |
|---|---|---|---|
| fill | empty | state filled, `current_lot_id`, `fill_count + 1`, `last_moved_at` | event fill, `lot_id` |
| return | at_customer, filled | state returned_dirty, `current_holder_kind = 'location'`, `current_holder_id` = packaged_goods location, `current_lot_id = NULL` | event return, `customer_id` |
| clean | returned_dirty | state empty, `last_cleaned_at` | event clean |
| mark_lost | any except out_of_service | state lost, `current_holder_kind = 'unknown'`, `current_holder_id = NULL` | event mark_lost (confirm) |
| found | lost | state returned_dirty, holder = packaged_goods location | event found |
| retire | empty, returned_dirty, lost | state out_of_service | event retire (confirm) |
Fill requires a finished lot select (`finished_lots` joined `packaging_configurations.package_kind = 'keg'` with available units); fill also posts nothing to the ledger (the finished lot already counts units; the keg is the container). Ship happens in slice 10 (removal post).

### Files (exactly these)
- /var/www/html/kegs/index.php · form.php · view.php · save.php · state.php · return.php · delete.php
- /var/www/app/features/kegs/queries.php
- /var/www/app/views/kegs/page.php · partials/table.php · row.php · form.php · view.php · state-card.php · return-form.php · saved.php

### Query functions (signatures fixed)
- find_kegs(PDO, search='', filters=[], sort='serial', page=1): array
- find_keg(PDO, int id): ?array
- find_keg_by_serial(PDO, string serial): ?array
- find_keg_movements(PDO, int id): array
- find_keg_state_counts(PDO): array
- insert_keg(PDO, string serial, float size_l, string ownership, float deposit_amount, ?string notes, int holder_location_id): array
- update_keg(PDO, int id, string serial, float size_l, string ownership, float deposit_amount, ?string notes): array
- transition_keg(PDO, int id, string event, ?int lot_id, ?int customer_id, ?int location_id, int actor_id, ?string note): array — validates the allowed-from table above, updates `kegs`, inserts `keg_movements`; one transaction.
- return_kegs_by_serial(PDO, array serials, ?int customer_id, int actor_id): array — returns per-serial result (returned / not found / wrong state).
- delete_keg(PDO, int id): bool — only when `fill_count = 0` and no movements.

### Action manifest entries
- Screens: the five above.
- Actions: `keg_register` / `keg_update` → `POST /kegs/save`; `keg_fill` → `POST /kegs/{id}/fill` (param finished_lot; undo reverse); `keg_return` → `POST /kegs/return` (serials[], customer?; undo reverse); `keg_clean` → `POST /kegs/{id}/clean`; `keg_mark_lost` → `POST /kegs/{id}/lost` (confirm); `keg_found` → `POST /kegs/{id}/found`; `keg_retire` → `POST /kegs/{id}/retire` (confirm, undo none). `state.php` serves fill/clean/lost/found/retire by `event` parameter; the manifest endpoints map to `state.php?event=`.

### Activity log events
- `screen_entered`; `keg_registered`, `keg_updated`, `keg_filled`, `keg_returned`, `keg_cleaned`, `keg_marked_lost`, `keg_found`, `keg_retired`, `keg_deleted`.

### Status vocabulary mapping
- empty → success; returned_dirty, cleaning → warning; lost → danger; filled, at_customer → info; out_of_service → secondary.

### Out of scope for this slice
- Deposit accounting (events `deposit_collected` / `deposit_refunded` exist in the schema but get no screen yet); barcode scanning hardware; rental pool reporting.

### Open Questions
- (none)
