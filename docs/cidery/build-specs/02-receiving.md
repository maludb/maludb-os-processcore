# Build spec: Receiving slice (slice 2) — THE EXEMPLAR

**Built by the planning-class model.** This slice is the canonical reference every later slice replicates: its file layout, handler sequence, list/form/view partials, posting transaction, unit conversion, and activity logging are the patterns workers copy. Worker prompts for slices 3 to 10 read: "Build the {entity} slice exactly like the receipts slice, per its build spec."

Schema tables: `app.purchase_orders`, `app.purchase_order_lines`, `app.goods_receipts`, `app.goods_receipt_lines`, `app.weigh_tags`, `app.lots`, `app.lot_attributes`, `app.certificates_of_analysis`, `app.release_decisions`, `app.attachments`, `app.inventory_transactions` (written by the post handler), `app.inventory_balances` (trigger-maintained, read only here), `app.number_sequences` via `app.next_number()`. Views: `app.v_open_po_lines`, `app.v_supplier_performance`, `app.v_lot_balances`. Never modify them.

Shared rules (as in 01-foundation.md) plus:
- Document numbers come from `app.next_number('po')`, `('receipt')`, `('lot')` inside the insert transaction; never generated in PHP.
- Draft documents (`status = 'draft'`) are editable; posted documents are read-only; corrections after posting are reversals (slice 3 and later), never edits.
- Quantities: PO and receipt lines are entered in the purchase unit (`purchase_unit_code`, from `app.units` or the item's `item_units`), stored with `to_base_factor`, and `qty_*_base` is derived. Weigh tags are entered in pounds (`fruit_display_unit`) and stored in kg: `kg = lb * 0.45359237` (`app.units` factor for `lb`). Costs are entered per purchase unit and stored per base (`unit_cost_base = unit_price / to_base_factor`).
- Display: every base quantity renders through `fmt_qty($qty_base, $base_unit_code)` which converts to the display unit from `app.client_settings` and appends the unit; exact base values appear in tooltips.

---

## Entity: purchase orders

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| purchase-orders-list | /purchase-orders/ | List |
| purchase-order-add | /purchase-orders/new | Form with lines (empty) |
| purchase-order-edit | /purchase-orders/{id}/edit | Form with lines (draft only; posted/open orders redirect to view) |
| purchase-order-view | /purchase-orders/{id} | Detail: header, lines with received quantities, receipts against it; Approve / Close short / Cancel buttons |

### List screen
- Columns: number (link → purchase-order-view; dot per status vocabulary) | supplier name | status (badge) | ordered_on | expected_on (danger text when overdue and status in open, partial) | lines count | Actions (Edit when draft)
- Search: number, supplier name; sort allowlist: number, expected_on, status, supplier; filter select by status; page size 25.
- Row link target: purchase-order-view.

### Form
- Header: supplier_id | select (active suppliers) | required | `purchase-order-form-field-supplier-id`; premises_id | select | required, default the single active premises | `-premises-id`; ordered_on | date | default today | `-ordered-on`; expected_on | date | `-expected-on`; notes | textarea | `-notes`.
- Lines (repeating rows, `purchase-order-form-line-{n}`, add/remove via Pattern A `hx-get /purchase-orders/line-row?n=` and client remove): item_id | select (search) | required | `purchase-order-form-line-{n}-item-id`; purchase_unit_code | select (base unit + item_units + supplier_items purchase unit, pre-selected from supplier_items when present) | required | `-purchase-unit-code`; qty_ordered | number > 0 | `-qty-ordered`; unit_price | number ≥ 0, default supplier_items.last_price | `-unit-price`; expected_on | date, optional override | `-expected-on`.
- Save `purchase-order-form-save-btn`, Cancel `purchase-order-form-cancel-btn` in the page header. Save returns `HX-Redirect` to the view URL.
- Prefill: supplier (name → resolved id), expected_on.

### Files
- /var/www/html/purchase-orders/index.php · form.php · save.php · view.php · line-row.php · approve.php · close-short.php · cancel.php
- /var/www/app/features/purchase-orders/queries.php
- /var/www/app/views/purchase-orders/page.php · partials/table.php · row.php · form.php · form-line.php · view.php · saved.php

### Query functions
- find_purchase_orders(PDO, search='', sort='number', page=1, ?string status=null, ?int supplier_id=null): array
- find_purchase_order(PDO, int id): ?array
- find_purchase_order_lines(PDO, int purchase_order_id): array (joins items for name, base unit)
- find_receipts_for_po(PDO, int purchase_order_id): array
- insert_purchase_order(PDO, int supplier_id, int premises_id, ?string ordered_on, ?string expected_on, ?string notes, int created_by): array (number from next_number('po'), status 'draft')
- update_purchase_order(PDO, int id, int supplier_id, ?string ordered_on, ?string expected_on, ?string notes): array
- replace_purchase_order_lines(PDO, int purchase_order_id, array lines): void (delete + insert, draft only; each line: item_id, line_no, qty_ordered, purchase_unit_code, to_base_factor, unit_price, expected_on)
- approve_purchase_order(PDO, int id, int approved_by): array (draft → open, sets approved_by/at)
- close_purchase_order_short(PDO, int id, int reason_code_id): array (open lines → closed_short with close_reason_code_id; order → closed_short)
- cancel_purchase_order(PDO, int id): array (draft/open with nothing received → cancelled)

### Action manifest entries
- Screens: purchase-orders-list, purchase-order-add, purchase-order-edit, purchase-order-view.
- Actions: po_create / po_update → `POST /purchase-orders/save` | delete_row / restore_prior (draft only) | no | receiving; po_approve → `POST /purchase-orders/{id}/approve` | restore_prior if nothing received | no | owner; po_close_short → `POST /purchase-orders/{id}/close-short` (reason) | restore_prior | yes | receiving; po_cancel → `POST /purchase-orders/{id}/cancel` | restore_prior | yes | receiving.

### Activity log events
- screen_entered, po_created, po_updated, po_approved, po_closed_short, po_cancelled (entity_type 'purchase_order', entity_label = number).

### Status vocabulary
- draft → dark; open → info; partial → warning; closed → success; closed_short, cancelled → danger.

### Out of scope
- Blanket orders, three-way invoice matching, email to supplier.

### Open Questions
- (none)

---

## Entity: goods receipts

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| receipts-list | /receipts/ | List |
| receipt-add | /receipts/new | Form with lines (empty; `?po_number=` pre-fills header and lines from open PO lines) |
| receipt-edit | /receipts/{id}/edit | Form with lines (draft only) |
| receipt-view | /receipts/{id} | Detail: header, lines with lots created, weigh tags, discrepancies; Post button (draft), Putaway button (posted) |
| putaway | /receipts/{id}/putaway | Per-line destination location form for a posted receipt |

### List screen
- Columns: number (link → receipt-view; dot per status) | supplier name | purchase order number (link, or "Unplanned") | received_at (medium date) | status (badge) | lines count | Actions (Edit when draft)
- Search: number, supplier name, delivery_note_ref; sort allowlist: number, received_at, status; filter by status.

### Form
- Header: supplier_id | select | required | `receipt-form-field-supplier-id`; purchase_order_id | select of open/partial orders for that supplier (optional; selecting one loads outstanding lines via Pattern A `/receipts/po-lines?po=`) | `-purchase-order-id`; premises_id | select, default | `-premises-id`; receiving_location_id | select of locations with kind 'receiving' (fallback: any active) | required | `-receiving-location-id`; received_at | datetime-local, default now | `-received-at`; delivery_note_ref | text | `-delivery-note-ref`; notes | textarea | `-notes`.
- Lines (`receipt-form-line-{n}`): purchase_order_line_id | hidden when loaded from a PO | `-po-line-id`; item_id | select | required | `-item-id`; purchase_unit_code | select | required | `-purchase-unit-code`; qty_received | number ≥ 0 | `-qty-received`; unit_price (per purchase unit, default from the PO line or supplier_items) | `-unit-price`; supplier_lot_number | text | `-supplier-lot-number`; expires_on | date, default today + items.shelf_life_days when set | `-expires-on`; discrepancy_kind | select none, short, over, damaged, substituted | `-discrepancy-kind`; discrepancy_note | text | `-discrepancy-note`; notes | text | `-notes`.
- Weigh tag sub-form, shown when the line's item has `catch_weight = true` or `item_class = 'fruit'` (`receipt-form-line-{n}-weigh-tag`): tag_number `-tag-number`; gross (lb) `-gross`; tare (lb) `-tare`; net (computed, read-only) `-net`; bin_count `-bin-count`; variety `-variety`; orchard `-orchard`; block `-block`; brix_at_receipt `-brix`; condition_note `-condition-note`. For a catch-weight line the line's `qty_base` = net kg and `qty_received` is informational (bins); for other lines `qty_base = qty_received * to_base_factor`.
- Save → `HX-Redirect` to receipt-view. Prefill: supplier, po_number.

### Post handler (`post.php`) — the transaction every later posting handler copies
Sequence inside one `beginTransaction`/`commit`, after `require_post(); verify_csrf();`, role ≥ receiving, status must be draft:
1. Load receipt and lines with items (`for update`).
2. For each line with `qty_base > 0`:
   a. Create the lot: `lot_number = app.next_number('lot')`, item_id, premises_id, supplier_id, supplier_lot_number, received_on = received_at::date, expires_on, `quality_status = items.default_receipt_status` (fruit, juice, yeast, additive default to quarantine per the item master; packaging and consumables release), `unit_cost_base`, `source_kind = 'receipt_line'`, `source_id = line id`, created_by. Write `lot_id` back to the line.
   b. If a weigh tag exists: insert `app.lot_attributes` rows from it with `source = 'weigh_tag'`: variety (value_text), orchard, block, brix (value_num, unit '°Bx'), bin_count (value_num), net_kg (value_num, unit 'kg').
   c. Insert the ledger receipt: `app.inventory_transactions` with txn_type 'receipt', item_id, lot_id, location_id = receiving_location_id, premises_id, qty_base (positive), unit_cost_base, tax_state (any value; the trigger overwrites it from the location), counterparty_kind 'supplier', counterparty_id = supplier_id, ttb_category 'received', reference_kind 'goods_receipt', reference_id = receipt id, idempotency_key = `'receipt:' . $receiptId . ':line:' . $lineId`, occurred_at = received_at, actor_id. All lines share one `group_id`.
   d. If the line references a PO line: `qty_received_base += qty_base`; line status → 'received' when `qty_received_base >= qty_ordered_base`, else 'partial'. After all lines, the PO status → 'closed' when every line is received or closed_short, else 'partial'.
3. Receipt status → 'posted', posted_by, posted_at.
4. `log_activity('receipt_posted', entity 'goods_receipt', before {status: draft}, after {status: posted, lots: [...]})` inside the transaction.
5. Commit; return the view partial with `HX-Trigger: receiptsChanged, lotsChanged, inventoryChanged`.
Interlocks the handler must respect: the ledger trigger rejects a lot/item mismatch, snapshots tax_state and premises from the location, and blocks negative balances (not reachable on a receipt). A receipt with zero lines, or a fruit line without a weigh tag, fails validation before the transaction (422, form re-rendered).

### Putaway (`putaway.php` GET form, `putaway-save.php` POST)
- One row per posted line: lot_number, item, qty on hand at the receiving location, `to_location_id` select (active locations of the same premises, same tax_state as the receiving location) `putaway-form-line-{n}-to-location-id`.
- Save: for each line with a destination different from the receiving location, insert two ledger rows sharing a `group_id`: 'transfer_out' (negative) at the receiving location and 'transfer_in' (positive) at the destination, reference_kind 'goods_receipt', reference_id = receipt id, idempotency_key `'putaway:' . $receiptId . ':lot:' . $lotId . ':out'` / `':in'`, ttb_category 'none'; write `putaway_location_id` on the line. Log `putaway_recorded`. The tax-state trigger rejects a cross-tax-state move, hence the select filter.

### Files
- /var/www/html/receipts/index.php · form.php · save.php · view.php · line-row.php · po-lines.php · post.php · putaway.php · putaway-save.php
- /var/www/app/features/receipts/queries.php
- /var/www/app/views/receipts/page.php · partials/table.php · row.php · form.php · form-line.php · weigh-tag.php · view.php · putaway-form.php · saved.php

### Query functions
- find_receipts(PDO, search='', sort='received_at', page=1, ?string status=null, ?int supplier_id=null): array
- find_receipt(PDO, int id): ?array
- find_receipt_lines(PDO, int receipt_id): array (joins items, lots, weigh_tags, purchase_order_lines)
- find_open_po_lines(PDO, int purchase_order_id): array (from `app.v_open_po_lines`)
- insert_receipt(PDO, int premises_id, int supplier_id, ?int purchase_order_id, string received_at, int receiving_location_id, ?string delivery_note_ref, ?string notes, int received_by): array (number from next_number('receipt'))
- update_receipt(PDO, int id, …header fields): array
- replace_receipt_lines(PDO, int receipt_id, array lines): void (draft only; each line carries an optional weigh tag array; weigh tags insert into `app.weigh_tags` with gross_kg, tare_kg)
- insert_lot(PDO, string lot_number, int item_id, int premises_id, ?int supplier_id, ?string supplier_lot_number, ?string received_on, ?string expires_on, string quality_status, float unit_cost_base, string source_kind, int source_id, int created_by): array
- set_lot_attribute(PDO, int lot_id, string key, ?float value_num, ?string value_text, ?string unit_code, string source, ?int recorded_by): array (upsert on (lot_id, key))
- insert_inventory_transaction(PDO, string group_id, string txn_type, int item_id, int lot_id, int location_id, int premises_id, float qty_base, float unit_cost_base, string counterparty_kind, ?int counterparty_id, ?int reason_code_id, string ttb_category, string reference_kind, int reference_id, string idempotency_key, string occurred_at, ?int actor_id, ?string note): array — lives in /var/www/app/features/inventory/ledger.php (shared by every posting handler; slice 3 owns the file but this slice creates it)
- post_receipt_line_to_po(PDO, int purchase_order_line_id, float qty_base): void
- recompute_purchase_order_status(PDO, int purchase_order_id): string
- mark_receipt_posted(PDO, int id, int posted_by): array
- update_receipt_line_putaway(PDO, int line_id, int location_id): void

### Action manifest entries
- Screens: receipts-list, receipt-add, receipt-edit, receipt-view, putaway.
- Actions: receipt_create / receipt_update → `POST /receipts/save` | delete_row / restore_prior (draft) | no | receiving; receipt_line_add → `POST /receipts/{id}/lines/save` | delete_row | no | receiving (same save handler with a single line); weigh_tag_record → `POST /receipts/{id}/lines/{line}/weigh-tag` | restore_prior | no | receiving; receipt_post → `POST /receipts/{id}/post` | reverse (slice 3 reversal; until then the undo returns "post a reversing adjustment") | no | receiving; putaway_record → `POST /receipts/{id}/putaway` | reverse | no | receiving.

### Activity log events
- screen_entered, receipt_created, receipt_updated, receipt_line_added, weigh_tag_recorded, receipt_posted, putaway_recorded (entity_type 'goods_receipt', entity_label = number; lot creation inside the post is recorded in `after.lots`).

### Status vocabulary
- draft → dark; posted → success; cancelled → danger.

### Out of scope
- Unposting; receipt reversal (slice 3); attachments of delivery photos; landed cost allocation.

### Open Questions
- (none)

---

## Entity: lots

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| lots-list | /lots/ | List |
| lot-view | /lots/{id} | Detail with tabs: Overview (balances by location from `app.v_lot_balances`), Attributes, Certificates, Release history, Movements (slice 3 fills; until then a link to inventory-movements) |
| lot-edit | /lots/{id}/edit | Edit expiry, supplier lot number, notes; attributes editing is on the view tab |
| lot-coa-add | /lots/{id}/coa/new | CoA form with file upload and values |
| lot-release | /lots/{id}/release | Release decision form |

### List screen
- Columns: lot_number (link → lot-view; dot per quality_status) | item (code + name) | quality_status (badge) | received_on / produced_on | expires_on (danger text when < today + 30 days) | on hand (sum from `app.v_lot_balances`, display unit) | supplier name | Actions (Edit)
- Search: lot_number, supplier_lot_number, item code/name; sort allowlist: lot_number, received_on, expires_on, quality_status; filters: item_class, quality_status, expiring within 30 days.

### Form (lot-edit)
- supplier_lot_number | text | `lot-form-field-supplier-lot-number`; expires_on | date | `-expires-on`; notes | textarea | `-notes`. item_id, premises_id, source, cost and status are read-only text.

### Attributes tab (lot-view)
- Table `lot-view-attributes-table`: key, value (value_num + unit_code or value_text), source, recorded_at, recorded_by. Inline upsert form (Pattern A, `/lots/{id}/attributes/save`): key | select of known keys (variety, orchard, block, brix, ph, ta, free_so2, total_so2, abv, co2_g_100ml, fruit_share_pct, strain, generation, viability_pct, alpha_acid_pct, moisture_pct) with "other" free text | `lot-attributes-form-field-key`; value_num `-value-num`; value_text `-value-text`; unit_code `-unit-code`. Role: quality.

### CoA form (lot-coa-add)
- issued_on | date | `lot-coa-form-field-issued-on`; issuer | text | `-issuer`; file | file input (pdf, jpg, png ≤ 10 MB) | `-file`; values: a repeating key/value/unit row set `lot-coa-form-value-{n}-key/-value/-unit` (same key list as attributes). Save: store the file under `/var/www/storage/{client}/coa/`, insert `app.attachments` (entity_type 'lot', kind 'coa'), insert `app.certificates_of_analysis` with `values_json` = the rows, upsert each row into `app.lot_attributes` with `source = 'coa'`. Return to lot-view Certificates tab.

### Release form (lot-release)
- Shows current status, the lot's attributes, and CoA presence. to_status | select released, hold, rejected | `lot-release-form-field-to-status`; basis | select coa, inspection, readings, sensory, override, other | `-basis`; is_override | checkbox (required when basis = override; the submit button then carries `hx-confirm`) | `-is-override`; reason_code_id | select of reason_codes applies_to 'override' (required when is_override) | `-reason-code-id`; note | textarea | `-note`.
- Save (transaction): insert `app.release_decisions` (target_kind 'lot', from_status, to_status, basis, is_override, reason_code_id, note, decided_by), update `lots.quality_status`, log `lot_released` with before/after status. Role: quality. Return lot-view with `HX-Trigger: lotsChanged`.

### Files
- /var/www/html/lots/index.php · form.php · save.php · view.php · attributes-save.php · coa-form.php · coa-save.php · release.php · release-save.php
- /var/www/app/features/lots/queries.php
- /var/www/app/views/lots/page.php · partials/table.php · row.php · form.php · view.php · attributes-tab.php · certificates-tab.php · releases-tab.php · coa-form.php · release-form.php · saved.php

### Query functions
- find_lots(PDO, search='', sort='lot_number', page=1, ?string quality_status=null, ?string item_class=null, bool expiring_only=false): array
- find_lot(PDO, int id): ?array
- find_lot_by_number(PDO, string lot_number): ?array
- find_lot_balances(PDO, int lot_id): array (from `app.v_lot_balances`)
- update_lot(PDO, int id, ?string supplier_lot_number, ?string expires_on, ?string notes): array
- find_lot_attributes(PDO, int lot_id): array
- set_lot_attribute(…) — shared with receipts (defined there)
- find_lot_certificates(PDO, int lot_id): array (joins attachments)
- insert_attachment(PDO, string entity_type, int entity_id, string kind, string file_name, string mime_type, string storage_path, int byte_size, int uploaded_by): array
- insert_certificate(PDO, int lot_id, ?int attachment_id, ?string issued_on, ?string issuer, array values_json, int recorded_by): array
- find_release_decisions(PDO, string target_kind, int target_id): array
- insert_release_decision(PDO, string target_kind, int target_id, string from_status, string to_status, string basis, bool is_override, ?int reason_code_id, ?string note, int decided_by): array
- update_lot_quality_status(PDO, int id, string quality_status): array

### Action manifest entries
- Screens: lots-list, lot-view, lot-edit, lot-coa-add, lot-release.
- Actions: lot_update → `POST /lots/{id}/save` | restore_prior | no | receiving; lot_attribute_set → `POST /lots/{id}/attributes/save` | restore_prior | no | quality; coa_record → `POST /lots/{id}/coa/save` | delete_row | no | quality; lot_release → `POST /lots/{id}/release` | reverse (a new decision back to the prior status) | yes when override | quality.

### Activity log events
- screen_entered, lot_updated, lot_attribute_set, coa_recorded, lot_released (before/after quality_status; details.basis, details.is_override).

### Status vocabulary
- released → success; hold → warning; rejected → danger; quarantine → dark.

### Out of scope
- Lot creation by hand (lots come only from receipts, press runs, batches, packaging); movements tab content (slice 3); merging lots.

### Open Questions
- (none)

---

## Entity: certificates of analysis

Covered by the lots entity above (screen lot-coa-add, action coa_record, tables `app.certificates_of_analysis` + `app.attachments`). No list screen of its own.

### Open Questions
- (none)

---

## Entity: release decisions

Covered by the lots entity above (screen lot-release, action lot_release, table `app.release_decisions`, read on the lot-view Release history tab). Slice 8 reuses the same table, form partial, and query functions for `target_kind = 'batch'`.

### Open Questions
- (none)

---

## Supplier view additions (slice 1 screens, filled here)
- supplier-view Orders tab: `find_purchase_orders(PDO, '', 'expected_on', 1, null, $supplierId)` rendered with the purchase-orders row partial.
- supplier-view Performance tab: one row from `app.v_supplier_performance` (receipts, late_receipts, short_lines, damaged_lines).
