# Equipment scheduling: design (step 1)

**Date:** 2026-10-08
**Status:** built alongside `db/023_equipment_schedule.sql` after the owner approved every recommendation of
[15-equipment-schedule-plan.md](15-equipment-schedule-plan.md) (D1–D13) the same day. Extends
[04-mcp-tool-surface.md](04-mcp-tool-surface.md) and [05-action-manifest.md](05-action-manifest.md); merged into them
when the screens ship (step 6).
**Checked:** `scripts/prove-equipment-schedule.sh` — a scratch copy of the live database's `app` schema (never the
database itself, D13), seeded with four production orders whose vessel plans overlap two by two and one cancelled, then
`db/023` applied as `cidery_app` and `db/020` re-run exactly as `deploy/os-provision.sh` does, then 39 checks (section 8).
All 39 pass; the scratch database is dropped afterwards.

## 1. Schema summary

| Object | Kind | Notes |
|---|---|---|
| `app.client_timezone()` | function | The business's time zone from `client_settings`, `UTC` when the row is missing. Turns a booking's instants into its calendar days in the views |
| `app.equipment` | table | What a run needs that holds nothing: `premises_id`, optional `location_id`, `name` (unique per premises), `kind` ∈ mill, pump, filter, chiller, carbonator, canning_line, bottling_line, keg_line, keg_washer, labeler, other; `status` ∈ available, cleaning, out_of_service; `rating` (words: "120 cans/min"); `notes`; `active`. A press is a vessel of kind `press`, not equipment |
| `app.equipment_reservations` | table | One resource × one window. `resource_kind` ∈ vessel, equipment + `resource_id`; `kind` ∈ run, cleaning, maintenance, hold; `subject_kind` ∈ production_order, batch, press_run, packaging_run + `subject_id` — required for a run, forbidden for a block; `role` ∈ primary, maturation, brite, blend (vessels, as before), press, mill, transfer, filter, carbonate, package, other; `starts_at` < `ends_at` (exclusive — an all-day booking ends at 00:00 after its last day); `all_day`; `shared` (saved over a clash under the allow policy); `status` ∈ booked, cancelled with `cancelled_at`/`cancelled_by`; `notes`; `created_by`; touch trigger |
| `equipment_reservations_check_refs` | trigger | The resource and the run must exist (a polymorphic pair has no foreign key): a missing vessel, equipment or run raises `foreign_key_violation` |
| `equipment_reservations_window_idx` | GiST index | `(resource_kind, resource_id, tstzrange(starts_at, ends_at))` on booked rows — the clash query and the schedule window |
| `app.production_order_vessels` | **view** (was a table) | The migration copies every vessel-plan row into a booking (all day, kind run, the order as subject, role kept; rows of cancelled orders arrive cancelled), drops the table and recreates the name as a view with the same six columns over booked vessel bookings of production orders. `find_production_order_vessels`, `find_vessel_conflicts`, `find_calendar_rows` and the records MCP's `PRODUCTION_ORDERS` query run unchanged (proven) |
| `app.v_equipment_resources` | view | Vessels and equipment as one list: `resource_kind`, `resource_id`, `name`, `kind`, `premises_id`, `location_id`, `status`, `capacity_l` (NULL for equipment), `active`, `sort_group` (vessels by kind first, equipment after) |
| `app.v_equipment_schedule` | view | Every booked reservation with its resource (`resource_name`, `resource_type`, `resource_status`, `capacity_l`), its run (`subject_number`, `subject_label` — the product for an order or batch, "Press run", the format for a packaging run — and `subject_status`), `local_from`/`local_to` (calendar days in the business's zone) and `clash_count` (other booked bookings on the resource whose window overlaps) |
| `app.equipment_clashes(resource_kind, resource_id, starts_at, ends_at, exclude_id)` | function | The booked bookings on that resource overlapping the window, each with its run; `exclude_id` leaves out the booking being edited; a run that is itself cancelled is left out. The handler, the form and the MCP tool all use it |
| `client_settings.settings.equipment.double_booking` | jsonb key | `refuse` or `allow`. The migration writes `allow` and marks the rows `shared` when overlapping vessel plans of live orders already exist (the old rule allowed them with a warning), else `refuse`. It never overwrites a key already there |
| `db/020_grants.sql` | appended | `EXECUTE` on `equipment_clashes` and `client_timezone` for `cidery_records_ro`; the views and tables get `SELECT` through the existing blanket grant |

**Rules the schema enforces** (the table, the trigger, the checks): a run has a subject and a block has none; a subject
names a row that exists; the window is non-empty and half-open (a booking that starts the day another ends does not
clash); a cancelled booking carries when it was cancelled; equipment is unique by name per premises and has a known
kind. **What it leaves to the application:** whether a clash is refused or shared (the policy), the capacity warning,
the out-of-service shading, the cascades on cancel and close (D10), who may book (section 7).

**Time:** a booking is stored as two instants. The form takes a from date and a to date (inclusive, as the vessel plan
did) and, with "All day" off, a start and an end time; the handler builds `starts_at` = from 00:00 (or the start time)
and `ends_at` = the day after to at 00:00 (or the end time) in `client_settings.timezone`. The views give the calendar
days back the same way, so a booking's days never drift across a time zone or a daylight change.

## 2. Status vocabulary (locked colours)

| Entity | success | warning | danger | info | secondary | dark |
|---|---|---|---|---|---|---|
| Equipment status | available | cleaning | out_of_service | — | — | — |
| Vessel status (unchanged) | empty | — | out_of_service | cleaning | in_use | — |
| Booking (bar or chip) | — | a bar that overlaps another or is shared: edged warning | on a resource out of service: edged danger | cleaning block | maintenance block | hold |
| Reservation status | — | — | cancelled | booked | — | — |
| Booking of a run | the run's own status colour: `production_order_status_color()` for an order, the batch, press-run and packaging-run colours for theirs | | | | | |

A bar's text is the run's number, product and role ("WO-00012 · Dry · Primary"); a block's is its kind and note; a timed
booking carries a clock; a bar that runs on past the window has a dashed end. What a vessel holds right now shows as an
info badge ("Now: B-26-004") under its name. (Built 2026-10-08: the equipment status colours follow the locked vocabulary,
where cleaning is warning; the plan's "cleaning = info" was wrong.)

## 3. Screen registry (new and changed)

| Screen id | URL | Title | When the user wants to… | Prefill |
|---|---|---|---|---|
| `equipment-schedule` | `/schedule/` | Equipment schedule | see what is booked on every tank, press, line and piece of equipment, day by day, and spot clashes; `?view=month` for the month grid | `from` (any date; the window starts on its Monday), `weeks` (1, 2, 4, 8, 12), `view`, `month`, `premises_id`, `kind` (vessel, equipment, or a vessel or equipment kind), `resource` (vessel:12), `subject` (batch:4 — one run's bookings) |
| `reservation-add` | `/reservations/new` | Reserve equipment | book a resource for a run or block it for cleaning, maintenance or a hold | `resource` (vessel:ID or equipment:ID), `on`, `subject_kind`, `subject_id`, `kind` |
| `reservation-edit` | `/reservations/{id}/edit` | Reservation | change a booking's window, role, resource or notes | |
| `reservation-view` | `/reservations/{id}` | Reservation | see a booking — its resource, window, run, who booked it — and cancel it | |
| `equipment-list` | `/equipment/` | Equipment | see the mills, pumps, filters, lines and other equipment, their status and next booking (cards) | |
| `equipment-add` / `equipment-edit` | `/equipment/new`, `/equipment/{id}/edit` | Equipment | add or change a piece of equipment, set its status | `name`, `kind` |
| `equipment-view` | `/equipment/{id}` | Equipment | see a piece of equipment and its upcoming and past bookings | |
| `settings-client` | `/settings/client` | Organization settings | gains "Equipment may be double-booked" | |
| `production-order-add` / `-edit` | existing | | the "Vessel plan" rows are the **Equipment plan**: resource grouped Vessels / Equipment, role by resource kind, from, to, optional times | |
| `production-order-view` | existing | | cards in order: Equipment plan, Inputs (the material check), Processing time, Outputs — section 6 | |
| `production-calendar` | `/production-orders/calendar` | (redirect) | 301 to `/schedule/?kind=vessel`; the nav item "Vessel calendar" is replaced by "Equipment schedule" | |

Navigation: Production → Production orders, **Equipment schedule**, Press runs, Tank board, Batches. Setup → … Vessels,
**Equipment**, Items ….

## 4. Action registry (new and changed)

| Action | Endpoint | Parameters | Undo | Approval | Roles |
|---|---|---|---|---|---|
| `equipment_create` / `equipment_update` | `POST /equipment/save` | name, kind, premises, location?, rating?, status?, notes?, active? | delete_row / restore_prior | no | production |
| `equipment_set_status` | `POST /equipment/{id}/status` | status (available, cleaning, out_of_service) | restore_prior | no | production |
| `equipment_reserve` | `POST /reservations/save` | the form sends resource (vessel:12 / equipment:3), kind, subject_kind + subject_id, role, planned_from, planned_to, all_day, start_time, end_time, share, notes; the kernel's actions server sends ids by name instead — vessel or equipment, order / batch / press_run / packaging_run or block, from, to, start_time, end_time (nothing = all day), share, notes — and the handler reads both | delete_row (cancels) | no | production |
| `equipment_reservation_update` | `POST /reservations/save` | id + the same | restore_prior | no | production |
| `equipment_reservation_cancel` | `POST /reservations/{id}/cancel` | — | restore_prior | no | production |
| `production_order_create` / `_update` | existing | `vessels[]` as today; gains `equipment[]` (resource, role, from, to) | as today | no | production |
| `client_settings_update` | existing `POST /settings/client-save` | gains `equipment_double_booking` (off, on) | restore_prior | no | owner |

**The clash rule, in the handler** (`/reservations/save` and the order's save, one function `reservation_clashes()`):
`equipment_clashes()` for the row's resource and window, excluding the row itself. Any clash under `refuse` → 422 with
the clashes listed under the dates ("FV-2 is booked for WO-00012 · Dry · Primary, Nov 10 – Nov 20"). Under `allow` →
the same 422 unless `share` was sent for that row, in which case the row saves with `shared = true` and the activity
details carry `shared: true` and the clashing numbers. The order form renders the clashes and the "Book anyway (shared
use)" checkbox per row from the same 422 data, as it renders the capacity warning today.

**Cascades (D10):** `production_order_cancel`, `press_run_cancel` and `packaging_run_cancel` cancel the run's booked
reservations (each logged as `equipment_reservation_cancelled` with `cause: run_cancelled`); `production_order_close`
trims a booked reservation that is still running to now and cancels one that has not started.

## 5. Activity log event names (new)

`equipment_created`, `equipment_updated`, `equipment_status_set`, `equipment_reserved` (details: resource, window,
run, role, `shared`, clashes), `equipment_reservation_updated`, `equipment_reservation_cancelled` (`cause`: person,
run_cancelled, run_closed), `screen_entered` on `equipment-schedule` with the window and filters. `client_settings_updated`
is unchanged and its details show the switch.

## 6. The production order as a run

| Card | Reads | Shows |
|---|---|---|
| Equipment plan | `v_equipment_schedule` for the order, `equipment_clashes` per row, the open occupancy of each vessel | resource, role, from, to (times when not all day), days, capacity, clashes (shared bookings by number; an occupant that is not this order's batch); Reserve button → `/reservations/new?subject_kind=production_order&subject_id=` |
| Inputs | the existing material check and allocations; `consumptions` of the order's batches | unchanged tables; after a batch is pitched a "Consumed so far" line per item, linking to the batch |
| Processing time | `recipe_stages` of the order's recipe version; `stage_events` of its batches; the order's dates | one row per stage: expected days, planned start and end rolled forward from `planned_pitch_on` (days only when there is no pitch date), the batch's actual entry and exit with the variance in days; footer: planned total days, planned package date, elapsed days; each equipment-plan row shown against the stage its role covers |
| Outputs | `planned_volume_l`, `recipe_versions.expected_total_loss_pct`, `production_order_packages`, the order's `batches`, their `packaging_runs` and `finished_lots` with `v_finished_stock` | planned: volume, expected packaged volume, planned packages (format, units or share, the customer order line); actual: batches (number, stage, volume), packaging runs (number, format, units out, loss), finished lots (units on hand) — every number a link |

## 7. Roles

| Action | Roles |
|---|---|
| See the schedule, equipment, reservations | every role |
| Reserve, change, cancel; block equipment | owner, production |
| Add or change equipment, set its status | owner, production |
| The double-booking switch | owner (the application's admin role under the OS) |

## 8. The proof (`scripts/prove-equipment-schedule.sh`)

The scratch copy is `cidery_prove_023`, made with `pg_dump -n app` over a fresh `maludb_core` extension (a template
copy needs the source idle and the full dump collides with the extension's seed rows). The seed
(`prove-equipment-schedule-seed.sql`) adds a cellar, three vessels, a product and recipe, and four orders with five
vessel-plan rows — A and B overlapping on FV-A, C cancelled and overlapping A, D alone — and keeps the plan aside in
`app.prove_before`. The 39 checks (`prove-equipment-schedule.sql`):

1. the old name is a view with the six columns in order;
2. live plans migrate row for row; the view holds four rows; the cancelled order's row arrived cancelled; migrated bookings are all-day vessel runs of their order starting and ending at local midnight;
3. the switch starts on because live plans overlapped, and exactly the two overlapping rows are marked shared;
4. the three readers' SQL (`find_vessel_conflicts`, `find_calendar_rows`, the MCP's vessels aggregate) returns what it did against the table;
5. `equipment_clashes` finds both A and B on a shared day, leaves out the excluded booking, ignores the cancelled order, finds nothing after every booking, and treats the window as half-open;
6. equipment lists after vessels with no capacity; two timed runs on one line (morning, afternoon) do not clash and one across lunch clashes with both; the schedule names a batch, its product and the local day; a cleaning block has no subject, appears on the schedule and in the clashes;
7. nine refusals — a run without a subject, a block with one, an empty window, a vessel, equipment or run that does not exist, cancelled without a time, an unknown equipment kind, a duplicate name;
8. cancelling a booking takes it out of the view, the schedule and the clashes; the touch trigger moves `updated_at`;
9. `cidery_records_ro` reads both views and calls both functions and cannot insert; with no live overlap the policy derivation says refuse.

## 9. Open points

None. Two notes for the build: a cancelled order's old vessel rows are no longer on its view (they arrive cancelled);
the live database holds no vessel plans today, so the live migration moves nothing and writes `refuse`.
