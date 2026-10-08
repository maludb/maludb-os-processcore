# OS adoption — Cidery into the MaluDB Business OS

**Date:** 2026-10-04. **Skill:** `os-adopt` (maludb-os-integration 0.5.1). **Branch:** `os-adoption`, merged to `main` when proven.
**Repository after adoption:** `github.com/maludb/maludb-os-cidery` (moved from `maludb-ed/beverage-process`).

## 1. Survey

### 1.1 Stack
- PHP 8.3, Apache, one page controller per screen under `html/{feature}/` with a pretty-URL router (`html/_router.php`, `html/.htaccess`); HTMX partials. Built with `htmx-php-builder` 0.4.x.
- PostgreSQL 17 with `maludb_core`; schema in `db/000`–`020` (`db/README.md`); the MaluDB memory schema lives INSIDE each database (`memory`, `db/001`, `deploy/provision-client.sh`).
- Configuration: `config/application.php` defaults overridden by `config/local.php` (PHP array, gitignored); the Python services read `config/services.env`. Hard-coded per server: the deployment root `/var/www` in `deploy/*.service`, `deploy/activity-ingest.sh`, the README (the repository root was the web root's parent).
- Python 3.12 services in `services/` with one venv `services/.venv`: `records_mcp` (:8701), `activity_mcp` (:8702), `actions_mcp` (:8703, localhost), `assistant` (:8765, Claude Agent SDK, holds `ANTHROPIC_API_KEY`). MCP library `mcp==2.2.0` (`MCPServer`, stateless JSON streamable HTTP).

### 1.2 Every way into a session
- **Login function:** `complete_login($user, $method)` (`app/auth.php:103`) — sets `$_SESSION['user_id']`, rotates CSRF, touches `last_login_at`, logs `login`/`login_2fa`/`login_google`. `begin_session_for()` (`app/auth.php:84`) in front of it decides the TOTP challenge.
- Callers: the password form `html/login.php`; the 2FA page `html/auth/2fa.php`; Google `html/auth/google/callback.php`; the invitation `html/auth/invite.php`; password reset `html/auth/reset-confirm.php`. No remember-me, no registration page (users are invited).
- Other session writers: none (no impersonation, no tenant switch — one database is one business).
- **Guard:** `require_login()` (`app/auth.php:36`), `require_role(...)` on top of it; 299 files call one of them. Not HTMX-aware: it answers `redirect()`, which sends `HX-Redirect` for HTMX.
- **Action tokens:** `current_user()` also accepts `X-Action-Token` (a 2-part base64url HMAC the app mints for its own assistant, localhost only) — `app/auth.php:17`, `verify_action_token()` `:197`; `verify_csrf()` waives CSRF for it (`app/csrf.php:21`).
- Pages with no guard: `/login`, `/login/2fa`, `/password/reset`, `/invite/<token>`, `/auth/google/*` — all public on purpose; nothing else.

### 1.3 People and tenants
- `app.users` (`db/003_auth.sql`): `email`, `display_name`, `password_hash` (NULL = Google-only), `role` ∈ owner · production · receiving · quality · compliance · sales · viewer (one value; `db/016` added sales), `status` ∈ invited · active · disabled, TOTP columns.
- **No tenant table.** The tenant is the database (`app.client_settings`, one row). The multi-client registry `cidery_host` is the operator's, outside the application's data.
- Platform-level role: `owner` (everything; `require_role()` with no arguments = owner only).
- Screens that create, invite, change roles or deactivate users: `html/users/{index,form,save,role,disable,enable,resend}.php`. Create the business: `deploy/provision-client.sh` + `scripts/create-owner.php`.

### 1.4 Machine access
- `app.mcp_access_tokens` (scope records | activity): sha256 of a 64-hex token, checked by `services/common/auth.py`; **not bound to a user** (a token is named, not owned) and not dependent on a user being active.
- MCP servers: records (`/mcp/records`), activity (`/mcp/activity`), both bearer; the actions server (:8703) and the assistant (:8765) are localhost only (`deploy/apache/cidery-services.conf`).
- Webhooks: none. Cron: the ingest timer runs a shell script against `cidery_host`; nothing web-reachable. No phpinfo/test pages. Every POST handler calls `require_post()` + `verify_csrf()` (checked by grep, 0 exceptions).

### 1.5 What it holds that the kernel should
- `ANTHROPIC_API_KEY` in `config/services.env`, used by `services/assistant` (the command bar and Ask me anything). The contract: an application never holds a model key — under the OS the bar goes to the kernel's chat endpoint and the assistant service is not installed.
- Activity log: `app.activity_log` written by one function `app.log_activity()` via PHP `log_activity()` (`app/activity.php`), actions like `receipt_posted` (underscore verbs), `source` ∈ screen · command_bar · ama · mcp · system; shipped to the in-database memory schema by `app.activity_ingest_pending()`.
- Outbound mail through MaluMail (`app/mail.php`). No SMS.

### 1.6 Security gaps
None found that the kernel's name would expose: CSRF everywhere, no unsigned webhooks, no diagnostic pages, no web-reachable cron, one database per business. (The records read role is already denied the auth tables, `db/020`.)

## 2. Decisions

| Question | Decision (recommended by the survey, applied 2026-10-04) |
|---|---|
| Scope kind | **`none`** — one installation is one business; premises and locations are regulatory and physical structure inside the business, not access scopes. |
| Catalog key, DNS label, path, database | `cidery` → `cidery.<domain>`, `/srv/apps/cidery`, `<tenant>_cidery` (the installer's naming; `cidery_<slug>` and `cidery_host` remain the standalone product's). |
| Business area / category / icon | Operations / other / `feather-droplet`. |
| Roles published to the kernel | The seven the application has, with the rights each gives (db/021 `app_roles`): **owner** (admin, `is_admin`), production, receiving, quality, compliance, sales (write), viewer (read). |
| A member holding SEVERAL roles | `users.os_roles text[]` holds the set; `user_can()`/`require_role()` consult it under the flag; `users.role` keeps the highest (owner, else the first held in the order above) for screens that show one. |
| Kernel `super_admin` | becomes `owner` here while `OS_ENABLED` is on. |
| Capability without roles (a grant made before the kernel read the roles) | `admin` → owner; `write` or `read` → viewer until a role arrives. |
| The standalone product | Kept whole behind `OS_ENABLED` (off = exactly as before, including its own assistant and actions server). |
| Memory | Both: the in-database memory schema stays (the activity MCP reads it); under the OS the same timer also ships each row to the tenant's one MaluDB through the API with `application: cidery`. |
| MCP library | `mcp` 2.x kept; the kernel's middleware contract (kernel token, run tokens, run-facts gate, `app_roles`) implemented on it. |

## 3. What changed (the adapter)
See the commit log on `os-adoption` and `CLAUDE.md` → "Under the Business OS". In short: `config/.env` read by PHP and Python (`env()`, `common/config.py`); db/021; `app/os.php`; `/sso`, `/sso/logout`, `/api/v1/health`; the guard and the local account screens under the flag; JSON mode for the kernel's actions server; `bin/build_action_registry.php` → `mcp/action_registry.json`; `bin/directory_sync.php`, `bin/activity_ingest.php`; the MCP servers' kernel contract and `find_*` resolvers; the command bar through the kernel's chat endpoint; `maludb-os.json`, `os/expert.md`, `skills/`, `deploy/` templates, `deploy/os-provision.sh`.

## 4. Proven
Recorded in `docs/os-adoption-proofs.md` when the proofs ran.

## 5. Owed / handed over
- The owner's: `sudo php /var/www/bin/app_install.php apply /srv/apps/cidery --by <email> --domain <domain>`, DNS/TLS for `cidery.<domain>`, grants, hiring the expert.
- Moving the standalone assistant's model key out of the product entirely (the standalone mode still holds one by design).
- Approval categories: none of Cidery's actions moves money or sends outside; deletions and TTB report filing are listed in `maludb-os.json` `approvals[]`.
