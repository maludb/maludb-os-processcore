"""MCP usage is activity memory: every tool call is written to app.activity_log
(source 'mcp', actor 'mcp/token:{name}'), which the ingest timer ships to MaluDB."""
from __future__ import annotations

import json
import time
from contextvars import ContextVar
from typing import Any

from psycopg.types.json import Jsonb

from . import db

current_token_name: ContextVar[str] = ContextVar("current_token_name", default="unknown")
current_server: ContextVar[str] = ContextVar("current_server", default="mcp")
# False when the caller may not see prices and order values (the assistant sends X-ProcessCore-Show-Prices: 0 for
# users who are neither owner nor sales). Client tokens are created by owners, so they default to showing them.
current_show_prices: ContextVar[bool] = ContextVar("current_show_prices", default=True)


def _summarize(args: dict[str, Any]) -> dict[str, Any]:
    # Round-trip through JSON so dates, decimals and models become JSON-safe values.
    text = json.dumps(args, default=str)
    return json.loads(text) if len(text) <= 2000 else {"truncated": text[:2000]}


async def log_tool_call(tool: str, args: dict[str, Any], duration_ms: float, rows: int | None = None, error: str | None = None) -> None:
    details = {"server": current_server.get(), "tool": tool, "arguments": _summarize(args), "duration_ms": round(duration_ms, 1)}
    if rows is not None:
        details["rows"] = rows
    if error is not None:
        details["error"] = error[:500]
    try:
        await db.execute(
            "app",
            """SELECT app.log_activity(NULL, %s, 'mcp', NULL, NULL, 'mcp_tool_called', NULL, 'mcp_tool', NULL, %s, NULL, NULL, %s, NULL)""",
            (f"mcp/token:{current_token_name.get()}", tool, Jsonb(details)),
        )
    except Exception:  # logging must never break a tool call
        pass


class Timer:
    def __enter__(self) -> "Timer":
        self.start = time.perf_counter()
        return self

    def __exit__(self, *exc: object) -> None:
        self.ms = (time.perf_counter() - self.start) * 1000
