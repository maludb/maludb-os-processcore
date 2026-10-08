# Build spec: products and recipes slice (slice 4)

Exemplar to replicate: the **receiving** slice (slice 2).
Schema tables (never modify): `app.products`, `app.recipe_versions`, `app.recipe_stages`, `app.recipe_lines`, `app.specs`, `app.packaging_configurations`, `app.packaging_bom_lines`, `app.standard_costs`, `app.overhead_rates`, `app.product_approvals`, `app.stages`, `app.measurement_types`, `app.items`, `app.premises`, `app.attachments`, `app.units`, `app.client_settings`; views `app.v_item_stock`.

Worker's standing instruction: build this slice exactly like the receiving slice, applying this spec. If anything here is ambiguous, conflicting, or missing, STOP — record the exact question under Open Questions and escalate. Do not improvise.

## Slice-wide rules

- **Units.** Volumes (`target_batch_volume_l`, `fill_volume_l`, `qty_per_l` denominator) are entered in the client's volume display unit (`gal` default) and stored in L **(display→base)**; masses in recipe lines and BOM lines are entered in the mass display unit (`lb`) when the item's base unit is `kg`; `ea` as-is. `qty_per_l` is entered as "per {display volume unit}" and converted (`qty_per_l = entered / to_base_factor(display unit)`, then mass conversion if applicable).
- **Recipe immutability** is enforced by the `recipe_guard_immutable` trigger on `recipe_stages` and `recipe_lines`: only `status='draft'` versions accept child changes. The recipe form endpoint must refuse (HTTP 409, re-render view with alert) when the version is not draft; also never UPDATE `recipe_versions` fields other than `status`, `activated_*`, `expected_total_loss_pct`, `standard_cost_*` once active.
- `products.status` and `recipe_versions.status` have one active version per product (`recipe_versions_one_active` unique index): activation runs in one transaction — retire the current active, activate the new.
- Roles: `production` for products, recipes, packaging configs; `quality` for specs; `owner` for standard costs and overhead; `compliance` for approvals.

---

## Entity: product

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| products-list | /products/ | List |
| product-add | /products/new | Full-container form (empty) |
| product-edit | /products/{id}/edit | Same form, pre-filled |
| product-view | /products/{id} | Detail with tabs: Recipes, Packaging, Specs, Approvals, Batches |

### List screen
- Columns: name (`name` + `<small>code</small>`, status dot) · style · beverage (`beverage_type`) · intended tax class (`intended_tax_class`) · target ABV (`target_abv`, 2 dp %) · fruit share (`target_fruit_share_pct` %) · active recipe (`v{version_no}` of the active `recipe_versions` row, or "none") · status badge
- Search: `name`, `code`, `style`; filter `status`, `beverage_type`; sort allowlist `name` (default), `code`, `status`; page 25
- Row link: product-view; Edit button → product-edit; Add button → product-add

### Form
- code | text, unique (case-insensitive, catch `23505` → "code already used") | required | `product-form-field-code`
- name | text | required | `product-form-field-name`
- beverage_type | select cider/wine/beer | required, default cider | `product-form-field-beverage-type`
- style | text | optional | `product-form-field-style`
- intended_tax_class | select (hard_cider, still_wine, artificially_carbonated_wine, sparkling_wine, beer) | required, default hard_cider | `product-form-field-intended-tax-class`
- target_abv | number 0–25 step 0.01 | optional | `product-form-field-target-abv`
- target_fruit_share_pct | number 0–100 | optional, default 100 | `product-form-field-target-fruit-share`
- contains_other_fruit | checkbox | | `product-form-field-contains-other-fruit`
- contains_flavoring | checkbox | | `product-form-field-contains-flavoring`
- status | select draft/active/retired | required, default draft | `product-form-field-status`
- notes | textarea | optional | `product-form-field-notes`
- Prefill params: `name`, `style`.

### Detail view (product-view) tabs (card-header nav-tabs pattern)
- Recipes `product-view-tab-recipes`: table of `recipe_versions` (version, status dot, batch volume display, expected total loss, standard cost total, activated at/by, change note) → row link recipe-view; "New version" button `product-view-new-recipe-btn` → `/products/{id}/recipes/new`.
- Packaging `product-view-tab-packaging`: packaging configurations for the product (name, package kind, fill volume display, units per case, expected loss, active) → packaging-config-edit; add button → `/packaging-configs/new?product={code}`.
- Specs `product-view-tab-specs`: specs grouped by stage → `/products/{id}/specs`.
- Approvals `product-view-tab-approvals`: `product_approvals` rows (kind, reference_no, status badge, approved_on, expires_on) → approval-edit.
- Batches `product-view-tab-batches`: `batches` for the product (number, status, stage, started_at) → `/batches/{id}` (slice 6 provides the screen; link only).

### Files
- /var/www/html/products/index.php · form.php · save.php · view.php · retire.php
- /var/www/app/features/products/queries.php
- /var/www/app/views/products/page.php · view-page.php · partials/table.php · row.php · form.php · view.php · saved.php

### Query functions
- find_products(PDO, search='', status=null, sort='name', page=1): array
- find_product(PDO, int id): ?array (with active recipe version, packaging configs, specs, approvals, batches)
- insert_product(PDO, string code, string name, string beverage_type, ?string style, string intended_tax_class, ?float target_abv, ?float target_fruit_share_pct, bool contains_other_fruit, bool contains_flavoring, string status, ?string notes): array
- update_product(PDO, int id, ...same): array
- retire_product(PDO, int id): array (status → retired)

### Action manifest entries
- Screens: products-list, product-add, product-edit, product-view.
- Actions: `product_create`/`product_update` (undo delete_row / restore_prior), `product_retire` (undo restore_prior; confirm).

### Activity log events
- `screen_entered`, `product_created`, `product_updated` (before/after), `product_retired`.

### Status vocabulary
- draft=dark, active=success, retired=secondary.

### Out of scope
- Deleting products; beverage-specific fields for wine/beer.

### Open Questions
- (none)

---

## Entity: recipe version

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| recipe-add | /products/{id}/recipes/new | Form: creates a draft version (optionally copied from another) |
| recipe-edit | /recipes/{id}/edit | Draft editor: header, stages table, lines table (draft only) |
| recipe-view | /recipes/{id} | Read view with scale control, diff selector, Activate button |

### Form (recipe-add)
- product_id | hidden from URL | required | `recipe-form-field-product`
- target_batch_volume | number > 0 **(display→base L)** | required | `recipe-form-field-batch-volume`
- copy_from_version_id | select (this product's versions, "blank" default) | optional | `recipe-form-field-copy-from`
- change_note | textarea | optional | `recipe-form-field-change-note`
- Prefill params: `batch_volume_gal`.
- On save: `version_no = max(version_no)+1` for the product; `status='draft'`; if copy_from set, copy `recipe_stages` and `recipe_lines` (new ids, same seq); redirect to recipe-edit.

### Draft editor (recipe-edit)
- Header fields (same ids as recipe-add plus) `recipe-form-field-batch-volume`, `recipe-form-field-change-note`; save button `recipe-form-save-btn`.
- Stages table `recipe-form-stages` (rows `recipe-stage-row-{id}`, Pattern C inline rows, add button `recipe-form-add-stage-btn`, fragment `/recipes/stage-row.php`):
  - seq | number | required, unique per version | `recipe-stage-row-{id}-seq`
  - stage_code | select from `app.stages` where `beverage_types @> product.beverage_type`, ordered by `display_order` | required | `recipe-stage-row-{id}-stage`
  - expected_loss_pct | number 0–100 step 0.01 | required default 0 | `recipe-stage-row-{id}-loss`
  - expected_duration_days | number ≥ 0 | optional | `recipe-stage-row-{id}-days`
  - instructions | text | optional | `recipe-stage-row-{id}-instructions`
  - delete icon (`hx-delete /recipes/{id}/stages/{stage_id}`, `hx-confirm`)
- Lines table `recipe-form-lines` (rows `recipe-line-row-{id}`, add button `recipe-form-add-line-btn`, fragment `/recipes/line-row.php`):
  - seq | number | required unique | `recipe-line-row-{id}-seq`
  - item_id | select (active items, class in fruit/juice/yeast/additive/consumable/intermediate) | required | `recipe-line-row-{id}-item`
  - stage_code | select (the version's stages) | required | `recipe-line-row-{id}-stage`
  - purpose | select (base_juice, yeast, nutrient, sulfite, enzyme, sweetener, acid, fining, other) | required | `recipe-line-row-{id}-purpose`
  - basis | radio per-batch / per-volume | required | `recipe-line-row-{id}-basis`
  - qty | number > 0 **(display→base; per-volume entered as per display volume unit)** | required | `recipe-line-row-{id}-qty` (saves exactly one of `qty_per_batch_base` / `qty_per_l`; the other NULL — table CHECK)
  - consumption_mode | select explicit/backflush | required, default item's `consumption_mode` | `recipe-line-row-{id}-mode`
  - notes | text | optional
  - delete icon (`hx-delete`, `hx-confirm`)
- Any write when `status <> 'draft'` → 409 and alert "Version {n} is {status}; create a new version." (trigger `recipe_guard_immutable` is the backstop).

### Read view (recipe-view)
- Header: product, version, status badge, batch volume (display), expected total loss, standard cost total / per L and per display unit, activated at/by, change note.
- Scale control `recipe-view-scale-volume` (number, display unit; `hx-get /recipes/{id}?scale=` Pattern A replaces `recipe-view-lines-table`): lines show quantity for the entered volume: per-batch lines scale linearly `qty × scale/target`; per-volume lines `qty_per_l × scale_l`.
- Diff selector `recipe-view-diff-version` (select other versions; `hx-get /recipes/{id}/diff.php?other=` replaces `recipe-view-diff`): three groups — added lines, removed lines, changed lines (qty, stage, purpose, mode) matched on (`item_id`, `stage_code`, `purpose`); same for stages matched on `stage_code`.
- Buttons: Edit (`recipe-view-edit-btn`, draft only), Activate (`recipe-view-activate-btn`, draft only, `hx-confirm` not required per manifest), "New version from this" (`recipe-view-copy-btn` → recipe-add with `copy_from`).

### Activate handler (`activate.php`)
- Preconditions: draft; ≥1 stage; ≥1 line; every line's stage exists in the version's stages.
- Transaction: previous active version of the product → `status='retired'`; this version → `status='active'`, `activated_at=now()`, `activated_by`; `expected_total_loss_pct = 100 × (1 − Π(1 − loss_i/100))` over stages; `standard_cost_total = Σ lines (qty_base_at_target × cost)` where cost = `items.standard_cost_per_base` when `costing_method='standard'` else the latest `lots.unit_cost_base` for the item (most recent `received_on`), else 0; plus overhead `target_batch_volume_l × overhead_rates.rate_per_l` (latest for the product's… see Open Questions) ; `standard_cost_per_l = total / target_batch_volume_l`. If `products.status='draft'` set it to `active`.
- Undo (`restore_prior`): allowed only when no `batches.recipe_version_id` references the new version: new → draft, previous → active.

### Files
- /var/www/html/recipes/new.php (under products: `/var/www/html/products/recipes-new.php` is NOT used; use rewrite `/products/{id}/recipes/new` → `/recipes/form.php?product_id=`) · form.php · save.php · view.php · edit.php · stage-save.php · stage-delete.php · line-save.php · line-delete.php · stage-row.php · line-row.php · activate.php · diff.php
- /var/www/app/features/recipes/queries.php
- /var/www/app/views/recipes/page.php (view full page) · edit-page.php · partials/form.php · editor.php · stage-row.php · line-row.php · view.php · lines-table.php · diff.php · saved.php

### Query functions
- find_recipe_versions(PDO, int product_id): array
- find_recipe_version(PDO, int id): ?array (header + stages + lines with item names/units)
- insert_recipe_version(PDO, int product_id, float target_batch_volume_l, ?int copy_from_id, ?string change_note, int created_by): array
- update_recipe_version(PDO, int id, float target_batch_volume_l, ?string change_note): array (draft only)
- upsert_recipe_stage(PDO, int version_id, ?int stage_id, int seq, string stage_code, float expected_loss_pct, ?int expected_duration_days, ?string instructions): array
- delete_recipe_stage(PDO, int stage_id): bool
- upsert_recipe_line(PDO, int version_id, ?int line_id, int seq, int item_id, string stage_code, string purpose, ?float qty_per_batch_base, ?float qty_per_l, string consumption_mode, ?string notes): array
- delete_recipe_line(PDO, int line_id): bool
- activate_recipe_version(PDO, int id, int actor_id): array
- scale_recipe_lines(PDO, int id, float volume_l): array
- diff_recipe_versions(PDO, int a_id, int b_id): array

### Action manifest entries
- Screens: recipe-add, recipe-edit, recipe-view.
- Actions: `recipe_create_draft` (undo delete_row), `recipe_update_draft` (undo restore_prior), `recipe_activate` (undo restore_prior while unused).

### Activity log events
- `screen_entered`, `recipe_version_created`, `recipe_version_updated`, `recipe_stage_saved`, `recipe_stage_deleted`, `recipe_line_saved`, `recipe_line_deleted`, `recipe_version_activated` (before: previous active id; after: cost snapshot).

### Status vocabulary
- draft=dark, active=success, retired=secondary.

### Out of scope
- Editing active versions; recipe-level QC targets (specs are per product/stage); yield simulations.

### Resolved (2026-10-01)
- Overhead in the standard cost snapshot at `recipe_activate`: use the current `overhead_rates` row of the active premises whose `kind` matches the product's beverage (`bonded_winery` for cider and wine, `brewery` for beer); if several match, the lowest id; if none, exclude overhead from `standard_cost_total` and show "overhead not included" on the recipe view.

### Open Questions
- (none)

---

## Entity: packaging configuration

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| packaging-configs-list | /packaging-configs/ | List |
| packaging-config-add | /packaging-configs/new | Form (empty) with BOM lines |
| packaging-config-edit | /packaging-configs/{id}/edit | Same form, pre-filled |

### List screen
- Columns: name (status dot: active=success, inactive=secondary) · product (`products.name`) · finished item (`items.name` + `<small>code</small>`) · kind (`package_kind`) · fill volume (`fill_volume_l` display, 3 dp) · units/case · expected loss % · BOM lines (count)
- Search: name, product name, finished item; filter `product_id`, `package_kind`, `active`; sort `product_name` (default), `name`, `package_kind`; page 25
- Row link: packaging-config-edit (no detail view)

### Form
- product_id | select (products not retired) | required | `packaging-config-form-field-product`
- finished_item_id | select (items where `item_class='finished_good'` and active) | required, unique with product (`23505` → "this product already has a configuration for that item") | `packaging-config-form-field-finished-item`
- name | text | required | `packaging-config-form-field-name`
- package_kind | select keg/can/bottle | required | `packaging-config-form-field-package-kind`
- fill_volume | number > 0 **(display→base L)**; for cans allow fl oz entry via unit select `packaging-config-form-field-fill-unit` (gal, L, floz, mL from `app.units` volume rows) | required | `packaging-config-form-field-fill-volume`
- units_per_case | number ≥ 1 | optional (required when package_kind ≠ keg) | `packaging-config-form-field-units-per-case`
- expected_loss_pct | number 0–100 | required default 2 | `packaging-config-form-field-expected-loss`
- active | checkbox default on | | `packaging-config-form-field-active`
- BOM lines (`packaging-config-form-bom`, add button `packaging-config-form-add-bom-btn`, fragment `/packaging-configs/bom-row.php`):
  - item_id | select (items class packaging/consumable/returnable_asset) | required, unique per config | `packaging-config-form-bom-{n}-item`
  - qty_per_unit | number > 0 per packaged unit **(display→base for kg items; ea as-is)** | required | `packaging-config-form-bom-{n}-qty`
- Prefill params: `product` (code), `package_kind`.
- Save replaces BOM lines in a transaction.

### Files
- /var/www/html/packaging-configs/index.php · form.php · save.php · bom-row.php
- /var/www/app/features/packaging-configs/queries.php
- /var/www/app/views/packaging-configs/page.php · partials/table.php · row.php · form.php · bom-row.php · saved.php

### Query functions
- find_packaging_configurations(PDO, search='', filters=[], sort='product_name', page=1): array
- find_packaging_configuration(PDO, int id): ?array (with BOM lines)
- insert_packaging_configuration(PDO, int product_id, int finished_item_id, string name, string package_kind, float fill_volume_l, ?int units_per_case, float expected_loss_pct, bool active, array bom_lines): array
- update_packaging_configuration(PDO, int id, ...same): array

### Action manifest entries
- Screens: packaging-configs-list, packaging-config-add, packaging-config-edit.
- Actions: `packaging_config_create` / `packaging_config_update` (undo delete_row / restore_prior).

### Activity log events
- `screen_entered`, `packaging_config_created`, `packaging_config_updated` (before/after incl. BOM).

### Status vocabulary
- active=success, inactive=secondary.

### Out of scope
- Deleting configurations referenced by `finished_lots` or `packaging_runs` (deactivate instead); label artwork.

### Open Questions
- (none)

---

## Entity: spec

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| specs-list | /products/{id}/specs | Specs for one product grouped by stage (table per the canonical pattern, grouped rows) |
| spec-add | /products/{id}/specs/new | Form (empty, product fixed) |
| spec-edit | /specs/{id}/edit | Same form, pre-filled |

### List screen
- Columns: stage (`stages.name`, ordered by `display_order`) · measurement (`measurement_types.name` + `<small>unit</small>`) · min · max · target · active (dot) 
- No search; sort fixed by stage order then measurement; no pagination
- Row link: spec-edit; Add button `specs-list-add-btn` → spec-add

### Form
- product_id | hidden | required | `spec-form-field-product`
- stage_code | select (`app.stages` for product beverage) | required | `spec-form-field-stage`
- measurement_type_code | select (`app.measurement_types`) | required; unique (product, stage, measurement) `23505` → "a spec for this measurement at this stage exists" | `spec-form-field-measurement`
- min_value | number | optional | `spec-form-field-min`
- max_value | number | optional (at least one of min/max; min ≤ max) | `spec-form-field-max`
- target_value | number | optional | `spec-form-field-target`
- active | checkbox default on | | `spec-form-field-active`
- Prefill params: `stage`, `measurement`.
- Values are in the measurement type's own unit (no display conversion).

### Files
- /var/www/html/specs/index.php · form.php · save.php · delete.php
- /var/www/app/features/specs/queries.php
- /var/www/app/views/specs/page.php · partials/table.php · row.php · form.php · saved.php

### Query functions
- find_specs(PDO, int product_id): array
- find_spec(PDO, int id): ?array
- insert_spec(PDO, int product_id, string stage_code, string measurement_type_code, ?float min_value, ?float max_value, ?float target_value, bool active): array
- update_spec(PDO, int id, ...same): array
- delete_spec(PDO, int id): bool (allowed only when no `readings.spec_id` references it; else deactivate)

### Action manifest entries
- Screens: specs-list, spec-add, spec-edit.
- Actions: `spec_create` / `spec_update` (undo delete_row / restore_prior).

### Activity log events
- `screen_entered`, `spec_created`, `spec_updated`, `spec_deleted`.

### Status vocabulary
- active=success, inactive=secondary.

### Out of scope
- Evaluating readings (trigger `evaluate_reading_spec` + slice 8).

### Open Questions
- (none)

---

## Entity: standard cost and overhead rate

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| standard-costs-list | /standard-costs/ | Items with current standard cost + an overhead-rates card per premises |
| standard-cost-add | /standard-costs/new | Form: set a standard cost for an item |
| (overhead form) | /standard-costs/overhead | Form: set an overhead rate for a premises (`standard-cost-overhead-form`) — reached from the overhead card's Add button |

### List screen
- Columns: item (`items.name` + `<small>code</small>`) · class · costing method (`costing_method`) · current standard (`items.standard_cost_per_base` per base unit, plus per display unit) · effective from (latest `standard_costs.effective_from`) · history (count of `standard_costs` rows)
- Filter: `item_class`, `costing_method`; search name/code; sort `name` default; page 50
- Row link: standard-cost-add with `item` prefilled (no edit of history rows)
- Overhead card `standard-costs-overhead-card`: premises · current `rate_per_l` (and per display volume unit) · effective from; Add button `standard-costs-overhead-add-btn`.

### Form (standard-cost-add)
- item_id | select (active items) | required | `standard-cost-form-field-item`
- cost | number ≥ 0, entered per display unit of the item's base dimension (lb/gal/ea) **(display→base: cost_per_base = cost / to_base_factor)** | required | `standard-cost-form-field-cost`
- effective_from | date default today | required; unique (item, date) `23505` → "a cost for that date exists" | `standard-cost-form-field-effective-from`
- Prefill params: `item` (code), `cost`.
- On save: insert `standard_costs`; if `effective_from <= current_date` and it is the latest, update `items.standard_cost_per_base` (and keep `costing_method` unchanged).

### Form (overhead)
- premises_id | select | required | `standard-cost-overhead-form-field-premises`
- rate | number ≥ 0 per display volume unit **(display→base: rate_per_l = rate / to_base_factor)** | required | `standard-cost-overhead-form-field-rate`
- effective_from | date | required; unique (premises, date) | `standard-cost-overhead-form-field-effective-from`

### Files
- /var/www/html/standard-costs/index.php · form.php · save.php · overhead.php · overhead-save.php
- /var/www/app/features/standard-costs/queries.php
- /var/www/app/views/standard-costs/page.php · partials/table.php · row.php · form.php · overhead-card.php · overhead-form.php · saved.php

### Query functions
- find_standard_cost_items(PDO, search='', filters=[], sort='name', page=1): array
- find_standard_cost_history(PDO, int item_id): array
- insert_standard_cost(PDO, int item_id, float cost_per_base, string effective_from, int created_by): array
- find_overhead_rates(PDO): array
- insert_overhead_rate(PDO, int premises_id, float rate_per_l, string effective_from, int created_by): array

### Action manifest entries
- Screens: standard-costs-list, standard-cost-add.
- Actions: `standard_cost_set` (`POST /standard-costs/save`; undo delete_row), `overhead_rate_set` (`POST /standard-costs/overhead`; undo delete_row). Owner role.

### Activity log events
- `screen_entered`, `standard_cost_set` (after: item, cost, effective_from; before: previous standard), `overhead_rate_set`.

### Status vocabulary
- None.

### Out of scope
- Cost roll-ups (view `v_batch_costs`, slice 9); editing or deleting history rows.

### Open Questions
- (none)

---

## Entity: product approval

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| approvals-list | /approvals/ | List across products, with "missing" rows for active products lacking a required approval |
| approval-add | /approvals/new | Form (empty) |
| approval-edit | /approvals/{id}/edit | Same form, pre-filled |

### List screen
- Columns: product (`products.name`, status dot by approval status) · kind (`formula`/`label`) · package (`packaging_configurations.name`, label only) · reference (`reference_no`) · status badge · approved on · expires on (`text-danger` when < today+60)
- Search: product name, reference_no; filter `kind`, `status`, `product_id`; sort `product_name` default, `expires_on`, `status`; page 25
- Row link: approval-edit; Add button → approval-add

### Form
- product_id | select | required | `approval-form-field-product`
- kind | select formula/label | required | `approval-form-field-kind`
- packaging_configuration_id | select (configs of the chosen product; Pattern A `/approvals/configs.php?product_id=`) | optional, label only | `approval-form-field-packaging-config`
- reference_no | text | optional | `approval-form-field-reference-no`
- status | select (not_required, required, submitted, approved, expired, rejected) | required default required | `approval-form-field-status`
- approved_on | date | required when status=approved | `approval-form-field-approved-on`
- expires_on | date | optional | `approval-form-field-expires-on`
- attachment | file (pdf/png/jpg ≤ 10 MB → `app.attachments` kind `cola` or `formula`, entity_type `product_approval`) | optional | `approval-form-field-attachment`
- notes | textarea | optional | `approval-form-field-notes`
- Prefill params: `product` (code), `kind`.

### Files
- /var/www/html/approvals/index.php · form.php · save.php · configs.php
- /var/www/app/features/approvals/queries.php
- /var/www/app/views/approvals/page.php · partials/table.php · row.php · form.php · saved.php

### Query functions
- find_approvals(PDO, search='', filters=[], sort='product_name', page=1): array
- find_approval(PDO, int id): ?array
- insert_approval(PDO, int product_id, string kind, ?int packaging_configuration_id, ?string reference_no, string status, ?string approved_on, ?string expires_on, ?int attachment_id, ?string notes): array
- update_approval(PDO, int id, ...same): array
- find_products_missing_approvals(PDO): array (active products with no `approved`/`not_required` row per kind)

### Action manifest entries
- Screens: approvals-list, approval-add, approval-edit.
- Actions: `approval_record` / `approval_update` (undo delete_row / restore_prior). Compliance role.

### Activity log events
- `screen_entered`, `approval_recorded`, `approval_updated` (before/after).

### Status vocabulary
- approved=success, submitted/required=warning, rejected/expired=danger, not_required=secondary.

### Out of scope
- Filing with TTB; COLA lookups.

### Open Questions
- (none)
