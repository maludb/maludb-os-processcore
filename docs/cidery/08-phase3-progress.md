# Phase 3 progress

Slice order and builders per `docs/03-phase0-plan.md` section 4. Every slice passes `scripts/conformance.sh`, curl tests of its screens and actions, and the 375px sweep before it counts as done.

| # | Slice | Builder | Status | Notes |
|---|---|---|---|---|
| 1 | Foundation | Planning model (premises reference) + three worker agents | Done 2026-10-01 | Decisions below |
| 2 | Receiving (exemplar) | Planning model | Done 2026-10-01 | Purchase orders, receipts with weigh tags, posting, putaway, lots with attributes, certificates, release decisions; supplier Orders and Performance tabs |
| 3 | Inventory | Worker | Done 2026-10-01 | Balances, movements, reorder, transfers, adjustments with approval, counts; reversal endpoints for all three; lot Movements and item Stock tabs |
| 4 | Products and recipes | Worker | Done 2026-10-01 | Products, recipe versions (editor, scale, diff, activate), packaging configs with BOM, specs, standard costs and overhead, approvals with documents |
| 5 | Production orders | Worker | Done 2026-10-01 | Orders with vessel plans and overlap warnings, material check net of other orders' soft allocations, release/close/cancel, vessel calendar |
| 6 | Batch execution | Planning-class agent | Done 2026-10-01 | Press runs, tank board, batches (pitch, readings, additions, stage moves, transfers, splits, blends, losses with approval, dump, yeast harvest), pomace dispositions; batch view carries the Package and Release buttons |
| 7 | Packaging | Worker | Done 2026-10-01 | Packaging runs with materials, release gate, reversal; finished lots with tax class check and override; keg register, state changes, fill, return |
| 8 | Quality | Worker | Done 2026-10-01 | Lab readings (spec result from the trigger), sensory records, release queue, batch release at /releases/batch (route /batches/{id}/release added at integration) |
| 9 | Reports | Worker | Done 2026-10-01 | Yields, juice yield, batch costs, valuation (current and as-of); CSV at /reports/{name}/csv |
| 10 | Removals and compliance | Planning-class agent | Done 2026-10-01 | Customers, removals and returns with tax determination and keg shipping, reversal, 5120.17 generation with drill-down, finalize and file, trace forward and backward |

## Decisions recorded during slices 1 and 2

- **No `saved.php`.** Saves flash and navigate with `HX-Location` (conventions doc).
- **Router.** Nested routes map to `{a}-{b}.php`; POSTs prefer `{verb}-save.php` (conventions doc).
- **Vessel form:** one location select grouped by premises (no client script); the server rejects a location from another premises. In-use vessels keep `in_use` on edit; the status endpoint returns 409 for them. No list UI calls the status endpoint yet (slice 6's tank board will).
- **Users:** role changes after creation go through the separate confirm-guarded role endpoint; disabling a user also expires their pending invite and reset tokens; the last active owner can be neither demoted nor disabled; activity rows for users carry only id, email, name, role and status.
- **Reason codes:** the approval threshold label switches between gallons and "item base unit" with a small `hx-on:change` handler.
- **Items:** item-unit factors are entered in base units (1 bin = 360 kg); several units may be marked purchase default; supplier-item factors default on the server from the chosen unit.
- **Receipts:** fruit and catch-weight lines are received by weigh tag (pounds in, kilograms stored); the count field is optional for them; `unit_cost_base` is the line cost divided by the net base quantity, so a fruit line priced per bin or bushel still costs per kilogram. A receipt that selects a purchase order takes the order's supplier. `insert_lot` and `set_lot_attribute` live in `app/features/lots/queries.php` (the lot owner); receipts require that file.
- **Lots:** a certificate file is served by `/lots/{id}/coa-file?attachment_id=` (not in the spec; needed to open the document) and only for attachments of that lot. Release decisions confirm with `hx-confirm` on every submission because a release changes what production may use.
- **Mobile:** all 36 slice 1 and 2 screens pass the 375px sweep (no horizontal scroll, no console errors).

## Decisions recorded during slices 3 and 4

- **Reversal** (the manifest's undo for posted transfers, adjustments and count approvals): `POST /{feature}/{id}/reverse` writes one compensating `reversal` row per original ledger row (`reverses_id` set, same TTB category, negated quantity) in one group, sets the document to `cancelled`, and logs `{entity}_reversed`. The ledger triggers still apply, so stock already consumed blocks the reversal. Helper `reverse_document_ledger()` in `app/features/inventory/ledger.php`; later posting slices reuse it.
- **Adjustment TTB category:** a negative delta carries the reason's loss category; a positive delta carries `inventory_gain` only when the reason has a TTB category.
- **Adjustments above a reason's threshold** save as `pending_approval`; owner approval returns them to draft; editing clears the approval; the threshold is re-checked at posting.
- **Transfers** offer only released lots and only destinations with the same tax state.
- **Counts** correct against the quantity expected when the count started.
- **Recipes:** fixed-per-batch lines never scale; per-volume lines scale. The editor saves stages and lines in one form (the PO pattern) and logs one `recipe_version_updated`. Diff matches lines on item, stage and purpose. The standard-cost snapshot uses the overhead rate of the lowest-id active premises matching the beverage, and materials at standard cost or the latest lot cost.
- **Approval statuses** (`not_required`, `required`, `submitted`, `expired`) were added to the shared color vocabulary; approval documents download from `/approvals/{id}/file`.
- **Purchase orders** accept `?item=CODE` to pre-fill the first line (used by the reorder report).

## Decisions recorded during slice 5

- **Allocations are soft** (item level, `lot_id` NULL) and never touch `inventory_balances`. The material check's available figure is released-lot stock minus open allocations of other orders (`production_item_availability()`), shown as its own column. Close and cancel set `released_at` on open allocations.
- **Vessel conflicts warn, never block:** any open occupancy or overlapping plan on a vessel shows a warning on both orders and shades the calendar cell.
- **Production order colors** follow the manifest (released and in progress are info), through a local map in the feature, because `released` means success for lots.

## Decisions recorded during slices 8 and 9

- **Batch release** forces an override, with a reason (default SPECOVR) and a note, when any reading since the current stage began fails its spec. A batch awaits release when it is active at a qualifying stage with no `released` decision after its current stage began.
- **Lab readings** on batches carry a stage (default the batch's current stage) so specs apply; lot readings have no stage and so no spec result. Users delete only their own readings taken today.
- **Sensory records** are deletable only by their panelist on the day recorded; a record entered for a named outside panelist has no panelist id and cannot be deleted (accepted; corrections go through a new record).
- **Reports** export CSV at `/reports/{name}/csv` in display units with the unit in each header; valuation supports an as-of date from the ledger; batch cost per case is the lowest can-lot unit cost times units per case.

## Decisions recorded during slice 7

- **Release gate:** the latest release decision on the batch since its current stage began must be `released`; a later hold or rejection blocks posting when `require_batch_release` is on, and is flagged as `release_missing` when it is off.
- **Materials** are issued from one lot each (backflush by FEFO, explicit by choice) at a location with the output location's tax state; the run refuses when no single lot covers the quantity.
- **Units must fit the volume** taken from the batch; units, ABV and CO2 are required to post.
- **Reversal** of a posted run is allowed only while every unit is still on hand and no keg holds the lot; it posts compensating ledger rows, returns the volume to the batch and its vessel, rejects the finished lot and cancels the run.
- **Kegs** change state through one endpoint, `/kegs/{id}/state` with an `event`; a lot's fillable kegs are its units available minus kegs already filled from it; new kegs live at the first packaged-goods location.

## Decisions recorded during slice 6 and integration

- **Liquid in vessels:** juice is a lot whose balance sits at the vessel's cellar location; a batch's volume lives on `batches.current_volume_l` and its open occupancies. A batch may span vessels; losses, splits and blends draw from the largest occupancy first. A vessel emptied by an event becomes `empty` (a dump leaves it `cleaning`).
- **One occupant per vessel** is enforced; pitching into a vessel holding juice requires pitching all of that juice. Capacity overruns warn and are logged, never blocked.
- **Blends** close the stage events only of inputs used in full; partly used inputs stay active.
- **Yeast harvests** need a yeast item stocked in liters (slurry), since the harvest is measured by volume.
- **Batch tax class** is derived from readings; before the first ABV reading it reads as still wine (expected until ABV is recorded).
- **Posted documents are never re-posted.** Corrections are reversals plus a new document, so idempotency keys such as `press_run:{id}:{n}` never collide.
- **Exception handling fix (all slices):** handlers test `PDOException` before `RuntimeException`, because PDOException extends it; trigger messages now reach users through `db_error_message()` instead of raw SQLSTATE text.
- **Integration:** `/batches/{id}/release` delegates to the quality slice's controllers; the batch view shows Release (quality role) and Package (links to `/packaging-runs/new?batch=`); ledger movements link press runs, packaging runs and removals.
- **Finished lots carry their unit cost** (liquid cost per liter times fill plus the packaging bill at standard), so the batch cost report shows cost per keg and per case. Existing lots were backfilled.
- **Stage events never close before they open:** packaging closes open stage events at the later of the run time and the entry time; event forms refuse times more than 10 minutes in the future.
- **Batch release decisions** cannot repeat the latest decision since the current stage began.
- **Report verification:** stage yields, batch costs and juice yield per ton and bushel were checked by hand against the views for real batches and press runs; negative dollar amounts render as "-$310.00".

## Decisions recorded during slice 10 and the final gate

- **Removals** take their premises from the from-location (the to-location for returns). A taproom transfer is a removal whose ledger group moves stock from bond into the tax-paid taproom. Keg lots are stored one row per keg. Mixed tax classes on one removal store `tax_class = 'mixed'`.
- **Reversal of a removal** posts a return (or re-posts the original sale when reversing a return) and refuses once a keg has moved on.
- **5120.17 generation:** Section A counts bottling in the batch's tax class and Section B in the finished lot's; bulk means intermediate items, bottled means finished goods; destroyed bulk wine is line A29d (`db/014_ttb_line_map_fixes.sql`); only reportable losses count; reversed removals stay in B8 with their return on B4, so the excise total is gross with the offset on the return line.
- **Reversed packaging runs** keep their loss event as history, marked not reportable. With that fix the test period reconciles in both sections.
- **Fruit items** all carry the TTB material category `fruit`, so Part IV counts every variety.

**Owner to confirm (compliance):** family-use removals are treated as tax-determined; excise for a period is reported gross, with reversals offset through the B4 return line.

## Final gate (2026-10-01)

- `scripts/conformance.sh` passes on all 37 feature directories.
- The 375px sweep passes on 80 distinct screens (every navigation screen, a detail screen per entity, every edit form): no horizontal scroll, no console errors, no failed loads.
- End-to-end flows proven through HTTP: receive fruit by weigh tag → release → press → pitch → ferment with readings, additions, stage moves, transfers, splits, blends, losses → release → package into cans and kegs → remove tax paid, to the taproom, in bond, export, destroyed → return → reverse → generate, drill into, finalize and file the 5120.17 → trace a fruit lot forward to customers.
