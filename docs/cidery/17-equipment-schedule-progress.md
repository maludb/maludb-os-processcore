# Equipment scheduling progress

Plan: [15-equipment-schedule-plan.md](15-equipment-schedule-plan.md) (approved 2026-10-08, D1–D13 all the recommendations).
Design: [16-equipment-schedule-design.md](16-equipment-schedule-design.md). Everything below was built and checked on
2026-10-08 against `cidery_dev` — a copy of the live database's `app` schema with `db/023` applied and seed data
(three vessels, three pieces of equipment, four orders with overlapping vessel plans, a batch in primary) — served by
`php -S 127.0.0.1:8183` through the router (`DB_NAME=cidery_dev OS_ENABLED=0`), with HTTP checks as an owner, a production
user and a viewer. The live database is untouched: `db/023` applies there through the installer's apply.

| Step | Work | Status | Notes |
|---|---|---|---|
| 1 | Design, `db/023`, the proof | Done | `scripts/prove-equipment-schedule.sh`: 39 checks on a scratch copy, dropped afterwards; `ed8725d` |
| 2 | Setup → Equipment | Done | See below |
| 3 | Reservations, the switch, the order's equipment plan, the cascades | Done | See below |
| 4 | The Equipment schedule | Done | See below |
| 5 | Processing time and Outputs on the production order | Done | See below |
| 6 | The assistant | Done | See below |
| 7 | Test pass, docs | Done | See below |

## Step 2: Setup → Equipment

- **Screens:** `/equipment/` (cards, grouped by premises when there are several; search, kind, status and premises
  filters refresh the results region; each card shows status, rating, where it stands and its next booking), `/equipment/new`,
  `/equipment/{id}/edit`, `/equipment/{id}` (summary, three status buttons, bookings ahead and past, Schedule and Reserve
  buttons). Navigation: Setup → Equipment, after Vessels. A press stays a vessel (the form says so).
- **Handlers:** `/equipment/save` (`equipment_created` / `equipment_updated`; a duplicate name on a premises is a field error),
  `/equipment/{id}/status` (`equipment_status_set`; taking a piece out of service names the bookings ahead in the trail and
  the flash; nothing is cancelled). The kernel's parameter names `premises` and `location` are read beside `premises_id` and
  `location_id`.
- `app/features/equipment/queries.php`; `find_resource_bookings()` serves the equipment page (and would serve a vessel's).
- **Checked:** list, cards, form, view as owner; create, status; viewer gets 403 on the status change and sees no Add button.

## Step 3: Reservations, the switch, the order's equipment plan

- **Screens:** `/reservations/new` (resource grouped Vessels / Equipment; For: a run or cleaning / maintenance / hold; kind
  of run + the run, the run select reloaded by a Pattern A fragment `/reservations/subject-options`; role; from, to; All
  day; start and end time; notes; prefill `resource`, `on`, `subject_kind`, `subject_id`, `kind`), `/reservations/{id}/edit`,
  `/reservations/{id}` (the booking, its overlaps, the vessel's foreign occupant, Edit and Cancel). Breadcrumbs lead to the
  schedule.
- **The clash rule** (`/reservations/save`, `app/features/reservations/queries.php`): `app.equipment_clashes()` for the
  resource and window, excluding the booking being edited. Any clash under refuse → 422, the clashes listed in a warning card
  ("PROVE canning line is booked for PROVE-B-1 · PROVE Dry · Package, Nov 25, 2026, 8:00 AM – 12:00 PM"). Under allow the
  card carries "Book anyway (shared use)"; ticked, the booking saves `shared` and the trail (`equipment_reserved`,
  `equipment_reservation_updated`) carries `shared: true` and the clashing numbers; the flash names them. A resource out of
  service cannot be booked. Times: a booking is two instants in the business's time zone; the form's dates are inclusive;
  all day = 00:00 to 00:00 the day after. The kernel's actions server may send `vessel` / `equipment`, `order` / `batch` /
  `press_run` / `packaging_run` / `block`, `from`, `to`, `start_time`, `end_time` (nothing = all day), `share` instead of the
  form's fields; the handler reads both shapes.
- **The switch:** Organization settings gains "Equipment may be double-booked" (`settings.equipment.double_booking`,
  `set_double_booking()`); `client_settings_updated` shows it among the fields.
- **The production order:** the form's Vessel plan rows became the **Equipment plan** (`plan[n][…]`: resource grouped,
  role offered by resource kind, from, to, All day with start and end time, hidden id for an existing booking; the row fragment
  `/production-orders/plan-row` refreshes the capacity warning and the roles when the resource changes; the older
  `vessels[n][vessel_id]` shape is still read). `/production-orders/save` validates the rows, runs the clash rule on each
  (a row's own booking excluded), refuses with the clashes under the row — and the "Book anyway" tick per row under allow —
  then saves the plan in place (`save_production_order_plan()`: rows with an id are updated and keep their shared mark, new
  rows inserted, bookings the form dropped deleted). The view's card is the Equipment plan: resource, role, when, days,
  capacity (amber when too small), clashes (shared with …, overlaps …, occupied now by …), plus Schedule and Reserve buttons.
- **Cascades:** cancelling an order cancels its bookings (`equipment_reservation_cancelled`, cause `run_cancelled`, one row
  each, and the order's trail counts them); closing trims a booking still running to now and cancels one not started (cause
  `run_closed`); dumping a batch and deleting a draft press or packaging run cancel their bookings.
- **Removed:** `html/production-orders/vessel-row.php`, the vessel-row partial, the Vessel calendar's views and
  `find_calendar_rows`, `find_production_order_vessels`, `find_vessel_conflicts`, `production_vessel_catalog`,
  `production_validate_vessel_rows`, `replace_production_order_vessels`, `PRODUCTION_ORDER_VESSEL_ROLES`.
- **Checked:** a timed booking on the canning line; the same window refused (clash card, 422) and then saved shared (both
  bookings show "1 overlap", the second "Shared"); a block; the switch off → the clash refused with "does not allow" and no
  tick offered; a viewer's POST → 403; cancel; an order created with a vessel and a timed line booking; an order's row that
  clashes with another order's booking refused under refuse and saved shared under allow (the trail: `{"shared": true,
  "clashes": ["WO-00001"]}`); the edit form round-trips the booking's id and the shared tick; cancelling the order cancels
  its bookings with cause `run_cancelled`; the kernel's parameter shape (vessel=, order=, from=, to=; equipment=, batch=,
  start_time=, end_time=; equipment=, block=maintenance).

## Step 4: the Equipment schedule

- `/schedule/` (Production → Equipment schedule, second item; the Vessel calendar item is gone and
  `/production-orders/calendar` answers 301 — HX-Location for HTMX — to `/schedule/?kind=vessel`).
- **Timeline** (default): one column per day for 1, 2, 4, 8 or 12 weeks from the Monday of `from`; Vessels then Equipment
  as groups; one row per resource with its kind, capacity, status and what it holds now ("Now: B-26-004"); a bar per booking
  spanning its days (two overlapping bookings take two lanes, `rowspan` on the name), coloured by the run's status (a block:
  cleaning info, maintenance secondary, hold dark), edged amber when it overlaps or is shared, red on a resource out of
  service, dashed where it runs past the window, a clock when timed; a tooltip with the full window; the bar opens the run
  (a block opens its reservation); a "+" per row opens the reservation form prefilled with the resource and the day; earlier /
  this week / later buttons push the URL; the resource column is sticky and the table scrolls sideways on a phone.
- **Month** (`?view=month`): the month grid, a chip per booking on every day it covers (resource · run; an arrow when it
  continues from an earlier day, a clock when timed; amber edge when overlapping), a "+" per day; previous / this / next month.
- **Filters** in the page header: premises (when several), kind (all vessels, all equipment, a vessel kind, an equipment
  kind), one resource, the window; `subject=batch:4` (from a run page's Schedule button) shows only that run's bookings.
  Reserve in the header prefills the resource filter.
- `app/features/schedule/queries.php` (`find_schedule_resources`, `find_schedule_bookings`, `find_schedule_occupants`,
  `schedule_lanes`, the bar helpers); `app-overrides.css` gains the `.schedule-*` rules. `screen_entered` carries the window
  and filters.
- **Checked:** the November window shows A and B on FV-A in two lanes, both marked shared, A's maturation on FV-B, the two
  timed canning-line runs; the month grid for November with the equipment filter; the subject and resource filters; the
  redirect; the viewer sees the schedule without the Reserve button.

## Step 5: the production order as a run

- The order view's cards, in order: **Equipment plan**; **Inputs** (the material check with a new "Consumed so far" column
  from the order's batches' consumptions, `find_order_consumed()`); **Processing time** (`find_order_processing_time()`: the
  recipe's stages with expected days, planned start and end rolled forward from the pitch date, the batches' actual entry and
  exit from `stage_events`, actual days, variance, and the bookings whose role serves the stage — `PRODUCTION_ROLE_STAGES`;
  footer: planned total days, the planned end, the planned package date, elapsed days); **Outputs — planned**
  (volume, expected loss, expected packaged volume, the planned packages with their customer order) and **Outputs — actual**
  (batches, packaging runs, finished lots with units on hand) from `find_order_outputs()`; Allocations once released.
- **Checked:** PROVE-WO-A shows its two bookings (one "Shared with PROVE-WO-B"), 40 planned days over six stages, the
  batch's pitch (1 day) and primary (in progress), the planned 1,000 cans; an order whose batch has not started shows dashes.

## Step 6: the assistant

- **Records MCP:** `equipment_schedule` (E1: by vessel, equipment, kind, premises, window, order or batch; each booking with
  its run, role, days, times, shared mark and overlaps), `equipment_free` (E2: free windows of at least N days per resource of a
  kind with at least a capacity, earliest first), `find_equipment`, `find_press_run`, `find_reservation` (resolvers; a
  reservation by its resource or run, or `id:`); `production_orders_by_status` gains `equipment`. Suite entries E1–E3 in
  `test_client.py`; the tools were called in-process against `cidery_dev` (the window, a resource, a run, a kind, free
  fermenters over 400 gal, the line's free days, the resolvers, an unknown kind refused with the list).
- **Actions (standalone server):** `equipment_create`, `equipment_set_status`, `equipment_reserve` (one of vessel /
  equipment; one of order / batch / press_run / packaging_run or a block; days and optional times; `share`), and
  `equipment_reservation_cancel` (confirms); undo handlers for `equipment_status_set` and `equipment_reserved` (cancel);
  resolver kinds `equipment` and `reservation`; the catalog's lists.
- **Manifests:** `docs/05` gains the screens, the actions (every parameter named plainly so the kernel resolves `vessel`,
  `equipment`, `order`, `batch`, `press_run`, `packaging_run`, `reservation`), the colours and the events;
  `production_order_create` takes `plan[]`. `config/manifest.json` rebuilt (`--no-http`: 172 screens, 141 actions, 46 tools,
  nothing flagged); `mcp/action_registry.json` and `deploy/kernel-registry-cidery.json` rebuilt (135 actions, 129 built; 17
  resolvers incl. `equipment`, `reservation`, `press_run`). `docs/04` gains the tools. `maludb-os.json` grants the expert the
  new tools; `os/expert.md` and `skills/cidery-basics` carry the vocabulary.
- **Owed to the owner:** the kernel's `mcp/registries/cidery.json` is install-specific — the installer's apply (or
  `bos-app.sh update`) re-registers the actions and the expert's grants after this update, and applies `db/023`.

## Step 7: the test pass

- `scripts/conformance.sh equipment reservations schedule production-orders settings`: PASS (the static id warning on
  `schedule/page.php` is the two branches of one input; `settings/2fa.php` was already warned).
- `php -l` on every touched file; the services' modules parse and the four new action tools register
  (`equipment_create`, `equipment_reservation_cancel`, `equipment_reserve`, `equipment_set_status`).
- The dev server's log is free of PHP warnings after the whole pass.

## Not built, on purpose

- The booking's end prefilled from the recipe's stage days (D11), per-resource sharing rules (D5), drag to move a bar,
  the schedule on the dashboard — docs/15 §13.
- `equipment_update` and `equipment_reservation_update` as standalone action tools (the registry carries them for the
  kernel; the screens do the editing).
