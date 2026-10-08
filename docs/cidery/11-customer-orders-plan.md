# Customer orders and projections: plan

**Status:** owner answers received 2026-10-02 (section 10); ready for step 0. Builds on the Phase 3 slices (packaging, removals, production orders, purchasing) and Phase 4 (assistant). Follows the `new-app` build order: schema and design first, then screens, then the assistant.

## 1. Goal

Track upcoming and past customer orders, and use them to project:

- what to **package** (from bulk cider, as orders come in),
- what to **produce** (new batches, and when to pitch them),
- what to **purchase** (fruit, juice, concentrate, yeast, additives, packaging), and by when.

Placing an order can create the packaging runs that fill it.

## 2. How it fits the current model

```
demand: firm order lines + standing-order occurrences + forecast (each kept as its own type)
   │  net against finished stock on hand (released finished lots)
   ▼
packaging need ──► packaging run (draft, created from the order) ──► finished lot
   │  net against bulk cider (active batches at a packageable stage)
   ▼
production need ──► production order (pitch date = due date − recipe stage durations)
   │  recipe lines × volume + packaging BOM × units
   ▼
material need ──► net against released stock + open purchase orders ──► suggested purchase (order-by = need date − supplier lead time)
   ▼
shipping the order = a removal linked to the order lines (tax and TTB unchanged)
```

Nothing in the ledger, tax or TTB logic changes. Orders are planning documents. Packaging runs, removals and production orders still post through their existing screens and rules, including the batch release gate.

## 3. Schema (`db/016_customer_orders.sql`)

| Table / change | Purpose |
|---|---|
| `app.sales_orders` | number (`SO-…` via `next_number`), customer, premises, status (`draft`, `confirmed`, `in_fulfillment`, `shipped`, `closed`, `cancelled`), origin (`entered`, `imported`, `standing`), ordered_on, requested_on (due date), customer reference (their PO), `fulfilled_outside` flag for history, standing order that generated it, import batch, notes, created/confirmed/closed by and at |
| `app.sales_order_lines` | line_no, packaging configuration (product and format, for example "Dry 16 oz can case"), units ordered, units shipped (rolled up from removals), unit price, line total, line status, notes |
| `packaging_configurations.default_unit_price` | the list price per unit for a format, prefilled on order lines and overridable per line |
| `app.standing_orders`, `app.standing_order_lines` | recurring demand: customer, lines (format, units, price), frequency (weekly, every N weeks, monthly), day, start and end dates, active. Projects future occurrences; each occurrence can be turned into a firm order with one click |
| `app.demand_forecasts` | forecast demand per format per week: method (`run_rate` from order history over a trailing window, or `manual`), units, the history window used, created by and at |
| `app.order_imports` | spreadsheet imports: file (in attachments), column mapping, row counts (imported, skipped, failed), per-row errors as JSON, imported by and at |
| `app.packaging_run_order_lines` | links a packaging run to the order lines it was created for (units per line). One run can serve several orders of the same format; one line can take several runs |
| `removals.sales_order_id`, `removal_lines.sales_order_line_id` | shipping fulfills the order; units shipped roll up from posted removals and are undone by reversals |
| `app.production_order_packages` (optional) | an optional split of a production order's volume across formats, linked to order lines when the order created it. Blank means bulk, decide later |
| users `role` check | adds `sales` |

**Demand types**, always kept apart in projections:

| Type | Source | Counted |
|---|---|---|
| Firm | confirmed and in-fulfillment order lines (open units) | always |
| Standing | future occurrences of active standing orders not yet turned into firm orders | when "firm + standing" or "all" is selected |
| Forecast | run rate from order history (or a manual figure), minus firm and standing demand already in that week, never below zero | when "all" is selected |

Draft orders are not demand until confirmed. Forecasts never double count: a week's forecast only covers what firm and standing orders do not.

## 4. Roles

| Action | Roles |
|---|---|
| View orders, standing orders, projections | every role (viewer is read only) |
| Create, edit, confirm and cancel orders; standing orders; imports | owner, sales |
| Create draft packaging runs from an order | owner, sales, production |
| Post a packaging run | owner, production (unchanged) |
| Ship: create a draft removal from an order | owner, sales, compliance |
| Post a removal | owner, compliance (unchanged) |
| Create production and purchase orders from suggestions | owner, production (production orders); owner, receiving (purchase orders), as today |
| Prices on orders and order value in reports | owner, sales (other roles see quantities only) |

## 5. Screens

| Screen | URL | Notes |
|---|---|---|
| Orders list | `/orders/` | Filters: status, customer, due window, product, origin. Default: open orders by due date. Order value column for owner and sales |
| New / edit order | `/orders/new`, `/orders/{id}/edit` | Customer, dates, reference, lines (format, units, price). Each line shows on hand, in bulk and short, live; the order shows its total |
| Order view | `/orders/{id}` | Header, lines with fulfillment status, linked packaging runs, linked removals, actions: Confirm, Create packaging runs, Ship, Close, Cancel |
| Create packaging runs | `/orders/{id}/package` | See section 6 |
| Ship order | button on the order | Opens a new draft removal prefilled with the customer, destination and lines (lots chosen FEFO, kegs chosen as today) |
| Packaging queue | `/orders/to-package` | Open order lines not covered by finished stock, grouped by format and due date; package several orders in one run |
| Standing orders | `/orders/standing/`, `/orders/standing/{id}` | List, form, view with the next occurrences; "Create order for {date}" turns an occurrence into a firm order |
| Import orders | `/orders/import` | Upload, map columns, preview, import (section 7) |
| Forecast | `/planning/forecast` | Run rate per format by week from order history (trailing window chosen by the user, default 12 weeks), manual overrides |
| Projections | `/planning/` | Weekly buckets for the next 12 weeks: demand by type, packaging, production and purchasing. A demand selector (firm, firm + standing, all) changes every figure; each row drills to its sources |
| Suggested production | `/planning/production` | Batches to start, with pitch-by dates, marked by the demand type that drives them; "Create production order" prefills the existing form |
| Suggested purchases | `/planning/purchasing` | Items short, quantity, order-by date, preferred supplier, marked by demand type; "Create purchase order" prefills the existing form (it already takes `?item=`) |
| Order history | report at `/reports/orders` | Past orders by customer, product and month: units and value, with CSV |

Also: an Orders tab on the customer and product views, and dashboard tiles for orders due this week, orders at risk and items to order this week.

## 6. Creating packaging runs from an order

On a confirmed order, **Create packaging runs** proposes one draft run per format:

1. **Units:** the line's open units, minus released finished stock not already promised to earlier-due orders. The user can round up to full cases or add units for stock.
2. **Batch:** the oldest released batch of that product at a packageable stage with enough volume, with a choice when there are several. Volume in = units × fill ÷ (1 − the format's expected loss).
3. **The run is created as a draft** and linked to the order lines. Posting still happens on the packaging run screen, with ABV, CO2, materials and the release gate as today.
4. **No bulk available:** the screen says so and offers **Create production order** instead, prefilled with the product, the volume needed and a pitch-by date, with its packaging plan linked to the order.

Several orders for the same format can share one run, from the packaging queue.

## 7. Importing prior orders from spreadsheets

- **Formats:** CSV and Excel (`.xlsx`). Excel needs one new Composer dependency, `phpoffice/phpspreadsheet`.
- **Template:** a downloadable template with one row per order line: order reference, customer, ordered on, due on, product or format, units, unit price, status (optional), notes. Rows sharing an order reference become one order.
- **Mapping:** the user maps their columns to these fields; the mapping is remembered for the next import.
- **Matching:** customers match by name (case-insensitive); unknown customers are listed in the preview and can be created in the same import. Formats match by configuration name or finished item code; unmatched rows must be mapped or skipped.
- **Preview:** every row is validated before anything is written: errors shown per row, nothing imported until the user confirms.
- **Result:** past-due rows import as `closed` with `fulfilled_outside` set (history for forecasts and reports, with no stock or tax effect); future rows import as `confirmed`, or `draft` when the user chooses. One import is one transaction and one activity event, and can be undone (deleting the orders it created) while none of them has been fulfilled.
- Orders entered one at a time can also be backdated and marked "fulfilled outside the system".

## 8. Projection rules

- **Demand:** by type, as in section 3. Promising follows due date, then order number, firm before standing before forecast. Finished stock is promised softly, with no hard reservation in version 1.
- **Bulk ready date:** active batches count as available on the expected date of their packageable stage (stage start plus the recipe's stage durations). Planned production orders count on their planned package date.
- **Production lead time:** the sum of the active recipe's `expected_duration_days` from pitch to package.
- **Batch size:** suggested runs round up to the recipe's target batch volume, checked against vessel capacity.
- **Materials:** recipe lines scale with volume (fixed lines per batch). Packaging BOM × units. Juice converts to fruit using the juice yield from press history. Net against released stock, then open purchase order lines by expected date.
- **Fruit, juice and concentrate** are ordinary purchasable items with no seasonal window: projected like any other material, by lead time.
- **Order-by date:** need date minus the supplier item's `lead_time_days`.
- **Value:** projections show the value of firm, standing and forecast demand for owner and sales.

## 9. Assistant (Phase 4 surfaces)

- **Records tools:** `orders_find`, `order_status`, `standing_orders_find`, `demand_projection` (by type), `production_projection`, `purchase_projection`, and order history by customer and product (units and value).
- **Actions:** create an order by voice ("Joe's Taproom wants 4 half barrels of Hill Dry on the 15th"), add a line, confirm, create packaging runs, ship, cancel, turn a standing occurrence into an order, all with undo or confirmation as today. Imports stay on the screen (file upload).
- New manifest entries and screens; eval questions added to `EVAL.md`.

## 10. Owner decisions (2026-10-02)

1. **Past orders:** entered one at a time or imported from spreadsheets (section 7).
2. **Who places orders:** owner and a new `sales` role (section 4).
3. **Demand:** firm, standing and forecast, each kept as its own type (section 3).
4. **Prices:** quantities and prices, for order value; no invoicing.
5. **Fruit:** fruit, juice and concentrate can be bought at any time, outside the harvest; no seasonal handling.

## 11. Build order

| Step | Work |
|---|---|
| 0 | Commit the current uncommitted work (racks, user enable and resend, view changes) |
| 1 | Schema `016`, `sales` role, grants, activity events, manifest entries, tool surface. **Owner checkpoint** |
| 2 | Orders slice: list, form, view, confirm, cancel, close, prices, customer and product tabs |
| 3 | Fulfillment: create packaging runs from orders, packaging queue, ship to removal, status roll-up, reversal handling |
| 4 | Import: template, upload, mapping, preview, import, undo |
| 5 | Standing orders and forecasts |
| 6 | Projections: the planning engine as SQL views and functions, plus the planning screens |
| 7 | Order history report, dashboard tiles |
| 8 | Assistant tools and actions, evals |
| 9 | Conformance script, 375px sweep, end-to-end tests: order → package → ship → reverse; order with no bulk → production order → purchase suggestion; import a spreadsheet of past orders → forecast → projection |

## 12. Data the projections need (current state)

| Data | Now | Needed |
|---|---|---|
| Supplier lead times | 0 of 3 supplier items | Every purchased item |
| Recipe stage durations | 2 of 7 stages on the active recipe | Every stage from pitch to package |
| Packaging bills of materials | 2 lines across both formats | Full bill per format (cans, lids, carriers, cases, labels; keg caps, collars) |
| Format prices | none (new field) | A default price per format |
| Juice yield | From press history | At least one press run per variety, or a default yield |
| Order history | none | A spreadsheet of past orders, for forecasts |
