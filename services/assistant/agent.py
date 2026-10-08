"""One assistant turn through the Claude Agent SDK, and extraction of the
browser directives (navigate, refresh, undo, needs_confirmation) from the
actions server's structured tool results.

SDK options used here were checked against the installed claude-agent-sdk
0.2.163 source (types.py ClaudeAgentOptions, _internal/transport/subprocess_cli.py
_build_command) and https://code.claude.com/docs/en/agent-sdk/{mcp,sessions}."""
from __future__ import annotations

import asyncio
import json
import logging
import re
import time
from contextlib import aclosing
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ResultMessage,
    SystemMessage,
    TextBlock,
    ToolResultBlock,
    ToolUseBlock,
    UserMessage,
    query,
)

from common import config

log = logging.getLogger("assistant.agent")

STATE_DIR = Path(__file__).resolve().parent / "state"
WORK_DIR = STATE_DIR / "work"          # empty cwd: no CLAUDE.md, no project settings
CLI_HOME = STATE_DIR / "claude"        # CLAUDE_CONFIG_DIR: isolated from the login user's ~/.claude

# Built-in tools the deployed agent must never have. `tools=[]` already removes the
# built-in set; this list is defense in depth (and removing ToolSearch turns MCP tool
# search off so the router sees every tool's schema on its first call).
DENIED_BUILTINS = [
    "Bash", "BashOutput", "KillShell", "Read", "Write", "Edit", "MultiEdit", "NotebookEdit", "Glob", "Grep",
    "WebFetch", "WebSearch", "Task", "Agent", "TodoWrite", "Skill", "SlashCommand", "ExitPlanMode",
]

EVENT_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_:.\-]{0,63}$")


@dataclass
class TurnResult:
    reply: str
    session_id: str | None = None
    navigate: dict[str, str] | None = None
    refresh: list[str] = field(default_factory=list)
    undo_id: str | None = None
    needs_confirmation: str | None = None
    tool_calls: list[dict[str, Any]] = field(default_factory=list)
    sources: list[str] = field(default_factory=list)
    duration_ms: int = 0
    model: str | None = None
    cost_usd: float | None = None
    error: str | None = None

    def payload(self) -> dict[str, Any]:
        return {
            "reply": self.reply, "session_id": self.session_id, "navigate": self.navigate, "refresh": self.refresh,
            "undo_id": self.undo_id, "needs_confirmation": self.needs_confirmation, "tool_calls": self.tool_calls,
            "sources": self.sources, "duration_ms": self.duration_ms, "model": self.model, "cost_usd": self.cost_usd,
            "error": self.error,
        }


# --- directives -----------------------------------------------------------------------

def _result_objects(content: Any, structured: Any = None) -> list[dict[str, Any]]:
    """JSON objects carried by an MCP tool result: structuredContent if the CLI passed
    it through, else each text block parsed as JSON (MCPServer serializes dict returns
    as JSON text as well as structured content)."""
    found: list[dict[str, Any]] = []
    if isinstance(structured, dict):
        sc = structured.get("structuredContent", structured.get("structured_content"))
        if isinstance(sc, dict):
            found.append(sc.get("result", sc) if isinstance(sc.get("result"), dict) else sc)
    texts: list[str] = []
    if isinstance(content, str):
        texts.append(content)
    elif isinstance(content, list):
        texts.extend(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    for text in texts:
        text = text.strip()
        if not text.startswith("{"):
            continue
        try:
            obj = json.loads(text)
        except ValueError:
            continue
        if isinstance(obj, dict):
            found.append(obj)
    return found


def _safe_path(path: Any) -> str | None:
    if not isinstance(path, str) or not path.startswith("/") or path.startswith("//") or "\\" in path:
        return None
    if any(c in path for c in "\r\n\t<>\"'") or len(path) > 500:
        return None
    return path


def apply_directives(turn: TurnResult, obj: dict[str, Any]) -> None:
    """Fold one actions-tool result into the turn's directives (later calls win)."""
    status = str(obj.get("status", "")).lower()
    nav = obj.get("navigate")
    if isinstance(nav, dict):
        path = _safe_path(nav.get("path"))
        if path:
            # The shell has one swap target for navigation; never trust another from a tool.
            turn.navigate = {"path": path, "target": "#page-content"}
    pending = obj.get("needs_confirmation")
    if status in ("needs_confirmation", "confirm", "confirmation_required") or pending:
        summary = pending if isinstance(pending, str) else (pending.get("summary") if isinstance(pending, dict) else None)
        summary = summary or obj.get("summary") or obj.get("message") or "This action needs confirmation."
        turn.needs_confirmation = str(summary)[:500]
        return
    if status in ("success", "ok", "done"):
        turn.needs_confirmation = None
    # Only "undo_id" is a handle; "undo" in a result is a human note ("This cannot be undone by voice.").
    undo = obj.get("undo_id")
    if isinstance(undo, (str, int)) and not isinstance(undo, bool) and str(undo):
        turn.undo_id = str(undo)[:100]
    refresh = obj.get("refresh", obj.get("hx_trigger"))
    if isinstance(refresh, str):
        refresh = [r.strip() for r in refresh.split(",")]
    if isinstance(refresh, dict):
        refresh = list(refresh.keys())
    if isinstance(refresh, list):
        for name in refresh:
            if isinstance(name, str) and EVENT_NAME.match(name) and name not in turn.refresh:
                turn.refresh.append(name)


# --- running a turn ------------------------------------------------------------------------

def _mcp_servers(action_token: str | None, confirmed: bool, show_prices: bool = True) -> dict[str, Any]:
    actions_headers = {"X-Action-Token": action_token or ""}
    if confirmed:
        # The user pressed Confirm (a human click in PHP, never the model's say-so).
        actions_headers["X-Action-Confirmed"] = "1"
    return {
        "records": {"type": "http", "url": f"http://127.0.0.1:{config.get('PROCESSCORE_RECORDS_MCP_PORT', '8701')}/mcp",
                    # Prices and order values only for owner and sales users (records tools leave them out otherwise).
                    "headers": {"Authorization": f"Bearer {config.get('PROCESSCORE_SERVICE_RECORDS_TOKEN', '')}", "X-ProcessCore-Show-Prices": "1" if show_prices else "0"}},
        "activity": {"type": "http", "url": f"http://127.0.0.1:{config.get('PROCESSCORE_ACTIVITY_MCP_PORT', '8702')}/mcp",
                     "headers": {"Authorization": f"Bearer {config.get('PROCESSCORE_SERVICE_ACTIVITY_TOKEN', '')}"}},
        "actions": {"type": "http", "url": f"http://127.0.0.1:{config.get('PROCESSCORE_ACTIONS_MCP_PORT', '8703')}/mcp",
                    "headers": actions_headers},
    }


def build_options(*, surface: str, system_prompt: str, resume: str | None, action_token: str | None,
                  confirmed: bool, api_key: str, show_prices: bool = True) -> ClaudeAgentOptions:
    router = surface == "command_bar"
    model = config.get("PROCESSCORE_ROUTER_MODEL" if router else "PROCESSCORE_AMA_MODEL") or None
    effort = config.get("PROCESSCORE_ROUTER_EFFORT", "low") if router else config.get("PROCESSCORE_AMA_EFFORT")
    effort = effort if effort in ("low", "medium", "high", "xhigh", "max") else None
    budget = config.get("PROCESSCORE_ASSISTANT_MAX_BUDGET_USD")
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    CLI_HOME.mkdir(parents=True, exist_ok=True)
    disallowed = list(DENIED_BUILTINS)
    if config.get("PROCESSCORE_ASSISTANT_TOOL_SEARCH", "0") != "1":
        disallowed.append("ToolSearch")
    return ClaudeAgentOptions(
        tools=[],                                   # no built-in tools at all
        mcp_servers=_mcp_servers(action_token, confirmed, show_prices),
        strict_mcp_config=True,                     # ignore any other MCP config the CLI could find
        allowed_tools=["mcp__records__*", "mcp__activity__*", "mcp__actions__*"],
        disallowed_tools=disallowed,
        permission_mode="dontAsk",                  # anything not pre-approved is denied, never prompted
        setting_sources=[],                         # no user/project/local settings, hooks, plugins, CLAUDE.md
        skills=[],                                  # no skills in the listing either
        system_prompt=system_prompt,                # replaces the Claude Code prompt entirely
        model=model,
        effort=effort,
        max_turns=int(config.get("PROCESSCORE_ROUTER_MAX_TURNS" if router else "PROCESSCORE_AMA_MAX_TURNS", "8" if router else "24")),
        max_budget_usd=float(budget) if budget else None,
        resume=resume,
        cwd=str(WORK_DIR),
        verbatim_prompts=True,                      # the user's text is never expanded (@path, /commands)
        env={
            # An OAuth token (claude setup-token) is rejected when sent as an API key, and the CLI
            # prefers ANTHROPIC_API_KEY (inherited from the systemd EnvironmentFile), so blank it.
            **({"CLAUDE_CODE_OAUTH_TOKEN": api_key, "ANTHROPIC_API_KEY": ""} if api_key.startswith("sk-ant-oat")
               else {"ANTHROPIC_API_KEY": api_key}),
            "CLAUDE_CONFIG_DIR": str(CLI_HOME),
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
            "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
            "CLAUDE_CODE_DISABLE_CLAUDE_MDS": "1",
            "CLAUDE_CODE_MCP_STARTUP_WAIT_MS": "8000",
            "CLAUDE_AGENT_SDK_CLIENT_APP": "processcore-assistant/1.0",
        },
        stderr=lambda line: log.debug("cli: %s", line[:500]),
    )


def _summarize_input(data: dict[str, Any]) -> dict[str, Any]:
    text = json.dumps(data, default=str)
    return data if len(text) <= 600 else {"truncated": text[:600]}


def _friendly_error(result: ResultMessage | None, exc: BaseException | None) -> str:
    status = getattr(result, "api_error_status", None)
    if status in (401, 403):
        return "The assistant's API key was rejected; check ANTHROPIC_API_KEY in config/services.env."
    if status == 429 or status == 529:
        return "The assistant is busy right now; try again in a moment."
    if result is not None and result.subtype == "error_max_turns":
        return "That took more steps than I allow for one message; try asking in smaller pieces."
    if result is not None and result.subtype == "error_max_budget_usd":
        return "That question hit the assistant's cost limit; try a narrower question."
    return "Sorry, something went wrong answering that. Try again in a moment."


async def run_turn(*, surface: str, prompt: str, system_prompt: str, resume: str | None, action_token: str | None,
                   confirmed: bool, api_key: str, timeout_s: float, show_prices: bool = True) -> TurnResult:
    started = time.perf_counter()
    turn = TurnResult(reply="")
    try:
        await asyncio.wait_for(
            _collect(turn, surface=surface, prompt=prompt, system_prompt=system_prompt, resume=resume,
                     action_token=action_token, confirmed=confirmed, api_key=api_key, show_prices=show_prices),
            timeout=timeout_s)
    except asyncio.TimeoutError:
        turn.error = "timeout"
        turn.reply = turn.reply or ("That is taking too long for the command bar; try the Ask me anything page."
                                    if surface == "command_bar" else "That took too long to answer; try a narrower question.")
    turn.duration_ms = int((time.perf_counter() - started) * 1000)
    return turn


async def _collect(turn: TurnResult, *, surface: str, prompt: str, system_prompt: str, resume: str | None,
                   action_token: str | None, confirmed: bool, api_key: str, show_prices: bool = True) -> None:
    attempt_resume = resume
    for attempt in (1, 2):
        options = build_options(surface=surface, system_prompt=system_prompt, resume=attempt_resume,
                                action_token=action_token, confirmed=confirmed, api_key=api_key, show_prices=show_prices)
        pending: dict[str, dict[str, Any]] = {}
        texts: list[str] = []
        result: ResultMessage | None = None
        saw_assistant = False
        try:
            async with aclosing(query(prompt=prompt, options=options)) as stream:
                async for msg in stream:
                    if isinstance(msg, SystemMessage) and msg.subtype == "init":
                        turn.session_id = msg.data.get("session_id") or turn.session_id
                        failed = [s.get("name") for s in msg.data.get("mcp_servers", []) if s.get("status") in ("failed", "needs-auth")]
                        if failed:
                            log.warning("MCP servers unavailable this turn: %s", failed)
                    elif isinstance(msg, SystemMessage) and msg.subtype == "api_retry":
                        # The CLI retries even a 401 up to ten times with backoff; a rejected key never recovers.
                        if msg.data.get("error_status") in (401, 403):
                            turn.error = "authentication_failed"
                            turn.reply = "The assistant's API key was rejected; check ANTHROPIC_API_KEY in config/services.env."
                            return
                    elif isinstance(msg, AssistantMessage):
                        saw_assistant = True
                        turn.model = msg.model or turn.model
                        for block in msg.content:
                            if isinstance(block, ToolUseBlock):
                                parts = block.name.split("__")
                                server = parts[1] if len(parts) >= 3 and parts[0] == "mcp" else "builtin"
                                call = {"tool": block.name, "server": server, "input": _summarize_input(block.input)}
                                pending[block.id] = call
                                turn.tool_calls.append(call)
                                if server in ("records", "activity") and server not in turn.sources:
                                    turn.sources.append(server)
                            elif isinstance(block, TextBlock) and block.text.strip():
                                texts.append(block.text.strip())
                    elif isinstance(msg, UserMessage) and isinstance(msg.content, list):
                        for block in msg.content:
                            if not isinstance(block, ToolResultBlock):
                                continue
                            call = pending.get(block.tool_use_id)
                            if call is None:
                                continue
                            call["is_error"] = bool(block.is_error)
                            if call["server"] == "actions":
                                for obj in _result_objects(block.content, msg.tool_use_result):
                                    apply_directives(turn, obj)
                    elif isinstance(msg, ResultMessage):
                        result = msg
                        turn.session_id = msg.session_id or turn.session_id
                        turn.cost_usd = msg.total_cost_usd
        except Exception as exc:  # the SDK raises after an error result, or when the CLI fails
            if attempt == 1 and attempt_resume and not saw_assistant:
                # A session id the CLI cannot load (state dir wiped, other host): start fresh.
                log.warning("resume of %s failed (%s); starting a new session", attempt_resume, exc)
                attempt_resume = None
                turn.tool_calls.clear()
                turn.sources.clear()
                continue
            log.error("assistant turn failed: %s", exc)
            turn.error = (result.subtype if result else type(exc).__name__)
            turn.reply = _friendly_error(result, exc)
            return
        if result is not None and result.is_error:
            turn.error = result.subtype
            turn.reply = _friendly_error(result, None)
            return
        turn.reply = ((result.result if result and result.result else None) or (texts[-1] if texts else "")).strip() or "Done."
        return
