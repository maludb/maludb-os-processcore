# ProcessCore — CLAUDE.md

A base manufacturing application for converting processes, built with the `htmx-php-builder` plugin (PHP 8.3 + HTMX +
Bootstrap 5.3 nxl, PostgreSQL 17 + MaluDB, Python MCP servers), one of the applications of the MaluDB Business OS. The
repository is `github.com/maludb/maludb-os-processcore` (private); the clone is `/srv/apps/processcore`. **Forked verbatim
from `maludb-os-cidery` (commit `adf4733`) on 2026-10-08, history kept.** The plan is `docs/processcore-design.md`
(approved 2026-10-08, every recommendation, D1–D19); the record of the build is `docs/processcore-progress.md`; the cidery's
own documents are `docs/cidery/` (history — their cross-references point at the cidery's layout).

## State (read first)

- **Step 1, the rename, is done (2026-10-08):** catalog key `processcore`, name ProcessCore, DNS label `processcore`,
  database roles `processcore_app` / `processcore_records_ro` / `processcore_activity_ro`, env keys `PROCESSCORE_*`
  (standalone) with the contract aliases, services `processcore_records_mcp` / `processcore_activity_mcp` /
  `processcore_actions_mcp`, units and vhost `deploy/processcore-*`, skills `skills/processcore-*`, ports 8189 / 8839 / 8840.
- **The domain model is still the cidery's** (vessels, batches, press runs, kegs, TTB) until steps 2–5 of the build order
  land: step 2 rewrites `db/` in place as ProcessCore's own schema (D2), step 3 cuts the beverage layer, step 4 builds
  runs (the exemplar), step 5 the steel profile. Do not build a feature on the cidery's tables.
- The one rule: **industry is data, not code.** No file says "coil"; the steel profile (`db/profiles/steel/`) does.

## Two ways to run it (the cidery's, kept by D17)

- **Standalone** (`OS_ENABLED` unset): its own login with TOTP and Google, one database per client provisioned by
  `deploy/provision-client.sh`, its own assistant and actions servers under `services/`, configuration in
  `config/local.php` + `config/services.env`.
- **Beside the Business OS kernel** (`OS_ENABLED=1` in `config/.env`, written by the kernel's installer from
  `maludb-os.json`): the kernel's hand-off token is the only way in (`/sso`), people and roles from the directory
  (`bin/directory_sync.php`), the kernel's actions server reaches the handlers in JSON mode (`app/json_mode.php`), the
  command bar runs the expert in the kernel (`app/os_assistant.php`), activity ships to the tenant's MaluDB
  (`bin/activity_ingest.php`), the read MCP servers accept the kernel's token (`app_roles`). `app/os.php` holds every
  OS function; the contract is the `maludb-os-integration` plugin.

## Rules that outlive the build

- `php-patterns` governs PHP, `design-system` the screens (no modals, 375px), `chat-actions` the command bar. A new
  screen or action goes into `docs/05-action-manifest.md` first; then `services/actions_mcp/build_manifest.py` (the
  standalone manifest) and `php bin/build_action_registry.php` (the kernel's registry) — commit both outputs.
- Every POST handler: `require_post()` + `verify_csrf()` + `require_role(...)` + `log_activity()`. A handler that needs
  to say more than its HTML does calls `emit_action_status()`.
- Schema: until step 2 lands the files are rewritten in place (D2); after it, a change is a new numbered file, never an
  edit of an applied one. `db/020_grants.sql` is re-run after every file; `deploy/os-provision.sh` applies what is new
  on the kernel's install. The schema is proven on `processcore_dev` on this host (D19), never on a live tenant database.
- Secrets: `config/local.php`, `config/services.env`, `config/.env` — all gitignored; nothing in the repository holds
  a credential.
- Commit after every finished step on `main`, in the repository's message style; push at the owner's word.
