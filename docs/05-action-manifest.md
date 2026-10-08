# Action manifest (Phase 1)

**Date:** 2026-10-01
**Status:** Phase 1 deliverable for approval, alongside the schema in `db/` and [04-mcp-tool-surface.md](04-mcp-tool-surface.md).
**Contract:** every screen the application has is in the screen registry; every state change a person can make is in the action registry. The actions MCP server (`processcore_actions_mcp`, localhost only, per the chat-actions skill) generates its `navigate` description and its action tools from this file at startup. A screen or action missing here is unreachable by voice, which counts as unfinished design.

## URL conventions

Pretty URLs map onto the php-patterns file set through one rewrite rule set in `html/.htaccess` (Phase 2):

| Canonical URL | File | Notes |
|---|---|---|
| `/{feature}/` | `html/{feature}/index.php` | List (Pattern B: full page or partial) |
| `/{feature}/new` | `html/{feature}/form.php` | Empty form |
| `/{feature}/{id}` | `html/{feature}/view.php?id=` | Detail |
| `/{feature}/{id}/edit` | `html/{feature}/form.php?id=` | Pre-filled form |
| `/{feature}/{id}/{verb}` | `html/{feature}/{verb}.php?id=` | State change, POST only |
| `/{parent}/{id}/{child}/...` | `html/{child}/...?{parent}_id=` | Nested resources (receipt lines, recipe versions) |

Screen ids are `{feature}-{kind}` (`lots-list`, `lot-view`, `lot-edit`). Element ids follow the design-decisions scheme (`lots-list-table`, `lot-form-field-expires-on`, `lot-row-42`). Every partial stamps `#page-content` with `data-screen`, `data-entity`, `data-record-id` so the command bar can resolve "that".

## Screen registry

Prefill parameters (for `navigate(screen, params)`) are listed where a create form accepts them.

### Shell and cross-cutting (Phase 2)

| Screen id | URL | Title | When the user wants to… |
|---|---|---|---|
| `dashboard` | `/` | Dashboard | see the overview: what is in tanks, what is arriving, what needs release |
| `ama` | `/ama/` | Ask me anything | ask a question in full conversation form |
| `login` | `/login` | Sign in | sign in (full page, never swapped) |
| `login-2fa` | `/login/2fa` | Two-factor code | enter the authenticator code |
| `password-reset` | `/password/reset` | Reset password | reset a forgotten password |
| `settings-profile` | `/settings/profile` | My profile | change their name or password |
| `settings-2fa` | `/settings/2fa` | Two-factor authentication | enrol or disable an authenticator app |
| `settings-client` | `/settings/client` | Organization settings | change the organization name, display units, time zone |
| `settings-mcp-tokens` | `/settings/mcp-tokens` | AI access tokens | connect their own AI tools: see the MCP URLs, create or revoke a token |
| `activity-list` | `/activity/` | Activity | browse the activity log (read only; the activity server answers the questions) |

### Slice 1: foundation

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `premises-list` | `/premises/` | Premises | see or manage TTB premises |  |
| `premises-add` / `premises-edit` | `/premises/new`, `/premises/{id}/edit` | Premises | add or change a premises (permit kind, registry number, filing frequency) | `name`, `kind` |
| `locations-list` | `/locations/` | Locations | see where stock can be kept |  |
| `location-add` / `location-edit` | `/locations/new`, `/locations/{id}/edit` | Location | add or change a storage location and its tax state | `name`, `kind` |
| `vessels-list` | `/vessels/` | Vessels | see tanks, totes and barrels and their status |  |
| `vessel-add` / `vessel-edit` | `/vessels/new`, `/vessels/{id}/edit` | Vessel | add or change a vessel | `name`, `kind`, `capacity_gal` |
| `items-list` | `/items/` | Items | browse everything that can be stocked |  |
| `item-add` / `item-edit` | `/items/new`, `/items/{id}/edit` | Item | add or change an item (class, unit, lot control, quarantine default, reorder point); `kind=material` adds a material from Inventory, Materials | `name`, `item_class`, `kind` |
| `item-view` | `/items/{id}` | Item | see an item's stock, lots, alternate units, suppliers |  |
| `item-classes-list` | `/item-classes/` | Item classes | see or manage the item classes (material types): material or finished product, purchasable, recipe ingredient | `kind` |
| `item-class-add` / `item-class-edit` | `/item-classes/new`, `/item-classes/{id}/edit` | Item class | add a material type or change a class's name, flags or order | `kind` |
| `units-list` | `/units/` | Units | see the unit conversions (read only) |  |
| `suppliers-list` | `/suppliers/` | Vendors | see vendors (suppliers) and orchards, under Purchasing |  |
| `supplier-add` / `supplier-edit` | `/suppliers/new`, `/suppliers/{id}/edit` | Supplier | add or change a supplier | `name`, `kind` |
| `supplier-view` | `/suppliers/{id}` | Supplier | see a supplier's items, prices, orders and performance |  |
| `users-list` | `/users/` | Users | see who can sign in (owner only) |  |
| `user-add` / `user-edit` | `/users/new`, `/users/{id}/edit` | User | invite a user or change a role | `email`, `role` |
| `reason-codes-list` | `/reason-codes/` | Reason codes | see or manage reason codes and their TTB categories |  |
| `reason-code-add` / `reason-code-edit` | `/reason-codes/new`, `/reason-codes/{id}/edit` | Reason code | add or change a reason code |  |

### Slice 2: receiving (exemplar)

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `purchase-orders-list` | `/purchase-orders/` | Purchase orders | see open, overdue, or past purchase orders, under Purchasing |  |
| `purchase-order-add` / `purchase-order-edit` | `/purchase-orders/new`, `/purchase-orders/{id}/edit` | Purchase order | create or change an order with its lines | `supplier`, `expected_on`, `item`, `qty` |
| `purchase-order-view` | `/purchase-orders/{id}` | Purchase order | see an order, its lines, what has been received against it |  |
| `receipts-list` | `/receipts/` | Receipts | see deliveries received or in progress |  |
| `receipt-add` / `receipt-edit` | `/receipts/new`, `/receipts/{id}/edit` | Receipt | record a delivery: lines, quantities, lot numbers, weigh tags, discrepancies | `supplier`, `po_number` |
| `receipt-view` | `/receipts/{id}` | Receipt | see a posted receipt and the lots it created |  |
| `receipts-projected` | `/receipts/projected` | Projected | see a calendar of when shipments are expected, from the expected dates on open purchase orders |  |
| `lots-list` | `/lots/` | Lots | find lots by item, status, expiry |  |
| `lot-view` | `/lots/{id}` | Lot | see a lot: balances by location, attributes, CoA values, release history |  |
| `lot-edit` | `/lots/{id}/edit` | Lot | change a lot's expiry, supplier lot number, attributes |  |
| `lot-coa-add` | `/lots/{id}/coa/new` | Certificate of analysis | attach a CoA and enter its values |  |
| `lot-release` | `/lots/{id}/release` | Release lot | release, hold, or reject a lot with a basis |  |
| `putaway` | `/receipts/{id}/putaway` | Putaway | move a receipt's lots from the dock to storage |  |

### Slice 3: inventory

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `inventory-materials` | `/inventory/materials` | Materials | see what materials are on hand (fruit, juice, yeast, additives, packaging, intermediates) by item, lot, location, with available and allocated |  |
| `inventory-finished` | `/inventory/finished` | Finished product | see what finished product is on hand by item, lot, location, with available and allocated |  |
| `inventory-movements` | `/inventory/movements` | Movements | see the ledger history for an item, lot, or location | `item`, `lot_number`, `location` |
| `reorder-list` | `/inventory/reorder` | Reorder | see what is below reorder point and on order |  |
| `rack-board` | `/racks/` | Rack board | see which product, lot and batch is on each numbered rack; find where a product is stored |  |
| `rack-fifo` | `/racks/fifo` | FIFO pick order | see which lot to pick or use next, oldest first, and the rack it is on |  |
| `tank-view` | `/tanks/` | Tank view | see the tanks as they stand on the floor and how much each holds (juice, fermenting, base cider, finished); arrange them by dragging |  |
| `rack-add` / `rack-edit` | `/racks/new`, `/racks/{id}/edit` | Rack | add or change a numbered rack in a storage area | `rack_number` |
| `transfers-list` | `/transfers/` | Transfers | see stock transfers between locations |  |
| `transfer-add` | `/transfers/new` | Transfer | move stock between locations | `from_location`, `to_location`, `item`, `lot_number`, `qty` |
| `transfer-view` | `/transfers/{id}` | Transfer | see a transfer |  |
| `adjustments-list` | `/adjustments/` | Adjustments | see inventory adjustments and their reasons |  |
| `adjustment-add` | `/adjustments/new` | Adjustment | correct stock with a reason | `location`, `item`, `lot_number`, `qty_delta`, `reason` |
| `adjustment-view` | `/adjustments/{id}` | Adjustment | see or approve an adjustment |  |
| `counts-list` | `/counts/` | Counts | see cycle and physical counts |  |
| `count-add` | `/counts/new` | Count | start a count of a location | `location`, `kind` |
| `count-view` | `/counts/{id}` | Count | enter counted quantities, review variances, approve |  |

### Slice 4: products and recipes

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `products-list` | `/products/` | Products | see the ciders made |  |
| `product-add` / `product-edit` | `/products/new`, `/products/{id}/edit` | Product | add or change a product (style, target ABV, fruit share, intended tax class) | `name`, `style` |
| `product-view` | `/products/{id}` | Product | see a product: recipe versions, packaging, specs, approvals, batches |  |
| `recipe-add` / `recipe-edit` | `/products/{id}/recipes/new`, `/recipes/{id}/edit` | Recipe version | create or edit a draft recipe: stages, expected losses, lines | `batch_volume_gal` |
| `recipe-view` | `/recipes/{id}` | Recipe version | see a version, scale it, compare with another, activate it |  |
| `packaging-configs-list` | `/packaging-configs/` | Packaging configurations | see how products are packaged |  |
| `packaging-config-add` / `packaging-config-edit` | `/packaging-configs/new`, `/packaging-configs/{id}/edit` | Packaging configuration | define a package: finished item, fill volume, bill of materials, expected loss | `product`, `package_kind` |
| `specs-list` | `/products/{id}/specs` | Specs | see or edit acceptable ranges per stage for a product |  |
| `spec-add` / `spec-edit` | `/products/{id}/specs/new`, `/specs/{id}/edit` | Spec | add or change a spec | `stage`, `measurement` |
| `standard-costs-list` | `/standard-costs/` | Standard costs | see and set standard costs and the overhead rate |  |
| `standard-cost-add` | `/standard-costs/new` | Standard cost | set a standard cost for an item | `item`, `cost` |
| `approvals-list` | `/approvals/` | Approvals | see formula and label approvals and what is missing |  |
| `approval-add` / `approval-edit` | `/approvals/new`, `/approvals/{id}/edit` | Approval | record a formula or label approval | `product`, `kind` |

### Slice 5: production orders

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `production-orders-list` | `/production-orders/` | Production orders | see planned, released, and in-progress orders |  |
| `production-order-add` / `production-order-edit` | `/production-orders/new`, `/production-orders/{id}/edit` | Production order | plan a batch: product, recipe, volume, dates, the equipment plan (vessels and equipment with their days) | `product`, `volume_gal`, `pitch_on` |
| `production-order-view` | `/production-orders/{id}` | Production order | see an order as a run: its equipment plan with clashes, inputs (the material check, consumed so far), processing time (recipe stages planned vs actual), outputs (planned packages, batches, packaging runs, finished lots), allocations; release or close it |  |
| `production-calendar` | `/production-orders/calendar` | Vessel calendar | (2026-10-08: redirects to the Equipment schedule, `/schedule/?kind=vessel`) |  |

### Slice 6: batch execution

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `press-runs-list` | `/press-runs/` | Press runs | see pressing history and yields |  |
| `press-run-add` / `press-run-edit` | `/press-runs/new`, `/press-runs/{id}/edit` | Press run | record a press: fruit lots in, juice lots out, pomace, vessel | `press` |
| `press-run-view` | `/press-runs/{id}` | Press run | see a press run, its yield, post it |  |
| `tank-board` | `/tank-board/` | Tank board | see what is in every vessel right now |  |
| `batches-list` | `/batches/` | Batches | see active and past batches |  |
| `batch-add` | `/batches/new` | Pitch a batch | start a batch by pitching yeast into juice | `product`, `vessel`, `production_order` |
| `batch-view` | `/batches/{id}` | Batch | see a batch: stage, vessel, readings curve, consumptions, losses, lineage, cost |  |
| `batch-edit` | `/batches/{id}/edit` | Batch | change a batch's notes or tax class override |  |
| `batch-reading-add` | `/batches/{id}/readings/new` | Reading | record a reading (Brix, SG, pH, SO2, temperature, ABV, CO2) | `measurement`, `value` |
| `batch-addition-add` | `/batches/{id}/additions/new` | Addition | add an ingredient (nutrient, sulfite, enzyme, sweetener, acid) by lot | `item`, `qty`, `purpose` |
| `batch-stage-move` | `/batches/{id}/stage` | Move stage | move the batch to the next stage with volume out | `stage` |
| `batch-transfer` | `/batches/{id}/transfer` | Transfer | move the batch to another vessel | `to_vessel`, `volume_gal`, `loss_gal` |
| `batch-split` | `/batches/{id}/split` | Split | split the batch into several vessels |  |
| `batch-blend-add` | `/batches/blend` | Blend | blend batches into a new one | `vessel` |
| `batch-loss-add` | `/batches/{id}/losses/new` | Loss | record a loss with a reason | `qty_gal`, `reason` |
| `batch-dump` | `/batches/{id}/dump` | Dump batch | dump a batch (destructive, confirms) |  |
| `yeast-harvest-add` | `/batches/{id}/yeast/new` | Harvest yeast | harvest yeast from the batch into a new lot | `volume_l`, `generation` |
| `pomace-disposition-add` | `/dispositions/new` | Pomace disposition | record where pomace went | `lot_number`, `destination` |

### Slice 7: packaging

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `packaging-runs-list` | `/packaging-runs/` | Packaging runs | see packaging history |  |
| `packaging-run-add` / `packaging-run-edit` | `/packaging-runs/new`, `/packaging-runs/{id}/edit` | Packaging run | package a batch: configuration, volume in, units out, CO2, materials | `batch`, `package` |
| `packaging-run-view` | `/packaging-runs/{id}` | Packaging run | see a run, its loss, finished lots, tax class; post it |  |
| `finished-lots-list` | `/finished-lots/` | Finished goods | see what is packaged and ready, by product, package, location |  |
| `finished-lot-view` | `/finished-lots/{id}` | Finished lot | see a finished lot: batch, tax class check, removals, kegs |  |
| `kegs-list` | `/kegs/` | Kegs | see the keg fleet by state and holder |  |
| `keg-add` / `keg-edit` | `/kegs/new`, `/kegs/{id}/edit` | Keg | register or change a keg | `serial`, `size` |
| `keg-view` | `/kegs/{id}` | Keg | see a keg's history; fill, return, clean, mark lost |  |
| `keg-return` | `/kegs/return` | Keg returns | scan or type returned keg serials | `serials` |

### Slice 8: quality

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `lab-list` | `/lab/` | Lab | see recent readings and out-of-spec results |  |
| `lab-reading-add` | `/lab/new` | Lab reading | record a lab test on a batch or lot | `batch`, `measurement`, `value` |
| `sensory-list` | `/sensory/` | Sensory | see panel records |  |
| `sensory-add` | `/sensory/new` | Sensory record | record a panel verdict | `batch` |
| `release-queue` | `/releases/` | Release queue | see what is awaiting release |  |
| `batch-release` | `/batches/{id}/release` | Release batch | release a batch for packaging with the readings it was based on, or override with a reason |  |

### Slice 9: reports

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `report-yields` | `/reports/yields` | Yield report | see per-stage yield and loss by batch or product | `product` |
| `report-juice-yield` | `/reports/juice-yield` | Juice yield | see gallons per ton and per bushel by variety | `season_year` |
| `report-batch-costs` | `/reports/batch-costs` | Batch costs | see cost per batch, per liter, per keg and case, variance | `product` |
| `report-valuation` | `/reports/valuation` | Inventory valuation | see inventory value by class and tax state | `as_of` |

### Slice 10: removals and compliance

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `customers-list` | `/customers/` | Customers | see removal destinations |  |
| `customer-add` / `customer-edit` | `/customers/new`, `/customers/{id}/edit` | Customer | add or change a customer | `name`, `kind` |
| `customer-view` | `/customers/{id}` | Customer | see a customer's removals and kegs out |  |
| `removals-list` | `/removals/` | Removals | see finished goods that left, by destination |  |
| `removal-add` / `removal-edit` | `/removals/new`, `/removals/{id}/edit` | Removal | record finished goods leaving: destination, lots, units, kegs | `customer`, `destination_kind` |
| `removal-view` | `/removals/{id}` | Removal | see a removal and its tax determination; post or reverse it |  |
| `return-add` | `/removals/new?direction=in` | Return | record goods coming back from a customer | `customer` |
| `ttb-reports-list` | `/ttb-reports/` | TTB reports | see generated period reports |  |
| `ttb-report-add` | `/ttb-reports/new` | Generate report | generate a 5120.17 for a period | `period` |
| `ttb-report-view` | `/ttb-reports/{id}` | TTB report | see a report's lines, drill into the transactions behind a line, finalize, mark filed |  |
| `trace` | `/trace/` | Trace | trace a lot forward or a batch backward for a recall | `lot_number`, `batch_number` |

### Customer orders and planning (docs/11, docs/12)

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `orders-list` | `/orders/` | Customer orders | see open or past customer orders, what is due, overdue orders |  |
| `order-add` / `order-edit` | `/orders/new`, `/orders/{id}/edit` | Customer order | enter a customer order: customer, due date, lines of product format and units, prices | `customer` |
| `order-view` | `/orders/{id}` | Customer order | see an order's lines, packaging runs and shipments; confirm, package, ship, close or cancel it |  |
| `order-package` | `/orders/{id}/package` | Package for an order | create the draft packaging runs that fill an order |  |
| `orders-package-format` | `/orders/package` | Package for orders | package one format for every open order that needs it | `format` |
| `orders-to-package` | `/orders/to-package` | Packaging queue | see what must be packaged for customer orders, by format and due date |  |
| `standing-orders-list` | `/orders/standing` | Standing orders | see recurring customer orders |  |
| `standing-order-add` / `standing-order-edit` | `/orders/standing/new`, `/orders/standing/{id}/edit` | Standing order | set up or change a recurring order (weekly, every few weeks, monthly) | `customer` |
| `standing-order-view` | `/orders/standing/{id}` | Standing order | see a standing order's next dates; turn a date into an order; pause or resume it |  |
| `orders-import` | `/orders/import` | Import orders | load past or upcoming orders from a spreadsheet (CSV or Excel) |  |
| `order-import-view` | `/orders/import/{id}` | Order import | see an import's preview, columns, result or errors; import, undo or discard it |  |
| `planning` | `/planning/` | Projections | see demand by week and what to package, brew and buy | `demand` |
| `planning-production` | `/planning/production` | Suggested production | see which batches to start and by when | `demand` |
| `planning-purchasing` | `/planning/purchasing` | Suggested purchases | see what to buy, how much and by when | `demand` |
| `planning-forecast` | `/planning/forecast` | Forecast | see and set forecast demand per format and week |  |
| `report-orders` | `/reports/orders` | Order history | see past orders by customer, product, format or month | `group_by`, `date_from`, `date_to` |

### Equipment scheduling (docs/15, docs/16 — 2026-10-08)

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `equipment-schedule` | `/schedule/` | Equipment schedule | see what is booked on every tank, press, line and piece of equipment, day by day, and spot clashes; `view=month` for the month grid | `from`, `weeks`, `view`, `month`, `premises_id`, `kind`, `resource`, `subject` |
| `reservation-add` | `/reservations/new` | Reserve equipment | book a vessel or a piece of equipment for a run, or block it for cleaning, maintenance or a hold | `resource`, `on`, `subject_kind`, `subject_id`, `kind` |
| `reservation-edit` | `/reservations/{id}/edit` | Reservation | change a booking's window, role, resource or notes |  |
| `reservation-view` | `/reservations/{id}` | Reservation | see a booking, its overlaps and the vessel's occupant; cancel it |  |
| `equipment-list` | `/equipment/` | Equipment | see the mills, pumps, filters, lines and other equipment, their status and next booking (cards) | `kind`, `status` |
| `equipment-add` / `equipment-edit` | `/equipment/new`, `/equipment/{id}/edit` | Equipment | add or change a piece of equipment, set its status | `name`, `kind` |
| `equipment-view` | `/equipment/{id}` | Equipment | see a piece of equipment and its bookings ahead and past; set its status |  |

## Action registry

Rules (chat-actions skill, locked): creates and updates execute immediately and return an undo handle; destructive actions and anything that changes tax state confirm first; posting a document is immediate but its undo is a reversal document, never a delete. Every action calls the app's own endpoint with a signed action token; the endpoint applies the same `require_post()`, `verify_csrf()`, authorization, interlocks, and `log_activity()` as a human request.

Undo definitions: `delete_row` removes the created row (allowed only while the document is still a draft); `restore_prior` writes the before-image back; `reverse` posts the compensating document; `none` means irreversible (confirm first).

Role column: the minimum role; `owner` can do everything.

### Foundation

| Action | Endpoint | Parameters | Undo | Confirm | Role |
|---|---|---|---|---|---|
| `premises_create` / `premises_update` | `POST /premises/save` | name, kind, registry_number, filing_frequency | delete_row / restore_prior | no | owner |
| `location_create` / `location_update` | `POST /locations/save` | name, kind, tax_state, premises | delete_row / restore_prior | no | owner |
| `rack_create` / `rack_update` | `POST /racks/save` | area, rack_number | delete_row / restore_prior | no | owner |
| `tank_position_set` | `POST /tanks/{id}/position` | x, y (grid units where the tank stands on the Tank view) | restore_prior | no | production |
| `vessel_create` / `vessel_update` | `POST /vessels/save` | name, kind, capacity_gal, location | delete_row / restore_prior | no | production |
| `vessel_set_status` | `POST /vessels/{id}/status` | status (empty, cleaning, out_of_service) | restore_prior | no | production |
| `item_create` / `item_update` | `POST /items/save` | name, item_class, base_unit, lot_controlled, quarantine_default, reorder_point | delete_row / restore_prior | no | receiving |
| `item_class_create` / `item_class_update` | `POST /item-classes/save` | code, name, kind, purchasable, recipe_ingredient, display_order | delete_row / restore_prior | no | receiving |
| `item_class_delete` | `POST /item-classes/{id}/delete` | — (custom classes with no items only; built-in classes cannot be deleted) | none | yes | receiving |
| `item_unit_add` | `POST /items/{id}/units/save` | unit_name, to_base_factor | delete_row | no | receiving |
| `supplier_create` / `supplier_update` | `POST /suppliers/save` | name, kind, contact | delete_row / restore_prior | no | receiving |
| `supplier_delete` | `POST /suppliers/{id}/delete` | — (deleted with no purchase orders, receipts or lots; otherwise deactivated) | none | yes | receiving |
| `supplier_item_add` | `POST /suppliers/{id}/items/save` | item, purchase_unit, price, lead_time_days | delete_row | no | receiving |
| `user_invite` | `POST /users/save` | email, display_name, role | delete_row (if never signed in) | no | owner |
| `user_invite_resend` | `POST /users/{id}/resend` | — (new 3-day link; earlier links stop working; emails the invitee) | none | yes | owner |
| `user_set_role` | `POST /users/{id}/role` | role | restore_prior | yes | owner |
| `user_disable` | `POST /users/{id}/disable` | — | restore_prior | yes | owner |
| `user_enable` | `POST /users/{id}/enable` | — (back to active if they have signed in before, otherwise to invited) | restore_prior | no | owner |
| `reason_code_create` / `reason_code_update` | `POST /reason-codes/save` | code, name, applies_to, ttb_category | delete_row / restore_prior | no | compliance |
| `client_settings_update` | `POST /settings/client/save` | client_name, timezone, display units | restore_prior | no | owner |
| `mcp_token_create` | `POST /settings/mcp-tokens/save` | name, scope | reverse (revoke) | no | owner |
| `mcp_token_revoke` | `POST /settings/mcp-tokens/{id}/revoke` | — | none | yes | owner |

### Receiving

| Action | Endpoint | Parameters | Undo | Confirm | Role |
|---|---|---|---|---|---|
| `po_create` / `po_update` | `POST /purchase-orders/save` | supplier, expected_on, lines[item, qty, unit, price] | delete_row / restore_prior (draft only) | no | receiving |
| `po_approve` | `POST /purchase-orders/{id}/approve` | — | restore_prior (back to draft, if nothing received) | no | owner |
| `po_close_short` | `POST /purchase-orders/{id}/close-short` | reason | restore_prior | yes | receiving |
| `po_cancel` | `POST /purchase-orders/{id}/cancel` | — | restore_prior | yes | receiving |
| `receipt_create` / `receipt_update` | `POST /receipts/save` | supplier, po_number?, received_at, lines[item, qty, unit, supplier_lot, expires_on, discrepancy] | delete_row / restore_prior (draft) | no | receiving |
| `receipt_line_add` | `POST /receipts/{id}/lines/save` | item, qty, unit, supplier_lot, expires_on, discrepancy | delete_row | no | receiving |
| `weigh_tag_record` | `POST /receipts/{id}/lines/{line}/weigh-tag` | gross_lb, tare_lb, bin_count, variety, orchard, block, brix | restore_prior | no | receiving |
| `receipt_post` | `POST /receipts/{id}/post` | — (creates lots, posts ledger receipts) | reverse (posts reversal transactions; lots marked rejected) | no | receiving |
| `putaway_record` | `POST /receipts/{id}/putaway` | lines[lot, to_location] | reverse | no | receiving |
| `lot_update` | `POST /lots/{id}/save` | expires_on, supplier_lot, notes | restore_prior | no | receiving |
| `lot_attribute_set` | `POST /lots/{id}/attributes/save` | key, value, unit | restore_prior | no | quality |
| `coa_record` | `POST /lots/{id}/coa/save` | issued_on, issuer, values{} (+ attachment) | delete_row | no | quality |
| `lot_release` | `POST /lots/{id}/release` | to_status (released, hold, rejected), basis, note, override? | reverse (a new decision back to the prior status) | yes when override | quality |

### Inventory

| Action | Endpoint | Parameters | Undo | Confirm | Role |
|---|---|---|---|---|---|
| `transfer_create` | `POST /transfers/save` | from_location, to_location, lines[item, lot, qty] | delete_row (draft) | no | receiving |
| `transfer_post` | `POST /transfers/{id}/post` | — | reverse | no | receiving |
| `adjustment_create` | `POST /adjustments/save` | location, reason, lines[item, lot, qty_delta, note] | delete_row (draft) | no | receiving |
| `adjustment_approve` | `POST /adjustments/{id}/approve` | — | restore_prior | no | owner |
| `adjustment_post` | `POST /adjustments/{id}/post` | — | reverse | yes when any line is a write-down | receiving |
| `count_start` | `POST /counts/save` | location, kind | delete_row | no | receiving |
| `count_line_record` | `POST /counts/{id}/lines/save` | item, lot, qty_counted | restore_prior | no | receiving |
| `count_submit` | `POST /counts/{id}/submit` | — | restore_prior | no | receiving |
| `count_approve` | `POST /counts/{id}/approve` | — (posts count corrections) | reverse | yes | owner |
| `count_cancel` | `POST /counts/{id}/cancel` | — | restore_prior | yes | receiving |

### Products and recipes

| Action | Endpoint | Parameters | Undo | Confirm | Role |
|---|---|---|---|---|---|
| `product_create` / `product_update` | `POST /products/save` | name, style, target_abv, fruit_share, intended_tax_class, flags | delete_row / restore_prior | no | production |
| `product_retire` | `POST /products/{id}/retire` | — | restore_prior | yes | production |
| `recipe_create_draft` | `POST /products/{id}/recipes/save` | batch_volume_gal, copy_from_version? | delete_row | no | production |
| `recipe_update_draft` | `POST /recipes/{id}/save` | stages[], lines[], change_note | restore_prior | no | production |
| `recipe_activate` | `POST /recipes/{id}/activate` | — (retires the previous active) | restore_prior (reactivates the previous, if no batch used the new one) | no | production |
| `packaging_config_create` / `_update` | `POST /packaging-configs/save` | product, finished_item, package_kind, fill_volume, bom[] | delete_row / restore_prior | no | production |
| `spec_create` / `spec_update` | `POST /specs/save` | product, stage, measurement, min, max, target | delete_row / restore_prior | no | quality |
| `standard_cost_set` | `POST /standard-costs/save` | item, cost, effective_from | delete_row | no | owner |
| `overhead_rate_set` | `POST /standard-costs/overhead` | premises, rate_per_gal, effective_from | delete_row | no | owner |
| `approval_record` / `approval_update` | `POST /approvals/save` | product, kind, reference_no, status, dates | delete_row / restore_prior | no | compliance |

### Production orders

| Action | Endpoint | Parameters | Undo | Confirm | Role |
|---|---|---|---|---|---|
| `production_order_create` / `_update` | `POST /production-orders/save` | product, recipe_version?, volume_gal, pitch_on, package_on, plan[] (resource, role, planned_from, planned_to, all_day, start_time, end_time, share) | delete_row / restore_prior | no | production |
| `production_order_release` | `POST /production-orders/{id}/release` | — (creates allocations) | restore_prior (releases allocations) | no | production |
| `production_order_close` | `POST /production-orders/{id}/close` | — | restore_prior | no | production |
| `production_order_cancel` | `POST /production-orders/{id}/cancel` | — | restore_prior | yes | production |

### Equipment scheduling (docs/16)

| Action | Endpoint | Parameters | Undo | Confirm | Role |
|---|---|---|---|---|---|
| `equipment_create` / `equipment_update` | `POST /equipment/save` | name, kind (mill, pump, filter, chiller, carbonator, canning_line, bottling_line, keg_line, keg_washer, labeler, other), premises, location, rating, status, notes | restore_prior (never deleted; deactivated) | no | production |
| `equipment_set_status` | `POST /equipment/{id}/status` | status (available, cleaning, out_of_service) | restore_prior | no | production |
| `equipment_reserve` | `POST /reservations/save` | vessel (the tank or press to book — one of vessel / equipment), equipment (the mill / pump / filter / line to book), from (first day), to (last day — inclusive), order (the production order it is for — one of order / batch / press_run / packaging_run / block), batch, press_run, packaging_run, block (cleaning / maintenance / hold — blocks the resource instead of a run), role (primary / maturation / brite / blend / press / mill / transfer / filter / carbonate / package / other), start_time (HH:MM when not all day), end_time (HH:MM when not all day), share (1 books over a clash as shared use — only when the organization allows double booking), notes | delete_row (cancels the booking) | no | production |
| `equipment_reservation_update` | `POST /reservations/save` | reservation (the booking's id), vessel, equipment, from, to, order, batch, press_run, packaging_run, block, role, start_time, end_time, share, notes | restore_prior | no | production |
| `equipment_reservation_cancel` | `POST /reservations/{id}/cancel` | — | none | yes | production |
| `client_settings_update` | `POST /settings/client-save` | equipment_double_booking (on or off; with the display units and time zone) | restore_prior | no | owner |

### Batch execution

| Action | Endpoint | Parameters | Undo | Confirm | Role |
|---|---|---|---|---|---|
| `press_run_create` / `_update` | `POST /press-runs/save` | press, run_on, inputs[fruit_lot, lb], outputs[juice_item, gal, brix, vessel], pomace_lb, location | delete_row / restore_prior (draft) | no | production |
| `press_run_post` | `POST /press-runs/{id}/post` | — (issues fruit, creates juice and pomace lots, occupies vessels) | reverse | no | production |
| `batch_pitch` | `POST /batches/save` | product, vessel, juice_lots[lot, gal], yeast_lot, qty, production_order? | reverse (returns juice lots, voids batch) while no later event | no | production |
| `batch_reading_record` | `POST /batches/{id}/readings/save` | measurement, value, taken_at?, stage? | delete_row | no | production |
| `batch_addition_record` | `POST /batches/{id}/additions/save` | item, lot?, qty, unit, purpose | reverse | no | production |
| `batch_stage_move` | `POST /batches/{id}/stage` | to_stage, volume_out_gal? | restore_prior | no | production |
| `batch_transfer` | `POST /batches/{id}/transfer` | to_vessel, volume_gal, loss_gal? | reverse | no | production |
| `batch_split` | `POST /batches/{id}/split` | outputs[vessel, volume_gal] | reverse (while children have no events) | no | production |
| `batch_blend` | `POST /batches/blend` | inputs[batch, volume_gal], vessel, product? | reverse (while the result has no events) | no | production |
| `batch_loss_record` | `POST /batches/{id}/losses/save` | qty_gal, reason, stage?, note | reverse | yes when exceptional above threshold | production |
| `batch_dump` | `POST /batches/{id}/dump` | reason, note | none | yes | production |
| `batch_tax_class_override` | `POST /batches/{id}/tax-class` | tax_class, reason | restore_prior | yes | compliance |
| `batch_update` | `POST /batches/{id}/save` | notes | restore_prior | no | production |
| `yeast_harvest_record` | `POST /batches/{id}/yeast/save` | volume_l, generation, cell_count?, viability? | reverse | no | production |
| `pomace_disposition_record` | `POST /dispositions/save` | lot, qty_lb, destination, recipient | reverse | no | production |

### Packaging and kegs

| Action | Endpoint | Parameters | Undo | Confirm | Role |
|---|---|---|---|---|---|
| `packaging_run_create` / `_update` | `POST /packaging-runs/save` | batch, package, run_on, volume_in_gal, units_out, co2, abv, materials[] | delete_row / restore_prior (draft) | no | production |
| `packaging_run_post` | `POST /packaging-runs/{id}/post` | — (creates the finished lot with tax class, consumes materials, posts loss) | reverse (`POST /packaging-runs/{id}/reverse`) | no | production |
| `finished_lot_tax_class_override` | `POST /finished-lots/{id}/tax-class` | tax_class, reason | restore_prior | yes | compliance |
| `keg_register` / `keg_update` | `POST /kegs/save` | serial, size, ownership, deposit | delete_row / restore_prior | no | production |
| `keg_fill` | `POST /kegs/{id}/state` (event=fill) | finished_lot | reverse | no | production |
| `keg_return` | `POST /kegs/return` | serials[], customer? | reverse | no | production |
| `keg_clean` | `POST /kegs/{id}/state` (event=clean) | — | reverse | no | production |
| `keg_mark_lost` / `keg_found` | `POST /kegs/{id}/state` (event=mark_lost / found) | — | reverse | yes (lost) | production |
| `keg_retire` | `POST /kegs/{id}/state` (event=retire) | — | none | yes | production |

### Quality

| Action | Endpoint | Parameters | Undo | Confirm | Role |
|---|---|---|---|---|---|
| `lab_reading_record` | `POST /lab/save` | batch or lot, measurement, value, method, taken_at | delete_row | no | quality |
| `sensory_record` | `POST /sensory/save` | batch or lot, verdict, attributes{}, faults[], comment | delete_row | no | quality |
| `batch_release` | `POST /batches/{id}/release` | to_status, basis, override?, note | reverse | yes when override | quality |

### Removals and compliance

| Action | Endpoint | Parameters | Undo | Confirm | Role |
|---|---|---|---|---|---|
| `customer_create` / `customer_update` | `POST /customers/save` | name, kind, default_destination, permit_number | delete_row / restore_prior | no | compliance |
| `customer_delete` | `POST /customers/{id}/delete` | — (deleted with no orders, standing orders, removals or keg records; otherwise deactivated) | none | yes | compliance, sales |
| `removal_create` / `removal_update` | `POST /removals/save` | destination_kind, customer?, removed_at, lines[finished_lot, units, kegs[]] | delete_row / restore_prior (draft) | no | compliance |
| `removal_post` | `POST /removals/{id}/post` | — (ledger removal, tax determination, keg ships) | reverse (posts a reversing removal) | yes (changes tax state) | compliance |
| `removal_reverse` | `POST /removals/{id}/reverse` | reason | none | yes | compliance |
| `return_create` + `return_post` | `POST /removals/save` with direction=in, then `/post` | customer, lines[] | delete_row / reverse | yes (post) | compliance |
| `ttb_report_generate` | `POST /ttb-reports/save` | premises, period_start, period_end | delete_row (draft) | no | compliance |
| `ttb_report_regenerate` | `POST /ttb-reports/{id}/regenerate` | — | restore_prior | no | compliance |
| `ttb_report_finalize` | `POST /ttb-reports/{id}/finalize` | — | restore_prior | yes | compliance |
| `ttb_report_mark_filed` | `POST /ttb-reports/{id}/filed` | filed_at | restore_prior | yes | compliance |

### Customer orders and planning

| Action | Endpoint | Parameters | Undo | Confirm | Role |
|---|---|---|---|---|---|
| `order_create` | `POST /orders/save` then `POST /orders/{id}/confirm` | customer, due_on, lines[] (product, format, units, unit_price?), reference?, ordered_on?, confirm? | delete_row (cancels the order) | no | sales |
| `po_supplier_quick` | `POST /purchase-orders/supplier-quick` | new_supplier[name, kind, contact_name?, email?, phone?] (screen only: the New supplier panel of the purchase order form) | none | no | receiving |
| `order_customer_quick` | `POST /orders/customer-quick` | new_customer[name, kind, default_destination, contact_name?, email?, phone?, permit_number?] (screen only: the New customer panel of the order and standing order forms) | none | no | sales |
| `order_add_line` | `POST /orders/save` (all lines) | order, product, format, units, unit_price? | none | yes | sales |
| `order_confirm` | `POST /orders/{id}/confirm` | — | none | no | sales |
| `order_cancel` | `POST /orders/{id}/cancel` | reason | none | yes | sales |
| `order_close` | `POST /orders/{id}/close` | — (open lines become closed short) | none | yes | sales |
| `order_package` | `POST /orders/package-save` | order (the suggested units, batch, vessel and location of the Package screen) | delete_row (deletes the draft runs) | no | sales |
| `order_ship` | `POST /orders/{id}/ship` | — | delete_row (deletes the draft removal) | no | sales |
| `order_from_standing` | `POST /orders/standing/{id}/occurrence` | standing order, date | delete_row (cancels the order) | no | sales |
| `standing_order_deactivate` | `POST /orders/standing/{id}/active` | — (active = 0; active = 1 resumes) | restore_prior | no | sales |
| `orders_import_commit` / `orders_import_undo` / `orders_import_discard` | `POST /orders/import/{id}/commit`, `/undo`, `/discard` | — (screen only: the file upload and preview happen on the screen) | none | yes | sales |
| `forecast_generate` / `forecast_set` | `POST /planning/forecast/generate`, `POST /planning/forecast/save` | history_weeks, horizon_weeks / format, week_start, units (screen only) | none | yes | sales |

### Assistant-internal

| Action | Endpoint | Parameters | Notes |
|---|---|---|---|
| `navigate` | — | screen, params | Resolves against the screen registry above; returns an `HX-Location` directive |
| `undo_last` | `POST /assistant/undo` | undo_id | Applies the undo definition of the named action from the activity log |

## Status vocabulary (locked colors)

| Entity | success | warning | danger | info | secondary | dark |
|---|---|---|---|---|---|---|
| Lot quality | released | hold | rejected | — | — | quarantine |
| Purchase order | closed | partial | closed_short, cancelled | open | — | draft |
| Receipt, transfer, adjustment, press run, packaging run, removal | posted | pending_approval | cancelled, reversed | — | — | draft |
| Count | approved | review | cancelled | counting | — | open |
| Recipe version | active | — | — | — | retired | draft |
| Production order | complete | — | cancelled | released, in_progress | closed | planned |
| Batch | packaged | — | dumped | active | closed | — |
| Vessel | empty | cleaning | out_of_service | in_use | — | — |
| Keg | empty | returned_dirty, cleaning | lost | filled, at_customer | out_of_service | — |
| TTB report | filed | — | — | final | — | draft |
| User | active | invited | disabled | — | — | — |
| Customer order | shipped | — | cancelled | confirmed, in_fulfillment | closed | draft |
| Order line | — | closed_short | cancelled | open | — | — |
| Order import | imported | previewed | — | — | undone, abandoned | — |
| Demand type (badge) | firm | standing | — | forecast | planned production | — |
| Equipment | available | cleaning | out_of_service | — | — | — |
| Equipment booking (bar) | the run's own colour; a block: cleaning = info, maintenance = secondary, hold = dark; a shared or overlapping bar is edged warning; a bar on a resource out of service is edged danger | | | | | |
| Reservation | — | — | cancelled | booked | — | — |

## Activity log event names

`screen_entered` on every screen render, plus one event per action above using the action name as the event name (`receipt_posted`, `lot_released`, `batch_pitched`, `removal_posted`, ...), `login`, `login_google`, `login_2fa`, `logout`, `totp_enabled`, `totp_disabled`, `identity_linked`, `password_reset`, `action_undone`, `assistant_message`, `ama_question`, `mcp_tool_called`.

Customer orders and planning: `order_created`, `order_updated`, `order_confirmed`, `order_cancelled`, `order_closed`, `order_status_changed` (roll-up), `order_packaging_runs_created`, `order_shipment_created`, `order_created_from_standing`, `standing_order_created`, `standing_order_updated`, `standing_order_deactivated`, `orders_import_previewed`, `orders_imported`, `orders_import_undone`, `orders_import_discarded`, `forecast_generated`, `forecast_set`; `packaging_run_created` and `removal_created` are also written when an order creates them.

Equipment scheduling (2026-10-08): `equipment_created`, `equipment_updated`, `equipment_status_set`, `equipment_reserved` (details: resource, window, run, role, `shared`, clashes), `equipment_reservation_updated`, `equipment_reservation_cancelled` (details `cause`: person, run_cancelled, run_closed); `production_order_created` / `_updated` carry the plan (`plan`) and, when a row was booked over a clash, `shared` and the clashing numbers; `production_order_cancelled` and `_closed` count the bookings cancelled or trimmed; `screen_entered` on `equipment-schedule` carries the window and filters.
