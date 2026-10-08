# ProcessCore progress

Plan: [processcore-design.md](processcore-design.md) (approved 2026-10-08, D1–D19 all the recommendations). Each step of
its section 13 ends with a proof script in `scripts/`, a commit on `main` and a row here. The scratch install is
`processcore_dev` on this host (D19): provisioned by `deploy/os-provision.sh`, served by `php -S 127.0.0.1:8189` through
`html/_router.php` with `config/.env` (standalone, `OS_ENABLED` empty), the owner `owner@processcore.test`; never a live
tenant database.

| Step | Work | Status | Notes |
|---|---|---|---|
| 0 | The fork | Done 2026-10-08 | `maludb-os-processcore` (private) = `maludb-os-cidery` adf4733 with history; clone `/srv/apps/processcore`; the plan; approved the same day |
| 1 | The rename sweep | Done 2026-10-08 | See below; `scripts/prove-rename.sh`: 43 checks |
| 2 | The schema, in place (D2) | — | |
| 3 | The cut | — | |
| 4 | Runs — the exemplar | — | |
| 5 | The steel profile and the lot | — | |
| 6 | Packaging, shipping, quality | — | workers |
| 7 | Capabilities, orders, costing | — | workers |
| 8 | The expert, the skills, the surfaces | — | workers, then review |
| 9 | Install | — | the owner's |

## Step 1 — the rename (2026-10-08)

- **Identifiers:** `cidery_*` → `processcore_*` (the three database roles, the server names `processcore_records_mcp` /
  `processcore_activity_mcp` / `processcore_actions_mcp`, advisory-lock names, `application_name`), `CIDERY_*` →
  `PROCESSCORE_*` (the standalone services' env keys; the contract aliases in `services/common/config.py` unchanged),
  `cidery-*` → `processcore-*` (units, timers, vhost, skills directories), `Cidery` → `ProcessCore` in every string and
  comment, `X-Cidery-Show-Prices` → `X-ProcessCore-Show-Prices`. 93 files; nothing of the domain model touched.
- **Files renamed:** `deploy/apache-processcore.conf`, `deploy/apache/processcore-services.conf`, the six
  `deploy/processcore-*` units and timers, the four `deploy/systemd/processcore-*` units,
  `deploy/kernel-registry-processcore.json`, `skills/processcore-basics|receiving-day|month-end-ttb`.
- **Identity:** `maludb-os.json` name, description, icon `feather-layers`, category `manufacturing`; `composer.json`
  `processcore/app`; `config/.env.example` ports 8189 / 8839 / 8840. `CLAUDE.md` and `README.md` rewritten at the top;
  the standalone install instructions below the README's fold are the cidery's, renamed.
- **Documents:** the cidery's `docs/01–03, 06–17`, `os-adoption*.md` and `build-specs/` moved to `docs/cidery/` (the
  fork's record; a README there says so); every reference in code and in `docs/04`, `docs/05` repointed. `docs/04` and
  `docs/05` stay at the top as the live inputs of the manifest builder until step 8 rewrites them.
- **Kernel:** K29 built as `db/174_k29_processcore_catalog.sql` (the catalog row under Operations, the category check
  and `APPLICATION_CATEGORIES` widened with `manufacturing`), applied to `certstudy` the same day.
- **Proof** (`scripts/prove-rename.sh`, 43 checks, all green): no cidery identifier outside `docs/cidery/` and the plan;
  the manifest, units, vhost, registry and skills under their new names; the roles and `processcore_dev` (118 tables,
  19 migration rows) provisioned by `deploy/os-provision.sh`; `php -l` over every PHP file; under `php -S` the health
  endpoint answers `processcore`, the login page renders, the owner signs in, the dashboard says ProcessCore and never
  Cidery, seventeen screens (one per navigation group and more) answer 200, no PHP warning; both read MCP servers start
  from `services/.venv` on 8839/8840, initialize under their new names, list 89 tools, answer `app_roles` with the seven
  roles and `processcore.admin`, refuse an unknown token; `php /var/www/bin/app_install.php plan` reads the manifest
  clean (23 steps, 5 notes).
