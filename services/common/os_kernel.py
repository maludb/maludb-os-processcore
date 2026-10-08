"""The Business OS kernel's contract on the two read MCP servers (os-adoption 2026-10-04; maludb-os-integration:
mcp-and-api.md §1, roles-and-rights.md §2, agents.md §1).

Three callers besides a person's own hashed token:
  - the KERNEL itself: 'kernel.{exp}.{app_key}.{nonce}.{hmac}' over "kernel:exp.app_key.nonce" with ACTION_TOKEN_KEY, 60 s,
    bound to this application — it may list and call app_roles and nothing else;
  - an AGENT's run token: '{member}.{exp}.{run}.{hmac}' over "run:member.exp.run" — the kernel's run-facts call says which
    tools it was granted on THIS endpoint; a token the kernel does not vouch for lists and calls nothing (fail closed);
  - a PERSON's action token: '{member}.{exp}.{hmac}' over "member.exp" — admitted when app.users links and admits that member.
"""
from __future__ import annotations

import hashlib
import hmac
import logging
import time
from contextvars import ContextVar
from typing import Any

import httpx

from . import config, db

log = logging.getLogger("processcore_mcp.os")

KERNEL_TOOLS = {"app_roles"}
request_is_kernel: ContextVar[bool] = ContextVar("request_is_kernel", default=False)
# None = a person (every tool); a dict = an agent's granted tools -> constraints (may be empty: nothing).
request_grants: ContextVar[dict | None] = ContextVar("request_grants", default=None)

_facts_cache: dict[int, tuple[dict, float]] = {}
_FACTS_TTL = 300


def _key() -> bytes | None:
    k = config.get("PROCESSCORE_ACTION_TOKEN_KEY") or ""
    return k.encode() if len(k) >= 32 else None


def verify_kernel_token(token: str) -> bool:
    parts = token.split(".")
    key = _key()
    if key is None or len(parts) != 5 or parts[0] != "kernel":
        return False
    _, exp, app, nonce, sig = parts
    if not exp.isdigit() or app != (config.get("APP_KEY", "processcore") or "processcore") or len(nonce) != 32:
        return False
    expected = hmac.new(key, f"kernel:{exp}.{app}.{nonce}".encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, sig) and time.time() <= int(exp)


def verify_signed_token(token: str) -> tuple[int, int | None] | None:
    """(member_id, run_id | None) for the tenant's 4-part run token or 3-part person token; else None."""
    parts = token.split(".")
    key = _key()
    if key is None:
        return None
    if len(parts) == 4:
        mid, exp, run, sig = parts
        if not (mid.isdigit() and exp.isdigit() and run.isdigit()) or time.time() > int(exp):
            return None
        expected = hmac.new(key, f"run:{mid}.{exp}.{run}".encode(), hashlib.sha256).hexdigest()
        return (int(mid), int(run)) if hmac.compare_digest(expected, sig) else None
    if len(parts) == 3:
        mid, exp, sig = parts
        if not (mid.isdigit() and exp.isdigit()) or time.time() > int(exp):
            return None
        expected = hmac.new(key, f"{mid}.{exp}".encode(), hashlib.sha256).hexdigest()
        return (int(mid), None) if hmac.compare_digest(expected, sig) else None
    return None


async def run_facts(token: str, run_id: int | None) -> dict | None:
    """The kernel's word on a token. None when the kernel cannot be reached or is not configured — fail closed."""
    if run_id is not None and run_id in _facts_cache and time.time() - _facts_cache[run_id][1] < _FACTS_TTL:
        return _facts_cache[run_id][0]
    base = (config.get("OS_INTERNAL_URL", "http://127.0.0.1:8080") or "").rstrip("/")
    app_token = config.get("OS_APPLICATION_TOKEN") or ""
    if not app_token:
        log.error("OS_APPLICATION_TOKEN is not configured; agents are refused")
        return None
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.post(f"{base}/api/v1/runs/facts.php", json={"token": token},
                                  headers={"Authorization": f"Bearer {app_token}", "Accept": "application/json"})
        if r.status_code != 200:
            log.warning("run-facts answered %s", r.status_code)
            return None
        facts = r.json()
    except Exception as exc:  # noqa: BLE001
        log.warning("run-facts unreachable: %s", exc)
        return None
    if run_id is not None and facts.get("valid"):
        _facts_cache[run_id] = (facts, time.time())
    return facts


async def person_admitted(member_id: int) -> str | None:
    """The display name of the linked, active, admitted user for a kernel member id; None otherwise."""
    row = await db.fetch_one("app", "SELECT display_name FROM app.users WHERE os_member_id = %s AND status = 'active' AND os_capability IS NOT NULL", (member_id,))
    return None if row is None else str(row["display_name"])


async def classify(token: str, endpoint_name: str) -> tuple[str, str, dict | None] | None:
    """What a signed (non-hashed) bearer is: ('kernel'|'agent'|'person', label, grants) or None when refused."""
    if verify_kernel_token(token):
        return ("kernel", "os/kernel", {})
    signed = verify_signed_token(token)
    if signed is None:
        return None
    member_id, run_id = signed
    if run_id is not None:
        facts = await run_facts(token, run_id)
        if not facts or not facts.get("valid"):
            return None
        if not facts.get("is_agent"):
            name = await person_admitted(member_id)
            return None if name is None else ("person", f"os/member:{member_id} {name}", None)
        grants: dict = {}
        for ep in facts.get("endpoints") or []:
            if ep.get("name") == endpoint_name:
                grants = dict(ep.get("tools") or {})
        return ("agent", f"agent/{member_id} {facts.get('member_name') or ''}".strip(), grants)
    name = await person_admitted(member_id)
    return None if name is None else ("person", f"os/member:{member_id} {name}", None)


def install_gate(server: Any) -> None:
    """Wrap the server's list_tools / call_tool: the kernel sees app_roles alone; an agent sees what it was granted."""
    inner_list, inner_call = server.list_tools, server.call_tool

    async def list_tools():
        tools = await inner_list()
        if request_is_kernel.get():
            return [t for t in tools if t.name in KERNEL_TOOLS]
        g = request_grants.get()
        return tools if g is None else [t for t in tools if t.name in g]

    async def call_tool(name: str, arguments: dict, context=None):
        from mcp.server.mcpserver.exceptions import ToolError
        if request_is_kernel.get() and name not in KERNEL_TOOLS:
            raise ToolError(f"The kernel's token reaches {', '.join(sorted(KERNEL_TOOLS))} only.")
        g = request_grants.get()
        if g is not None and name not in g and not request_is_kernel.get():
            raise ToolError(f"'{name}' is not among the tools this agent was granted on this endpoint.")
        return await inner_call(name, arguments, context)

    server.list_tools = list_tools
    server.call_tool = call_tool
