# Customer orders progress

Plan: [11-customer-orders-plan.md](11-customer-orders-plan.md). Design: [12-customer-orders-design.md](12-customer-orders-design.md).

| Step | Work | Status | Notes |
|---|---|---|---|
| 0 | Commit prior work | Done 2026-10-02 | `2262a58` |
| 1 | Schema `016`, design | Done 2026-10-02 | Applied to `cidery_dev`; `5fab7df` |
| 2 | Orders screens | Done 2026-10-02 | See below |
| 3 | Packaging runs and shipping from orders | Done 2026-10-02 | See below |
| 4 | Spreadsheet import | Done 2026-10-02 | See below |
| 5 | Standing orders and forecasts | Done 2026-10-02 | See below |
| 6 | Projections | Done 2026-10-02 | See below |
| 7 | Order history report, dashboard tiles | Done 2026-10-02 | See below |
| 8 | Assistant tools and actions | Done 2026-10-02 | See below |
| 9 | Full test pass | Done 2026-10-02 | See below |

## Step 2: orders screens

- **Screens:** `/orders/` (open orders by default, "All statuses" shows every order; value column for owner and sales), `/orders/new` (`?customer=` prefills the customer and their destination), `/orders/{id}`, `/orders/{id}/edit` (draft and confirmed only).
- **Actions:** save (create/update with lines), confirm, cancel (needs a reason; refused once anything is shipped or in a packaging run), close (open lines become closed short). Events: `order_created`, `order_updated`, `order_confirmed`, `order_cancelled`, `order_closed`.
- **Lines** are saved in place by id, so lines that packaging runs or shipments point at keep their identity. Such a line cannot be removed, change format, or drop below what is shipped or in runs.
- **Line availability:** choosing a format sets its list price and shows released units on hand, units promised to other open orders, and the product's bulk volume.
- **History:** a new or draft order can be saved as "Already fulfilled outside the system": closed, counted as shipped, no stock or tax effect.
- **Prices:** `List price per unit` on the packaging configuration form (owner only, since that form needs the production role and only owner and sales see prices). Prices and values are hidden from other roles on every orders screen.
- **Role:** `sales` added to user roles; the Sales navigation group holds Customer orders.
- **Tabs:** Orders on the customer view (with New order) and the product view (`?tab=orders`).
- **Checked:** every action through HTTP as a sales user and as a viewer (403 on save and new), validation 422s, duplicate customer reference, conformance (`orders`, `packaging-configs`, `users`), 375px sweep of 10 screens with no problems.

## Step 3: packaging and shipping from orders

- **Package** (`/orders/{id}/package`, and `/orders/package?format=` for every open line of a format): one card per format with each line's open units, units in draft runs, units covered by stock and units to package. Stock on hand is promised in due-date order, then order number, across all open orders. Each card proposes units (the need), a batch and vessel (oldest released batch with a vessel holding enough; else the oldest that holds enough; else the oldest), the output location and the run date. **Create Packaging Runs** makes one draft run per format, linked to the order lines in due order. Units above the need go to stock. Backflushed materials are set from the bill of materials; ABV, CO2 and explicit material lots are entered on the run before posting, as before. When no batch is ready, the card says so and offers **Plan production** (a production order prefilled with the product and volume).
- **Packaging queue** (`/orders/to-package`, Sales menu): every format with open order lines: open, on hand, to package, and the lines in due order, with **Package** when something is needed.
- **Ship** (order view, sales or compliance): drafts one removal from the bonded location holding the most of the order's units, FEFO by packaging date. Keg lots ship only in kegs recorded as filled with the lot. It ships what is on hand; the rest stays open. Destination and reference come from the order (taproom transfers go to the premises' tax-paid taproom; in-bond needs the customer's permit). One draft shipment per order at a time. Compliance reviews and posts it on the removal screen, unchanged.
- **Links:** removal lines map to order lines by format (oldest open line first) every time the removal is saved; reversals copy the order and line links, so shipped units net out. The removal view shows its customer order.
- **Status roll-up** (`order_status_changed`, logged): shipped when every open line has shipped in full; in fulfillment once anything is shipped, in a packaging run or drafted for shipping; confirmed otherwise. Refreshed on package, ship, and on removal save, post, reverse and delete, and packaging run delete and reverse.
- **Checked:** draft runs created and linked (48 cans for a 46 need, 1 keg), vessel capacity refused with 422, queue and per-format page, ship (54 cans; refused while a draft exists), removal edit keeps links, deleting drafts returns the order to confirmed. Posting and reversing a shipment, and a full shipment, were tested inside a rolled-back transaction: 54/100 shipped after posting, 0 after reversal, `shipped` when complete. Conformance (`orders`, `removals`, `packaging-runs`) and the 375px sweep pass.
- **Noticed:** finished keg lots L-261001-017 and L-261001-018 have units on hand but no keg recorded as filled with them, so Ship cannot pick kegs for them.

## Step 4: spreadsheet import

- **Library:** `phpoffice/phpspreadsheet` 3.10.8 (Composer reported no advisories). CSV, XLSX and XLS, first sheet, up to 5 MB and 5,000 rows; Excel date cells are read as dates.
- **Screens:** `/orders/import` (upload, CSV template download, past imports; also Import on the orders list and Import orders in the Sales menu for owner and sales) and `/orders/import/{n}` (preview, columns, result).
- **Mapping:** columns are matched by header name (many common names: "Order #", "Ship Date", "Qty", "SKU", ...) or by the last import's mapping; the Columns card changes any of them and re-runs the preview.
- **Rows:** grouped into orders by customer and order reference (or, without a reference, customer and dates). Formats match by configuration name or finished item code, narrowed by a Product column. Dates in Y-m-d, m/d/Y, d-Mon-Y and "May 1, 2026" forms. A blank status means history when due before today, otherwise the chosen upcoming status; a Status column can say history/closed/shipped, confirmed/open, draft, or cancelled (skipped). An order whose customer reference already exists is skipped, so re-uploading a file imports nothing twice.
- **Commit:** one transaction and one `orders_imported` event; new customers are created (kind "other") when allowed; rows with errors block the import unless the user chooses to skip them, and are kept on the import with their reasons. **Undo** deletes the import's orders while none has packaging runs, shipments or a production plan; customers it created stay. **Discard** sets a preview aside.
- **Checked:** a CSV with history, upcoming, draft, new-customer, cancelled, duplicate and invalid rows (preview, refusal without skip, commit with skip, re-upload skips everything); an XLSX with date cells and unrecognised headers fixed through the Columns card; undo; viewer gets 403; conformance and the 375px sweep pass. Test imports were undone or discarded and the test customer deleted.

## Step 5: standing orders and forecasts

- **Standing orders** (`/orders/standing`, Sales menu): list (running by default; schedule, units each time, next date), form (customer, every week / every N weeks / every month on a day 1 to 28, start, optional end, lines with optional prices; a blank price uses the list price), view (lines, value per delivery, next 8 dates, orders made from it). **Create order** turns one date into a confirmed order (origin standing) due that day; each date converts once. **Pause/Resume**; paused or ended standing orders stop counting as demand. Events: `standing_order_created`, `standing_order_updated`, `standing_order_deactivated`, `order_created_from_standing`.
- **Forecast** (`/planning/forecast`, new Planning menu): per format and week (12 weeks), firm, standing, the forecast (run rate or manual) and the forecast counted after netting. **Generate from order history** sets each format's run rate (units ordered on confirmed, in-fulfillment, shipped and closed orders due in the last N weeks, divided by N) for the weeks ahead and keeps manual figures; **Set forecast** saves a manual figure for one week (blank clears it). Events: `forecast_generated`, `forecast_set`.
- **Checked:** validation (interval, end before start), weekly and monthly schedules and next dates, value per delivery with a list-price line, order from a date (and refusal for a repeat or a non-date), standing demand replaced by firm demand for that date, pause removes demand; run rate 6 kegs / 26 weeks = 0.23 a week, manual 100 against 48 firm counts 52, regeneration keeps manual rows, viewer 403 on changes; conformance and the 375px sweep pass.
- **Cleanup:** test standing orders STO-0001 and STO-0002 are paused, SO-00009 cancelled, and the test forecast rows deleted, so no test demand remains.

## Step 6: projections

- **Engine** (`app/features/planning/projection.php`, computed on request, nothing stored): 12 weekly buckets from this week, for one demand level (firm; firm and standing, the default; all with forecast).
  1. *Finished goods* by format: released units plus draft packaging runs (in their run week) minus demand gives units to package.
  2. *Bulk* by product: liters to package (units x fill / (1 - expected loss)) against active batches (volume less draft runs, ready when the recipe's remaining stage durations have passed, after the remaining stages' losses; carbonate and package stages are ready now) and production orders not yet started (at their planned package date, or pitch date plus the recipe's durations). Shortfalls become suggested batches, rounded up to the active recipe's batch size, with pitch-by = needed-by minus the recipe's pitch-to-ready days.
  3. *Materials* by item: packaging bills of materials for units to package and for draft runs, recipe lines for suggested batches and unstarted production orders (in their pitch week), against released stock and open purchase order lines (in their expected week). Shortfalls become suggested purchases: first week short, total over the horizon, preferred supplier (shortest lead time, then price), order-by = needed-by minus lead time, quantity in the supplier's purchase unit. Juice shortfalls also show the fruit equivalent at the press-history yield.
- **Driven by:** each suggestion is labelled with its first reason: planned production (needed even with no customer demand), firm, standing or forecast.
- **Screens** (Planning menu): Projections (`/planning/`: batches to start, items to buy, data notes, week-by-week demand by type with value, units to package per format, bulk short per product), Suggested production (`/planning/production`, with **Create production order** prefilled with product, volume and pitch date, and the bulk counted as supply), Suggested purchases (`/planning/purchasing`, with **Create purchase order** prefilled with item, supplier, quantity and expected date; the purchase order form now accepts `?qty=`). A demand switch on each.
- **Data notes** list what weakens the numbers: batches without a recipe to time them, stages without durations, production orders past their pitch date without a batch, items without a supplier or lead time.
- **Checked:** a rolled-back scenario (2,400 cans and 30 kegs due in three weeks, a weekly standing order, a manual keg forecast): 2,346 cans and 27 kegs to package, one batch suggested and flagged late, juice short converted to 1,751 gal, standing and forecast levels adding their weeks; the screens with live data; prefills; conformance and the 375px sweep.

## Step 7: order history report and dashboard tiles

- **Order history** (`/reports/orders`, Reports menu): orders due in a period (default the last 12 months to 3 months ahead) by customer, product, format or month, optionally for one customer: orders, units ordered, units shipped, share of units and, for owner and sales, value (flagging groups with unpriced lines). Counts confirmed, in-fulfillment, shipped and closed orders, history included. Sortable; **Export CSV** (`/reports/orders/csv`, logged as `report_exported`; the value column only for owner and sales).
- **Dashboard:** four more tiles, each linking to its screen: orders due this week (with overdue), orders at risk (due in 14 days with units still to package after stock and draft runs), batches to start (pitch by the end of next week, late ones noted) and items to order (order by the end of next week, late and no-lead-time ones noted), the last two from the firm-and-standing projection. The dashboard renders in about 0.19 s.
- **Checked:** report by customer, month and format with totals and CSV; dashboard figures against the data; conformance and the 375px sweep.

## Step 8: assistant

- **Records server** (`records_mcp/tools_orders.py`, 65 tools now): `orders_find`, `order_status`, `orders_history`, `standing_orders_find`, `demand_projection`, `production_projection`, `purchase_projection` (questions O1 to O7 in docs/12; results in `records_mcp/EVAL.md`). The projection tools run `scripts/planning-json.php` under the read-only records role, so the screens and the assistant use one engine. Price and value fields are dropped when the request carries `X-Cidery-Show-Prices: 0`, which the assistant sends for users who are neither owner nor sales (`common/auth.py`, `assistant/agent.py`, `assistant/app.py`).
- **Actions server** (`actions_mcp/actions_orders.py`): `order_create` (saves and confirms; undo cancels), `order_add_line` (confirms first), `order_confirm`, `order_cancel` and `order_close` (confirm first), `order_package` (the Package screen's suggestions, capped to what the suggested tank holds, skipped formats named; undo deletes the drafts through the new `POST /orders/package-undo`), `order_ship` (undo deletes the draft shipment; sales may now delete a draft removal tied to an order), `order_from_standing` (undo cancels), `standing_order_deactivate` (pause or resume; undo resumes). Imports and forecasts stay on their screens.
- **Undo:** "undo" now skips an action whose effect is already gone (for example the `removal_created` row beside a shipment another undo deleted) and goes on to the one before.
- **Manifest:** docs/05 gained the 16 customer order and planning screens, the actions, the colors and the events; `config/manifest.json` rebuilt (158 screens, 154 navigable; the three flags are older: login-2fa, rack-edit, recipe-edit). Navigation maps `/orders/standing/{id}` and `/orders/import/{id}` to their own records.
- **Assistant prompt:** knows customer orders and planning, the sales role, and that only owner and sales see prices.
- **Package defaults:** when no ready tank holds a format's need, the suggestion now falls back to the batch with the fullest tank (screen and voice).
- **Checked:** every new records tool over MCP; price stripping; every action over MCP as the sales user (create, add line with confirmation, package, ship, undo chain, standing order date, pause and resume, viewer refused); two live assistant turns and a voice undo; a production user's value question answered without values. Test orders SO-00010, SO-00011, SO-00012 and SO-00013 were cancelled and their drafts deleted; STO-0001 is paused again.

## Step 9: full test pass

- **Conformance:** `scripts/conformance.sh` passes on all 44 feature directories (auth excluded as before: its pages run before sign-in).
- **375px sweep:** 71 screens (every navigation item and the order, standing order, import, planning, customer and product detail screens): no horizontal scroll, no console errors, no failed loads. (A deleted test removal returned 404, as it should.)
- **Records suite:** 92 of 92 calls behaved as expected, the seven new tools included (`test_client --suite`).
- **End to end, order to production:** a confirmed order for 120 half barrels due in 8 weeks showed 117 kegs to package; the projection suggested 2 batches (3,785 L) to pitch by Oct 10; creating that production order through the production order form removed the suggestion and moved the juice need to the production order. Cleaned up (order and production order cancelled).
- **End to end, history to forecast:** a CSV of 12 weeks of past orders imported as history; generating the forecast gave 3 kegs and 96 cans a week; the all-demand projection showed 42 cans to package this week then 96 a week, and cans and ends to buy driven by the forecast. Cleaned up (import undone, forecast regenerated empty).
- Earlier steps covered order, package, ship, edit, delete and (in a rolled-back transaction) post, reverse and full shipment.
- **PHP error log:** no warnings or fatals from this work.

## After the build

- **New customer from the order form (2026-10-02):** the customer field of the order and standing order forms has a **New customer** button that opens an inline panel (name, kind, usual destination, contact, email, phone, TTB permit). **Add customer** saves it on its own through `POST /orders/customer-quick` (sales or compliance; same rules as the customer form, plus a check for an existing customer with the same name), logs `customer_created`, and returns the field with the new customer selected and, on orders, their usual destination. Checked over HTTP (blank name, duplicate, in-bond without permit, success, viewer 403) and in a browser at 375px.

- **New supplier from the purchase order form (2026-10-02):** the same pattern on `/purchase-orders/new` and edit: **New supplier** opens an inline panel (name, kind, contact, email, phone); **Add supplier** saves through `POST /purchase-orders/supplier-quick` (receiving, the supplier form's role; refuses a name that already exists), logs `supplier_created`, and returns the field with the new supplier selected. Checked over HTTP and in a browser at 375px; the test suppliers were removed afterwards (there is no supplier delete in the app, so by SQL).

- **Delete customers and suppliers with no history (2026-10-02):** the customer and supplier views show **Delete** when nothing refers to the record (customers: orders, standing orders, removals, keg records; suppliers: purchase orders, receipts, lots; a supplier's item list is setup and goes with it), and **Deactivate** otherwise, naming the history in the confirmation. The customer delete check now includes orders and standing orders (before, deleting a customer with only orders failed on the foreign key), and sales may delete customers as well as compliance; suppliers delete through the new `POST /suppliers/{id}/delete` (receiving). Shared helper `history_summary()` in `app/ui.php`.

## Not built, or waiting on data

- **Packaging plan on production orders:** the `app.production_order_packages` table exists (an optional split of a production order across formats, linked to order lines) but has no screen yet, so the projections treat planned production as bulk and the older `packaging_material_needs` tool still shows one scenario per format.
- **Planning data** (the data notes on the planning screens list them): supplier lead times (none set, so order-by dates are unknown), suppliers for yeast, nutrient, cans and can ends, durations for 5 of 7 stages of the active recipe (pitch-by dates come out late, batch ready dates early), full bills of materials for both formats, real list prices (the $1.85 and $165 are placeholders), keg fills for lots L-261001-017 and L-261001-018, batch B-26-004 has no recipe, and WO-00006 was due to pitch on Oct 1 with no batch.
- **Assistant evals:** the new tools were checked over MCP and in live turns; `assistant.run_eval` was not re-run.

**Test data left in the dev database:** user 10 "Sales Test" (role sales, no password, cannot sign in; used with action tokens), orders SO-00001 (closed), SO-00002 (history), SO-00003, SO-00004, SO-00009 to SO-00013 (cancelled), standing orders STO-0001 and STO-0002 (paused), and list prices $1.85 per can and $165 per half barrel on the two Hill Dry formats.
