# Build spec: removals and compliance slice (slice 10)

Exemplar to replicate: receiving slice (slice 2, `goods_receipts` with lines and post, built by the planning-class model).
Model class: **planning-class builds this slice** (compliance judgment: tax determination, report derivation). The spec is still written so the build is a substitution exercise and so the conformance review has a reference.

Schema tables (never modify): `app.customers`, `app.removals`, `app.removal_lines`, `app.inventory_transactions`, `app.finished_lots`, `app.lots`, `app.kegs`, `app.keg_movements`, `app.tax_class_rules`, `app.premises`, `app.ttb_line_map`, `app.period_reports`, `app.period_report_lines`, `app.loss_events`, `app.vessel_occupancies`, `app.batches`, `app.goods_receipt_lines`, `app.items`. Views: `app.v_finished_stock`, `app.v_lot_balances`. Functions: `app.trace_forward(bigint)`, `app.trace_backward(bigint)`, `app.next_number('removal')`, `app.next_number('period_report')`.

Units: `removal_lines.volume_l` is computed (`units × finished_lots.unit_volume_l`) and stored in liters; `removals.wine_gallons` is stored in US gallons (liters ÷ 3.785411784, rounded to 4 places, which is the TTB unit). Report lines are in gallons (`unit = 'gal'`) except Part IV fruit in tons and sugar in pounds.

---

## Entity: customer

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| customers-list | /customers/ | List per the canonical table pattern |
| customer-add | /customers/new | Full-container form; prefill `name`, `kind` |
| customer-edit | /customers/{id}/edit | Same form, pre-filled |
| customer-view | /customers/{id} | Removals to this customer, kegs currently out, returns |

### List screen
- Columns, in order: name → `name` (row link, dot: active success / inactive secondary); kind → `kind`; default destination → `default_destination`; kegs out → count of `kegs` where `current_holder_kind = 'customer' and current_holder_id = id`; last removal → max `removals.removed_at` posted; actions → Edit, View.
- Search matches: `name`, `contact_name`, `email`; sort allowlist: `name`, `kind`, `created_at`; page size: 25.
- Row link target: customer-view.

### Form
- name | text | required | `customer-form-field-name`
- kind | select distributor, retailer, taproom, consumer, bonded_premises, other | required | `-kind`
- default_destination | select tax_paid_sale, taproom_transfer, in_bond_transfer, export | required | in_bond_transfer requires permit_number | `-default-destination`
- permit_number | text | required when default_destination = in_bond_transfer | `-permit-number`
- contact_name, email, phone | text | optional | `-contact-name`, `-email`, `-phone`
- address | textarea | optional | `-address`
- notes | textarea | optional | `-notes`
- active | checkbox | default on | `-active`

### Files (exactly these)
- /var/www/html/customers/index.php · form.php · view.php · save.php · delete.php
- /var/www/app/features/customers/queries.php
- /var/www/app/views/customers/page.php · partials/table.php · row.php · form.php · view.php · saved.php

### Query functions (signatures fixed)
- find_customers(PDO, search='', sort='name', page=1): array
- find_customer(PDO, int id): ?array
- find_customer_removals(PDO, int id): array
- find_customer_kegs_out(PDO, int id): array
- insert_customer(PDO, string name, string kind, string default_destination, ?string permit_number, ?string contact_name, ?string email, ?string phone, ?string address, ?string notes, bool active): array
- update_customer(PDO, int id, ...same explicit fields): array
- delete_customer(PDO, int id): bool — only when no removals reference it; otherwise set `active = false`.

### Action manifest entries
- Screens: the four above.
- Actions: `customer_create` / `customer_update` → `POST /customers/save` (undo delete_row / restore_prior; confirm no; role compliance).

### Activity log events
- `screen_entered`; `customer_created`, `customer_updated`, `customer_deleted`.

### Status vocabulary mapping
- active → success; inactive → secondary.

### Out of scope for this slice
- Sales orders, invoices, pricing, delivery routes, customer portals.

### Open Questions
- (none)

---

## Entity: removal (and return)

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| removals-list | /removals/ | Removals and returns by destination and status |
| removal-add | /removals/new | Full-container form; prefill `customer`, `destination_kind`; `?direction=in` renders the return variant (screen id `return-add`) |
| removal-edit | /removals/{id}/edit | Same form, pre-filled (draft only) |
| removal-view | /removals/{id} | Lines, kegs, tax determination; Post, Reverse |

### List screen
- Columns, in order: number → `number` (row link, status dot); date → `removed_at` (medium date); direction → arrow icon out/in; destination → `destination_kind` with customer name `<small>`; units → sum `removal_lines.units`; gallons → `wine_gallons`; tax → `tax_amount` (currency, blank when not tax determined); status → badge; actions → Edit (draft) or View.
- Search matches: `number`, customer name, `reference`; sort allowlist: `removed_at`, `number`, `status`, `destination_kind`; page size: 25.
- Filters: `destination_kind`, `customer_id`, `status`, date range.
- Row link target: removal-view.

### Form
- direction | hidden out / in | `removal-form-field-direction`
- destination_kind | select; for direction out: tax_paid_sale, taproom_transfer, in_bond_transfer, export, sample_testing, destroyed, breakage, family_use; for direction in: return_from_customer only | required | `-destination-kind`
- customer | select active customers (required for tax_paid_sale, in_bond_transfer, export, return_from_customer; hidden otherwise); changing it sets destination_kind to the customer's default | `-customer-id`
- from_location | select (locations kind `packaged_goods` or `taproom`, bonded for every destination except taproom_transfer which also allows tax_paid source?) — rule: `from_location.tax_state` must be `bonded` for tax_paid_sale, in_bond_transfer, export, sample_testing, destroyed, breakage, family_use, taproom_transfer; for returns `from_location` is blank | `-from-location-id`
- to_location | select; required for taproom_transfer (a `tax_paid` location kind taproom) and return_from_customer (a bonded `packaged_goods` location); hidden otherwise | `-to-location-id`
- removed_at | datetime-local | required | default now | `-removed-at`
- reference | text | optional (invoice or bill of lading) | `-reference`
- notes | textarea | optional | `-notes`
- Lines tab (`removal-form-tab-lines`), rows added via Pattern A `/removals/line-row.php`: finished lot | select over `app.v_finished_stock` at `from_location` with `units_available > 0` (for returns: any finished lot ever removed to this customer) | required | `removal-form-line-{n}-lot-id`; units | integer ≥ 1 ≤ available | `-units`; kegs | multi-select of kegs where `state = 'filled' and current_lot_id = lot` (for returns: kegs at the customer), shown only when the lot's `package_kind = 'keg'`; the units value must equal the number of kegs selected | `-keg-ids`.
- Readback panel (readonly, recomputed with Pattern A on change): per tax class, gallons = Σ units × unit_volume_l ÷ 3.785411784; tax determined = destination_kind in (tax_paid_sale, taproom_transfer); rate and CBMA credit from `app.tax_class_rules` (`beverage_type` of the product; `params->{tax_class}->>'rate_per_gal'`, credit from `params->'cbma_credit_per_gal'` by the premises `cbma_tier`: tier1 → first element, tier2 → second, tier3 → third, none → 0); tax amount = gallons × (rate − credit). Mixed tax classes on one removal are allowed; `removals.tax_class` holds the class when there is one, else `'mixed'`, and `removal_lines.tax_class` holds each line's class.

### Files (exactly these)
- /var/www/html/removals/index.php · form.php · view.php · save.php · post.php · reverse.php · delete.php · line-row.php · tax-preview.php
- /var/www/app/features/removals/queries.php
- /var/www/app/views/removals/page.php · partials/table.php · row.php · form.php · line-row.php · tax-preview.php · view.php · saved.php

### Query functions (signatures fixed)
- find_removals(PDO, search='', filters=[], sort='removed_at', page=1): array
- find_removal(PDO, int id): ?array
- find_removal_lines(PDO, int id): array
- find_removable_finished_lots(PDO, int location_id): array
- find_returnable_finished_lots(PDO, int customer_id): array
- find_kegs_for_lot(PDO, int lot_id, ?int customer_id): array
- compute_removal_tax(PDO, int premises_id, array lines): array — per tax class gallons, rate, credit, tax; total.
- insert_removal(PDO, int premises_id, string direction, string destination_kind, ?int customer_id, ?int from_location_id, ?int to_location_id, string removed_at, ?string reference, ?string notes, int created_by): array — `number = app.next_number('removal')`.
- update_removal(PDO, int id, ...same explicit fields): array — draft only.
- replace_removal_lines(PDO, int id, array lines): void — recomputes `volume_l` and `tax_class` per line.
- post_removal(PDO, int id, int actor_id): array — one transaction, one ledger `group_id`: (1) validate every line's availability and keg states; (2) for direction out, per line an `inventory_transactions` row `txn_type = 'removal'`, `qty_base = -units`, `location_id = from_location_id`, `counterparty_kind = 'customer'` (or `'disposal'` for destroyed, breakage, sample_testing, family_use), `counterparty_id = customer_id`, `ttb_category` by destination: tax_paid_sale → `removed_tax_paid`, taproom_transfer → `removed_tax_paid`, in_bond_transfer → `removed_in_bond`, export → `export`, sample_testing → `testing`, destroyed → `destroyed`, breakage → `breakage`, family_use → `removed_tax_paid`; `reference_kind = 'removal'`, `reference_id = id`, `idempotency_key = 'rm:{id}:line:{line_id}'`; for taproom_transfer add a second row `txn_type = 'transfer_in'`, `qty_base = +units`, `location_id = to_location_id`, same group (the tax-state trigger allows it because `reference_kind = 'removal'`); (3) for direction in (return): one row per line `txn_type = 'return'`, `qty_base = +units`, `location_id = to_location_id`, `counterparty_kind = 'customer'`, `ttb_category = 'returned'`, `reference_kind = 'return'`; (4) kegs: for each keg on an out line, `transition_keg(... 'ship' ...)`: `kegs.state = 'at_customer'`, `current_holder_kind = 'customer'`, `current_holder_id = customer_id`, `last_moved_at`, and a `keg_movements` row event `ship` with `lot_id`, `customer_id`, `removal_id`; for destroyed/breakage/family_use with kegs: state `empty`, holder location; for returns: `kegs.state = 'returned_dirty'`, holder = `to_location_id`, movement `return` with `removal_id`; (5) write `wine_gallons`, `tax_class`, `tax_rate_per_gal`, `cbma_credit_per_gal`, `tax_amount`, `tax_determined` (true for tax_paid_sale, taproom_transfer, family_use), `status = 'posted'`, `posted_by`, `posted_at`.
- reverse_removal(PDO, int id, int actor_id, string reason): array — inserts a new removal with the same lines and `direction` flipped (`destination_kind = 'return_from_customer'` for an out removal; the original's destination for an in), posts it through the same code path with `ttb_category = 'returned'` (or the original category negated by sign for out-reversals of in), sets the original `status = 'reversed'`, `reversed_by_id` = new id; kegs return to their prior state.
- delete_removal(PDO, int id): bool — draft only.

### Action manifest entries
- Screens: removals-list, removal-add, return-add, removal-edit, removal-view.
- Actions: `removal_create` / `removal_update` → `POST /removals/save` (undo delete_row / restore_prior, draft only); `removal_post` → `POST /removals/{id}/post` (undo reverse; confirm yes, it changes tax state); `removal_reverse` → `POST /removals/{id}/reverse` (param reason; undo none; confirm yes); `return_create` + `return_post` → the same endpoints with `direction = in`.

### Activity log events
- `screen_entered`; `removal_created`, `removal_updated`, `removal_posted` (after = {destination_kind, customer, units, wine_gallons, tax_amount}), `removal_reversed` (details = {reason, reversal_number}), `removal_deleted`; keg transitions log through the keg slice's `keg_shipped` / `keg_returned` events.

### Status vocabulary mapping
- posted → success; draft → dark; reversed, cancelled → danger.

### Out of scope for this slice
- Invoicing and payment; distributor portals; bulk (unpackaged) removals in bond (every line is a finished lot); state excise.

### Open Questions
- (none)

---

## Entity: TTB report (form 5120.17)

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| ttb-reports-list | /ttb-reports/ | Generated period reports |
| ttb-report-add | /ttb-reports/new | Choose premises and period; generates on save; prefill `period` (YYYY-MM or YYYY-Qn) |
| ttb-report-view | /ttb-reports/{id} | Lines per section and tax class with drill-down; Regenerate, Finalize, Mark filed |

### List screen
- Columns, in order: number → `number` (row link, status dot); premises → `premises.name`; form → `form_code`; period → `period_start` to `period_end`; status → badge; generated → `generated_at`; filed → `filed_at`; actions → View.
- Search matches: `number`; sort allowlist: `period_start`, `status`; page size: 25.
- Row link target: ttb-report-view.

### Form (ttb-report-add)
- premises | select (premises where `report_form = '5120.17'`) | required | `ttb-report-form-field-premises-id`
- period_kind | select month / quarter / year (default from `premises.filing_frequency`) | required | `-period-kind`
- period | month input or quarter select | required | `-period`
- Save generates immediately (`number = app.next_number('period_report')`, `form_code = '5120.17'`) and redirects to ttb-report-view. Generating a period that already exists for the premises redirects to the existing report.

### View (ttb-report-view)
- Sections A (bulk), B (bottled), IV (materials) rendered as one table each (`ttb-report-view-section-{a|b|iv}-table`), rows from `period_report_lines` ordered by `ttb_line_map.display_order`, one column per tax class present (hard_cider, still_wine, artificially_carbonated_wine, sparkling_wine) plus a total column. Each non-zero cell is a link (`hx-get /ttb-reports/{id}/lines/{line_id}` into an offcanvas `#ttb-report-view-drilldown`, full width on mobile) listing the source rows (ledger transactions, loss events, or removals by `source_ids`) with date, document number, lot or batch, gallons.
- Totals card: per tax class, tax-determined gallons, rate, CBMA credit, tax, from `totals` jsonb.
- Buttons in the page header: Regenerate (draft only), Finalize (`hx-confirm`), Mark filed (final only, `hx-confirm`, asks `filed_at`).

### Generation algorithm (`generate_period_report`)
For the premises and period, per tax class (`finished_lots.tax_class` for packaged stock; `batches.tax_class_override` else `tax_class_derived` else the product's `intended_tax_class` for bulk):
1. Opening balances (A1, B1): bulk = Σ `vessel_occupancies.volume_l` open at `period_start` for batches of the premises (reconstruct from `stage_events` and `batch_transfers` is out of scope; use occupancies whose `from_at < period_start and (to_at is null or to_at >= period_start)`); bottled = Σ ledger `qty_base × unit_volume_l` for finished lots at bonded locations with `occurred_at < period_start`. Convert to gallons.
2. Flows: for each `ttb_line_map` row with `source in ('ledger','loss','removal','materials')`, select the matching rows in the period: `ledger` matches `inventory_transactions.ttb_category = match->>'ttb_category'` (and `bulk` by whether the item is a finished good; `in_bond` by `tax_state = 'bonded'`; `purpose` by joining `consumptions.purpose`); `loss` matches `loss_events.ttb_category` and `target_kind` (batch = bulk, lot = bottled); `removal` matches `removals.destination_kind` on posted removals (`bulk` always false in v1); `materials` matches `goods_receipt_lines` whose item `ttb_material_category` matches, in tons (fruit, kg ÷ 907.18474), gallons (juice), pounds (sugar). Sum per tax class, store gallons (or tons/lb) and `source_ids` (jsonb array of the row ids).
3. Produced by fermentation (A2) = Σ `stage_events.volume_in_l` for stage `pitch` entered in the period (TTB: whole volume including lees), by tax class of the batch.
4. Closing balances (A31, B18) = opening + inflows − outflows per the line signs; store and also compute the physical closing (same method as opening at `period_end + 1`) into `totals->'reconciliation'` with the difference, shown on the view as a warning when not zero.
5. Totals: tax-determined gallons per class = B8 + B8t + B12 lines; rate and credit per `tax_class_rules` and `premises.cbma_tier`; tax = gallons × (rate − credit).
6. Replace all `period_report_lines` for the report; set `generated_at`, `generated_by`.

### Files (exactly these)
- /var/www/html/ttb-reports/index.php · form.php · view.php · save.php · regenerate.php · finalize.php · filed.php · line.php
- /var/www/app/features/ttb-reports/queries.php
- /var/www/app/views/ttb-reports/page.php · partials/table.php · row.php · form.php · view.php · section.php · drilldown.php · saved.php

### Query functions (signatures fixed)
- find_period_reports(PDO, search='', sort='period_start', page=1): array
- find_period_report(PDO, int id): ?array
- find_period_report_lines(PDO, int id): array
- find_period_report_line_sources(PDO, int line_id): array
- find_existing_period_report(PDO, int premises_id, string form_code, string period_start, string period_end): ?array
- insert_period_report(PDO, int premises_id, string form_code, string period_start, string period_end, int generated_by): array
- generate_period_report(PDO, int id, int actor_id): array — the algorithm above, in one transaction; allowed when `status = 'draft'`.
- finalize_period_report(PDO, int id, int actor_id): array — `status = 'final'`, `finalized_at`.
- mark_period_report_filed(PDO, int id, string filed_at, int actor_id): array — `status = 'filed'`, `filed_at`, `filed_by`.

### Action manifest entries
- Screens: the three above.
- Actions: `ttb_report_generate` → `POST /ttb-reports/save` (params premises, period_start, period_end; undo delete_row while draft); `ttb_report_regenerate` → `POST /ttb-reports/{id}/regenerate` (undo restore_prior: the previous lines are kept in `totals->'previous_lines'`); `ttb_report_finalize` → `POST /ttb-reports/{id}/finalize` (confirm; undo restore_prior to draft); `ttb_report_mark_filed` → `POST /ttb-reports/{id}/filed` (param filed_at; confirm; undo restore_prior to final).

### Activity log events
- `screen_entered`; `ttb_report_generated` (after = totals), `ttb_report_regenerated`, `ttb_report_finalized`, `ttb_report_marked_filed`; `ttb_report_line_viewed` (details = {line_code, tax_class}).

### Status vocabulary mapping
- filed → success; final → info; amended → warning; draft → dark.

### Out of scope for this slice
- Forms 5130.9 and 5130.26 (brewery premises); TTB F 5000.24 excise return itself (the totals card gives the numbers); Pay.gov submission; PDF rendering of the form; prior-period adjustment lines (`is_adjustment` stays false in v1); state reports.

### Open Questions
- (none)

---

## Entity: trace

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| trace | /trace/ | Trace a lot forward or a batch backward; prefill `lot_number`, `batch_number` |

### List screen
- Page header form (GET, `hx-get` into `#trace-results`, `hx-push-url` to `/trace/?lot_number=` or `?batch_number=`): lot_number (text with Pattern A autocomplete from `lots`, id `trace-field-lot-number`); batch_number (text with autocomplete from `batches`, id `trace-field-batch-number`); direction is implied by which field is filled (forward from a lot, backward from a batch; a finished lot number runs backward via its `finished_lots.batch_id`).
- Results table (`trace-results-table`): level → `level` (indent by level); kind → `kind` badge (batch info, finished_lot success, removal warning, lot secondary, fruit_lot dark); id → `label` linked to the entity's view screen by kind (batch-view, finished-lot-view, removal-view, lot-view); detail → key values from the `detail` jsonb (status and stage; packaged_on and units; destination, customer name resolved from `customer_id`, removed_at, units; item, supplier lot, purpose, qty; item, press run, kg in lb).
- Summary tiles above the table: batches affected, finished lots affected, units on hand across affected finished lots (from `v_lot_balances`), customers affected (distinct `customer_id`), with ids `trace-summary-{name}`.
- Export CSV button (`trace-export-btn`) with the same rows; the export logs `trace_exported`.
- Sort: fixed (level, kind, label); no pagination (recall traces must show everything).

### Form
- (none beyond the header inputs)

### Files (exactly these)
- /var/www/html/trace/index.php · suggest.php
- /var/www/app/features/trace/queries.php
- /var/www/app/views/trace/page.php · partials/results.php · summary.php

### Query functions (signatures fixed)
- find_trace_forward(PDO, int lot_id): array — `SELECT * FROM app.trace_forward(:lot_id) ORDER BY level, kind, label`, with customer names joined for removal rows.
- find_trace_backward(PDO, int batch_id): array — `SELECT * FROM app.trace_backward(:batch_id) ORDER BY level, kind, label`.
- find_lot_by_number(PDO, string lot_number): ?array
- find_batch_by_number(PDO, string batch_number): ?array
- find_trace_summary(PDO, array rows): array
- suggest_lot_numbers(PDO, string q, int limit=10): array
- suggest_batch_numbers(PDO, string q, int limit=10): array

### Action manifest entries
- Screens: `trace` ("trace a lot forward or a batch backward for a recall"; prefill `lot_number`, `batch_number`).
- Actions: none (read only).

### Activity log events
- `screen_entered` (details = {lot_number or batch_number, direction, row_count}); `trace_exported`.

### Status vocabulary mapping
- kind badges as listed above.

### Out of scope for this slice
- Mock-recall timing records; customer notification letters; tracing packaging material lots forward (the ledger holds it; add when asked).

### Open Questions
- (none)
