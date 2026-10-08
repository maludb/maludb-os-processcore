# Equipment scheduling: plan

**Date:** 2026-10-08
**Status:** APPROVED 2026-10-08 — the owner took every recommendation of section 10 (D1–D13). Step 1 is built the same day: [16-equipment-schedule-design.md](16-equipment-schedule-design.md) and `db/023_equipment_schedule.sql`, proven by `scripts/prove-equipment-schedule.sh` (39 checks). Steps 2–7 BUILT the same day: [17-equipment-schedule-progress.md](17-equipment-schedule-progress.md) is the record. Follows
the customer-orders pattern ([11](11-customer-orders-plan.md) plan → [12](12-customer-orders-design.md) design with the
schema file → [13](13-customer-orders-progress.md) steps): when the answers are in, the design doc and
`db/023_equipment_schedule.sql` come next, proven before a screen is written.

**The ask (2026-10-08):** during production we need a way to schedule and reserve equipment; a calendar that is easy to
read shows when equipment is scheduled; a reservation can span several days (a fermenter); two production runs may be
booked on the same equipment at the same time when the administrator allows it; a new sub-menu item under Production;
clicking a scheduled run shows its details — the inputs, the processing time and the outputs.

## 1. Goal

Plan the cidery's equipment the way it plans its materials: every run that needs a tank, a press, a pump, a filter or
the canning line books it for a window, the schedule shows at a glance what is booked and what is free, a clash is
refused or knowingly shared according to one organization setting, and a booking leads straight to the run behind it.

## 2. What exists today, and what the ask changes

| Today | Where | What the ask adds or changes |
|---|---|---|
| A production order plans **vessels** only: `production_order_vessels` (vessel, role, `planned_from`, `planned_to`, dates) | `db/008`, the order form's repeating "Vessel plan" rows, the order view's "Vessel plan" card | Equipment that holds no liquid (mill, pump, filter, chiller, carbonator, canning or bottling line, keg line, keg washer, labeler) can be booked too; a booking can carry a time of day |
| Overlapping vessel plans **warn and never block** (comment in `db/008`; `find_vessel_conflicts`) | order view, calendar | A policy: refused by default, allowed with a visible warning when the administrator turns sharing on |
| **Vessel calendar** `/production-orders/calendar`: vessels × weeks, a badge per order, shaded cells for conflicts | Production → Vessel calendar | A proper schedule: resources × days with bars that span their window, a month view, filters, one click to the run; it replaces the Vessel calendar |
| Only a **production order** can plan a vessel. Press runs name their press and packaging runs their source vessel only when they are recorded | press runs, packaging runs, batches | A press day, a canning day, a batch without an order and a cleaning or maintenance block can be booked |
| Actual use is `vessel_occupancies` (one open occupant per vessel), written when a batch is pitched, transferred, packaged | execution handlers | Unchanged: the schedule shows the occupant over the plan, as the calendar does today |
| The recipe carries **processing time**: `recipe_stages.expected_duration_days` per stage; `production_batches_in_progress` already estimates a ready date from it | `db/007`, records MCP | The production order view shows it: a stage timeline from the pitch date, planned beside actual |
| The order view shows **inputs** (the material check: recipe lines × volume, picks, shortfall; allocations once released) but no **outputs** | order view | An Outputs card: planned volume and planned packages (`production_order_packages`), then the batches, packaging runs and finished lots that came out |
| One organization switch already lives in `client_settings.settings` (`require_batch_release`) | `db/004`, packaging post | The double-booking switch lives beside it and gets a field on the Organization settings screen |
| Presses are **vessels** of kind `press` (press runs reference `vessels`) | `db/004`, press runs | Unchanged: a press stays a vessel; the equipment table is for kinds that hold nothing |

## 3. How it fits the model

```
resource     = a vessel (tank, fermenter, brite, tote, IBC, barrel, press)         ← app.vessels, unchanged
             | a piece of equipment (mill, pump, filter, chiller, carbonator,
               canning line, bottling line, keg line, keg washer, labeler, other)   ← app.equipment, new
reservation  = one resource × one window [starts_at, ends_at) — all day by default, timed when it matters
               for a RUN  (production order | batch | press run | packaging run)
               or a BLOCK (cleaning | maintenance | hold), which has no run
policy       = client_settings.settings.equipment.double_booking: refuse (default) | allow
               refuse: a window that overlaps a booked reservation on the same resource is refused, clashes listed
               allow : the same save goes through when the person ticks "Book anyway"; the booking is marked shared
schedule     = resources × days, a bar per reservation (timeline); chips per day (month); the occupant over the plan
run details  = the run's own page — a production order shows Inputs, Processing time, Outputs
```

The vessel plan does not become a second thing: `production_order_vessels` rows are moved into the reservations table
and the old name becomes a view over them, so every reader keeps working and there is one table of bookings
(decision D2). Nothing in the ledger, occupancy, tax or TTB logic changes. A reservation is a plan; what actually
happened stays in occupancies, press runs and packaging runs.

## 4. Schema (`db/023_equipment_schedule.sql`)

| Object | Kind | Notes |
|---|---|---|
| `app.equipment` | table | `premises_id`, `location_id` (optional; the cellar or packaging area it stands in), `name` (unique per premises), `kind` ∈ mill, pump, filter, chiller, carbonator, canning_line, bottling_line, keg_line, keg_washer, labeler, other (**not** press — a press is a vessel), `status` ∈ available, cleaning, out_of_service, `rating` (free text such as "120 cans/min", "4,000 L/h"), `notes`, `active`, timestamps, touch trigger |
| `app.equipment_reservations` | table | `resource_kind` ∈ vessel, equipment + `resource_id` (the polymorphic pair the schema already uses for readings, losses, occupancies); `kind` ∈ run, cleaning, maintenance, hold; `subject_kind` ∈ production_order, batch, press_run, packaging_run + `subject_id` — required when `kind = 'run'`, forbidden otherwise; `role` ∈ primary, maturation, brite, blend (vessels, as today), press, mill, transfer, filter, carbonate, package, other; `starts_at`, `ends_at` timestamptz with `ends_at > starts_at`; `all_day` (an all-day booking runs from 00:00 on its first day to 00:00 after its last, in the business's time zone); `shared` (saved over a clash under the allow policy); `status` ∈ booked, cancelled; `notes`; `created_by`, `cancelled_by`, `cancelled_at`, timestamps |
| index | GiST | `(resource_kind, resource_id, tstzrange(starts_at, ends_at))` where `status = 'booked'` — the clash query and the schedule window read it. No exclusion constraint: whether a clash is allowed is the policy's call, not the table's |
| `app.equipment_clashes(resource_kind, resource_id, starts_at, ends_at, exclude_id)` | function | The booked reservations on that resource whose window overlaps, with their subject's number and label. The handler, the view and the MCP tool all use it |
| `app.v_equipment_resources` | view | Vessels and equipment as one list: `resource_kind`, `resource_id`, `name`, `kind`, `premises_id`, `location_id`, `status`, `capacity_l` (vessels), `active`, a sort key (vessels by kind then name, equipment after) |
| `app.v_equipment_schedule` | view | Every booked reservation with its resource and its subject: number, label (product for an order or batch, format for a packaging run), the subject's status, the clash count, `shared` |
| `app.production_order_vessels` | **view** (was a table) | The migration copies every row into `equipment_reservations` (vessel, kind run, subject the order, role kept, all day from `planned_from` to the day after `planned_to`), drops the table and creates a view with the same six columns (`id`, `production_order_id`, `vessel_id`, `role`, `planned_from`, `planned_to`) over booked vessel reservations of production orders. Readers (`find_production_order_vessels`, `find_vessel_conflicts`, `find_calendar_rows`, the records MCP's `PRODUCTION_ORDERS` query) keep working; the one writer, `replace_production_order_vessels`, is rewritten to write reservations |
| `client_settings.settings` | jsonb key | `equipment.double_booking` = `refuse` or `allow`. The migration writes `allow` when overlapping vessel plans already exist in the data, so nothing already planned becomes a clash that cannot be saved; otherwise `refuse` |
| `db/020_grants.sql` | re-run | `cidery_app` read-write on the two tables; `cidery_records_ro` on the views and the function |

The cidery's rule (one new numbered file, never edit an applied one; `deploy/os-provision.sh` and
`deploy/provision-client.sh` apply what is new) holds. Turning a table into a view in a new migration is within it;
the alternative — keeping the old table and mirroring it by trigger — is listed under D2 and not recommended.

## 5. The double-booking rule

- **The setting** is on the Organization settings screen (`/settings/client`, owner only in the standalone product; under
  the Business OS, whoever holds the application's admin role — roles come from the kernel): "Equipment may be
  double-booked" off or on. Reading it is one query, cached per request like `client_settings()`.
- **Off (refuse):** saving a reservation whose window overlaps a booked one on the same resource is refused with a 422
  that names the clashes ("FV-2 is booked for WO-00012 Primary, Jun 3–Jun 17"). The order form shows the clash under
  the row, as the capacity warning shows today.
- **On (allow):** the same save shows the clashes and a checkbox "Book anyway (shared use)" per clashing row; ticked, the
  reservation saves with `shared = true` and the activity row carries `shared: true` and the clashing numbers. Unticked,
  it is refused as above. Nothing is ever double-booked silently.
- **Changing the setting from on to off** does not touch existing shared bookings; they stay, marked shared, and the
  schedule still shades them. A later edit of one of them must resolve the clash or be refused.
- **Actual occupancy** is not a clash: a vessel holding a batch of the same production order is what the plan intended;
  a vessel holding something else during a booked window is shown as a warning on the schedule and the order view, as
  today, and never blocks (the vessel may well be empty by then).
- **Capacity:** a vessel booked for a production order whose planned volume exceeds the vessel's capacity warns and
  never blocks, exactly as the vessel plan does today.
- **A resource out of service** cannot be booked for a window inside its out-of-service state; the status change itself
  does not cancel bookings but the schedule shades them red and lists them on the status change's confirmation.

## 6. Screens

| Screen id | URL | Nav | What it shows |
|---|---|---|---|
| `equipment-schedule` | `/schedule/` | Production → **Equipment schedule** (directly under Production orders; replaces Vessel calendar) | **Timeline** (default): one row per resource (grouped Vessels then Equipment, filterable by premises, kind, one resource), one column per day over the window (default the Monday of this week + 4 weeks; 1 to 12 weeks), a bar per booked reservation spanning its days with the run's number, product and role; two reservations that overlap on one resource take two lanes and the shared days are amber; a cancelled run's leftover booking is grey; today is marked; the current occupant appears as a small badge on today's cell when it differs from the plan. **Month** (`?view=month`): the projected-receipts grid, a chip per reservation on every day it covers with a continuation mark, filtered the same way. Both navigate by HTMX partial swaps with `hx-push-url`; at 375px the timeline scrolls sideways with the resource column sticky. Header buttons: Reserve, Equipment (Setup), Production orders |
| `reservation-add` / `reservation-edit` | `/reservations/new`, `/reservations/{id}/edit` | from the schedule (Reserve; a free cell's "+"), from a run's page | Full-page form (no modals): resource (one select grouped Vessels / Equipment), kind (run / cleaning / maintenance / hold), the run (a search-as-you-type picker over production orders, batches, press runs and packaging runs — shown only for kind run), role, from and to dates, "All day" on by default and, off, a start and end time, notes. Prefill: `resource`, `on`, `subject_kind`, `subject_id`. Clashes render under the dates after a save attempt; "Book anyway" appears only under the allow policy |
| `reservation-view` | `/reservations/{id}` | a bar or chip with no run (a block), the schedule's list | The reservation, its resource, its window, who booked it, cancel |
| `equipment-list` | `/equipment/` | Setup → **Equipment** (after Vessels) | Cards per the owner's preference for lists of named things: name, kind, premises, status, next booking; filters by premises, kind, status |
| `equipment-add` / `equipment-edit` | `/equipment/new`, `/equipment/{id}/edit` | | Premises, location (optional), name, kind, rating, status, notes, active. A status change to out of service lists the bookings it affects |
| `equipment-view` | `/equipment/{id}` | a card | The equipment and its upcoming and past bookings |
| `settings-client` | `/settings/client` | existing | Gains "Equipment may be double-booked" |
| `production-order-add` / `-edit` | existing | | The "Vessel plan" rows become the **Equipment plan**: the resource select is grouped Vessels / Equipment, the role list follows the resource kind, from and to as today, an optional time pair per row (collapsed when all day) |
| `production-order-view` | existing | | See section 7 |
| `/production-orders/calendar` | redirect | | 301 to `/schedule/?kind=vessel` |

A bar or chip is a link to its run's page (`nav_attrs`), so one click from the schedule lands on the production order,
batch, press run or packaging run; a block opens the reservation. Every run's page gets a "Schedule" button back to the
timeline focused on its first resource and week.

## 7. The production order as a run: inputs, processing time, outputs

The order view is rearranged so the three questions are answered in order, each a card:

1. **Equipment plan** (was Vessel plan): resource, role, from, to (and times), duration in days, capacity, clashes
   (shared bookings named, actual occupant named), a Reserve button that opens the reservation form prefilled with
   the order.
2. **Inputs** — the existing Material check card (recipe lines × planned volume, where to pick, available, allocated
   elsewhere, on order, shortfall), then Allocations once released; once a batch is pitched, a line "Consumed so far"
   per item from the batch's consumptions, linking to the batch.
3. **Processing time** — the recipe version's stages in sequence: stage, expected days, instructions, a planned start and
   end rolled forward from the planned pitch date (an order with no pitch date shows days only), and, for each stage a
   linked batch has entered, the actual entry and exit from `stage_events` with the variance in days. The footer gives
   planned total days, the planned package date, and the elapsed days to date. The equipment plan's windows are shown
   against the stages they cover (a primary booking against the primary stage) so a too-short booking is visible.
4. **Outputs** — planned: volume, less the recipe's expected total loss → expected packaged volume; the planned packages
   (`production_order_packages`: format, units or share, the customer order line when there is one). Actual: the
   batches of the order (number, stage, current volume), their packaging runs (number, format, units out, loss) and the
   finished lots with units on hand, each a link. Nothing here changes a figure anywhere else; it reads what the batch,
   packaging and finished-lot slices already keep.

Press runs, batches and packaging runs already show their inputs and outputs on their own pages (fruit in → juice and
pomace out; consumptions, stage history, lineage; volume in → units out). They get the Schedule button and nothing
else.

## 8. Roles

| Action | Roles |
|---|---|
| See the schedule, equipment, reservations | every role (viewer read only) |
| Reserve, change, cancel a reservation; block equipment for cleaning or maintenance | owner, production |
| Add or change equipment, set its status | owner, production (as vessels today) |
| Turn double-booking on or off | owner (the application's admin role under the OS) |

## 9. Assistant

**Records MCP** (`services/records_mcp/tools_production.py`, read-only):

| Tool | Answers |
|---|---|
| `equipment_schedule` | What is booked on which equipment, when, for which run: filters resource, kind, premises, a window (default this week + 4), a run; each booking with its subject, role, window, shared flag and clashes |
| `equipment_free` | When is a resource (or any resource of a kind, with at least a given capacity) free for N days inside a window — the question behind "where can I ferment 500 gallons for two weeks starting Monday" |
| `find_equipment` | Resolver over vessels and equipment by name (candidates carry the kind and status) |
| `production_orders_by_status` | Gains the order's equipment rows (today it lists vessels only, through the view) |

**Actions MCP** (manifest `docs/05-action-manifest.md` → `build_manifest.py` and `bin/build_action_registry.php`, both
outputs committed):

| Action | Endpoint | Parameters | Undo | Roles |
|---|---|---|---|---|
| `equipment_create` / `_update` | `POST /equipment/save` | name, kind, premises, location?, rating?, status?, notes? | delete_row / restore_prior | production |
| `equipment_set_status` | `POST /equipment/{id}/status` | status | restore_prior | production |
| `equipment_reserve` | `POST /reservations/save` | resource, kind, run? (order, batch, press_run or packaging_run), role?, from, to, start_time?, end_time?, share? (book over a clash when the policy allows), notes? | delete_row | production |
| `equipment_reservation_update` | `POST /reservations/save` | id + the same | restore_prior | production |
| `equipment_reservation_cancel` | `POST /reservations/{id}/cancel` | — | restore_prior | production |
| `production_order_create` / `_update` | existing | `vessels[]` stays; gains `equipment[]` (resource, role, from, to) | as today | production |

No approval category: no money and no deletion (a cancelled reservation stays). `maludb-os.json` grants the expert the
new tools; `os/expert.md` and `skills/cidery-basics` gain the vocabulary (equipment, reservation, the schedule) and the
rows "What is booked on the canning line / when is FV-3 free → `equipment_schedule`, `equipment_free`".

**Activity events:** `equipment_created`, `equipment_updated`, `equipment_status_set`, `equipment_reserved` (details:
resource, window, subject, `shared`, the clashing numbers), `equipment_reservation_updated`,
`equipment_reservation_cancelled`, `client_settings_updated` (existing; the details show the switch), and
`screen_entered` on the schedule with the window and filters.

**Business OS:** nothing in the kernel changes. After the build the owner re-runs the installer's apply (or
`bos-app.sh update` under Docker) so the kernel's registry and the expert's grants pick up the new actions; the new
migration applies through `deploy/os-provision.sh` as every file does.

## 10. Owner decisions

Each line is a recommendation; "the rest" below means every line not answered otherwise.

| # | Question | Recommendation | The alternative |
|---|---|---|---|
| D1 | What is equipment? | A new `equipment` table for what holds no liquid (mill, pump, filter, chiller, carbonator, canning/bottling/keg line, keg washer, labeler, other). Vessels stay vessels; a press stays a vessel | Widen `vessels.kind` and make capacity optional — every tank query, the board and occupancy would have to learn to skip them |
| D2 | One table of bookings | `production_order_vessels` is migrated into `equipment_reservations` and kept as a view of the same shape; one writer changes | Keep both tables and mirror by trigger — two sources of truth for a vessel booking |
| D3 | What can hold a reservation? | A production order, a batch, a press run, a packaging run, or a block (cleaning, maintenance, hold) with no run | Production orders only — then a press day, a canning day for an orderless batch and a cleaning block cannot be on the calendar |
| D4 | Time of day? | Timestamps with "all day" the default; a time pair when two runs share a day on the canning line or the press | Dates only — then two half-day runs on one line are always a clash and the administrator would turn sharing on to silence it |
| D5 | Where does "the administrator allows it" live? | One organization setting, off by default; the migration turns it on only when overlapping vessel plans already exist | Per-resource flag (a fermenter never, a press sometimes) — can be added later on top of the switch; or both at once |
| D6 | How is a shared booking made? | Under the allow policy the person ticks "Book anyway" per clash; it saves marked shared and is logged with the clashing numbers | Allow saves silently with a warning shown afterwards |
| D7 | Which views? | Timeline (resources × days, bars) as the default and a month grid; the Vessel calendar item goes and its URL redirects | Keep the weekly Vessel calendar beside the new schedule |
| D8 | Navigation | Production → Equipment schedule, second item; Setup → Equipment, after Vessels | Equipment under Production too |
| D9 | Run details | Three cards on the production order view — Inputs (the material check), Processing time (recipe stages, planned vs actual), Outputs (planned packages, batches, runs, finished lots); other runs open their own pages | A separate run-summary page reached from the schedule |
| D10 | What happens to bookings when the run ends? | Cancelling an order, press run or packaging run cancels its booked reservations; closing an order trims bookings still running to now; posting leaves the booking as the record | Leave bookings alone until a person cancels them |
| D11 | Prefill the booking's end from the recipe's stage days? | Not in this version; listed under later work | Prefill `to` = `from` + the stage days for the row's role |
| D12 | Roles | As section 8 | — |
| D13 | Where is the schema proven? | The only cidery database on this host is `subello_cidery` (the live install). The schema is proven on a scratch database restored from it and dropped afterwards, never on the live one; the live apply is the owner's | — |

## 11. Build order

| Step | Work | Proof |
|---|---|---|
| 0 | This plan, the owner's answers in section 10 | — |
| 1 | `docs/16-equipment-schedule-design.md` (schema summary, status colours, screen and action registries, events, tools — merged into 04 and 05 when approved) and `db/023_equipment_schedule.sql` | Applied to a scratch copy of the database: the vessel plans migrate row for row, the view returns what the table did, `equipment_clashes` finds overlaps and ignores cancelled rows and the excluded id; dropped afterwards |
| 2 | Setup → Equipment: list, form, view, status; `find_equipment` in both resolvers | Conformance on `equipment`; HTTP as production and as viewer (403) |
| 3 | Reservations: the form, save with the clash rule and the setting, cancel; the Organization setting; the production order form and view write and read reservations (Equipment plan); cascades on cancel and close | The 422 with clashes under refuse; the shared save under allow with its activity row; an order's rows round-trip through edit; cancel cascades |
| 4 | The schedule screen: timeline and month, filters, lanes and shading, the occupant badge, `hx-push-url`; the nav item; the redirect; Schedule buttons on run pages | 375px sweep; a 12-week window renders under 300 ms on the live-sized data |
| 5 | The production order view: Processing time and Outputs cards; Inputs gains "Consumed so far" | An order with a pitched batch shows planned vs actual per stage; an order with planned packages shows them with their order lines |
| 6 | Assistant: `equipment_schedule`, `equipment_free`, `find_equipment`; the five actions; manifest + both registries; expert grants; `expert.md` and the basics skill | `records_mcp.test_client --suite`; the actions server's catalog loads; the kernel's `application_actions.py` reads the registry clean |
| 7 | Full test pass, `docs/17-equipment-schedule-progress.md`, commit | `scripts/conformance.sh`; the OS-adoption proofs re-run where touched |

Then the owner's: the live migration through the installer's apply (or `bos-app.sh update`), the equipment entered,
the switch set.

## 12. What does not change

The ledger, occupancies, press and packaging posting, allocations, costing, quality, removals and TTB reporting. A
reservation never moves liquid and is never a tax event. The batch release gate is untouched. Standalone and
OS-adopted installs get the same screens; under the OS, roles still come from the kernel's directory.

## 13. Later, in no fixed order

Per-resource sharing rules on top of the switch (D5); the booking's end prefilled from the recipe (D11); a booking
proposed automatically when a production order is created from the projections; a resource's cleaning block inserted
automatically after a run ends; drag to move a bar on the timeline (the Tank view's drag-to-place pattern); the
schedule as a card on the dashboard ("booked today"); maintenance history per piece of equipment.
