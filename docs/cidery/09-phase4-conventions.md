# Phase 4 conventions (read before building any service)

**Date:** 2026-10-01. Skills: mcp-servers, chat-actions, new-app `references/ama-implementation.md`. Contracts: `docs/04-mcp-tool-surface.md` (read tools), `docs/05-action-manifest.md` (screens, actions, undo, confirm).

## Layout

```
services/
  .venv/                 one Python 3.12 virtualenv for every service (mcp 2.2, claude-agent-sdk, psycopg 3, fastapi, uvicorn, httpx)
  common/                shared: config.py, db.py, auth.py, activity.py, sql_guard.py, serve.py  (do not edit; ask the coordinator)
  records_mcp/server.py  cidery_records_mcp   port 8701  role cidery_records_ro   bearer scope 'records'
  activity_mcp/server.py cidery_activity_mcp  port 8702  role cidery_activity_ro  bearer scope 'activity'
  actions_mcp/server.py  cidery_actions_mcp   port 8703  localhost only, no bearer; acts through PHP with action tokens
  assistant/app.py       assistant service    port 8765  localhost only; FastAPI + Claude Agent SDK
config/services.env      secrets and ports (gitignored); read with common.config.get()/require()
deploy/systemd/          one unit per service (User=maludb, WorkingDirectory=/var/www/services, ExecStart=.venv/bin/python -m <pkg>.server)
```

Run a module from `/var/www/services`: `.venv/bin/python -m records_mcp.server`.

## MCP 2.2 (not FastMCP 1.x)

`from mcp.server.mcpserver import MCPServer` (FastMCP was renamed). `server = MCPServer(name="cidery_records_mcp", instructions=...)`; `@server.tool(name=..., title=..., description=..., annotations=ToolAnnotations(readOnlyHint=True, openWorldHint=False))` with Pydantic v2 input parameters. Check the installed source under `.venv/lib/python3.12/site-packages/mcp/` rather than recalling v1 APIs. Serve with `common.serve.build_app(server, scope='records', server_name='cidery_records_mcp')` and `common.serve.run(app, port)` — stateless JSON streamable HTTP at `/mcp`, bearer check in front, `/health` unauthenticated.

## Rules

- **Read servers never write.** Queries run on `common.db` role `'records'` or `'activity'` (read-only roles, 15 s statement timeout). The `'app'` pool is only for token checks and activity logging, already handled in `common`.
- **Log every tool call** with `common.activity.log_tool_call(tool, args, duration_ms, rows=..., error=...)` (use `common.activity.Timer`).
- **Inputs:** Pydantic models with `extra="forbid"` and constraints; human labels in (lot_number, batch_number, item name or code, supplier name), resolved server side with ILIKE + similarity; ambiguity returns candidates. `limit` 1–200 default 50, `offset`.
- **Outputs:** compact JSON (dicts/lists) with quantities in base units plus display values (gallons, pounds) using the factors in `app.units` and `app.client_settings`; dates ISO.
- **Errors** are actionable sentences, never stack traces.
- **Descriptions** say *when* to call the tool and name the questions (R1–R54, A1–A12) it answers.
- **Long tail:** `records_search` / `activity_sql` use `common.sql_guard.validate_select`; the description embeds a schema summary generated at startup from `information_schema` (tables, columns, views).

## Action tokens (PHP side is built)

`app/auth.php`: `mint_action_token(int $userId, int $ttlSeconds = 300)` and `verify_action_token()`. A request to any PHP endpoint with header `X-Action-Token: <token>` from 127.0.0.1 authenticates as that user, skips CSRF (cookie protection), and logs activity with source `command_bar`. Python never mints tokens; PHP mints one per command-bar message and passes it to the assistant service, which passes it to the actions server per call (the actions server receives it as a tool-call header or argument from the assistant, never from the model). Endpoint responses are the normal PHP ones: success = `HX-Location` (and often `HX-Trigger`) headers; validation failure = HTTP 422 with the re-rendered form (parse `invalid-feedback` text and `#*-errors` list items into messages).

## Ownership while building in parallel

| Builder | Owns |
|---|---|
| Records | `services/records_mcp/` |
| Activity + exposure | `services/activity_mcp/`, `deploy/systemd/cidery-{records,activity}-mcp.service`, `deploy/apache/cidery-services.conf` (proxies `/mcp/records`, `/mcp/activity`, and `/assistant/stream` to 8765), PHP token screen `html/settings/mcp-tokens*.php`, `app/features/mcp-tokens/`, `app/views/mcp-tokens/` |
| Actions | `services/actions_mcp/`, `config/manifest.json` (machine-readable screen + action registry generated from docs/05), `deploy/systemd/cidery-actions-mcp.service`, PHP `html/assistant/undo.php` |
| Assistant | `services/assistant/`, `deploy/systemd/cidery-assistant.service`, PHP `html/assistant/message.php`, `transcript.php`, `app/views/assistant/*`, `app/views/ama/*`, `html/ama/*` |

Nobody edits `services/common/`, `app/*.php`, `html/_router.php`, the layout, CSS, or the schema; ask the coordinator in your report if you need a change there.

## No API key yet

`ANTHROPIC_API_KEY` is not set on this host. Build the assistant so it starts without one and answers "The assistant is not configured yet (no API key)." through the normal reply path; test everything else (MCP servers with an MCP client, actions end to end by calling tools directly, PHP integration with a stubbed assistant response mode `CIDERY_ASSISTANT_FAKE=1`).
