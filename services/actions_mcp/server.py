"""processcore_actions_mcp — localhost-only MCP server for the command bar and the AMA agent:
navigate (screen registry), find_record, the action tools, and undo_last.

Run from /var/www/services:  .venv/bin/python -m actions_mcp.server
Port PROCESSCORE_ACTIONS_MCP_PORT (8703), bound to 127.0.0.1, no bearer: every tool call must carry
the X-Action-Token header PHP minted for the message (the assistant service sets it on the
MCP HTTP request; the model never sees it). POST /undo serves html/assistant/undo.php.
"""
from __future__ import annotations

import asyncio
import difflib
import inspect
import json
import logging
import re
from typing import Annotated, Any

from mcp.server.mcpserver import Context, MCPServer
from mcp_types import ToolAnnotations
from pydantic import ConfigDict, Field
from starlette.requests import Request
from starlette.responses import JSONResponse

from common import activity as common_activity
from common import config, db, serve

from . import actions, actions_orders, catalog, core, resolve, screens, undo  # noqa: F401  (actions and actions_orders register the tools)

log = logging.getLogger(core.SERVER_NAME)

INSTRUCTIONS = """ProcessCore actions: take the user to a screen (navigate), resolve a record by its label (find_record),
perform an action through the app's own screens (one tool per action), and undo the last action (undo_last).
Every call needs the X-Action-Token header for the current message. Questions are answered by the records and
activity servers, never here. One action or navigation per message; after a success, reply in one short
sentence and end the turn."""


def load_manifest() -> dict[str, Any]:
    if not screens.MANIFEST.is_file():
        raise SystemExit(f"{screens.MANIFEST} is missing: run .venv/bin/python -m actions_mcp.build_manifest first.")
    return json.loads(screens.MANIFEST.read_text())


def _fill(text: str) -> str:
    text = inspect.cleandoc(text)
    values = {
        "measurements": catalog.measurement_lines(), "stages": catalog.stage_lines(), "loss_reasons": catalog.loss_reason_lines(),
        "attributes": ", ".join(catalog.LOT_ATTRIBUTE_KEYS), "override_reasons": ", ".join(f"{r['code']} ({r['name']})" for r in catalog.data["override_reasons"]),
        "terminal": actions.TERMINAL, "not_for": actions.NOT_FOR, "confirm": actions.CONFIRM,
    }
    return re.sub(r"<<(\w+)>>", lambda m: values.get(m.group(1), m.group(0)), text)


def _fill_schema(node: Any) -> Any:
    if isinstance(node, dict):
        return {k: _fill_schema(v) for k, v in node.items()}
    if isinstance(node, list):
        return [_fill_schema(v) for v in node]
    return _fill(node) if isinstance(node, str) else node


def _forbid_extras(server: MCPServer) -> None:
    """Pydantic models with extra='forbid' (docs/09): unknown argument names are an error, not silently dropped."""
    for tool in server._tool_manager.list_tools():  # noqa: SLF001
        base = tool.fn_metadata.arg_model
        strict = type(base.__name__ + "Strict", (base,), {"model_config": ConfigDict(arbitrary_types_allowed=True, extra="forbid")})
        tool.fn_metadata.arg_model = strict
        tool.parameters = _fill_schema(tool.parameters) | {"additionalProperties": False}


# Screen matching ----------------------------------------------------------------------------

def _score(query: str, s: dict[str, Any]) -> float:
    q = query.lower().replace("_", " ").replace("-", " ")
    hay = f"{s['id'].replace('-', ' ')} {s['title']} {s['when']}".lower()
    words = [w for w in re.findall(r"[a-z0-9]+", q) if len(w) > 2]
    overlap = sum(1 for w in words if w in hay or w.rstrip("s") in hay) / max(len(words), 1)
    ratio = max(difflib.SequenceMatcher(None, q, s["id"].replace("-", " ")).ratio(), difflib.SequenceMatcher(None, q, s["title"].lower()).ratio())
    return overlap + ratio


def closest_screens(manifest: dict[str, Any], query: str, n: int = 4) -> list[dict[str, Any]]:
    usable = [s for s in manifest["screens"] if s["navigable"]]
    ranked = sorted(usable, key=lambda s: _score(query, s), reverse=True)[:n]
    return [{"screen": s["id"], "title": s["title"], "when": s["when"], "needs_record": s["record_kind"] is not None or "{id}" in s["url"],
             "prefill": s["prefill"]} for s in ranked]


def screen_listing(manifest: dict[str, Any]) -> str:
    out, section = [], None
    for s in manifest["screens"]:
        if not s["navigable"]:
            continue
        if s["section"] != section:
            section = s["section"]
            out.append(f"\n{section}:")
        extra = []
        if "{id}" in s["url"]:
            extra.append("record")
        if s["prefill"]:
            extra.append("prefill " + ", ".join(s["prefill"]))
        if s.get("search"):
            extra.append("q")
        out.append(f"  {s['id']} — {s['title']}" + (f" [{'; '.join(extra)}]" if extra else ""))
    return "\n".join(out)


def create_server(manifest: dict[str, Any] | None = None) -> MCPServer:
    manifest = manifest or load_manifest()
    by_id = {s["id"]: s for s in manifest["screens"]}
    server = MCPServer(name=core.SERVER_NAME, instructions=INSTRUCTIONS)

    @server.tool(name="navigate", title="Navigate", annotations=ToolAnnotations(readOnlyHint=True, idempotentHint=True, destructiveHint=False, openWorldHint=False),
                 description=f"""Take the user to a screen of the application.

Call this when the user asks to go somewhere or see something: "go to…", "open…", "show me…", "take me to…",
"back to the list", "new purchase order for Can Supply". Do NOT call it to answer questions (use the record and
activity tools) or to save data (use the action tools). Compound utterances ("go to create a PO for Lallemand")
are ONE call: `params` pre-fill the destination form.

- `screen`: an id from the list below (unsure? call find_screen first).
- `record`: for screens marked [record] — the record's label as said ("L-261001-001", "B-26-004", "Hill Orchard")
  or its id from the screen context; it is resolved server side.
- `params`: only the prefill names listed for that screen; list screens marked [q] take {{"q": "search text"}}.

After a success result: tell the user where they are in one short sentence and END THE TURN — no further tool
calls. At most one navigation per message; a later call replaces an earlier one. The tool registers the
navigation; it does not know what the screen will show.

Screens:{screen_listing(manifest)}""")
    async def navigate(
        ctx: Context,
        screen: Annotated[str, Field(description="A screen id from the list in this tool's description")],
        record: Annotated[str | None, Field(default=None, description="For [record] screens: the record's label as the user said it, or its id")] = None,
        params: Annotated[dict[str, str] | None, Field(default=None, description="Optional prefill values (query-string parameters on the destination)")] = None,
    ) -> dict[str, Any]:
        with common_activity.Timer() as timer:
            result = await _navigate(ctx, manifest, by_id, screen, record, params)
        await common_activity.log_tool_call("navigate", {"screen": screen, "record": record, "params": params, "result_status": result.get("status")}, timer.ms,
                                            error=None if result["status"] == "success" else result.get("message"))
        return result

    @server.tool(name="find_screen", title="Find screen", annotations=ToolAnnotations(readOnlyHint=True, idempotentHint=True, openWorldHint=False),
                 description="""Find the screen ids that fit what the user wants to see or do, with their descriptions and prefill
parameters. Call it only when no id in navigate's list obviously fits; then call navigate with the best id.
Do NOT use it to answer questions.""")
    async def find_screen(
        ctx: Context,
        query: Annotated[str, Field(min_length=1, max_length=200, description="What the user wants, in their words")],
    ) -> dict[str, Any]:
        try:
            core.request_token(ctx)
        except core.Refused as exc:
            return {"status": "refused", "message": str(exc)}
        return {"status": "success", "screens": closest_screens(manifest, query, 6)}

    @server.tool(name="find_record", title="Find record", annotations=ToolAnnotations(readOnlyHint=True, idempotentHint=True, openWorldHint=False),
                 description=f"""Resolve a record label the user said to the matching records (id, label, detail), e.g. a batch
number, lot number, item code or name, supplier, vessel. Call it only when an action or navigation failed as
ambiguous and you need to show the user the choices, or to check which record they mean; action tools and
navigate already resolve labels themselves. Kinds: {', '.join(resolve.KINDS)}. Read-only.""")
    async def find_record(
        ctx: Context,
        kind: Annotated[str, Field(description="Record kind: " + ", ".join(resolve.KINDS))],
        query: Annotated[str, Field(min_length=1, max_length=120, description="The label as said: number, code or name")],
        limit: Annotated[int, Field(ge=1, le=50)] = 8,
    ) -> dict[str, Any]:
        with common_activity.Timer() as timer:
            try:
                core.request_token(ctx)
                k = resolve.kind_of(kind)
                if k is None:
                    result = {"status": "invalid", "message": f"Unknown kind '{kind}'. Kinds: {', '.join(resolve.KINDS)}"}
                else:
                    rows = await resolve.search(k, query, limit=limit)
                    result = {"status": "success", "kind": k, "matches": [{"id": r["id"], "label": r["label"], "detail": r["detail"],
                                                                         "exact": r["rank"] <= 1} for r in rows]}
            except core.Refused as exc:
                result = {"status": "refused", "message": str(exc)}
        await common_activity.log_tool_call("find_record", {"kind": kind, "query": query}, timer.ms, rows=len(result.get("matches", [])))
        return result

    @server.tool(name="undo_last", title="Undo", annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=True, idempotentHint=False, openWorldHint=False),
                 description="""Undo an action the user did: "undo that", "scratch that", "take it back".

Pass the undo_id from the earlier action result; omit it to undo the user's most recent undoable command-bar
action. It applies the manifest's undo (delete the draft or reading, restore the previous value, or post the
reversing document) through the app's own screens. Some actions cannot be undone; the result says why.
Reversing a posted removal changes tax state: on needs_confirmation, ask and call again with confirmed=true.
After a result: tell the user in one short sentence what was undone (or why not) and END THE TURN.""")
    async def undo_last(
        ctx: Context,
        undo_id: Annotated[int | None, Field(default=None, ge=1, description="The undo_id of the action to undo; omit for the latest")] = None,
        confirmed: Annotated[bool, Field(description="True only after the user confirmed a needs_confirmation undo")] = False,
    ) -> dict[str, Any]:
        with common_activity.Timer() as timer:
            try:
                token = core.request_token(ctx)
                common_activity.current_server.set(core.SERVER_NAME)
                common_activity.current_token_name.set(f"action-token:user/{token.user_id}")
                result = await undo.undo(core.Call("undo_last", token, {"undo_id": undo_id}), undo_id, core.header_confirmed(ctx))
            except core.Refused as exc:
                result = {"status": "refused", "message": str(exc)}
            except Exception as exc:  # noqa: BLE001
                log.exception("undo failed")
                result = {"status": "error", "message": f"Undo failed unexpectedly ({type(exc).__name__})."}
        await common_activity.log_tool_call("undo_last", {"undo_id": undo_id, "confirmed": confirmed, "result_status": result.get("status")}, timer.ms,
                                            error=None if result.get("status") in ("success", "needs_confirmation") else result.get("message"))
        return result

    for name, fn in core.TOOLS.items():
        meta = core.ACTIONS[name]
        server.tool(name=name, title=meta.title, description=_fill(fn.__doc__ or meta.title),
                    annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=meta.destructive or meta.undo_kind == "none",
                                                idempotentHint=False, openWorldHint=False))(fn)

    _forbid_extras(server)

    @server.custom_route("/health", methods=["GET"], include_in_schema=False)
    async def health(request: Request) -> JSONResponse:
        return JSONResponse({"status": "ok", "server": core.SERVER_NAME, "tools": len(server._tool_manager.list_tools())})  # noqa: SLF001

    @server.custom_route("/undo", methods=["POST"], include_in_schema=False)
    async def undo_route(request: Request) -> JSONResponse:
        """Localhost JSON endpoint for html/assistant/undo.php: {"undo_id": n, "confirmed": bool} + X-Action-Token."""
        with common_activity.Timer() as timer:
            try:
                token = core.request_token(type("H", (), {"headers": request.headers})())
                try:
                    body = await request.json()
                except ValueError:
                    body = {}
                raw = body.get("undo_id")
                undo_id = int(raw) if raw not in (None, "") and str(raw).isdigit() else None
                common_activity.current_server.set(core.SERVER_NAME)
                common_activity.current_token_name.set(f"action-token:user/{token.user_id}")
                hdrs = type("H", (), {"headers": request.headers})()
                result = await undo.undo(core.Call("undo_last", token, {"undo_id": undo_id}), undo_id, core.header_confirmed(hdrs))
                status = 200
            except core.Refused as exc:
                result, status = {"status": "refused", "message": str(exc)}, 401
            except Exception as exc:  # noqa: BLE001
                log.exception("undo route failed")
                result, status = {"status": "error", "message": f"Undo failed unexpectedly ({type(exc).__name__})."}, 500
        await common_activity.log_tool_call("undo_last", {"via": "POST /undo", "result_status": result.get("status")}, timer.ms,
                                            error=None if result.get("status") == "success" else result.get("message"))
        return JSONResponse(result, status_code=status)

    return server


async def _navigate(ctx: Context, manifest: dict[str, Any], by_id: dict[str, dict[str, Any]], screen: str, record: str | None,
                    params: dict[str, str] | None) -> dict[str, Any]:
    try:
        core.request_token(ctx)
    except core.Refused as exc:
        return {"status": "refused", "message": str(exc)}
    s = by_id.get(screen.strip().lower())
    if s is None:
        options = closest_screens(manifest, screen)
        return {"status": "unknown_screen", "message": f"No screen '{screen}'. Closest: " + "; ".join(f"{o['screen']} — {o['when']}" for o in options),
                "candidates": options}
    if not s["navigable"]:
        return {"status": "unavailable", "message": f"{s['id']} cannot be opened from the command bar: {s['not_navigable_reason']}."}
    record_id = None
    if "{id}" in s["url"]:
        if record is None or str(record).strip() == "":
            return {"status": "needs_record", "message": f"{s['title']} is about one record: which {resolve.KINDS[s['record_kind']].noun if s['record_kind'] else 'record'}?"}
        if s["record_kind"] is None:
            if not str(record).isdigit():
                return {"status": "invalid", "message": f"{s['id']} needs the record's numeric id (from the screen context)."}
            record_id = int(record)
        else:
            try:
                record_id = (await resolve.resolve(s["record_kind"], record))["id"]
            except resolve.ResolveError as exc:
                return exc.result()
    elif record:
        views = [v for v in manifest["screens"] if v["navigable"] and v["record_kind"] and v["url"].split("/")[1] == s["url"].split("/")[1] and v["id"].endswith("-view")]
        hint = f" Use {views[0]['id']} with record='{record}'." if views else ""
        return {"status": "invalid", "message": f"{s['id']} is not about one record.{hint}"}
    allowed = list(s["prefill"]) + (["q"] if s.get("search") else [])
    params = {k: str(v) for k, v in (params or {}).items() if str(v).strip() != ""}
    unknown = [k for k in params if k not in allowed]
    if unknown:
        return {"status": "invalid", "message": f"{s['id']} does not take {', '.join(unknown)}; it takes: {', '.join(allowed) or 'no parameters'}."}
    path = screens.build_path(s["url"], record_id, params)
    return {"status": "success", "navigate": {"path": path, "target": "#page-content"}, "screen": s["id"], "title": s["title"]}


async def _startup_catalog() -> None:
    await catalog.load()
    await db.close_all()   # pools are reopened inside uvicorn's event loop


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    asyncio.run(_startup_catalog())
    server = create_server()
    port = int(config.get("PROCESSCORE_ACTIONS_MCP_PORT", "8703"))
    app = serve.build_app(server, scope=None, server_name=core.SERVER_NAME,
                          allowed_hosts=[f"127.0.0.1:{port}", f"localhost:{port}", "127.0.0.1", "localhost"])
    serve.run(app, port)


if __name__ == "__main__":
    main()
