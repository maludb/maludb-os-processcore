# Build spec: inventory slice (slice 3)

Exemplar to replicate: the **receiving** slice (slice 2, built by the planning-class model) — same file set, same Pattern B list endpoints, same full-container form partial, same post handler shape (`require_post(); verify_csrf();` → authorization → validate → transaction → ledger rows → `log_activity()` → `HX-Redirect`).
Schema tables (never modify): `app.inventory_transactions`, `app.inventory_balances`, `app.inventory_transfers`, `app.inventory_transfer_lines`, `app.inventory_adjustments`, `app.inventory_adjustment_lines`, `app.inventory_counts`, `app.inventory_count_lines`, `app.reason_codes`, `app.lots`, `app.items`, `app.locations`, `app.client_settings`, `app.units`; views `app.v_lot_balances`, `app.v_item_stock`; functions `app.next_number()`, `app.log_activity()`.

Worker's standing instruction: build this slice exactly like the receiving slice, applying this spec. If anything here is ambiguous, conflicting, or missing, STOP — record the exact question under Open Questions and escalate. Do not improvise.

## Slice-wide rules

- **Units.** Quantities are entered and displayed in the client's display units from `app.client_settings` (`mass_display_unit`, default `lb`; `volume_display_unit`, default `gal`) when the item's `base_unit_code` is `kg` or `L`; `ea` items are entered as-is. Convert on save with `app.units.to_base_factor` (store base: kg, L, ea). Fields affected are marked **(display→base)** below. Every quantity cell shows the display value with `<small class="text-muted">` base value.
- **Ledger rows** are inserted with `INSERT INTO app.inventory_transactions (...)`; triggers snapshot `tax_state`/`premises_id` and enforce interlocks (quarantine, negative stock, tax-state crossing). Catch the trigger's `check_violation` SQLSTATE `23514` and re-render the form with the trigger's message as the field error; never expose other exceptions.
- **Idempotency keys** are `{reference_kind}:{reference_id}:{line_id}:{side}` (side = `out`/`in`/`adj`/`count`).
- Every list screen stamps `#page-content` with `data-screen`, `data-entity`, `data-record-id`.
- Roles: `receiving` or higher for create/post; `owner` for approvals (per manifest). `viewer` sees lists and views only.

---

## Entity: inventory (balances, movements, reorder)

Read-only screens over the ledger; no form.

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| inventory-list | /inventory/ | On hand by item, lot, location (`app.v_lot_balances`) |
| inventory-movements | /inventory/movements | Ledger history (`app.inventory_transactions`) |
| reorder-list | /inventory/reorder | Items below reorder point (`app.v_item_stock`) |

### List screen: inventory-list
- Columns, in order: item (`item_name` + `<small>item_code</small>`, link to `/items/{item_id}`) · lot (`lot_number`, link to `/lots/{lot_id}`, status dot per lot quality vocabulary) · location (`location_name` + `<small>tax_state</small>`) · on hand (`qty_on_hand` display→base) · allocated (`qty_allocated`) · available (`qty_available`) · expires (`expires_on`, medium date, `text-danger` when < today+30) · value (`value_at_lot_cost`, currency 2 dp)
- Search matches: `item_name`, `item_code`, `lot_number`; filters (query params): `item_class`, `location_id`, `include_zero` (default false, view already excludes zero)
- Sort allowlist: `item_name`, `lot_number`, `location_name`, `qty_on_hand`, `expires_on` (default `item_name, lot_number`); page size 50
- Row link target: lot-view (`/lots/{lot_id}`)
- Page-header actions: "New Transfer" (`inventory-list-transfer-btn` → transfer-add), "New Adjustment" (`inventory-list-adjustment-btn` → adjustment-add), "Start Count" (`inventory-list-count-btn` → count-add)

### List screen: inventory-movements
- Columns: occurred (`occurred_at`, medium date + time) · type (`txn_type` badge: receipt/transfer_in/production_output/packaging_output/return = success; issue/transfer_out/removal = info; adjustment/count_correction = warning; destruction/reversal = danger) · item (`items.name`) · lot (`lots.lot_number`) · location (`locations.name`) · qty (`qty_base` signed, display→base) · reason (`reason_codes.code`) · reference (`reference_kind` + `reference_id`, link: goods_receipt→`/receipts/{id}`, transfer→`/transfers/{id}`, adjustment→`/adjustments/{id}`, count→`/counts/{id}`, else plain text) · actor (`users.display_name`)
- Filters: `item_id`, `lot_id`, `location_id`, `txn_type`, `date_from`, `date_to` (prefill params `item`, `lot_number`, `location` resolve to ids by exact match on code/number/name)
- Sort allowlist: `occurred_at` (default desc), `item_name`, `qty_base`; page size 50
- Row link: the reference document (above); no edit button (ledger is immutable)

### List screen: reorder-list
- Columns: item (`name` + `<small>code</small>`) · class (`item_class`) · on hand (`qty_on_hand`) · allocated · available (`qty_available`) · on order (`qty_on_order`) · reorder point (`reorder_point_base`) · shortfall (`reorder_point_base − qty_available − qty_on_order`, shown when > 0, `text-danger`)
- Filter: `item_class`; rows where `below_reorder_point = true` only
- Sort allowlist: `name`, `qty_available`, shortfall; page size 50
- Row link: item-view (`/items/{item_id}`); row action "Create PO" (`item-row-{id}-po-btn` → `/purchase-orders/new?item={code}`)

### Form
- None.

### Files (exactly these)
- /var/www/html/inventory/index.php · movements.php · reorder.php
- /var/www/app/features/inventory/queries.php
- /var/www/app/views/inventory/page.php · movements-page.php · reorder-page.php · partials/table.php · row.php · movements-table.php · movements-row.php · reorder-table.php · reorder-row.php

### Query functions
- find_lot_balances(PDO, search='', filters=[], sort='item_name', page=1): array
- find_inventory_movements(PDO, filters=[], sort='occurred_at', page=1): array
- find_reorder_items(PDO, item_class=null, sort='name', page=1): array
- find_item_stock(PDO, int item_id): ?array
- insert_inventory_transaction(PDO, array fields): array — the single ledger writer shared by transfers, adjustments, counts (fields: txn_type, item_id, lot_id, location_id, premises_id, qty_base, unit_cost_base, counterparty_kind, counterparty_id, reason_code_id, ttb_category, reference_kind, reference_id, idempotency_key, occurred_at, actor_id, note, group_id)
- find_balance(PDO, int item_id, int lot_id, int location_id): ?array

### Action manifest entries
- Screens: inventory-list, inventory-movements, reorder-list (see manifest; no actions).

### Activity log events
- `screen_entered` for all three screens (entity_type `item`/`lot`/`location` + id when filtered to one).

### Status vocabulary
- Lot quality dot: released=success, hold=warning, rejected=danger, quarantine=dark.

### Out of scope
- Editing balances directly; FEFO pick list screen (served by MCP `inventory_pick_order` and inside transfer form lot select ordering); valuation report (slice 9).

### Open Questions
- (none)

---

## Entity: transfer

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| transfers-list | /transfers/ | List per the canonical table pattern |
| transfer-add | /transfers/new | Full-container form (empty) |
| transfer-view | /transfers/{id} | Detail with lines; Post / Cancel buttons while draft |

### List screen
- Columns: number (`number`, status dot) · from (`from_location.name`) · to (`to_location.name`) · lines (count) · transferred (`transferred_at`, medium date) · status (badge) · posted by (`users.display_name`)
- Search matches: `number`, from/to location name; filter `status`; sort allowlist: `transferred_at` (default desc), `number`, `status`; page size 25
- Row link target: transfer-view; Edit button only when `status = 'draft'` (→ `/transfers/{id}/edit`, same form partial pre-filled)

### Form
- Fields, in order:
  - from_location_id | select (active locations, `name` + tax_state) | required | `transfer-form-field-from-location`
  - to_location_id | select (active locations) | required, ≠ from | `transfer-form-field-to-location`
  - transferred_at | datetime-local | required, default now | `transfer-form-field-transferred-at`
  - notes | textarea | optional | `transfer-form-field-notes`
  - lines (repeating row group `transfer-form-lines`, add-row button `transfer-form-add-line-btn`, HTMX Pattern A fragment `/transfers/line-row.php`):
    - item_id | select (items with stock at from-location) | required | `transfer-form-line-{n}-item`
    - lot_id | select (Pattern A: `/transfers/lots.php?item_id&location_id`, released lots at from-location in FEFO order, label `lot_number · on hand · expires`) | required | `transfer-form-line-{n}-lot`
    - qty | number ≥ 0.0001 **(display→base)** | required, ≤ on hand | `transfer-form-line-{n}-qty`
- Prefill query params: `from_location`, `to_location`, `item`, `lot_number`, `qty`.
- Server validation: from ≠ to; both locations same `tax_state` (else error "Record a removal or return to move between bonded and tax-paid locations"); qty_base ≤ `v_lot_balances.qty_available`.

### Post handler (`post.php`)
- Transaction: set `status='posted'`, `posted_by`, `posted_at`; for each line insert two ledger rows sharing one `group_id`:
  - `txn_type='transfer_out'`, `location_id=from`, `qty_base=-qty`, `counterparty_kind='location'`, `counterparty_id=to`, `reference_kind='transfer'`, `reference_id=transfer.id`, `ttb_category='none'`, `unit_cost_base=lots.unit_cost_base`, `occurred_at=transferred_at`
  - `txn_type='transfer_in'`, `location_id=to`, `qty_base=+qty`, `counterparty_id=from`, otherwise identical
- Interlocks: trigger rejects tax-state crossing (`23514`); re-render view with the message.
- Undo (`reverse`): a new transfer in the opposite direction, `notes='Reversal of {number}'`, auto-posted; original marked `status='cancelled'`.

### Files (exactly these)
- /var/www/html/transfers/index.php · form.php · save.php · view.php · post.php · cancel.php · lots.php · line-row.php
- /var/www/app/features/transfers/queries.php
- /var/www/app/views/transfers/page.php · view-page.php · partials/table.php · row.php · form.php · line-row.php · view.php · saved.php

### Query functions
- find_transfers(PDO, search='', status=null, sort='transferred_at', page=1): array
- find_transfer(PDO, int id): ?array (header + lines with item/lot/location names)
- insert_transfer(PDO, int from_location_id, int to_location_id, string transferred_at, ?string notes, int created_by, array lines): array (number from `app.next_number('transfer')`)
- update_transfer(PDO, int id, ...same, array lines): array (draft only; replaces lines)
- post_transfer(PDO, int id, int actor_id): array
- cancel_transfer(PDO, int id, int actor_id): bool
- find_lots_at_location(PDO, int item_id, int location_id): array (FEFO: `expires_on NULLS LAST, received_on`)

### Action manifest entries
- Screens: transfers-list, transfer-add, transfer-view.
- Actions: `transfer_create` (`POST /transfers/save`; undo delete_row while draft; no confirm), `transfer_post` (`POST /transfers/{id}/post`; undo reverse; no confirm).

### Activity log events
- `screen_entered`, `transfer_created`, `transfer_updated`, `transfer_posted` (after: lines + group_id), `transfer_cancelled`.

### Status vocabulary
- draft=dark, posted=success, cancelled=danger.

### Out of scope
- Transfers between premises; partial posting; vessel-to-vessel moves (batch_transfer, slice 6).

### Open Questions
- (none)

---

## Entity: adjustment

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| adjustments-list | /adjustments/ | List |
| adjustment-add | /adjustments/new | Full-container form (empty) |
| adjustment-view | /adjustments/{id} | Detail; Approve (owner) / Post / Cancel buttons by status |

### List screen
- Columns: number (status dot) · location (`locations.name`) · reason (`reason_codes.code` + `<small>name</small>`) · lines (count) · net qty (sum `qty_delta_base`, display→base) · adjusted (`adjusted_at`) · status badge · created by
- Search: `number`, location name, reason code; filter `status`, `reason_code_id`; sort allowlist `adjusted_at` (default desc), `number`, `status`; page 25
- Row link: adjustment-view; Edit only while `draft`

### Form
- location_id | select | required | `adjustment-form-field-location`
- reason_code_id | select (`reason_codes` where `applies_to='adjustment'` and active; label `code – name`) | required | `adjustment-form-field-reason`
- adjusted_at | datetime-local | required | `adjustment-form-field-adjusted-at`
- notes | textarea | optional | `adjustment-form-field-notes`
- lines (`adjustment-form-lines`, add button `adjustment-form-add-line-btn`, fragment `/adjustments/line-row.php`):
  - item_id | select | required | `adjustment-form-line-{n}-item`
  - lot_id | select (Pattern A `/adjustments/lots.php?item_id&location_id`, any quality status, lots with a balance at the location first, then any lot of the item) | required | `adjustment-form-line-{n}-lot`
  - qty_delta | number ≠ 0, signed **(display→base)** | required | `adjustment-form-line-{n}-qty`
  - unit_cost | number ≥ 0 per base unit | optional, default `lots.unit_cost_base` | `adjustment-form-line-{n}-unit-cost`
  - note | text | optional | `adjustment-form-line-{n}-note`
- Prefill params: `location`, `item`, `lot_number`, `qty_delta`, `reason`.
- Validation: negative lines may not exceed on hand (trigger enforces; pre-check for a friendly message).

### Status transitions
- On save: if `reason_codes.requires_approval_above` is not null and `sum(abs(qty_delta_base)) > requires_approval_above` → `status='pending_approval'`, else `status='draft'`.
- `approve.php` (owner): `pending_approval` → `draft` with `approved_by/approved_at` set.
- `post.php`: allowed from `draft` only (and `approved_at` set when the threshold applied). Sets `status='posted'`, `posted_by/at`; per line one ledger row: `txn_type='adjustment'`, `qty_base=qty_delta_base`, `location_id`, `reason_code_id`, `reference_kind='adjustment'`, `reference_id`, `counterparty_kind='none'`, `unit_cost_base` from line or lot, `ttb_category` = `reason_codes.ttb_category` when that is one of the ledger's allowed values (`destroyed`, `breakage`, `inventory_loss`, `casualty_loss`, `shortage`, `testing`) else `'none'`; positive deltas with ttb_category none → `'inventory_gain'`.
- Confirm (`hx-confirm`) on Post when any line is negative (manifest: "yes when any line is a write-down").
- Undo (`reverse`): new adjustment with negated lines, reason `CORRECT`, auto-posted; original unchanged (ledger immutable).

### Files
- /var/www/html/adjustments/index.php · form.php · save.php · view.php · approve.php · post.php · cancel.php · lots.php · line-row.php
- /var/www/app/features/adjustments/queries.php
- /var/www/app/views/adjustments/page.php · view-page.php · partials/table.php · row.php · form.php · line-row.php · view.php · saved.php

### Query functions
- find_adjustments(PDO, search='', status=null, sort='adjusted_at', page=1): array
- find_adjustment(PDO, int id): ?array
- insert_adjustment(PDO, int location_id, int reason_code_id, string adjusted_at, ?string notes, int created_by, array lines): array (number `app.next_number('adjustment')`; computes initial status)
- update_adjustment(PDO, int id, ...same, array lines): array (draft/pending only)
- approve_adjustment(PDO, int id, int actor_id): array
- post_adjustment(PDO, int id, int actor_id): array
- cancel_adjustment(PDO, int id, int actor_id): bool
- find_adjustment_lots(PDO, int item_id, int location_id): array

### Action manifest entries
- Screens: adjustments-list, adjustment-add, adjustment-view.
- Actions: `adjustment_create` (undo delete_row, draft), `adjustment_approve` (owner; undo restore_prior), `adjustment_post` (undo reverse; confirm when write-down).

### Activity log events
- `screen_entered`, `adjustment_created`, `adjustment_updated`, `adjustment_approved`, `adjustment_posted`, `adjustment_cancelled`.

### Status vocabulary
- draft=dark, pending_approval=warning, posted=success, cancelled=danger.

### Out of scope
- Loss events on batches (slice 6); cost revaluation without quantity change.

### Open Questions
- (none)

---

## Entity: count

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| counts-list | /counts/ | List |
| count-add | /counts/new | Form: location + kind; creates the count and its expected lines |
| count-view | /counts/{id} | Count sheet: inline counted-qty entry per line (Pattern C), Submit / Approve / Cancel |

### List screen
- Columns: number (status dot) · location · kind (`cycle`/`physical`) · lines (count) · variance lines (count where `variance_base <> 0`) · started (`started_at`) · status badge · approved by
- Search: `number`, location; filter `status`, `kind`; sort `started_at` (default desc), `number`, `status`; page 25
- Row link: count-view; no Edit button (the sheet is edited on the view)

### Form (count-add)
- location_id | select | required | `count-form-field-location`
- kind | select cycle/physical | required, default cycle | `count-form-field-kind`
- notes | textarea | optional | `count-form-field-notes`
- Prefill params: `location`, `kind`.
- On save: insert count (number `app.next_number('count')`, `status='open'`, `started_by`), then one `inventory_count_lines` row per `v_lot_balances` row at the location with `qty_on_hand <> 0` (`qty_expected_base = qty_on_hand`); status → `counting`; redirect to count-view.

### Count sheet (count-view)
- Table `count-sheet-table`, one row per line `count-line-row-{id}`: item · lot · expected (display) · counted input `count-line-row-{id}-counted` (number ≥ 0, **display→base**, `hx-post /counts/{id}/lines/save` on change, Pattern C replaces the row) · variance (display, `text-danger` when ≠ 0) · counted by/at · note input.
- "Add line" (`count-view-add-line-btn`, Pattern A fragment) for a lot found that had no expected balance: item + lot selects (any lot of item), `qty_expected_base=0`.
- Buttons: Submit (`count-view-submit-btn`, status counting→review, requires every line counted), Approve (`count-view-approve-btn`, owner, review→approved, `hx-confirm`), Cancel (`count-view-cancel-btn`, `hx-confirm`).

### Approve handler (`approve.php`)
- Transaction: `status='approved'`, `approved_by/at`, `completed_at`; for each line with `variance_base <> 0` one ledger row: `txn_type='count_correction'`, `qty_base=variance_base`, `location_id=count.location_id`, `reason_code_id` = reason code `COUNT`, `ttb_category='shortage'` when variance < 0 else `'inventory_gain'`, `reference_kind='count'`, `reference_id=count.id`, `counterparty_kind='none'`, `unit_cost_base=lots.unit_cost_base`, `occurred_at=completed_at`, idempotency `count:{id}:{line_id}:count`.
- Negative variance on a quarantined lot is allowed (trigger only blocks `issue/packaging_output/removal`).
- Undo (`reverse`): posts negated `count_correction` rows under `reference_kind='reversal'` with `reverses_id` set; count status unchanged, note appended.

### Files
- /var/www/html/counts/index.php · form.php · save.php · view.php · line-save.php · line-add.php · submit.php · approve.php · cancel.php
- /var/www/app/features/counts/queries.php
- /var/www/app/views/counts/page.php · view-page.php · partials/table.php · row.php · form.php · sheet.php · sheet-row.php · saved.php

### Query functions
- find_counts(PDO, search='', status=null, sort='started_at', page=1): array
- find_count(PDO, int id): ?array (header + lines)
- insert_count(PDO, int location_id, string kind, ?string notes, int started_by): array (creates expected lines)
- record_count_line(PDO, int line_id, float qty_counted_base, ?string note, int counted_by): array
- add_count_line(PDO, int count_id, int item_id, int lot_id): array
- submit_count(PDO, int id, int actor_id): array
- approve_count(PDO, int id, int actor_id): array
- cancel_count(PDO, int id, int actor_id): bool

### Action manifest entries
- Screens: counts-list, count-add, count-view.
- Actions: `count_start` (undo delete_row), `count_line_record` (undo restore_prior), `count_submit` (undo restore_prior), `count_approve` (owner; undo reverse; confirm), `count_cancel` (undo restore_prior; confirm).

### Activity log events
- `screen_entered`, `count_started`, `count_line_recorded` (before/after counted qty), `count_line_added`, `count_submitted`, `count_approved` (after: variance lines + group_id), `count_cancelled`.

### Status vocabulary
- open=dark, counting=info, review=warning, approved=success, cancelled=danger.

### Out of scope
- ABC cycle scheduling; recount workflow; count by item across locations.

### Open Questions
- (none)
