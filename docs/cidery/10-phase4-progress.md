# Phase 4 progress

| Component | Status | Notes |
|---|---|---|
| Shared services package (`services/common`) | Done | Config, pools per role, bearer auth against `app.mcp_access_tokens`, MCP call logging, SQL guard, serve helper |
| Activity ingestion timer | Done, running | `cidery-activity-ingest.timer` every minute; backfilled 1,478 rows |
| Action tokens (PHP) | Done | HMAC, localhost only, 5-minute life, skip CSRF, log as `command_bar`; also fixed CSRF accepting an empty token when the session had none |
| Activity MCP server (8702) | Done, running | 12 tools, A1–A12 answered against real data (`services/activity_mcp/EVAL.md`); `/mcp/activity` through Apache |
| AI access tokens screen | Done | `/settings/mcp-tokens`: create (token shown once), revoke, client instructions |
| Apache exposure | Done | `deploy/apache/cidery-services.conf`: `/mcp/records`, `/mcp/activity`, `/assistant/stream`; actions and the rest of the assistant stay private |
| Actions MCP server (8703) | Done, running | 133 navigable screens, 29 action tools covering 35 manifest actions, undo, confirmation gated by the human's Confirm click (`X-Action-Confirmed`) |
| Assistant service (8765) | Done, running | Claude Agent SDK with the three MCP servers only, no built-in tools, isolated config; command bar and AMA page; replies "not configured" until a key is set |
| Records MCP server (8701) | Done, running | 57 tools (the 56 in docs/04 plus `records_search`), R1–R54 answered against real data (`services/records_mcp/EVAL.md`); `/mcp/records` through Apache |

## Decisions

- **One conversation per user** across the command bar and the AMA page; PHP logs one activity row per exchange; the service never writes to the database.
- **Navigation** comes only from the actions server's `navigate` result; data actions refresh in place through `HX-Trigger`.
- **Confirmation** is the human's click: the assistant sends `X-Action-Confirmed: 1` only on the turn after Confirm, and the actions server ignores a model-supplied `confirmed=true` without it. Actions whose undo has no endpoint also confirm first.
- **Undo** resolves the user's own activity row and applies the manifest's inverse through PHP endpoints only; drafts with no delete endpoint are cancelled; posted documents are reversed.
- **MaluDB access** for the activity reader is through the facade views and text search only (internal lookup functions are not granted).

## Follow-ups (not blocking)

- **Schema changes for owner sign-off** (found by the records server): production orders do not record a packaging configuration, so packaging material needs are shown per configuration; and `app.v_batch_costs` counts only a batch's own consumptions, so split and blend children look cheap (the `cost_batch` tool adds the inherited parent cost).

- Endpoints that would let more actions act-and-undo instead of confirming first: delete a draft receipt, reverse a batch addition or loss, remove a lot attribute, clear a count line.
- PHP could return the activity id in a response header, replacing the actions server's "first new activity row" lookup.
- An Undo that itself needs confirmation is confirmed by voice; the reply view has no Confirm button for it yet.
- 73 manifest actions have no voice tool yet; the assistant navigates to their screen instead.
- SSE streaming for long AMA answers (v1 renders completed answers).

## To go live

Add `ANTHROPIC_API_KEY` to `config/services.env`, `sudo systemctl restart cidery-assistant`, then run `services/.venv/bin/python -m assistant.run_eval` (action cases write to the database and are undone afterwards unless `--no-undo`).
