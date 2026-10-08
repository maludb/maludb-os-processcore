"""Tiny MCP client for the actions server: call tools over streamable HTTP with an action token.

    .venv/bin/python -m actions_mcp.tests.mcp_call <tool> '<json args>' [--token T | --user-id N | --no-token] [--confirm  (sends X-Action-Confirmed: 1)]
"""
from __future__ import annotations

import asyncio
import json
import subprocess
import sys
from typing import Any

import httpx2
from mcp.client.session import ClientSession
from mcp.client.streamable_http import streamable_http_client

from common import config
from common.config import ROOT

URL = f"http://127.0.0.1:{config.get('PROCESSCORE_ACTIONS_MCP_PORT', '8703')}/mcp"


def mint(user_id: int, ttl: int = 300) -> str:
    return subprocess.run(["php", str(ROOT / "scripts" / "mint-action-token.php"), str(user_id), str(ttl)], capture_output=True, text=True, check=True).stdout.strip()


async def call(tool: str, args: dict[str, Any], token: str | None, confirm: bool = False) -> dict[str, Any]:
    headers = {"X-Action-Token": token} if token else {}
    if confirm:
        headers["X-Action-Confirmed"] = "1"
    async with httpx2.AsyncClient(headers=headers, timeout=60) as http:
        async with streamable_http_client(URL, http_client=http) as streams:
            read, write = streams[0], streams[1]
            async with ClientSession(read, write) as session:
                await session.initialize()
                result = await session.call_tool(tool, args)
                if result.structured_content is not None:
                    return result.structured_content | ({"_is_error": True} if result.is_error else {})
                text = "".join(getattr(c, "text", "") for c in result.content)
                try:
                    return json.loads(text)
                except ValueError:
                    return {"_text": text, "_is_error": result.is_error}


async def list_tools(token: str | None) -> list[str]:
    headers = {"X-Action-Token": token} if token else {}
    async with httpx2.AsyncClient(headers=headers, timeout=60) as http:
        async with streamable_http_client(URL, http_client=http) as streams:
            async with ClientSession(streams[0], streams[1]) as session:
                await session.initialize()
                return [t.name for t in (await session.list_tools()).tools]


if __name__ == "__main__":
    tool, raw = sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "{}"
    token = None
    if "--no-token" not in sys.argv:
        token = sys.argv[sys.argv.index("--token") + 1] if "--token" in sys.argv else mint(int(sys.argv[sys.argv.index("--user-id") + 1]) if "--user-id" in sys.argv else 5)
    print(json.dumps(asyncio.run(call(tool, json.loads(raw), token, "--confirm" in sys.argv)), indent=2, default=str))
