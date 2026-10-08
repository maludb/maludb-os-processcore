# OS adoption — proofs (2026-10-04)

All run on this host against a scratch database `cidery_osdev`, provisioned by `deploy/os-provision.sh` (twice; the
second run applied nothing and changed nothing), with `php -S 127.0.0.1:8183` serving `html/` through the router, the
two MCP servers from `services/.venv` on 8827/8828, and a DEVELOPMENT `ACTION_TOKEN_KEY` in `config/.env`
(`testing-without-a-kernel.md`). No kernel registration was made; the kernel's installer ran in `plan` mode only.

| # | Proof | Result |
|---|---|---|
| 1 | `deploy/os-provision.sh` on an empty database, then again | 17 files recorded in `app.schema_migrations`; the memory schema enabled once; 7 roles in `mcp_app_roles`; second run idempotent |
| 2 | `/api/v1/health` | 200 `{"ok":true,"application":"cidery",…}` |
| 3 | `/` and `/login` with no session; an HTMX request with no session | 302 to the launcher with `?app=cidery`; 401 + `HX-Redirect` |
| 4 | `bin/dev_handoff.php 26` (roles production+quality) | 302 to `/`; the dashboard renders with the cookie; the user row linked (`os_member_id` 26, `os_roles {production,quality}`, `os_capability write`) |
| 5 | The same URL again (replay); a token minted for `APP_KEY=other` | 403, 403 |
| 6 | `bin/dev_handoff.php 1` (business_role super_admin) | arrives as `owner`; `/users/` renders with the "Managed in the operating system" notice; `POST /users/save` → 403 |
| 7 | Priya at `/lab/` (quality via the roles set) and at `/users/` (owner only) | 200, 403 |
| 8 | The kernel's sign-out notice to `/sso/logout`; a bad notice | 204 and the next request lands on the launcher; 204 and nothing changes |
| 9 | A revocation in the fixture feed (`bin/directory_sync.php --from-file`) | the next request lands on the launcher (`member_sessions.ended_by = directory`); re-granted + a new hand-off → 200 |
| 10 | `POST /logout` | 303 to the launcher |
| 11 | Records MCP with the kernel's token | `tools/list` = `[app_roles]`; `app_roles` answers `os.app-roles/1` with 7 roles; any other tool → "The kernel's token reaches app_roles only." |
| 12 | The kernel's own reader (`mcp_call_tool_as_kernel` + `validate_application_roles`, with the tenant key for the duration of the call) | 7 roles valid, no errors, admin = owner |
| 13 | A hashed token; a person's 3-part token (member 1); a 3-part token for an unknown member 77; a run token the kernel does not vouch for | 84 tools; 84 tools; 401; 401 (fail closed) |
| 14 | Activity MCP with the kernel's token | `tools/list` = `[]` (app_roles lives on the records server) |
| 15 | JSON mode: `POST /premises/save`, `/locations/save`, `/vessels/save` with a person's token and `Accept: application/json` | 200 `{"ok":true,"location":"/premises/2","record_id":2,"entity_type":"premises","triggers":["premisesChanged"]}` — the record from the handler's own log row |
| 16 | `POST /vessels/1/status` (the path-parameter action) | 200; `find_vessel q=tank` then answers `{"rows":[{"vessel_id":1,"label":"Tank-9","detail":"tank · cleaning"}]}` |
| 17 | An invalid create | 422 `{"error":{"code":"invalid","errors":[…],"fields":{…}}}`, deduplicated |
| 18 | An agent's run token at a handler with the relay, no kernel vouching; the same without the relay | 403 in 0.09 s (`os_token_refused` logged, source agent); 403 |
| 19 | `OS_ENABLED=0` | `/` → 303 `/login`; `/login` → 200; `/sso` → 404 — the standalone product as before |
| 20 | `php bin/build_action_registry.php --check` | current, 122 of 128 actions built |
| 21 | `php /var/www/bin/app_install.php plan /srv/apps/cidery --domain subello.com` | 24 steps to do, 1 note (the expert proposed), no stop; venv and provision script recognised; every endpoint answering |

Owed to the owner: `sudo php /var/www/bin/app_install.php apply /srv/apps/cidery --by <email> --domain subello.com`
(the development `config/.env` and the scratch database were removed after these proofs so the installer writes a
fresh one with the tenant's keys), DNS/TLS for `cidery.subello.com`, grants, and hiring the expert
(`bin/hire_application_agent.php --app cidery --agent expert`). The real-kernel proofs (a launch from the launcher, a
revocation through the real feed, an agent's run through the kernel's actions server) run then.

## The real install (2026-10-04, the owner's apply)

Three applies. The first stopped at the vhost (`Header` needs mod_headers, not loaded here → the template now guards it; the
kernel installer now restores or disables a vhost that fails configtest before stopping). The second stopped at `answers`:
the two MCP units exited 200/CHDIR — their `WorkingDirectory` carried a stray `}}` from the way the templates were generated
(fixed). The third ran through: database `subello_cidery`, `config/.env`, ports 8104/8105/8106, vhost, six units, four
endpoints answering, **application 58**, the application token, `mcp/registries/cidery.json` on the kernel's actions server,
three skills at application scope, the `ttb_report.finalize` approval policy, the sign-on proof. The owner hired the expert:
**member 63, Cidery Expert**, on `claude-opus-5-5@max`, 95 tool grants.

Two things the proofs under `php -S` had not caught, found on the first launch from the kernel's launcher:
- `/sso` was also a directory (`html/sso/logout.php`), so Apache's mod_dir answered the launch with a slash redirect and a 403
  before the router ran. The sign-out receiver moved to `html/sso-logout.php`; `/sso` and `/sso/logout` keep their paths. Through
  Apache by name: `/sso?token=x` → 403 with cidery's own refusal page, `/sso/logout` GET → 405, POST bad notice → 204.
- The roles were read while the MCP units were still restarting, so the kernel held none and the expert's grant carried no role
  (cidery would have read it as viewer). `application_roles_refresh` run as the super-admin: 7 roles; the expert's grant changed
  to receiving, production, quality, compliance and sales at write (grant 84; 83 revoked).

Remaining for the owner: open Cidery from the launcher (the proof of the real hand-off), try the command bar (the proof of the
chat endpoint and the expert), DNS/TLS at the proxy for `cidery.subello.com`.
