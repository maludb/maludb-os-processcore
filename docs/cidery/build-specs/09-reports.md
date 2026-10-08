# Build spec: yield and cost reporting slice (slice 9)

Exemplar to replicate: receiving slice (slice 2) for files, shell wiring, ids, and the list-screen pattern; the lots list is the closest exemplar screen (read-only table with filters).
Model class: worker. Four report screens, no forms, no writes. If anything is ambiguous, conflicting, or missing, STOP, record the exact question under Open Questions, and escalate.

Schema (read only, never modify): views `app.v_batch_stage_yields`, `app.v_press_run_yields`, `app.v_batch_costs`, `app.v_inventory_valuation`, plus `app.products`, `app.batches`, `app.finished_lots`, `app.packaging_configurations`, `app.premises`, `app.locations`, `app.inventory_transactions`, `app.lots`, `app.items` for filters and the as-of valuation.

Common rules for every report
- One feature directory `reports`; each report is its own Pattern B endpoint rendering a partial into `#page-content`; filters are a `GET` form in the page header posting with `hx-get` (`hx-trigger="change, keyup changed delay:400ms"`) and `hx-push-url` set to the explicit canonical URL with its query string; results region id `report-{name}-results`.
- Every report has an "Export CSV" button (`report-{name}-export-btn`) linking to the same endpoint with `&format=csv`; the controller sets `Content-Type: text/csv` and `Content-Disposition: attachment; filename="{name}-{date}.csv"` and emits the same rows and column headers as the table, numbers unformatted.
- Volumes are displayed in gallons (`l_to_gal()`), masses in pounds, with the liter or kilogram value in a tooltip; CSV carries both columns (`*_l` and `*_gal`).
- No charts in this slice (the design system adds ApexCharts only when a plan demands it; it does not).
- Tables wrap in `.table-responsive`; at 375 px each report stacks its filter controls.

---

## Entity: yield report

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| report-yields | /reports/yields | Per-stage yield and loss per batch against the recipe's expectation; prefill `product` |

### List screen
- Source: `app.v_batch_stage_yields` joined `app.batches` (for `product_id`, `status`, `started_at`) and `app.products`.
- Filters (ids `report-yields-filter-{name}`): product (select, optional), batch (text search on `number`), date range on `batches.started_at` (default last 12 months), stage (select from `app.stages` where `'cider' = any(beverage_types)`).
- Columns, in order: batch → `number` (link batch-view) with product `<small>`; stage → `stage_name`; entered → `entered_at` (medium date); volume in → `volume_in_l` in gal; volume out → `volume_out_l` in gal; actual loss % → `actual_loss_pct`; expected loss % → `expected_loss_pct`; variance → `actual_loss_pct − expected_loss_pct` (points, red text when > 0); recorded loss → `recorded_loss_l` in gal.
- Group rows by batch (a `thead-light` subheader row per batch, id `report-yields-batch-{batch_id}`), with a batch total row: sum of recorded loss, first `volume_in_l` to last `volume_out_l` overall loss %.
- Sort allowlist: `entered_at`, `number`, `stage_code`; page size: 100 rows.
- Row link target: batch-view.

### Form
- (none; filters only)

### Files (exactly these)
- /var/www/html/reports/yields.php
- /var/www/app/features/reports/queries.php (shared by the four reports)
- /var/www/app/views/reports/page.php (shared wrapper: title, filters slot, results slot) · partials/yields-filters.php · yields-table.php

### Query functions (signatures fixed)
- find_yield_rows(PDO, ?int product_id, string batch_search, ?string date_from, ?string date_to, ?string stage_code, string sort='entered_at', int page=1, int page_size=100): array
- find_report_products(PDO): array — active and retired products for filter selects (shared).

### Action manifest entries
- Screens: `report-yields` ("see per-stage yield and loss by batch or product"; prefill `product`).
- Actions: none.

### Activity log events
- `screen_entered` (details = the filter values); `report_exported` (details = {report: 'yields', filters}).

### Status vocabulary mapping
- Variance cell: ≤ 0 → success text; > 0 and ≤ 2 points → warning; > 2 → danger.

### Out of scope for this slice
- Trend charts; brewhouse efficiency (beer); barrel evaporation (wine); editing stage events.

### Open Questions
- (none)

---

## Entity: juice yield report

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| report-juice-yield | /reports/juice-yield | Gallons per ton and per bushel by variety; prefill `season_year` |

### List screen
- Source: `app.v_press_run_yields`.
- Filters: season_year (select of distinct `extract(year from run_on)`, default current year), variety (select of distinct `variety`, optional), premises (select, shown only when more than one premises exists).
- Two tables. Summary (`report-juice-yield-summary-table`): one row per variety: variety → `variety` (null shown as "Unspecified"); press runs → count; fruit → sum `fruit_kg` in lb and tons; juice → sum `juice_l_attributed` in gal; gal/ton → sum juice gal ÷ sum tons; gal/bushel → sum juice gal ÷ (sum kg ÷ 19.05087954). Detail (`report-juice-yield-detail-table`): one row per press run and variety: run → `number` (link press-run-view); date → `run_on`; variety; fruit lb; juice gal; `gal_per_ton`; `gal_per_bushel`.
- Sort allowlist (detail): `run_on`, `variety`, `gal_per_ton`; page size: 100.
- Row link target: press-run-view.
- Benchmark line under the summary, static text from the research: 130 to 185 gal per ton, 2.5 to 3.5 gal per bushel.

### Form
- (none)

### Files (exactly these)
- /var/www/html/reports/juice-yield.php
- /var/www/app/views/reports/partials/juice-yield-filters.php · juice-yield-summary.php · juice-yield-table.php
- (queries in the shared /var/www/app/features/reports/queries.php)

### Query functions (signatures fixed)
- find_juice_yield_summary(PDO, int season_year, ?string variety, ?int premises_id): array
- find_juice_yield_rows(PDO, int season_year, ?string variety, ?int premises_id, string sort='run_on', int page=1, int page_size=100): array
- find_juice_yield_seasons(PDO): array
- find_juice_yield_varieties(PDO): array

### Action manifest entries
- Screens: `report-juice-yield` ("see gallons per ton and per bushel by variety"; prefill `season_year`).
- Actions: none.

### Activity log events
- `screen_entered`; `report_exported` (report: 'juice-yield').

### Status vocabulary mapping
- gal/ton cell: within 130 to 185 → success text; below 130 → warning; above 185 → info.

### Out of scope for this slice
- Yield by orchard or block (the weigh tag holds them; add a group-by later if asked); press efficiency by press vessel.

### Open Questions
- (none)

---

## Entity: batch cost report

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| report-batch-costs | /reports/batch-costs | Cost per batch, per liter and gallon, per keg and per case, variance to standard; prefill `product` |

### List screen
- Source: `app.v_batch_costs` joined `app.products`; per-package costs from `app.finished_lots` joined `app.packaging_configurations` for the batch (`unit_cost`, `package_kind`, `units_per_case`).
- Filters: product (select, optional), status (select active, packaged, closed, dumped; default all except dumped), date range on `batches.started_at` (default last 12 months).
- Columns, in order: batch → `number` (link batch-view) with product `<small>`; status → badge; starting volume → `starting_volume_l` in gal; material → `material_cost` (currency); packaging → `packaging_cost`; overhead → `overhead_cost`; total → `total_cost`; per gal → `liquid_cost_per_l × 3.785411784`; standard → `standard_cost_total`; variance → `variance_to_standard` (red when > 0, green when < 0); per keg → min `unit_cost` of finished lots with `package_kind = 'keg'` (blank if none); per case → `unit_cost × units_per_case` for `package_kind = 'can'` (blank if none).
- Footer row: sums of material, packaging, overhead, total, variance.
- Sort allowlist: `started_at`, `number`, `total_cost`, `variance_to_standard`; page size: 50.
- Row link target: batch-view.

### Form
- (none)

### Files (exactly these)
- /var/www/html/reports/batch-costs.php
- /var/www/app/views/reports/partials/batch-costs-filters.php · batch-costs-table.php
- (queries in the shared /var/www/app/features/reports/queries.php)

### Query functions (signatures fixed)
- find_batch_cost_rows(PDO, ?int product_id, array statuses, ?string date_from, ?string date_to, string sort='started_at', int page=1, int page_size=50): array
- find_batch_package_costs(PDO, array batch_ids): array — keyed by batch_id: per_keg, per_case.

### Action manifest entries
- Screens: `report-batch-costs` ("see cost per batch, per liter, per keg and case, variance"; prefill `product`).
- Actions: none.

### Activity log events
- `screen_entered`; `report_exported` (report: 'batch-costs').

### Status vocabulary mapping
- Batch status badges per the manifest: packaged → success; dumped → danger; active → info; closed → secondary.

### Out of scope for this slice
- Labor costing; moving-average cost; COGS by period (needs sales, out of scope for v1); margin.

### Open Questions
- (none)

---

## Entity: inventory valuation report

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| report-valuation | /reports/valuation | Inventory value by item class and tax state, now or as of a date; prefill `as_of` |

### List screen
- Source: `app.v_inventory_valuation` for the current position. When `as_of` is earlier than today, compute from the ledger instead: `sum(qty_base)` per item, lot, location from `app.inventory_transactions` where `occurred_at < as_of + 1 day`, valued at `lots.unit_cost_base` (or `items.standard_cost_per_base` when `costing_method = 'standard'`), grouped the same way. The query function chooses; the screen does not.
- Filters: as_of (date, default today), premises (select when more than one), group_by (select: item_class, tax_state, location; default item_class).
- Columns, in order: group → `item_class` / `tax_state` / `location name`; quantity → `qty_on_hand` with `base_unit_code` (mixed units show one row per unit); value → `value` (currency); share → value ÷ total %.
- Footer row: total value. A second small table (`report-valuation-tax-state-table`) always shows bonded vs tax paid totals regardless of group_by, which is R46.
- Sort allowlist: `group`, `value`; no pagination (groups are few).
- Row link target: `inventory-list` filtered by the group (`/inventory/?item_class=` or `?location_id=`).

### Form
- (none)

### Files (exactly these)
- /var/www/html/reports/valuation.php
- /var/www/app/views/reports/partials/valuation-filters.php · valuation-table.php · valuation-tax-state.php
- (queries in the shared /var/www/app/features/reports/queries.php)

### Query functions (signatures fixed)
- find_valuation_rows(PDO, string as_of, ?int premises_id, string group_by, string sort='value'): array
- find_valuation_by_tax_state(PDO, string as_of, ?int premises_id): array

### Action manifest entries
- Screens: `report-valuation` ("see inventory value by class and tax state"; prefill `as_of`).
- Actions: none.

### Activity log events
- `screen_entered`; `report_exported` (report: 'valuation').

### Status vocabulary mapping
- Tax state: bonded → info; tax_paid → success.

### Out of scope for this slice
- Accounting export formats; FIFO cost layers; write-downs.

### Open Questions
- (none)
