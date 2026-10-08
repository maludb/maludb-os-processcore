"""processcore_activity_mcp — activity memory over app.activity_log and MaluDB.

Run from /var/www/services:  .venv/bin/python -m activity_mcp.server
Serves stateless JSON streamable HTTP at http://127.0.0.1:$PROCESSCORE_ACTIVITY_MCP_PORT/mcp
behind a bearer check (scope 'activity'); /health is open."""
from __future__ import annotations

import asyncio
import logging
import json
from typing import Annotated, Any, Awaitable, Callable

import psycopg
from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from mcp.types import CallToolResult, TextContent, ToolAnnotations

from common import activity, config, db, serve

from . import models as m
from . import queries as q
from .util import PERIOD_HELP, set_timezone

log = logging.getLogger("processcore_activity_mcp")

SERVER_NAME = "processcore_activity_mcp"
READ_ONLY = ToolAnnotations(readOnlyHint=True, destructiveHint=False, idempotentHint=True, openWorldHint=False)

INSTRUCTIONS = f"""Activity memory of ProcessCore: who did what, when, on which record, from which screen, through which channel
(screen, command_bar = the assistant acting for a person, ama, mcp = client AI tools, system). Every screen entry and every
action is a row; nothing here is current state (ask the records server for quantities, statuses and documents).

How to use:
- Name people by name ('Ed') and records by the label shown in the app (L-261001-001, B-26-004, PO-00001, GR-00001,
  WO-00001, CNT-00001, 'Hill Dry Cider v2'); the server resolves them and lists candidates when ambiguous.
- Time windows: date_from/date_to (ISO, client time zone) or period ({PERIOD_HELP}).
- Start with the purposeful tool for the question; use activity_search for free text and activity_sql only for the long tail.
- Results are newest first unless a tool says otherwise; page with limit/offset (next_offset).
- Quantities in payloads are base units (L, kg); *_gal and *_lb display values are added beside them."""


Result = Annotated[CallToolResult, dict[str, Any]]


async def _run(tool: str, params: Any, fn: Callable[[], Awaitable[dict[str, Any]]]) -> CallToolResult:
    args = params.model_dump(exclude_none=True, exclude_defaults=True) if hasattr(params, "model_dump") else {}
    with activity.Timer() as t:
        try:
            result = await fn()
            error = None
        except ToolError as exc:
            result, error = None, str(exc)
        except psycopg.errors.QueryCanceled:
            result, error = None, "The query took longer than 15 seconds. Narrow the time window, name the record or person, or lower the limit."
        except psycopg.errors.InsufficientPrivilege:
            result, error = None, "The activity reader may not read that. Use app.activity_log, app.users (id, display_name, role, status) and memory views."
        except psycopg.Error as exc:
            log.exception("database error in %s", tool)
            result, error = None, f"The activity store could not answer ({type(exc).__name__}). Try again, or narrow the request."
    await activity.log_tool_call(tool, args, t.ms, rows=(result or {}).get("returned") if result else None, error=error)
    if error is not None:
        raise ToolError(error)
    data = {k: v for k, v in (result or {}).items() if v is not None}
    # Compact JSON text for the model; the same dict as structured content.
    text = json.dumps(data, default=str, ensure_ascii=False, separators=(",", ":"))
    return CallToolResult(content=[TextContent(type="text", text=text)], structured_content=data)


def build_server(schema_text: str, schemas: set[str]) -> MCPServer:
    server = MCPServer(name=SERVER_NAME, title="ProcessCore activity memory", instructions=INSTRUCTIONS, version="1.0.0")

    @server.tool(name="activity_record_history", title="Record history", annotations=READ_ONLY, description=
        "Everything that ever happened to one record, oldest first: who created, changed, posted, released, opened it; "
        "each event with actor, action, before and after values, screen and source. Also events on other records that mention it "
        "(lab readings on a lot, counts and removals naming it). Use when the question is about one lot, batch, PO, receipt, recipe, "
        "count, keg... Answers A1 (who received a delivery and when the lot numbers were entered: entity='GR-00001'), "
        "A5 (who released batch B and whether a reading was overridden: look at batch_release_decided after.is_override and basis), "
        "A10 (what happened to batch B; for a single day prefer activity_day_replay).")
    async def activity_record_history(params: m.RecordHistoryInput) -> Result:
        return await _run("activity_record_history", params, lambda: q.record_history(params))

    @server.tool(name="activity_actor_timeline", title="Actor timeline", annotations=READ_ONLY, description=
        "What one person did, in order, including the screens they opened; filter by time window, screen or action. "
        "order='desc' answers 'what did X do last'. Answers A2 (what did they look at before changing a recipe), "
        "A4 (who adjusted inventory last Tuesday and what they did right before: period='last tuesday'), "
        "A7 (when did someone last open the tank board: screen='tank board', order='desc').")
    async def activity_actor_timeline(params: m.ActorTimelineInput) -> Result:
        return await _run("activity_actor_timeline", params, lambda: q.actor_timeline(params))

    @server.tool(name="activity_who_did", title="Who did it", annotations=READ_ONLY, description=
        "Who performed an action, on what, and when, newest first, with before/after/details and the screen trail that preceded "
        "each event in the same session. Call this for 'who <verb>ed ...' questions. Answers A1 (receipt_created / receipt_posted: "
        "who received the delivery), A3 (production_order_created: who created the work order and the planning screens before it), "
        "A5 (batch_release_decided or lot_released: details/after carry basis and is_override), A6 (po_approved: who approved PO N), "
        "A8 (count_approved / count_started: who counted the cold room). Action names: receipt_created, receipt_posted, putaway_recorded, "
        "lot_released, batch_release_decided, production_order_created, production_order_released, po_created, po_approved, "
        "count_started, count_line_recorded, count_submitted, count_approved, adjustment_posted, recipe_version_created, "
        "recipe_version_activated, batch_loss_recorded, batch_dumped, removal_posted, packaging_run_posted... (fragments and 'count_*' work).")
    async def activity_who_did(params: m.WhoDidInput) -> Result:
        return await _run("activity_who_did", params, lambda: q.who_did(params))

    @server.tool(name="activity_before_and_after", title="Before and after an event", annotations=READ_ONLY, description=
        "The events just before and just after one event, in the same browser session (or by the same actor): what the person "
        "looked at and did around it. Anchor on activity_id (from any other tool) or on actor + at (+ action). "
        "Answers A4 (what did they do right before the adjustment) and A2 (what did they look at first before the recipe change).")
    async def activity_before_and_after(params: m.BeforeAfterInput) -> Result:
        return await _run("activity_before_and_after", params, lambda: q.before_and_after(params))

    @server.tool(name="activity_elapsed", title="Elapsed time between two actions", annotations=READ_ONLY, description=
        "Time between a starting action and the first ending action on the same record, per record, with who did each and how many "
        "other events happened in between; records with no end yet show still_open_for. Answers A6 (how long PO N sat: "
        "start_action='po_created', end_action='po_approved', entity='PO-00001') and A8 (how long the count took: count_started to "
        "count_approved). Also receipt_created to receipt_posted, production_order_created to production_order_released.")
    async def activity_elapsed(params: m.ElapsedInput) -> Result:
        return await _run("activity_elapsed", params, lambda: q.elapsed(params))

    @server.tool(name="activity_screen_usage", title="Screen usage", annotations=READ_ONLY, description=
        "Screen entries aggregated by screen, actor, role, local hour, day, or actor and screen, with first and last entry times. "
        "Filter by screen, actor, role, time window and local hours (hour_from=22, hour_to=6 wraps midnight for a night shift). "
        "Answers A7 (when did the cellar crew last open the tank board: screen='tank board', group_by='actor' or role='cellar'; "
        "which screens does the night shift use: hour_from/hour_to with group_by='screen').")
    async def activity_screen_usage(params: m.ScreenUsageInput) -> Result:
        return await _run("activity_screen_usage", params, lambda: q.screen_usage(params))

    @server.tool(name="activity_untouched", title="Records nobody opened", annotations=READ_ONLY, description=
        "Records of one type with no screen entry (optionally on one screen) for since_days, never-opened first. "
        "Answers A9 (which recipes has nobody opened in a year: entity_type='recipe_version', screen='recipe-view', since_days=365). "
        "The result's 'basis' says whether the record list came from the entity table or from records seen in the log.")
    async def activity_untouched(params: m.UntouchedInput) -> Result:
        return await _run("activity_untouched", params, lambda: q.untouched(params))

    @server.tool(name="activity_day_replay", title="Replay a day", annotations=READ_ONLY, description=
        "Every event of one day, in order, with full payloads and the MaluDB episode for each; optionally only events touching one "
        "record (directly or by mention). Without a date, day_of_action finds the day of the record's most recent event of that "
        "action. Answers A10 (what happened on the day batch B lost 40 gallons: entity='B-26-004', day_of_action='batch_loss_recorded').")
    async def activity_day_replay(params: m.DayReplayInput) -> Result:
        return await _run("activity_day_replay", params, lambda: q.day_replay(params))

    @server.tool(name="activity_assistant_actions", title="Assistant actions", annotations=READ_ONLY, description=
        "Actions the assistant took on someone's behalf (source command_bar or ama), newest first, each with whether an "
        "action_undone followed and by whom; include_messages adds what was asked. "
        "Answers A11 (what did the assistant do on my behalf yesterday, and was anything undone: actor='<me>', period='yesterday').")
    async def activity_assistant_actions(params: m.AssistantActionsInput) -> Result:
        return await _run("activity_assistant_actions", params, lambda: q.assistant_actions(params))

    @server.tool(name="activity_mcp_usage", title="MCP usage by client AI tools", annotations=READ_ONLY, description=
        "Calls made to ProcessCore MCP servers by client AI tools, summarised per access token (calls, tools used, errors, first and "
        "last call) with the individual calls and their arguments. "
        "Answers A12 (which client AI tools queried our memory this week, and what did they ask: period='this_week').")
    async def activity_mcp_usage(params: m.McpUsageInput) -> Result:
        return await _run("activity_mcp_usage", params, lambda: q.mcp_usage(params))

    @server.tool(name="activity_search", title="Search activity episodes", annotations=READ_ONLY, description=
        "Long-tail search over the MaluDB activity episodes (one per activity row), newest first: full-text over episode titles "
        "('<actor> <action words> <record type> <label>') through maludb_core.text_search, and/or subject-verb search over the svpor "
        "statements (subject = actor or record label fragment, verb = action). Use when no purposeful tool fits or to find the "
        "right action name or label, e.g. query='keg lost', subject='Ed', verb='lot_released'.")
    async def activity_search(params: m.SearchInput) -> Result:
        return await _run("activity_search", params, lambda: q.activity_search(params))

    @server.tool(name="activity_sql", title="Activity SQL (guarded)", annotations=READ_ONLY, description=
        "Last resort: one read-only SELECT (or WITH ... SELECT) over app.activity_log, app.users (id, display_name, role, status) and "
        "the memory.maludb_* views; other schemas and app tables are rejected, no semicolons or comments, 15 s timeout, 200 rows max. "
        "Prefer the purposeful tools. activity_log.action values are event names (screen_entered, login, lot_released, ...); "
        "source is screen|command_bar|ama|mcp|system; details/before/after are jsonb; times are timestamptz (UTC).\n"
        "Schema:\n" + schema_text)
    async def activity_sql(params: m.SqlInput) -> Result:
        return await _run("activity_sql", params, lambda: q.activity_sql(params, schemas))

    return server


async def _prepare() -> tuple[str, set[str], str | None]:
    try:
        text, schemas = await q.schema_summary()
        zone = await q.client_timezone()
        return text, schemas, zone
    finally:
        await db.close_all()   # uvicorn runs its own event loop; pools reopen there


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    schema_text, schemas, zone = asyncio.run(_prepare())
    set_timezone(zone)
    server = build_server(schema_text, schemas)
    app = serve.build_app(server, scope="activity", server_name=SERVER_NAME)
    serve.run(app, int(config.get("PROCESSCORE_ACTIVITY_MCP_PORT", "8702") or 8702))


if __name__ == "__main__":
    main()
