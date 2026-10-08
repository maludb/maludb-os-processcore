"""End-to-end MCP client for the activity server.

    .venv/bin/python -m activity_mcp.test_client [URL] [--token T] [--list] [--call TOOL JSON]
    .venv/bin/python -m activity_mcp.test_client http://127.0.0.1/mcp/activity --suite

Default URL http://127.0.0.1:8702/mcp, default token PROCESSCORE_SERVICE_ACTIVITY_TOKEN."""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
from typing import Any

from mcp.client.session import ClientSession
from mcp.client.streamable_http import streamable_http_client
from mcp.shared._httpx_utils import create_mcp_http_client

from common import config

SUITE: list[tuple[str, str, dict[str, Any]]] = [
    ("A1", "activity_who_did", {"action": "receipt_created", "entity": "GR-00001"}),
    ("A1", "activity_record_history", {"entity": "GR-00001", "include_screen_entries": False}),
    ("A2", "activity_who_did", {"action": "recipe_version_created", "entity": "Hill Dry Cider v2"}),
    ("A2", "activity_before_and_after", {"actor": "Ed", "at": "2026-10-01T09:04:02", "action": "recipe_version_created", "window_minutes": 10}),
    ("A3", "activity_who_did", {"action": "production_order_created", "entity": "WO-00001"}),
    ("A3", "activity_record_history", {"entity": "WO-00001", "include_related": False}),
    ("A4", "activity_who_did", {"action": "adjustment_posted", "period": "today", "trail_length": 3}),
    ("A4", "activity_actor_timeline", {"actor": "Ed Honour", "action": "adjustment_*", "include_payloads": True}),
    ("A5", "activity_who_did", {"action": "batch_release_decided", "entity": "B-26-004", "trail_length": 0}),
    ("A6", "activity_who_did", {"action": "po_approved", "entity": "PO-00001"}),
    ("A6", "activity_elapsed", {"start_action": "po_created", "end_action": "po_approved", "entity": "PO-00001"}),
    ("A7", "activity_screen_usage", {"screen": "tank board", "group_by": "actor"}),
    ("A7", "activity_actor_timeline", {"actor": "Ed", "screen": "tank board", "order": "desc", "limit": 3}),
    ("A7", "activity_screen_usage", {"group_by": "screen", "hour_from": 22, "hour_to": 6, "limit": 10}),
    ("A7", "activity_screen_usage", {"group_by": "role", "screen": "tank-board"}),
    ("A8", "activity_who_did", {"action": "count_approved", "trail_length": 2}),
    ("A8", "activity_elapsed", {"start_action": "count_started", "end_action": "count_approved", "entity_type": "count"}),
    ("A9", "activity_untouched", {"entity_type": "recipe", "screen": "recipe-view", "since_days": 365}),
    ("A10", "activity_day_replay", {"entity": "B-26-004", "day_of_action": "batch_loss_recorded", "include_screen_entries": False}),
    ("A10", "activity_record_history", {"entity": "B-26-004", "include_screen_entries": False, "limit": 10}),
    ("A11", "activity_assistant_actions", {"actor": "Ed", "period": "this_week", "include_messages": True}),
    ("A12", "activity_mcp_usage", {"period": "this_week", "limit": 5}),
    ("search", "activity_search", {"query": "lot released L-261001-002", "limit": 5}),
    ("search", "activity_search", {"subject": "Ed Honour", "verb": "po_approved"}),
    ("search", "activity_search", {"query": "keg lost"}),
    ("sql", "activity_sql", {"sql": "SELECT action, count(*) AS n FROM app.activity_log GROUP BY action ORDER BY n DESC LIMIT 5"}),
    ("sql", "activity_sql", {"sql": "SELECT e.episode_kind, count(*) FROM memory.maludb_episode e GROUP BY 1 ORDER BY 2 DESC LIMIT 3"}),
    ("sql-reject", "activity_sql", {"sql": "SELECT * FROM app.lots"}),
    ("sql-reject", "activity_sql", {"sql": "SELECT * FROM pg_catalog.pg_roles"}),
    ("sql-reject", "activity_sql", {"sql": "SELECT relname FROM pg_class"}),
    ("sql-reject", "activity_sql", {"sql": "SELECT count(*) FROM \"malu$episode_object\""}),
    ("sql-reject", "activity_sql", {"sql": "DELETE FROM app.activity_log"}),
    ("error", "activity_actor_timeline", {"actor": "Nobody Atall"}),
    ("error", "activity_record_history", {"entity": "L-26100"}),
    ("error", "activity_who_did", {"action": "approved"}),
    ("error", "activity_who_did", {"action": "po_approved", "bogus": 1}),
]


async def connect(url: str, token: str | None):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return create_mcp_http_client(headers=headers)


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("url", nargs="?", default="http://127.0.0.1:8702/mcp")
    ap.add_argument("--token", default=None)
    ap.add_argument("--no-token", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--call", nargs=2, metavar=("TOOL", "JSON"))
    ap.add_argument("--suite", action="store_true")
    ap.add_argument("--full", action="store_true", help="print full results")
    a = ap.parse_args()
    token = None if a.no_token else (a.token or config.get("PROCESSCORE_SERVICE_ACTIVITY_TOKEN"))
    http = await connect(a.url, token)
    async with await connect(a.url, token) as probe_client:
        probe = await probe_client.post(a.url, json={"jsonrpc": "2.0", "id": 0, "method": "ping"},
                                        headers={"Accept": "application/json, text/event-stream"})
    if probe.status_code == 401:
        print(f"HTTP 401 from {a.url}: {probe.text}")
        return 2
    async with http, streamable_http_client(a.url, http_client=http) as (read, write), ClientSession(read, write) as s:
        init = await s.initialize()
        print(f"connected: {init.server_info.name} {init.server_info.version}")
        tools = (await s.list_tools()).tools
        if a.list or a.suite:
            for t in tools:
                print(f"  tool {t.name}  readOnly={t.annotations.read_only_hint if t.annotations else None}")
        calls = SUITE if a.suite else ([("call", a.call[0], json.loads(a.call[1]))] if a.call else [])
        failures = 0
        for tag, name, args in calls:
            res = await s.call_tool(name, {"params": args})
            text = res.content[0].text if res.content else ""
            expect_error = tag in ("error", "sql-reject")
            ok = bool(res.is_error) == expect_error
            failures += 0 if ok else 1
            body = text if a.full else (text[:600] + ("..." if len(text) > 600 else ""))
            print(f"\n[{tag}] {name} {json.dumps(args)} -> {'ERROR ' if res.is_error else ''}{'ok' if ok else 'UNEXPECTED'}\n{body}")
        if calls:
            print(f"\n{len(calls) - failures}/{len(calls)} behaved as expected")
        return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
