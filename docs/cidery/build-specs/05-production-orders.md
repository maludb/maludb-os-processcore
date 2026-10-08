# Build spec: production orders slice (slice 5)

Exemplar to replicate: the **receiving** slice (slice 2, built by the planning-class model). Build this slice exactly like receiving, applying this spec. If anything here is ambiguous, conflicting, or missing, STOP, record the exact question under Open Questions, and escalate. Do not improvise.

Schema tables (approved Phase 1, never modify): `app.production_orders`, `app.production_order_vessels`, `app.allocations`; read-only use of `app.products`, `app.recipe_versions`, `app.recipe_lines`, `app.vessels`, `app.vessel_occupancies`, `app.premises`, `app.lots`, `app.v_item_stock`, `app.v_lot_balances`, `app.v_vessel_board`, `app.number_sequences` via `app.next_number('production_order')`.

Unit rules for every form in this slice: volumes are entered in gallons (`*_gal` fields) and stored in liters (`* 3.785411784`, round to 3 decimals); displayed back in gallons (`/ 3.785411784`, 1 decimal). Quantities in the material check are shown in the item's `base_unit_code` plus the client display unit from `app.client_settings` (volume → gal, mass → lb).

---

## Entity: production order

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| production-orders-list | /production-orders/ | List per the canonical table pattern |
| production-order-add | /production-orders/new | Full-container form (empty) |
| production-order-edit | /production-orders/{id}/edit | Same form, pre-filled; only while `status = 'planned'` |
| production-order-view | /production-orders/{id} | Detail: header, vessel plan with conflict warnings, material check, allocations, action buttons |

### List screen
- Columns, in order: number (row link, with status dot) → `number`; product → `products.name`; recipe version → `recipe_versions.version_no` as `v{n}`; planned volume → `planned_volume_l` in gal, 1 decimal; pitch date → `planned_pitch_on`, medium date; package date → `planned_package_on`, medium date; status → dot + badge per vocabulary; actions → Edit (planned only) and View.
- Search matches: `number`, `products.name`; sort allowlist: `number`, `planned_pitch_on`, `planned_package_on`, `status`, `product_name`; default sort `planned_pitch_on DESC NULLS LAST`; page size 25.
- Filter (page header, `hx-get` refresh of the results region): status select `production-orders-list-filter-status` (all, planned, released, in_progress, complete, closed, cancelled); default "planned, released, in_progress".
- Row link target: production-order-view.

### Form
Fields, in order (all ids `production-order-form-field-{name}`):

| Field | Input | Required | Validation | id suffix |
|---|---|---|---|---|
| product | select, option source `products` where `status = 'active'` and `beverage_type = 'cider'`, label `name` | yes | must exist | product |
| recipe_version | select, options loaded by Pattern A fragment `/production-orders/recipe-options.php?product_id=` on product change; `recipe_versions` for that product with `status IN ('active','draft')`, label `v{version_no} ({status})`, default the active one | yes | must belong to the product | recipe-version |
| planned_volume_gal | number step 0.1 | yes | > 0; prefill from `recipe_versions.target_batch_volume_l / 3.785411784` when the recipe is selected | planned-volume-gal |
| planned_pitch_on | date | no | — | planned-pitch-on |
| planned_package_on | date | no | ≥ planned_pitch_on when both set | planned-package-on |
| premises | select from `premises` where `active`; hidden and auto-set when exactly one premises exists | yes | — | premises |
| notes | textarea | no | — | notes |
| vessel plan | repeating rows (table inside the form card, ids `production-order-form-vessel-row-{n}`): vessel select (`vessels` where `active`, label `name (capacity gal)`), role select (primary, maturation, brite, blend), planned_from date, planned_to date; add row button `production-order-form-vessel-add-btn`, remove button per row `production-order-form-vessel-row-{n}-remove-btn` | at least one row | planned_to ≥ planned_from; a row with a vessel whose `capacity_l < planned_volume_l` renders a warning text under the row, not an error | vessel-{n}-vessel, vessel-{n}-role, vessel-{n}-from, vessel-{n}-to |

- Tabs: none.
- On save with validation errors: re-render the form partial in place with the Bootstrap `is-invalid` pattern from the exemplar.
- On successful save: `HX-Redirect` to production-order-view.

### View screen (production-order-view)
Panels, in order, copied from the receipt view pattern:
1. Header card: number, status badge, product, recipe version link to recipe-view, planned volume (gal), dates, premises, created by / released by / closed by with dates.
2. Vessel plan card `production-order-view-vessels`: table of `production_order_vessels` rows with vessel, role, from, to, capacity, and a **conflict** column. Conflict logic (query function `find_vessel_conflicts`): for each planned row, a warning badge (`warning`) is shown when (a) another `production_order_vessels` row for a different order with `status IN ('planned','released','in_progress')` overlaps the date range on the same vessel (`daterange(planned_from, planned_to, '[]') && daterange(other.planned_from, other.planned_to, '[]')`), or (b) `vessel_occupancies` has an open row (`to_at IS NULL`) for that vessel and the occupant is not this order's batch. Warnings never block.
3. Material check card `production-order-view-materials` (query function `find_material_check`): one row per `recipe_lines` row of the order's recipe version; required = `qty_per_batch_base` if set, else `qty_per_l * planned_volume_l`; available = `v_item_stock.qty_available` for the item (released lots only, computed from `v_lot_balances` where `quality_status = 'released'`); on order = `v_item_stock.qty_on_order`; shortfall = max(0, required − available); row dot `danger` when shortfall > 0, `success` otherwise. Shown in base unit and display unit.
4. Allocations card `production-order-view-allocations`: `allocations` rows for the order (item, lot or "any lot", qty, created, released), visible once status ≠ planned.
5. Action buttons in the page header (`production-order-view-release-btn`, `-close-btn`, `-cancel-btn`, `-edit-btn`), each `hx-post` to its endpoint; cancel carries `hx-confirm`.

### Files (exactly these, no additions)
- /var/www/html/production-orders/index.php · form.php · view.php · save.php · release.php · close.php · cancel.php · calendar.php · recipe-options.php
- /var/www/app/features/production-orders/queries.php
- /var/www/app/views/production-orders/page.php · partials/table.php · row.php · form.php · view.php · calendar.php · saved.php · recipe-options.php

### Query functions (signatures fixed)
- find_production_orders(PDO, search='', status_filter=[], sort='planned_pitch_on', page=1): array
- count_production_orders(PDO, search='', status_filter=[]): int
- find_production_order(PDO, int id): ?array  (joins product name, recipe version_no, premises name, user display names)
- find_production_order_vessels(PDO, int id): array
- find_vessel_conflicts(PDO, int id): array  (keyed by production_order_vessels.id → list of conflicts {kind: 'plan'|'occupancy', label})
- find_material_check(PDO, int id): array
- find_allocations(PDO, int id): array
- find_recipe_options(PDO, int product_id): array
- insert_production_order(PDO, int premises_id, int product_id, int recipe_version_id, float planned_volume_l, ?string planned_pitch_on, ?string planned_package_on, ?string notes, int created_by): array  (calls `app.next_number('production_order')` for `number`; status planned)
- update_production_order(PDO, int id, int product_id, int recipe_version_id, float planned_volume_l, ?string planned_pitch_on, ?string planned_package_on, ?string notes): array  (only when status = planned, else throw)
- replace_production_order_vessels(PDO, int id, array rows): void  (delete + insert inside the caller's transaction)
- release_production_order(PDO, int id, int user_id): array  (sets status released, released_by/at; inserts one `allocations` row per recipe line with `lot_id NULL`, `qty_base` = required quantity as in the material check)
- close_production_order(PDO, int id, int user_id): array  (status closed, closed_by/at; sets `released_at = now()` on open allocations)
- cancel_production_order(PDO, int id, int user_id): array  (status cancelled; releases open allocations)
- find_calendar_rows(PDO, string from, string to): array  (production_order_vessels joined to orders in planned/released/in_progress, plus open vessel_occupancies, within the window)

### Action manifest entries
- Screens: the table above, with the "when the user wants…" lines from 05-action-manifest.md (production-orders-list, production-order-add, production-order-edit, production-order-view, production-calendar).
- Actions: production_order_create / production_order_update (POST /production-orders/save; params product, recipe_version?, volume_gal, pitch_on, package_on, vessels[]; undo delete_row / restore_prior; no confirm; role production) · production_order_release (POST /production-orders/{id}/release; undo restore_prior releasing allocations; no confirm; production) · production_order_close (POST /production-orders/{id}/close; undo restore_prior; no confirm; production) · production_order_cancel (POST /production-orders/{id}/cancel; undo restore_prior; confirm yes; production).

### Activity log events
- `screen_entered` for every screen; `production_order_created`, `production_order_updated` (before/after of the order row and vessel rows), `production_order_released` (after includes allocation ids), `production_order_closed`, `production_order_cancelled`. Entity type `production_order`, label `number`.

### Status vocabulary mapping
- planned → dark; released → info; in_progress → info; complete → success; closed → secondary; cancelled → danger.

### State rules (enforced in the endpoints, in this order)
- release: only from planned. close: only from complete or in_progress. cancel: only from planned or released. Edit form: only planned; otherwise view.php shows a read-only header and no edit button.
- `in_progress` and `complete` are set by slice 6 (batch pitch sets in_progress; the batch reaching `packaged` sets complete); this slice never sets them.

### Out of scope for this slice
- Hard allocation to specific lots (lot_id stays NULL here); FEFO lot proposals; automatic vessel assignment; scheduling optimization; creating batches (slice 6); any ledger transaction (release only creates allocation rows).

### Open Questions (must be EMPTY before a worker starts)
- (none)

---

## Entity: production calendar (read-only screen)

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| production-calendar | /production-orders/calendar | Vessel-by-week grid of planned use and current occupancy |

### Screen content
- Page header with a week-range filter (`production-calendar-filter-from`, `-to`, default: today to today + 8 weeks), `hx-get` refreshing `#production-calendar-grid`.
- A canonical table card (`production-calendar-table`): one row per active vessel (`vessels.name`, capacity gal); one column per week in the range; a cell lists, as badges, each planned order (`number`, role, badge color per the order's status) and the current occupant from `v_vessel_board` (`occupant_label`, badge `info`) when the week contains today. A cell with two or more planned orders, or a planned order plus an occupant from another batch, gets the `bg-warning-subtle` cell class and a tooltip "conflict".
- Clicking an order badge `hx-get`s production-order-view with explicit `hx-push-url`.
- Table sits in `.table-responsive`; at 375px the week columns scroll horizontally inside the card only.

### Files
- Served by /var/www/html/production-orders/calendar.php and /var/www/app/views/production-orders/partials/calendar.php (listed above; no extra files).

### Query functions
- find_calendar_rows (listed above).

### Action manifest entries
- Screen production-calendar only; no actions.

### Activity log events
- `screen_entered` with `details.from`, `details.to`.

### Out of scope
- Drag-and-drop rescheduling; editing from the calendar.

### Open Questions
- (none)
