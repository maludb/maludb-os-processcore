"""Unified assistant service (localhost only, port PROCESSCORE_ASSISTANT_PORT, default 8765).

    POST /message   one turn from the command bar or the AMA page (called by PHP only)
    GET  /health    liveness and configuration summary (no secrets)

Run from /var/www/services:  .venv/bin/python -m assistant.app

PHP (html/assistant/message.php) authenticates the user, mints the action token,
keeps (user -> session id) in the PHP session, renders the reply, and writes the
activity row for the exchange (one place: PHP). This service never writes to the
database; the MCP servers log their own tool calls and the app endpoints log the
actions they perform."""
from __future__ import annotations

import asyncio
import base64
import datetime as dt
import hashlib
import hmac
import logging
import re
import time
from typing import Literal
from zoneinfo import ZoneInfo

import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from common import config

from . import agent, fake, manifest, prompts

log = logging.getLogger("assistant")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

NOT_CONFIGURED = "The assistant is not configured yet: add ANTHROPIC_API_KEY to config/services.env."

app = FastAPI(title="processcore_assistant", docs_url=None, redoc_url=None, openapi_url=None)
_user_locks: dict[int, asyncio.Lock] = {}


class User(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: int = Field(ge=1)
    display_name: str = Field(default="", max_length=200)
    role: str = Field(default="viewer", max_length=40)


class MessageIn(BaseModel):
    model_config = ConfigDict(extra="ignore")
    user: User
    session_id: str | None = Field(default=None, max_length=64)
    surface: Literal["command_bar", "ama"] = "command_bar"
    message: str = Field(min_length=1, max_length=4000)
    screen: str | None = Field(default=None, max_length=80)
    entity: str | None = Field(default=None, max_length=80)
    record_id: int | None = None
    action_token: str | None = Field(default=None, max_length=400)
    confirmed: bool = False
    today: str | None = Field(default=None, max_length=10)
    timezone: str | None = Field(default=None, max_length=64)


def _api_key() -> str | None:
    key = (config.get("ANTHROPIC_API_KEY") or "").strip()
    return key or None


def _fake() -> bool:
    return config.get("PROCESSCORE_ASSISTANT_FAKE", "0") == "1"


def _b64url_decode(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def _b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def token_user(token: str | None) -> int | None:
    """The user id a PHP-minted action token carries (same HMAC as app/auth.php), or None.
    Python only verifies; it never mints."""
    key = config.get("PROCESSCORE_ACTION_TOKEN_KEY") or ""
    if not token or len(key) < 32 or token.count(".") != 1:
        return None
    payload, signature = token.split(".")
    expected = _b64url_encode(hmac.new(key.encode(), payload.encode(), hashlib.sha256).digest())
    if not hmac.compare_digest(expected, signature):
        return None
    try:
        decoded = _b64url_decode(payload).decode()
    except (ValueError, UnicodeDecodeError):
        return None
    m = re.fullmatch(r"(\d+)\.(\d+)\.[a-f0-9]{16}", decoded)
    if not m or int(m.group(2)) < time.time():
        return None
    return int(m.group(1))


def _clean_session(session_id: str | None) -> str | None:
    if session_id and re.fullmatch(r"[0-9a-fA-F-]{8,64}", session_id):
        return session_id
    return None


def _empty(reply: str, session_id: str | None, mode: str) -> dict:
    return {"reply": reply, "session_id": session_id, "navigate": None, "refresh": [], "undo_id": None,
            "needs_confirmation": None, "tool_calls": [], "sources": [], "duration_ms": 0, "mode": mode, "error": None}


@app.get("/health")
async def health() -> dict:
    screens, actions, source = manifest.load()
    return {
        "status": "ok", "server": "processcore_assistant",
        "mode": "fake" if _fake() else ("live" if _api_key() else "unconfigured"),
        "api_key_configured": _api_key() is not None,
        "router_model": config.get("PROCESSCORE_ROUTER_MODEL"), "router_effort": config.get("PROCESSCORE_ROUTER_EFFORT", "low"),
        "ama_model": config.get("PROCESSCORE_AMA_MODEL"),
        "manifest": {"source": source, "screens": len(screens), "actions": len(actions)},
    }


@app.post("/message")
async def message(body: MessageIn) -> dict:
    session_id = _clean_session(body.session_id)
    # The request must carry a live action token PHP minted for this same user.
    if token_user(body.action_token) != body.user.id:
        raise HTTPException(status_code=403, detail="A valid action token for this user is required.")

    if _fake():
        turn = fake.run(surface=body.surface, message=body.message, session_id=session_id, entity=body.entity,
                        confirmed=body.confirmed)
        return {**turn.payload(), "mode": "fake"}

    key = _api_key()
    if key is None:
        return _empty(NOT_CONFIGURED, session_id, "unconfigured")

    tz_name = body.timezone or config.get("PROCESSCORE_TIMEZONE", "America/New_York")
    try:
        today = body.today or dt.datetime.now(ZoneInfo(tz_name)).date().isoformat()
    except Exception:
        today = dt.date.today().isoformat()
    system_prompt = prompts.build(surface=body.surface, user=body.user.model_dump(), today=today, timezone=tz_name,
                                  screen=body.screen, entity=body.entity, record_id=body.record_id,
                                  confirmed=body.confirmed)
    prompt = ("[confirmed] " if body.confirmed else "") + body.message
    timeout = float(config.get("PROCESSCORE_ROUTER_TIMEOUT_S", "18")) if body.surface == "command_bar" else float(config.get("PROCESSCORE_AMA_TIMEOUT_S", "57"))

    lock = _user_locks.setdefault(body.user.id, asyncio.Lock())
    async with lock:  # one turn at a time per user: a session transcript has one writer
        turn = await agent.run_turn(surface=body.surface, prompt=prompt, system_prompt=system_prompt,
                                    resume=session_id, action_token=body.action_token, confirmed=body.confirmed,
                                    api_key=key, timeout_s=timeout, show_prices=body.user.role in ("owner", "sales"))
    log.info("turn user=%s surface=%s tools=%d ms=%d error=%s", body.user.id, body.surface, len(turn.tool_calls),
             turn.duration_ms, turn.error)
    return {**turn.payload(), "mode": "live"}


def main() -> None:
    port = int(config.get("PROCESSCORE_ASSISTANT_PORT", "8765"))
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="info")


if __name__ == "__main__":
    main()
