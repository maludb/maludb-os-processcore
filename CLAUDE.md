# ProcessCore — CLAUDE.md

**This repository is ProcessCore** (`github.com/maludb/maludb-os-processcore`, private; clone `/srv/apps/processcore`): a base
manufacturing application for converting processes, forked verbatim from `maludb-os-cidery` (commit `adf4733`) on 2026-10-08,
history kept. **The code below is still the cidery's** — nothing is renamed or cut until the owner answers the plan:
`docs/processcore-design.md` (D1–D19, build order section 13). The default profile is steel processing (coils → slit coils,
cut sheets, blanks; heats and mill test reports; scrap by weight). The one rule: *industry is data, not code*.
Everything that follows is the cidery's CLAUDE.md, kept as the record of what was forked, and it governs the code until
step 1 of the build order replaces it.

---

# Cidery — CLAUDE.md

A memory-first inventory, receiving and production application for small cideries, built with the `htmx-php-builder`
plugin (PHP 8.3 + HTMX + Bootstrap 5.3 nxl, PostgreSQL 17 + MaluDB, Python MCP servers). The build's record is `docs/`
(phases 0–4, customer orders). The repository is `github.com/maludb/maludb-os-cidery` (moved 2026-10-04 from
`maludb-ed/beverage-process`); it is one of the applications of the MaluDB Business OS suite.

## Two ways to run it (decided 2026-10-04, `docs/os-adoption.md`)

- **Standalone** (`OS_ENABLED` unset): exactly the product the README describes — its own login with TOTP and Google,
  one database per client provisioned by `deploy/provision-client.sh`, its own assistant and actions servers under
  `services/`, configuration in `config/local.php` + `config/services.env`.
- **Beside the Business OS kernel** (`OS_ENABLED=1` in `config/.env`, written by the kernel's installer
  `bin/app_install.php` from `maludb-os.json`): the kernel's hand-off token is the only way in (`/sso`, `/sso/logout`),
  people and their roles come from the kernel's directory (`users.os_member_id`, `users.os_roles`, `bin/directory_sync.php`
  every minute), the local account screens are read-only ("Managed in the operating system"), the kernel's actions server
  reaches the handlers with the tenant's tokens in JSON mode (`app/json_mode.php`), the command bar runs Cidery's expert
  in the kernel (`app/os_assistant.php`), activity ships to the tenant's one MaluDB as well as the local memory schema
  (`bin/activity_ingest.php`), and the two read MCP servers accept the kernel's token (`app_roles`) and agents' run tokens.
  The contract is the `maludb-os-integration` plugin; `app/os.php` holds every OS function.

## Rules that outlive the build
- `php-patterns` governs PHP, `design-system` the screens (no modals, 375px), `chat-actions` the command bar. A new
  screen or action goes into `docs/05-action-manifest.md` first; then `services/actions_mcp/build_manifest.py` (the
  standalone manifest) and `php bin/build_action_registry.php` (the kernel's registry) — commit both outputs.
- Every POST handler: `require_post()` + `verify_csrf()` + `require_role(...)` + `log_activity()`. A handler keeps
  answering HTMX; JSON mode translates it for the kernel — a handler that needs to say more than its HTML does calls
  `emit_action_status()`.
- Schema changes are new numbered files in `db/` (never edit an applied one); `db/020_grants.sql` is re-run after
  every file; `deploy/os-provision.sh` applies what is new on the kernel's install, `deploy/provision-client.sh` on a
  standalone client.
- Secrets: `config/local.php`, `config/services.env`, `config/.env` — all gitignored; nothing in the repository holds a
  credential. The kernel's keys (`ACTION_TOKEN_KEY`, `ACTIONS_RELAY_KEY`, `OS_APPLICATION_TOKEN`) are the installer's to write.
- The MCP library is `mcp` 2.x (`MCPServer`); the kernel's middleware contract is in `services/common/auth.py`.

## Proofs
`docs/os-adoption-proofs.md` (what was run, against which database, with what result). Standalone regression:
`scripts/conformance.sh`, `services/.venv/bin/python -m records_mcp.test_client --suite`.
