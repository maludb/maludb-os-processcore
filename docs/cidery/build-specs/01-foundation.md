# Build spec: Foundation slice (slice 1)

Built by the planning-class model. This slice has no exemplar of its own; the receiving slice (02) is the canonical exemplar for every later slice. Foundation screens are plain CRUD and set the shell's first navigation group ("Setup").

Schema tables: `app.client_settings`, `app.premises`, `app.units`, `app.items`, `app.item_units`, `app.suppliers`, `app.supplier_items`, `app.locations`, `app.vessels`, `app.reason_codes`, `app.users` (from `db/003_auth.sql`), `app.attachments`. Never modify them.

Shared rules for every entity below:
- Files follow php-patterns: `/var/www/html/{feature}/index.php`, `form.php`, `save.php`, `delete.php` (where listed); `/var/www/app/features/{feature}/queries.php`; `/var/www/app/views/{feature}/page.php`, `partials/table.php`, `row.php`, `form.php`, `saved.php`.
- List screens are the canonical table card (design-decisions.md), server-rendered search (`hx-get`, `keyup changed delay:400ms`) and pagination; page size 25 unless stated.
- Every list has an "Add {Entity}" button `{feature}-list-add-btn` in the page header and an Edit button per row; both `hx-get` the form into `#page-content` with `hx-push-url` set to the explicit canonical URL.
- Every `save.php`: `require_post(); verify_csrf();` → role check → validate → query function → `log_activity()` → return the list partial with `HX-Trigger: {entity}Changed`, or re-render the form partial with errors (422).
- Role gate per the manifest (`owner` always allowed). Unauthorized → 403 page partial.
- All quantities with a base unit are stored in base (L, kg) and displayed in `app.client_settings` display units (`volume_display_unit`, `mass_display_unit`); the form input is in display units and converted on save using `app.units.to_base_factor`.
- Screen entry logs `screen_entered` with `screen` = screen id. Deletes do not exist in this slice except where stated; rows deactivate (`active = false`).

---

## Entity: client settings

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| settings-client | /settings/client | Single-row edit form (id = 1), no list |

### Form
- Fields, in order: client_name | text | required | 1-120 chars | `settings-client-field-client-name`
- subdomain | text | required, read-only after provisioning | `settings-client-field-subdomain`
- timezone | select | required | IANA list (PHP `DateTimeZone::listIdentifiers`) | `settings-client-field-timezone`
- volume_display_unit | select | required | `app.units` where dimension='volume' and not is_base | `settings-client-field-volume-display-unit`
- mass_display_unit | select | required | `app.units` dimension='mass' | `settings-client-field-mass-display-unit`
- fruit_display_unit | select | required | `app.units` dimension='mass' | `settings-client-field-fruit-display-unit`
- Save `settings-client-save-btn`, Cancel `settings-client-cancel-btn`.

### Files
- /var/www/html/settings/client.php (GET form) · /var/www/html/settings/client-save.php
- /var/www/app/features/settings/queries.php
- /var/www/app/views/settings/client-page.php · partials/client-form.php

### Query functions
- find_client_settings(PDO): array
- update_client_settings(PDO, string client_name, string timezone, string volume_display_unit, string mass_display_unit, string fruit_display_unit): array

### Action manifest entries
- Screen: settings-client. Action: `client_settings_update` → `POST /settings/client/save` | restore_prior | no confirm | owner.

### Activity log events
- screen_entered, client_settings_updated (before/after of the five fields).

### Out of scope
- Subdomain changes; `settings` jsonb editing.

### Open Questions
- (none)

---

## Entity: premises

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| premises-list | /premises/ | List |
| premises-add | /premises/new | Form (empty) |
| premises-edit | /premises/{id}/edit | Form (pre-filled) |

### List screen
- Columns: name (row link → premises-edit, dot = active ? success : secondary) | kind (badge: "Bonded winery" / "Brewery") | registry_number | report_form | filing_frequency | Actions (Edit)
- Search: name, registry_number; sort allowlist: name, kind, created_at; page size 25.

### Form
- name | text | required | `premises-form-field-name`
- kind | select | required | bonded_winery, brewery | `premises-form-field-kind`
- registry_number | text | optional | `premises-form-field-registry-number`
- report_form | select | required | 5120.17 (winery) / 5130.9, 5130.26 (brewery); the select filters on kind client-side and the DB constraint `premises_form_matches_kind` is the server check | `premises-form-field-report-form`
- filing_frequency | select | required | monthly, quarterly, annual | `premises-form-field-filing-frequency`
- tax_determination_point | select | required | removal, packaging, designated_tank | `premises-form-field-tax-determination-point`
- cbma_tier | select | required | none, tier1, tier2, tier3 | `premises-form-field-cbma-tier`
- active | checkbox | default true | `premises-form-field-active`
- Prefill from query: name, kind.

### Files
- /var/www/html/premises/index.php · form.php · save.php
- /var/www/app/features/premises/queries.php
- /var/www/app/views/premises/page.php · partials/table.php · row.php · form.php · saved.php

### Query functions
- find_premises_list(PDO, search='', sort='name', page=1): array
- find_premises(PDO, int id): ?array
- insert_premises(PDO, string name, string kind, ?string registry_number, string report_form, string filing_frequency, string tax_determination_point, string cbma_tier, bool active): array
- update_premises(PDO, int id, …same fields): array

### Action manifest entries
- Screens: premises-list, premises-add, premises-edit (manifest lines).
- Actions: premises_create / premises_update → `POST /premises/save` | delete_row / restore_prior | no | owner.

### Activity log events
- screen_entered, premises_created, premises_updated.

### Status vocabulary
- active → success; inactive → secondary.

### Out of scope
- Deleting a premises; more than one kind per premises.

### Open Questions
- (none)

---

## Entity: locations

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| locations-list | /locations/ | List |
| location-add | /locations/new | Form |
| location-edit | /locations/{id}/edit | Form |

### List screen
- Columns: name (link, dot active/inactive) | premises name | kind (badge) | tax_state (badge: bonded=info, tax_paid=warning) | allow_negative (Yes/No) | Actions
- Search: name; sort allowlist: name, kind, tax_state; filter select by premises_id.

### Form
- premises_id | select | required | active premises | `location-form-field-premises-id`
- name | text | required, unique per premises (catch SQLSTATE 23505 → error "A location with this name exists on that premises") | `location-form-field-name`
- kind | select | required | receiving, dry_store, cold_room, freezer, cellar, packaged_goods, taproom, outside | `location-form-field-kind`
- tax_state | select | required | bonded, tax_paid | `location-form-field-tax-state`
- allow_negative | checkbox | default false | `location-form-field-allow-negative`
- active | checkbox | `location-form-field-active`
- Prefill: name, kind.

### Files
- /var/www/html/locations/index.php · form.php · save.php
- /var/www/app/features/locations/queries.php
- /var/www/app/views/locations/page.php · partials/table.php · row.php · form.php · saved.php

### Query functions
- find_locations(PDO, search='', sort='name', page=1, ?int premises_id=null): array
- find_location(PDO, int id): ?array
- insert_location(PDO, int premises_id, string name, string kind, string tax_state, bool allow_negative, bool active): array
- update_location(PDO, int id, …same): array

### Action manifest entries
- Screens: locations-list, location-add, location-edit. Actions: location_create / location_update → `POST /locations/save` | delete_row / restore_prior | no | owner.

### Activity log events
- screen_entered, location_created, location_updated (tax_state change must appear in before/after).

### Status vocabulary
- active → success; inactive → secondary; tax_state bonded → info badge, tax_paid → warning badge.

### Out of scope
- Changing tax_state on a location that has non-zero balances (block with error "Move stock out first"; implemented by checking `app.inventory_balances`).

### Open Questions
- (none)

---

## Entity: vessels

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| vessels-list | /vessels/ | List |
| vessel-add | /vessels/new | Form |
| vessel-edit | /vessels/{id}/edit | Form |

### List screen
- Columns: name (link; dot by status: empty=success, in_use=info, cleaning=warning, out_of_service=danger) | kind | capacity (capacity_l → display volume unit, 1 decimal) | status (badge) | location name | Actions (Edit; a status dropdown-free inline control is NOT in this slice)
- Search: name; sort allowlist: name, kind, capacity_l, status.

### Form
- premises_id | select | required | `vessel-form-field-premises-id`
- location_id | select | required | locations of that premises with kind in (cellar, cold_room, receiving, outside) | `vessel-form-field-location-id`
- name | text | required, unique per premises | `vessel-form-field-name`
- kind | select | required | tank, fermenter, brite, tote, ibc, barrel, press | `vessel-form-field-kind`
- capacity | number | required > 0 | entered in display volume unit, stored as capacity_l | `vessel-form-field-capacity`
- status | select | required | empty, cleaning, out_of_service (in_use is set only by execution handlers; on edit, if current is in_use the select is disabled) | `vessel-form-field-status`
- notes | textarea | `vessel-form-field-notes`
- active | checkbox | `vessel-form-field-active`
- Prefill: name, kind, capacity_gal (converted).

### Files
- /var/www/html/vessels/index.php · form.php · save.php · status.php
- /var/www/app/features/vessels/queries.php
- /var/www/app/views/vessels/page.php · partials/table.php · row.php · form.php · saved.php

### Query functions
- find_vessels(PDO, search='', sort='name', page=1, ?int premises_id=null): array
- find_vessel(PDO, int id): ?array
- insert_vessel(PDO, int premises_id, int location_id, string name, string kind, float capacity_l, string status, ?string notes, bool active): array
- update_vessel(PDO, int id, …same): array
- update_vessel_status(PDO, int id, string status): array

### Action manifest entries
- Screens: vessels-list, vessel-add, vessel-edit. Actions: vessel_create / vessel_update → `POST /vessels/save` | delete_row / restore_prior | no | production; vessel_set_status → `POST /vessels/{id}/status` | restore_prior | no | production (status.php; refuses in_use).

### Activity log events
- screen_entered, vessel_created, vessel_updated, vessel_status_set.

### Status vocabulary
- empty → success; cleaning → warning; out_of_service → danger; in_use → info.

### Out of scope
- Occupancy display (slice 6 tank board).

### Open Questions
- (none)

---

## Entity: items

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| items-list | /items/ | List |
| item-add | /items/new | Form |
| item-edit | /items/{id}/edit | Form |
| item-view | /items/{id} | Detail with tabs: Overview, Alternate units, Suppliers (stock and lots tabs are added by slice 3) |

### List screen
- Columns: code (link → item-view; dot active) | name | item_class (badge) | base_unit_code | lot_controlled (Yes/No) | default_receipt_status (badge: quarantine=dark, released=success) | reorder_point_base (display unit) | Actions (Edit)
- Search: code, name; sort allowlist: code, name, item_class; filter select by item_class.

### Form (tabs: Basics, Control, Planning)
- Basics: code | text | required, unique (lower) | `item-form-field-code`; name | text | required | `item-form-field-name`; item_class | select | required | fruit, juice, yeast, additive, packaging, consumable, intermediate, finished_good, co_product, returnable_asset | `item-form-field-item-class`; base_unit_code | select | required | `app.units` where is_base | `item-form-field-base-unit-code`; units_per_case | integer | optional, finished_good only | `item-form-field-units-per-case`; notes | textarea | `item-form-field-notes`; active | checkbox | `item-form-field-active`
- Control: lot_controlled | checkbox | default true | `item-form-field-lot-controlled`; catch_weight | checkbox | `item-form-field-catch-weight`; shelf_life_days | integer ≥ 0 | `item-form-field-shelf-life-days`; default_receipt_status | select | quarantine, released (default: quarantine when item_class in fruit, juice, yeast, additive; released otherwise, set client-side on class change) | `item-form-field-default-receipt-status`; consumption_mode | select | explicit, backflush | `item-form-field-consumption-mode`; costing_method | select | actual_lot, standard | `item-form-field-costing-method`; standard_cost_per_base | number ≥ 0 | shown per display unit, stored per base | `item-form-field-standard-cost-per-base`; ttb_material_category | select | none, fruit, juice, concentrate, sugar, other | `item-form-field-ttb-material-category`
- Planning: reorder_point_base, min_qty_base, max_qty_base | number ≥ 0 | entered in display unit, stored base | `item-form-field-reorder-point`, `-min-qty`, `-max-qty`
- Prefill: name, item_class.

### Item units tab (item-view)
- Table `item-view-units-table`: unit_code, unit_name, to_base_factor (shown as "1 {unit} = X {base}"), is_purchase_default; inline add form at the bottom of the tab (Pattern A: `hx-post` to `/items/{id}/units/save`, re-renders the tab partial) with fields `item-units-form-field-unit-code`, `-unit-name`, `-to-base-factor`, `-is-purchase-default`. Remove button per row (`hx-confirm`, `/items/{id}/units/delete`).

### Files
- /var/www/html/items/index.php · form.php · save.php · view.php · units-save.php · units-delete.php
- /var/www/app/features/items/queries.php
- /var/www/app/views/items/page.php · partials/table.php · row.php · form.php · saved.php · view.php · units-tab.php · suppliers-tab.php

### Query functions
- find_items(PDO, search='', sort='code', page=1, ?string item_class=null, bool active_only=true): array
- find_item(PDO, int id): ?array
- find_item_by_code(PDO, string code): ?array
- insert_item(PDO, string code, string name, string item_class, string base_unit_code, bool lot_controlled, bool catch_weight, ?int shelf_life_days, string default_receipt_status, string consumption_mode, string costing_method, ?float standard_cost_per_base, ?float reorder_point_base, ?float min_qty_base, ?float max_qty_base, string ttb_material_category, ?int units_per_case, ?string notes, bool active): array
- update_item(PDO, int id, …same): array
- find_item_units(PDO, int item_id): array
- insert_item_unit(PDO, int item_id, string unit_code, string unit_name, float to_base_factor, bool is_purchase_default): array
- delete_item_unit(PDO, int id): bool
- find_item_suppliers(PDO, int item_id): array (join supplier_items → suppliers)

### Action manifest entries
- Screens: items-list, item-add, item-edit, item-view. Actions: item_create / item_update → `POST /items/save` | delete_row / restore_prior | no | receiving; item_unit_add → `POST /items/{id}/units/save` | delete_row | no | receiving.

### Activity log events
- screen_entered, item_created, item_updated, item_unit_added, item_unit_removed.

### Status vocabulary
- active → success; inactive → secondary; default_receipt_status quarantine → dark badge, released → success badge.

### Out of scope
- Stock balances and lots on item-view (slice 3); standard cost history (`app.standard_costs`, slice 4) — this form writes only `items.standard_cost_per_base`.

### Open Questions
- (none)

---

## Entity: units (read-only)

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| units-list | /units/ | Read-only table of `app.units` |

### List screen
- Columns: code | name | dimension | to_base_factor | is_base; sorted by display_order; no search, no pagination, no add/edit buttons.

### Files
- /var/www/html/units/index.php · /var/www/app/features/units/queries.php · /var/www/app/views/units/page.php · partials/table.php

### Query functions
- find_units(PDO, ?string dimension=null): array

### Action manifest entries
- Screen: units-list. No actions.

### Activity log events
- screen_entered.

### Open Questions
- (none)

---

## Entity: suppliers

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| suppliers-list | /suppliers/ | List |
| supplier-add | /suppliers/new | Form |
| supplier-edit | /suppliers/{id}/edit | Form |
| supplier-view | /suppliers/{id} | Detail with tabs: Overview, Items, Orders (slice 2 fills), Performance (slice 2 fills from `app.v_supplier_performance`) |

### List screen
- Columns: name (link → supplier-view; dot active) | kind (badge) | contact_name | email | phone | Actions
- Search: name, contact_name, email; sort allowlist: name, kind.

### Form
- name | text | required | `supplier-form-field-name`; kind | select | vendor, orchard, juice_supplier, packaging, other | `supplier-form-field-kind`; contact_name, email (format check), phone, address (textarea), notes (textarea) | optional | `supplier-form-field-{name}`; active | checkbox.
- Prefill: name, kind.

### Supplier items tab (supplier-view)
- Table `supplier-view-items-table`: item (code + name), supplier_sku, purchase_unit_code, to_base_factor, last_price (per purchase unit), lead_time_days, active. Inline add form (Pattern A, `/suppliers/{id}/items/save`): item_id | select (search of active items) `supplier-items-form-field-item-id`; supplier_sku `-supplier-sku`; purchase_unit_code | select of `app.units` codes plus the item's `item_units` codes `-purchase-unit-code`; to_base_factor | number > 0, auto-filled from the chosen unit `-to-base-factor`; last_price | number ≥ 0 `-last-price`; lead_time_days | integer ≥ 0 `-lead-time-days`. Unique (supplier_id, item_id): catch 23505 → "Already listed".

### Files
- /var/www/html/suppliers/index.php · form.php · save.php · view.php · items-save.php
- /var/www/app/features/suppliers/queries.php
- /var/www/app/views/suppliers/page.php · partials/table.php · row.php · form.php · saved.php · view.php · items-tab.php

### Query functions
- find_suppliers(PDO, search='', sort='name', page=1): array
- find_supplier(PDO, int id): ?array
- insert_supplier(PDO, string name, string kind, ?string contact_name, ?string email, ?string phone, ?string address, ?string notes, bool active): array
- update_supplier(PDO, int id, …same): array
- find_supplier_items(PDO, int supplier_id): array
- insert_supplier_item(PDO, int supplier_id, int item_id, ?string supplier_sku, string purchase_unit_code, float to_base_factor, ?float last_price, ?int lead_time_days): array
- update_supplier_item(PDO, int id, …same minus ids): array

### Action manifest entries
- Screens: suppliers-list, supplier-add, supplier-edit, supplier-view. Actions: supplier_create / supplier_update → `POST /suppliers/save` | delete_row / restore_prior | no | receiving; supplier_item_add → `POST /suppliers/{id}/items/save` | delete_row | no | receiving.

### Activity log events
- screen_entered, supplier_created, supplier_updated, supplier_item_added, supplier_item_updated.

### Status vocabulary
- active → success; inactive → secondary.

### Out of scope
- Orders and performance tab content (slice 2 adds them).

### Open Questions
- (none)

---

## Entity: users

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| users-list | /users/ | List (owner only) |
| user-add | /users/new | Invite form |
| user-edit | /users/{id}/edit | Edit display name and role |

### List screen
- Columns: display_name (link → user-edit; dot: active=success, invited=warning, disabled=danger) | email | role (badge) | status | last_login_at (medium date) | 2FA (totp_enabled_at not null → "On") | Actions (Edit; Disable button with `hx-confirm` → `/users/{id}/disable`)
- Search: display_name, email; sort allowlist: display_name, email, role, status, last_login_at.

### Form
- email | email | required on add, read-only on edit, normalized `strtolower(trim())` | `user-form-field-email`
- display_name | text | required | `user-form-field-display-name`
- role | select | owner, production, receiving, quality, compliance, viewer | `user-form-field-role`
- On add: insert with status 'invited', password_hash NULL, create an `app.one_time_tokens` row (purpose 'invite', 72 h) and send the invitation through `malumail_send()`; the invite link leads to the password set page (Phase 2 auth).
- Prefill: email, role.

### Files
- /var/www/html/users/index.php · form.php · save.php · role.php · disable.php
- /var/www/app/features/users/queries.php
- /var/www/app/views/users/page.php · partials/table.php · row.php · form.php · saved.php

### Query functions
- find_users(PDO, search='', sort='display_name', page=1): array
- find_user(PDO, int id): ?array
- insert_invited_user(PDO, string email, string display_name, string role): array
- update_user_profile(PDO, int id, string display_name): array
- update_user_role(PDO, int id, string role): array
- update_user_status(PDO, int id, string status): array
- insert_one_time_token(PDO, int user_id, string purpose, string token_hash, string expires_at): array

### Action manifest entries
- Screens: users-list, user-add, user-edit. Actions: user_invite → `POST /users/save` | delete_row (if never signed in) | no | owner; user_set_role → `POST /users/{id}/role` | restore_prior | yes | owner; user_disable → `POST /users/{id}/disable` | restore_prior | yes | owner.

### Activity log events
- screen_entered, user_invited, user_updated, user_role_set, user_disabled. Never log password hashes or tokens.

### Status vocabulary
- active → success; invited → warning; disabled → danger.

### Out of scope
- Password, 2FA, Google identity management (Phase 2 auth and settings-profile / settings-2fa); the last owner cannot be disabled or demoted (check count of active owners > 1).

### Open Questions
- (none)

---

## Entity: reason codes

### Screens
| Screen id | Canonical URL | Purpose |
|---|---|---|
| reason-codes-list | /reason-codes/ | List |
| reason-code-add | /reason-codes/new | Form |
| reason-code-edit | /reason-codes/{id}/edit | Form |

### List screen
- Columns: code (link; dot active) | name | applies_to (badge) | ttb_category | classification (expected=success, exceptional=warning badge) | requires_approval_above (display unit of… see Open Questions) | Actions
- Search: code, name; sort allowlist: code, applies_to, ttb_category.

### Form
- code | text | required, uppercase, unique | `reason-code-form-field-code`; name | text | required | `-name`; applies_to | select | adjustment, loss, override, count, short_close, dump | `-applies-to`; ttb_category | select | none, inventory_loss, casualty_loss, testing, destroyed, breakage, shortage | `-ttb-category`; classification | select | expected, exceptional | `-classification`; requires_approval_above | number ≥ 0 or empty | `-requires-approval-above`; active | checkbox.

### Files
- /var/www/html/reason-codes/index.php · form.php · save.php
- /var/www/app/features/reason-codes/queries.php
- /var/www/app/views/reason-codes/page.php · partials/table.php · row.php · form.php · saved.php

### Query functions
- find_reason_codes(PDO, search='', sort='code', page=1, ?string applies_to=null): array
- find_reason_code(PDO, int id): ?array
- insert_reason_code(PDO, string code, string name, string applies_to, string ttb_category, string classification, ?float requires_approval_above, bool active): array
- update_reason_code(PDO, int id, …same): array

### Action manifest entries
- Screens: reason-codes-list, reason-code-add, reason-code-edit. Actions: reason_code_create / reason_code_update → `POST /reason-codes/save` | delete_row / restore_prior | no | compliance.

### Activity log events
- screen_entered, reason_code_created, reason_code_updated.

### Status vocabulary
- active → success; inactive → secondary.

### Out of scope
- Deleting seeded codes.

### Resolved (2026-10-01)
- `reason_codes.requires_approval_above` is in liters for `applies_to in (loss, dump)` and in the item's base unit for `adjustment` and `count` (documented on the column in `db/004_foundation.sql`). The form labels the field "Approval needed above (gal)" when applies_to is loss or dump and "Approval needed above (item base unit)" otherwise; losses convert gallons to liters on save.

### Open Questions
- (none)
