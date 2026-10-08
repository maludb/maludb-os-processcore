# Customer orders: design (step 1)

**Date:** 2026-10-02
**Status:** for owner approval, alongside `db/016_customer_orders.sql`. Plan: [11-customer-orders-plan.md](11-customer-orders-plan.md). Extends [04-mcp-tool-surface.md](04-mcp-tool-surface.md) and [05-action-manifest.md](05-action-manifest.md); merged into them when approved.
**Checked:** the schema applies cleanly to `cidery_dev` and was rolled back (not applied yet). The smoke test showed weekly and every-2-weeks occurrences on the right days, forecast netting (a forecast of 20 against a firm 10 and a standing 4 gives 6 in that week) and order values.

## 1. Schema summary

| Object | Kind | Notes |
|---|---|---|
| `sales_orders`, `sales_order_lines` | tables | Number `SO-00001`. Status `draft → confirmed → in_fulfillment → shipped → closed`, or `cancelled`. Origin `entered`, `imported`, `standing`, `assistant`. Line total generated from units × price |
| `standing_orders`, `standing_order_lines` | tables | Number `STO-0001`. Weekly, every N weeks or monthly (day 1 to 28), with start and optional end |
| `demand_forecasts` | table | Units per format per ISO week; `run_rate` rows regenerate, `manual` rows are kept |
| `order_imports` | table | Number `IMP-0001`; the file is an attachment of kind `spreadsheet`; mapping, counts and row errors |
| `packaging_run_order_lines` | table | Run ↔ order lines with units |
| `production_order_packages` | table | Optional packaging plan on a production order: planned units or a share, optionally for an order line |
| `removals.sales_order_id`, `removal_lines.sales_order_line_id` | columns | Shipping links |
| `packaging_configurations.default_unit_price` | column | List price per format |
| `users.role` | check | Adds `sales` |
| `standing_order_occurrences(from, to)` | function | Occurrence dates of active standing orders |
| `v_sales_order_lines` | view | Line with shipped, in packaging runs and open units |
| `v_demand` | view | Firm, standing and forecast demand for 26 weeks, by format and week, with value |

**Rules the schema enforces:**
- A history order (`fulfilled_outside`) is always `closed`.
- An occurrence of a standing order becomes an order at most once.
- The same customer PO reference can't be entered twice, which also stops a spreadsheet being imported twice.
- Shipped units = outbound minus inbound removal units on the line, counting posted and reversed documents. A reversal therefore cancels its original, provided the reversal copies the line link; that's a step 3 change to `reverse_removal`.

**Not in this file:** the packaging, production and purchasing projection functions. They build on `v_demand` and come with step 6.

## 2. Status vocabulary (locked colors)

| Entity | success | warning | danger | info | secondary | dark |
|---|---|---|---|---|---|---|
| Customer order | shipped | — | cancelled | confirmed, in_fulfillment | closed | draft |
| Order line | — | closed_short | cancelled | open | — | — |
| Standing order | active | — | — | — | inactive | — |
| Order import | imported | previewed | — | — | undone, abandoned | — |
| Demand type (badge) | firm | standing | — | forecast | — | — |

## 3. Screen registry (new)

| Screen id | URL | Title | When the user wants to… |
|---|---|---|---|
| `orders-list` | `/orders/` | Customer orders | see open or past orders, filter by customer, product, due date |
| `order-add` | `/orders/new` | New order | enter an order (prefill: `customer`, `standing_order`, `occurs_on`) |
| `order-edit` | `/orders/{id}/edit` | Edit order | change a draft or confirmed order |
| `order-view` | `/orders/{id}` | Order | see an order's lines, fulfillment, runs and shipments |
| `order-package` | `/orders/{id}/package` | Package for order | create the packaging runs that fill an order |
| `orders-to-package` | `/orders/to-package` | Packaging queue | see what must be packaged for orders, by format and due date |
| `standing-orders-list` | `/orders/standing/` | Standing orders | see recurring orders |
| `standing-order-add` / `-edit` / `-view` | `/orders/standing/new`, `/{id}/edit`, `/{id}` | Standing order | set up or change a recurring order, see its next dates |
| `orders-import` | `/orders/import` | Import orders | load past or upcoming orders from a spreadsheet |
| `order-import-view` | `/orders/import/{id}` | Import | see an import's preview, result or errors; undo it |
| `planning-forecast` | `/planning/forecast` | Forecast | see and adjust forecast demand per format and week |
| `planning` | `/planning/` | Projections | see demand by type and what to package, produce and buy, week by week |
| `planning-production` | `/planning/production` | Suggested production | see which batches to start and when |
| `planning-purchasing` | `/planning/purchasing` | Suggested purchases | see what to buy, how much and by when |
| `report-orders` | `/reports/orders` | Order history | see past orders by customer, product and month |

Also new tabs: Orders on `customer-view` and `product-view`. New navigation group **Sales**: Orders, Packaging queue, Standing orders, Import, plus a **Planning** group: Projections, Production, Purchasing, Forecast.

## 4. Action registry (new)

| Action | Endpoint | Parameters | Undo | Confirm | Role |
|---|---|---|---|---|---|
| `order_create` / `order_update` | `POST /orders/save` | customer, requested_on, ordered_on?, reference?, destination?, lines[] (format, units, price?), notes? | delete_row (draft) / restore_prior | no | sales |
| `order_confirm` | `POST /orders/{id}/confirm` | — | restore_prior | no | sales |
| `order_cancel` | `POST /orders/{id}/cancel` | reason | restore_prior | yes | sales |
| `order_close` | `POST /orders/{id}/close` | — (open lines become closed_short) | restore_prior | yes | sales |
| `order_package` | `POST /orders/{id}/package` | per format: units, batch?, run_on? | delete_row (draft runs) | no | sales, production |
| `orders_package_queue` | `POST /orders/to-package/package` | format, order lines[], units, batch? | delete_row (draft run) | no | sales, production |
| `order_ship` | `POST /orders/{id}/ship` | lines? (default all open) | delete_row (draft removal) | no | sales, compliance |
| `order_from_standing` | `POST /orders/standing/{id}/occurrence` | occurs_on | delete_row | no | sales |
| `standing_order_create` / `_update` | `POST /orders/standing/save` | customer, frequency, interval?, weekday or day, starts_on, ends_on?, lines[] | delete_row / restore_prior | no | sales |
| `standing_order_deactivate` | `POST /orders/standing/{id}/deactivate` | — | restore_prior | no | sales |
| `orders_import_preview` | `POST /orders/import/preview` | file, mapping | none (preview only) | — | sales (screen only) |
| `orders_import_commit` | `POST /orders/import/{id}/commit` | create_customers?, future_status | `orders_import_undo` | yes | sales (screen only) |
| `orders_import_undo` | `POST /orders/import/{id}/undo` | — (refused once any order is fulfilled) | none | yes | sales |
| `orders_import_discard` | `POST /orders/import/{id}/discard` | — (previews only) | none | yes | sales (screen only) |
| `forecast_generate` | `POST /planning/forecast/generate` | history_weeks, horizon_weeks | restore_prior | no | sales |
| `forecast_set` | `POST /planning/forecast/save` | format, week_start, units | restore_prior | no | sales |
| `format_price_update` | `POST /packaging-configs/save` (existing) | default_unit_price | restore_prior | no | owner |

Creating production and purchase orders from suggestions reuses `production_order_create` and `po_create` with prefill, at those actions' existing roles. The `sales` role is also allowed to view every list and report, and posting is unchanged: packaging runs are posted by production and removals by compliance.

## 5. Activity log event names (new)

`order_created`, `order_updated`, `order_confirmed`, `order_cancelled`, `order_closed`, `order_packaging_runs_created`, `order_shipment_created`, `order_status_changed` (system roll-up to in_fulfillment or shipped), `standing_order_created`, `standing_order_updated`, `standing_order_deactivated`, `order_created_from_standing`, `orders_import_previewed`, `orders_imported`, `orders_import_undone`, `orders_import_discarded`, `forecast_generated`, `forecast_set`. One `orders_imported` event per import, not per order.

## 6. Records MCP tools (new)

| Tool | Answers | Input | Returns | Backing |
|---|---|---|---|---|
| `orders_find` | O1: "what orders does Joe's have?", "what's due this week?" | `customer?`, `product?`, `status?`, `due_from?`, `due_to?`, `origin?` | Orders with lines, open units, value | `v_sales_order_lines` |
| `order_status` | O2: "where is SO-00042?" | `order_number` or `customer_reference` | Lines with shipped, in runs, open; linked runs and removals | `v_sales_order_lines`, links |
| `orders_history` | O3: "what did we sell to X last quarter?", "best-selling format?" | `customer?`, `product?`, `date_from?`, `date_to?`, `group_by` (customer, product, format, month) | Units and value | `v_sales_order_lines` |
| `standing_orders_find` | O4: "what are our standing orders?", "when does X order next?" | `customer?`, `active?` | Schedules, lines, next occurrences | `standing_orders`, `standing_order_occurrences` |
| `demand_projection` | O5: "what do we need to deliver in the next 4 weeks?" | `weeks?`, `types?` (firm, standing, forecast), `product?` | Units, volume and value by week and type | `v_demand` |
| `production_projection` | O6: "what do we need to brew and when?" | `weeks?`, `types?` | Suggested batches with pitch-by dates and driving demand | step 6 functions |
| `purchase_projection` | O7: "what do we need to order this week?" | `weeks?`, `types?` | Items short, quantity, order-by date, supplier | step 6 functions |

Value fields (prices, line totals, order values, approximate purchase cost) are left out unless the caller may see them: the app's assistant sends `X-Cidery-Show-Prices: 0` for users who are neither owner nor sales; client tokens, which only owners create, see them. The three projection tools run the PHP engine (`scripts/planning-json.php`) under the read-only records role, so screens and assistant agree. O8 ("enter an order by voice") is the actions server's `order_create`.

## 7. Open points for approval

1. **Order numbers:** `SO-00001`, `STO-0001` and `IMP-0001`, matching the existing numbering style.
2. **Destination on the order:** taken from the customer's default destination (tax-paid sale, taproom, in bond, export) and copied to the shipment.
3. **Forecast horizon:** `v_demand` looks 26 weeks ahead; the planning screens show 12 by default.
4. **Current week:** forecasts count the whole current week even when part of it has passed, and overdue firm demand is placed in the current week.
