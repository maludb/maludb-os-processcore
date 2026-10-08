"""Shared machinery for the action tools: the token from the MCP request, the call
to the PHP endpoint, finding the activity row that is the undo handle, and the
structured results (success / needs_confirmation / invalid / not_found / ...)."""
from __future__ import annotations

import functools
import inspect
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable

from psycopg.types.json import Jsonb

from common import activity as common_activity
from common import db

from . import php, tokens
from .resolve import ResolveError

SERVER_NAME = "processcore_actions_mcp"


@dataclass
class ActionMeta:
    """One exposed tool's manifest entry (config/manifest.json is generated from these)."""
    name: str
    title: str
    doc_actions: list[str]
    endpoint: str
    role: str
    confirm: str                    # 'never', 'always', or 'when …' (the tool decides per call)
    undo_kind: str                  # delete_row | restore_prior | reverse | cancel_draft | none
    undo_how: str
    events: list[str]
    refresh: list[str]
    method: str = "POST"
    destructive: bool = False


ACTIONS: dict[str, ActionMeta] = {}
TOOLS: dict[str, Callable[..., Awaitable[dict[str, Any]]]] = {}


class Refused(Exception):
    pass


class Invalid(Exception):
    """A value the tool can reject before calling PHP (plausibility, unknown option)."""
    def __init__(self, message: str, field_name: str | None = None, candidates: list[Any] | None = None):
        super().__init__(message)
        self.message, self.field_name, self.candidates = message, field_name, candidates

    def result(self) -> dict[str, Any]:
        out: dict[str, Any] = {"status": "invalid", "message": self.message,
                               "errors": [{"field": self.field_name, "message": self.message}]}
        if self.candidates:
            out["candidates"] = self.candidates
        return out


def request_token(ctx: Any) -> tokens.ActionToken:
    """The X-Action-Token header of the MCP HTTP request (passed by the assistant service, never by the model)."""
    headers = None
    try:
        headers = ctx.headers
    except Exception:  # noqa: BLE001 - no request context (direct call)
        headers = None
    raw = None
    if headers is not None:
        raw = headers.get(tokens.HEADER) or headers.get("X-Action-Token")
    try:
        return tokens.parse(raw)
    except tokens.TokenError as exc:
        raise Refused(str(exc)) from exc


def header_confirmed(ctx: Any) -> bool:
    """The human confirmation gate: the assistant sends X-Action-Confirmed: 1 only on the turn after
    the user clicked Confirm. A model-supplied confirmed=true argument alone never executes."""
    try:
        headers = ctx.headers
    except Exception:  # noqa: BLE001
        return False
    return headers is not None and (headers.get("x-action-confirmed") or "").strip() == "1"


@dataclass
class Call:
    tool: str
    token: tokens.ActionToken
    args: dict[str, Any]
    notes: dict[str, Any] = field(default_factory=dict)

    @property
    def user_id(self) -> int:
        return self.token.user_id


# Activity log (read through the activity role) ---------------------------------------------

async def max_activity_id() -> int:
    row = await db.fetch_one("activity", "SELECT COALESCE(max(id), 0) AS id FROM app.activity_log")
    return int(row["id"]) if row else 0


async def new_activity_row(user_id: int, after_id: int, events: list[str]) -> dict[str, Any] | None:
    rows = await db.fetch_all(
        "activity",
        """SELECT id, action, entity_type, entity_id, entity_label, before, after, details, source
           FROM app.activity_log WHERE id > %s AND actor_id = %s AND action = ANY(%s) ORDER BY id LIMIT 1""",
        (after_id, user_id, events))
    return rows[0] if rows else None


async def activity_row(activity_id: int) -> dict[str, Any] | None:
    return await db.fetch_one(
        "activity",
        """SELECT id, occurred_at, actor_id, actor_label, source, action, screen, entity_type, entity_id, entity_label,
                  before, after, details FROM app.activity_log WHERE id = %s""", (activity_id,))


async def log_action_undone(original: dict[str, Any], inverse_id: int | None, summary: str) -> int | None:
    """The 'action_undone' event (docs/05 activity events), written through app.log_activity like PHP does."""
    try:
        row = await db.fetch_one(
            "app",
            """SELECT app.log_activity(%s, %s, 'command_bar', NULL, NULL, 'action_undone', NULL, %s, %s, %s, NULL, NULL, %s, NULL) AS id""",
            (original["actor_id"], original["actor_label"], original["entity_type"], original["entity_id"], original["entity_label"],
             Jsonb({"undone_activity_id": original["id"], "undo_id": original["id"], "undone_action": original["action"], "inverse_activity_id": inverse_id,
                    "summary": summary, "server": SERVER_NAME})))
        return int(row["id"]) if row else None
    except Exception:  # noqa: BLE001 - the undo itself already happened and is logged by PHP
        return None


# Results ----------------------------------------------------------------------------------

def needs_confirmation(summary: str) -> dict[str, Any]:
    return {"status": "needs_confirmation", "summary": summary,
            "message": "Ask the user to confirm in one short question and END THE TURN. It executes only when the user confirms (the app then re-sends the request with its confirmation header): on that turn call this tool again with the same arguments and confirmed=true."}


def _fail_from_response(resp: php.PhpResponse, meta: ActionMeta, field_map: dict[str, str] | None) -> dict[str, Any]:
    errors = php.field_errors(resp.html)
    for e in errors:
        if field_map and e["field"] in field_map:
            e["field"] = field_map[e["field"]]
    message = "; ".join(e["message"].rstrip(".") for e in errors) + "." if errors else None
    if resp.status == 403:
        return {"status": "forbidden", "message": f"Your role cannot do this: it needs the {meta.role} role (or owner)."}
    if resp.status == 404:
        return {"status": "not_found", "message": php.error_message(resp.html) or "That record does not exist."}
    if resp.status == 409:
        return {"status": "conflict", "message": message or "The record is not in a state that allows this."}
    if resp.status == 422:
        return {"status": "invalid", "message": message or "The app rejected the values.", "errors": errors}
    if resp.status in (401, 302, 303):
        return {"status": "refused", "message": "The app did not accept the action token (expired or not from this host)."}
    return {"status": "error", "message": message or f"The app answered HTTP {resp.status}; nothing was recorded."}


async def perform(call: Call, meta: ActionMeta, path: str, fields: list[tuple[str, Any]], *, done: str,
                  events: list[str] | None = None, undo_available: bool = True, undo_note: str | None = None,
                  field_map: dict[str, str] | None = None, extra: dict[str, Any] | None = None) -> dict[str, Any]:
    """POST to the app's endpoint as the user; success needs the expected activity row (that row is the undo id)."""
    before = await max_activity_id()
    resp = await php.post(path, fields, call.token.raw)
    if not resp.ok:
        return _fail_from_response(resp, meta, field_map)
    row = await new_activity_row(call.user_id, before, events or meta.events)
    if row is None:
        # Some endpoints flash an error and still navigate (Pattern: post/cancel/delete); read the flash.
        reason = None
        if resp.location:
            page = await php.get(resp.location, call.token.raw, cookies=resp.cookies)
            flashes = [m for k, m in php.flash_messages(page.html) if k in ("error", "warning")]
            reason = "; ".join(flashes) or None
        reason = reason or "; ".join(e["message"] for e in php.field_errors(resp.html)) or None
        return {"status": "error", "message": reason or "The app did not record the action; nothing changed."}
    result: dict[str, Any] = {
        "status": "success",
        "done": done,
        "undo_id": row["id"] if undo_available else None,
        "refresh": resp.triggers,
        "navigate": resp.location,
        "activity_id": row["id"],
    }
    if not undo_available:
        result["undo"] = undo_note or "This cannot be undone by voice."
    if extra:
        result.update(extra)
    call.notes["activity_id"] = row["id"]
    return result


def action(meta: ActionMeta) -> Callable[[Callable[..., Awaitable[dict[str, Any]]]], Callable[..., Awaitable[dict[str, Any]]]]:
    """Register the tool's manifest entry and wrap it: token check, error mapping, activity logging."""
    ACTIONS[meta.name] = meta

    def decorate(fn: Callable[..., Awaitable[dict[str, Any]]]):
        sig = inspect.signature(fn)

        @functools.wraps(fn)
        async def wrapper(**kwargs: Any) -> dict[str, Any]:
            ctx = kwargs.pop("ctx", None)
            args = {k: v for k, v in kwargs.items()}
            if "confirmed" in args:
                args["confirmed"] = header_confirmed(ctx)
            log_args = {k: (v.model_dump() if hasattr(v, "model_dump") else ([i.model_dump() if hasattr(i, "model_dump") else i for i in v] if isinstance(v, list) else v)) for k, v in args.items()}
            with common_activity.Timer() as timer:
                try:
                    token = request_token(ctx)
                    common_activity.current_server.set(SERVER_NAME)
                    common_activity.current_token_name.set(f"action-token:user/{token.user_id}")
                    call = Call(meta.name, token, log_args)
                    result = await fn(call, **args)
                except Refused as exc:
                    result = {"status": "refused", "message": str(exc)}
                except ResolveError as exc:
                    result = exc.result()
                except Invalid as exc:
                    result = exc.result()
                except Exception as exc:  # noqa: BLE001 - never a stack trace to the model
                    import logging
                    logging.getLogger(SERVER_NAME).exception("tool %s failed", meta.name)
                    result = {"status": "error", "message": f"The action failed unexpectedly ({type(exc).__name__}); nothing may have been recorded. Check the screen."}
            err = None if result.get("status") in ("success", "needs_confirmation") else result.get("message")
            await common_activity.log_tool_call(meta.name, log_args | {"result_status": result.get("status")}, timer.ms, error=err)
            return result

        # The MCP schema comes from the original parameters minus the leading `call`, plus ctx.
        params = list(sig.parameters.values())[1:]
        from mcp.server.mcpserver import Context
        ctx_param = inspect.Parameter("ctx", inspect.Parameter.KEYWORD_ONLY, annotation=Context)
        wrapper.__signature__ = sig.replace(parameters=[*[p.replace(kind=inspect.Parameter.KEYWORD_ONLY) for p in params], ctx_param])
        annotations = {k: v for k, v in getattr(fn, "__annotations__", {}).items() if k != "call"}
        annotations["ctx"] = Context
        wrapper.__annotations__ = annotations
        del wrapper.__wrapped__
        TOOLS[meta.name] = wrapper
        return wrapper

    return decorate
