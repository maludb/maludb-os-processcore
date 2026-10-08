# Phase 3 conventions (read before building any slice)

**Date:** 2026-10-01. These rules override the build specs where they disagree. Reference implementations:

- **Simple CRUD:** premises — `html/premises/`, `app/features/premises/queries.php`, `app/views/premises/`.
- **Documents with lines, posting to the ledger, detail views with tabs:** receipts and lots — `html/receipts/`, `html/lots/`, `app/features/receipts/`, `app/features/lots/`, `app/features/inventory/ledger.php`.

Build every slice **by copying the structure of the closest reference**, substituting the entity's fields from its build spec. Never invent a new UI pattern.

## Files

Per entity, as the build spec lists them, with one change: **there is no `saved.php`**. A successful save calls `flash('success', '…')`, `hx_trigger('{entity}Changed')` and `hx_location('{canonical list or view URL}')`. Validation failure re-renders the form screen with `http_response_code(422)` through `render_screen()` (the htmx config swaps 403/404/409/422).

## Routing (`html/_router.php`, do not edit)

| URL | File |
|---|---|
| `/{feature}/` | `index.php` |
| `/{feature}/new` | `form.php` |
| `/{feature}/{id}` | `view.php` (`$_GET['id']`) |
| `/{feature}/{id}/edit` | `form.php` |
| `/{feature}/{id}/{verb}` | `{verb}.php`; a POST prefers `{verb}-save.php` when it exists |
| `/{feature}/{id}/{a}/{b}` | `{a}-{b}.php` (`new` becomes `form`: `/lots/5/coa/new` → `coa-form.php`) |
| `/{feature}/{id}/{a}/{n}/{b}` | `{a}-{b}.php` with `$_GET['sub_id'] = n` |
| `/{feature}/{word}` | `{word}.php` (`/purchase-orders/line-row`) |

A planned screen without a controller renders the stub automatically; creating the file replaces the stub.

## Controller sequence

```
require bootstrap + the feature's queries.php (+ other features' queries.php you read from)
GET screens:  $user = require_login();  (writes: require_role('receiving') etc. per the manifest role column; owner always passes)
POST:         require_post(); verify_csrf(); $user = require_role(...);
read input (request_string, request_integer, post_decimal, post_date, post_bool) → validate into $errors[field] = message
writes:       $pdo->beginTransaction(); query functions; log_activity(...); $pdo->commit();
render:       render_screen($title, $screenId, view(...), $entityType, $recordId)  or  hx_location($url)
```

- Every GET screen calls `log_screen_entered($screenId, $entityType, $id, $label)` before rendering.
- Every state change calls `log_activity($pdo, $eventName, $entityType, $id, $label, $before, $after, $details, $screenId)` **inside the transaction**. Event names come from the spec's "Activity log events".
- Viewers (role `viewer`) see every list and detail; Add/Edit/post buttons render only when `user_can($user, ...roles)`.
- Inner refreshes (search, filters, sort, paging) are detected with `is_results_request('{screen}-results')` and return only the table partial.
- `PDOException`: roll back, `error_log()` the message, show `db_error_message($e)` (trigger/constraint text) or a generic sentence. Unique violations: `is_unique_violation($e)`.

## Helpers you must use (do not reimplement; do not edit these files)

- `app/http.php`: `render_screen`, `hx_location`, `hx_trigger`, `redirect`, `not_found`, `forbidden`, `flash`, `request_string`, `request_integer`, `format_date`, `format_datetime`, `e`, `view`.
- `app/list.php`: `paged_query`, `order_by` (sort allowlist: request key ⇒ SQL expression), `list_params`, `query_string`, `is_results_request`, `LIST_PAGE_SIZE`.
- `app/ui.php`: `status_dot`, `badge`, `status_badge`, `status_color`, `humanize`, `yes_no`, `nav_attrs`, `nav_button`, `row_edit_button`, `form_actions`, `list_search`, `list_filter`, `form_input`, `form_select`, `form_textarea`, `form_checkbox`, `form_static`, `detail_row`, `field_id`, `post_bool`, `post_decimal`, `post_date`, `in_options`, `is_unique_violation`, `db_error_message`, `today`.
- `app/units.php`: `fmt_qty`, `fmt_qty_html` (display unit + tooltip with the base value), `to_display`, `from_display`, `display_unit`, `fmt_unit_cost`, `client_settings`, `unit_table`, `unit_factor`. **Store base units (L, kg, ea); enter and show display units.** Fruit weights use `kind = 'fruit'`.
- `app/views/shared/`: `page-header.php` (title, screen, crumbs, actionsHtml), `list-card.php` (the canonical table card with sort and pagination), `validation-errors.php`, `flash.php`, `error.php`.
- `app/features/inventory/ledger.php`: `insert_inventory_transaction()` and `new_group_id()` — the only way to write the ledger.
- `app/features/premises/queries.php`: `premises_options()`.

If a slice genuinely needs a new shared helper, put it in the slice's own `queries.php` (prefixed with the feature name) and say so in your report. Do not edit `app/*.php`, `app/views/layout.php`, `app/views/shared/*`, `html/_router.php`, `app/navigation.php` or `assets/css/app-overrides.css`.

## Markup rules (design system)

- List page: `page.php` = `shared/page-header.php` with `list_search(...)`, optional `list_filter(...)`, and the Add button `{feature}-list-add-btn` via `nav_button`; then `.main-content > .row >` the table partial. `partials/table.php` renders rows with `row.php` and wraps them with `shared/list-card.php`.
- Row: `<tr id="{entity}-row-{id}">`, cells `{entity}-row-{id}-{column}`, first cell is the link with `status_dot`, last cell right-aligned actions with `row_edit_button`.
- Form page: page header with `form_actions('{entity}-form', $cancelUrl, 'Save …')`; `<form id="{entity}-form" method="post" action="…" hx-post="…" hx-target="#page-content" hx-swap="innerHTML">` with `csrf_field()`; one `card` (or the tabs-as-card-header pattern from components.md when the spec lists tabs); rows through `form_input`/`form_select`/… with prefix `{entity}-form`.
- Detail page: components.md detail pattern — left `col-xxl-4 col-xl-6` summary card, right `col-xxl-8 col-xl-6` card whose header is the nav-tabs strip; panes `{screen}-pane-{tab}`; tab links `{screen}-tab-{tab}`.
- Inline sub-forms on a tab (Pattern A): the form `hx-post`s to its endpoint with `hx-target="#{screen}-pane-{tab}" hx-swap="innerHTML"`; the endpoint returns the tab partial only (with errors when invalid, status 422).
- Status colors only from `STATUS_COLORS` (`app/ui.php`). Dates `format_date` (medium), timestamps `format_datetime`.
- Never: `.modal`, `hx-push-url="true"`, inline `style=` (except progress bar widths), DataTables, new CSS. `hx-confirm` only on destructive or tax-state-changing controls.
- Every meaningful element has a unique kebab-case id per the scheme. Mobile: tables inside `.table-responsive` (the list card does this), no fixed widths.

## Testing a slice

```bash
S=/tmp/claude-1000/-var-www/b67b684c-d141-48c2-b5e6-86ee256b9726/scratchpad
source $S/login.sh                       # signs in as the owner; defines H (HTMX curl with CSRF) and $J, $CSRF
H http://127.0.0.1/premises/ -o /tmp/x.html -w "%{http_code}\n"
H -d "name=…" http://127.0.0.1/premises/save -D - -o /dev/null
sudo -n tail -20 /var/log/apache2/error.log | grep -i php      # must be empty of new errors
php -l <file>                                                   # every file
scripts/conformance.sh <feature> [<feature>...]                # mechanical checklist
```

Database for tests: `sudo -n -u postgres psql -d cidery_dev` (`SET ROLE cidery_app;`). Test data you create may stay; do not drop tables or change the schema.

## Done means

All spec screens and actions work through curl (GET screens 200, POST validation 422, POST success with `HX-Location`), `scripts/conformance.sh` passes, no new PHP errors in the Apache log, and the report lists any decision you had to make. **An invented decision is a defect:** when the spec is ambiguous, pick nothing, note the exact question in your report, and build the rest.
