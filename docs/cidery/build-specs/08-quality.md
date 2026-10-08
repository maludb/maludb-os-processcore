# Build spec: quality slice (slice 8)

Exemplar to replicate: receiving slice (slice 2, `lots` and `release_decisions`, built by the planning-class model).
Model class: worker. Build each entity exactly like the exemplar, applying this spec. If anything is ambiguous, conflicting, or missing, STOP, record the exact question under Open Questions, and escalate.

Schema tables (never modify): `app.readings`, `app.specs`, `app.measurement_types`, `app.stages`, `app.sensory_records`, `app.release_decisions`, `app.batches`, `app.lots`, `app.reason_codes`. Trigger `readings_evaluate_spec` fills `spec_id` and `spec_result` on insert; the handler never computes pass/fail itself.

---

## Entity: lab reading

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| lab-list | /lab/ | Recent readings (lab and cellar) with an out-of-spec filter |
| lab-reading-add | /lab/new | Record a lab reading; prefill `batch`, `measurement`, `value` |

No edit screen: a wrong reading is deleted (own, same day) and re-entered; no view screen (the batch view shows the curve).

### List screen
- Columns, in order: taken → `taken_at` (medium date + time); target → batch number or lot number (link to batch-view / lot-view) with product `<small>`; measurement → `measurement_types.name`; value → `value` formatted to `measurement_types.decimals` plus `unit`; stage → `stages.name`; spec → `spec_result` badge (pass success, fail danger, none secondary) with the spec range `<small>` when a spec matched; lab → `is_lab` check icon; analyst → `users.display_name`; actions → Delete (`hx-confirm`, only own readings taken today).
- Search matches: batch number, lot number, measurement name; sort allowlist: `taken_at`, `measurement_type_code`, `spec_result`; page size: 50.
- Filters: `spec_result=fail`, `measurement_type_code`, `days` (default 30).
- Row link target: the target's view screen.

### Form
- target_kind | radio batch / lot | required | `lab-reading-form-field-target-kind`
- target | select (active batches `number — product`; or lots with stock, `lot_number — item`) swapped by target_kind via Pattern A `/lab/options.php?kind=` | required | `-target-id`
- measurement_type_code | select from `measurement_types` ordered by name | required | `-measurement-type-code`
- value | number step per `decimals` | required | within `min_valid`..`max_valid` of the type | `-value`
- taken_at | datetime-local | required | default now | `-taken-at`
- stage_code | select (`stages` for the batch's product `beverage_type`; default `batches.current_stage_code`) | optional for lots | `-stage-code`
- method | text | optional | `-method`
- note | textarea | optional | `-note`
- Hidden: `is_lab = true`; `analyst_id` = current user.

### Files (exactly these)
- /var/www/html/lab/index.php · form.php · save.php · delete.php · options.php
- /var/www/app/features/lab/queries.php
- /var/www/app/views/lab/page.php · partials/table.php · row.php · form.php · saved.php

### Query functions (signatures fixed)
- find_readings(PDO, search='', filters=[], sort='taken_at', page=1): array
- find_reading(PDO, int id): ?array
- find_measurement_types(PDO): array
- find_reading_targets(PDO, string kind): array
- insert_reading(PDO, string target_kind, int target_id, string measurement_type_code, float value, string taken_at, ?string stage_code, ?string method, bool is_lab, int analyst_id, ?string note): array — `RETURNING id, spec_id, spec_result`.
- delete_reading(PDO, int id, int actor_id): bool — only when `analyst_id = actor_id` and `taken_at::date = current_date`.

### Action manifest entries
- Screens: the two above.
- Actions: `lab_reading_record` → `POST /lab/save` (params batch or lot, measurement, value, method, taken_at; undo delete_row; confirm no; role quality). The reply states the spec result ("pH 3.42, in spec" / "free SO2 12 mg/L, below spec 20 to 40").

### Activity log events
- `screen_entered`; `lab_reading_recorded` (after = {target, measurement, value, spec_result}); `lab_reading_deleted`.

### Status vocabulary mapping
- spec_result: pass → success; fail → danger; none → secondary.

### Out of scope for this slice
- Analyzer integrations; editing a reading; charts beyond the batch view's existing curve (slice 6).

### Open Questions
- (none)

---

## Entity: sensory record

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| sensory-list | /sensory/ | Panel records |
| sensory-add | /sensory/new | Record a panel verdict; prefill `batch` |

No edit or view screen.

### List screen
- Columns, in order: panel date → `panel_on`; target → batch or lot number (link) with product `<small>`; panelist → `users.display_name` or `panelist_name`; sample → `sample_code`; verdict → `verdict` badge; faults → comma list of `faults[].fault` with intensity; actions → Delete (`hx-confirm`, own, same day).
- Search matches: batch number, lot number, panelist; sort allowlist: `panel_on`, `verdict`; page size: 25.
- Row link target: the target's view screen.

### Form
- target_kind | radio batch / lot | required | `sensory-form-field-target-kind`
- target | select (same option source as lab) | required | `-target-id`
- panel_on | date | required | default today | `-panel-on`
- panelist_name | text | optional | default current user's name; `panelist_id` = current user when the name is unchanged | `-panelist-name`
- sample_code | text | optional | `-sample-code`
- verdict | select pass / fail / hold | required | `-verdict`
- attributes | five range inputs 1–5: aroma, acidity, sweetness, tannin, body → stored as `attributes` jsonb `{"aroma":3,...}` | optional | ids `-attr-aroma` … `-attr-body`
- faults | checkbox group with intensity 1–3 each: acetic, ethyl_acetate, sulfide, oxidation, mousy, brett, diacetyl → stored as `faults` jsonb `[{"fault":"acetic","intensity":2}]` | optional | ids `-fault-{fault}`, `-fault-{fault}-intensity`
- comment | textarea | optional | `-comment`

### Files (exactly these)
- /var/www/html/sensory/index.php · form.php · save.php · delete.php
- /var/www/app/features/sensory/queries.php
- /var/www/app/views/sensory/page.php · partials/table.php · row.php · form.php · saved.php

### Query functions (signatures fixed)
- find_sensory_records(PDO, search='', sort='panel_on', page=1): array
- find_sensory_record(PDO, int id): ?array
- insert_sensory_record(PDO, string target_kind, int target_id, string panel_on, ?int panelist_id, ?string panelist_name, ?string sample_code, string verdict, array attributes, array faults, ?string comment): array
- delete_sensory_record(PDO, int id, int actor_id): bool — own, same day.

### Action manifest entries
- Screens: the two above.
- Actions: `sensory_record` → `POST /sensory/save` (params batch or lot, verdict, attributes{}, faults[], comment; undo delete_row; confirm no; role quality).

### Activity log events
- `screen_entered`; `sensory_recorded` (after = {target, verdict, faults}); `sensory_deleted`.

### Status vocabulary mapping
- pass → success; hold → warning; fail → danger.

### Out of scope for this slice
- Panelist training records; blind-code generation; aggregated panel statistics.

### Open Questions
- (none)

---

## Entity: batch release

### Screens

| Screen id | Canonical URL | Purpose |
|---|---|---|
| release-queue | /releases/ | Batches awaiting release plus lots in quarantine or hold, with latest readings and sensory |
| batch-release | /batches/{id}/release | Release, hold, or reject a batch with the basis; override path with reason and confirm |

Lots keep their own release screen from slice 2 (`lot-release`); the queue links to it.

### List screen (release-queue)
- Two tables in one page. Table 1 (`release-queue-batches-table`): batches where `status = 'active'` and `current_stage_code in ('carbonate','back_sweeten','blend','maturation')` and no `release_decisions` row with `target_kind = 'batch'`, `to_status = 'released'` after the latest stage event. Columns: batch → `number` (link batch-release) with product `<small>`; stage → `stages.name`; volume → `current_volume_l` in gal; last readings → latest value per measurement in (abv, co2, free_so2, ph) with spec_result dots; failing specs → count of `readings.spec_result = 'fail'` since the current stage's `entered_at`; sensory → latest `verdict` badge; actions → Release button. Table 2 (`release-queue-lots-table`): lots with `quality_status in ('quarantine','hold')` and stock: lot, item, received, status, CoA present; actions → link to `lot-release`.
- Search matches: batch number, product, lot number; sort allowlist: `number`, `entered_at`; page size: 25.
- Row link target: batch-release (batches), lot-release (lots).

### Form (batch-release)
- Read-only panel: the readings since the stage was entered with spec ranges and results; sensory records; the recipe's QC targets for the stage.
- to_status | select released / hold / rejected | required | `batch-release-form-field-to-status`
- basis | select readings / sensory / inspection / override / other | required | `-basis`
- is_override | checkbox, forced on when any reading since the stage entry has `spec_result = 'fail'` and `to_status = 'released'` | `-is-override`
- reason_code_id | select (`reason_codes` where `applies_to = 'override'`, default `SPECOVR`) | required when is_override | `-reason-code-id`
- note | textarea | required when is_override | `-note`
- Save button carries `hx-confirm` when is_override is checked (text: "Release with an out-of-spec reading on record?"). `from_status` is computed server side: `'released'` if the last decision for the batch was released, else `'pending'`.

### Files (exactly these)
- /var/www/html/releases/index.php
- /var/www/html/batches/release.php (GET form + POST save in one Pattern B endpoint, same as the exemplar's `lots/release.php`)
- /var/www/app/features/releases/queries.php
- /var/www/app/views/releases/page.php · partials/queue-batches.php · queue-lots.php · batch-release-form.php · released.php

### Query functions (signatures fixed)
- find_release_queue_batches(PDO, search='', sort='number', page=1): array
- find_release_queue_lots(PDO, search='', page=1): array
- find_batch_release_context(PDO, int batch_id): array — batch, readings since stage entry with spec, sensory, failing count, last decision.
- insert_batch_release_decision(PDO, int batch_id, string from_status, string to_status, string basis, bool is_override, ?int reason_code_id, ?string note, int decided_by): array — inserts `release_decisions` (`target_kind = 'batch'`); when `to_status = 'rejected'` nothing else changes (dumping is a separate slice 6 action).
- find_batch_last_release(PDO, int batch_id): ?array
Packaging (slice 7) calls `find_batch_last_release` and refuses to post a run unless the last decision is `released` and later than the batch's current stage entry; that check belongs to slice 7's `post_packaging_run`, this slice only supplies the query.

### Action manifest entries
- Screens: the two above.
- Actions: `batch_release` → `POST /batches/{id}/release` (params to_status, basis, override?, note; undo reverse: a new decision back to `from_status`; confirm yes when override; role quality).

### Activity log events
- `screen_entered`; `batch_release_decided` (before = {status: from_status}, after = {status: to_status, basis, is_override, failing_readings}).

### Status vocabulary mapping
- Queue row dot by failing specs: 0 → success; ≥ 1 → danger. Decision badge: released → success; hold → warning; rejected → danger; pending → dark.

### Out of scope for this slice
- Automatic release rules; electronic signatures; lot release (slice 2 owns it).

### Open Questions
- (none)
