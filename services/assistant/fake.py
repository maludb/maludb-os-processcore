"""PROCESSCORE_ASSISTANT_FAKE=1: deterministic results with no model call, so the PHP
integration (navigation, data action + undo, confirmation, AMA thread) can be
tested end to end without an API key. Never enable it in production."""
from __future__ import annotations

import hashlib
import re
import uuid

from . import manifest
from .agent import TurnResult


def _session(session_id: str | None) -> str:
    return session_id or str(uuid.uuid4())


def run(*, surface: str, message: str, session_id: str | None, entity: str | None, confirmed: bool) -> TurnResult:
    text = re.sub(r"\s+", " ", message.strip().lower())
    text = re.sub(r"^(uh|um|okay|ok|so)[, ]+", "", text)
    sid = _session(session_id)
    digest = hashlib.sha256(text.encode()).hexdigest()[:8]

    m = re.match(r"^(go to|goto|navigate to|take me to|open|show me) (.+)$", text)
    if m:
        screen = manifest.match_screen(m.group(2))
        path = screen.url if screen else "/lots/"
        title = screen.title if screen else "Lots"
        return TurnResult(reply=f"Opening {title}.", session_id=sid, navigate={"path": path, "target": "#page-content"},
                          tool_calls=[{"tool": "mcp__actions__navigate", "server": "actions", "input": {"screen": screen.id if screen else "lots-list"}, "is_error": False}])
    if text in ("undo", "undo that", "undo it", "undo the last thing"):
        return TurnResult(reply="Nothing to undo in this conversation.", session_id=sid, undo_id=None,
                          tool_calls=[{"tool": "mcp__actions__undo_last", "server": "actions", "input": {}, "is_error": False}])
    if re.match(r"^(dump|delete|cancel|reverse|disable|revoke) ", text):
        if not confirmed:
            return TurnResult(reply=f"Confirm: {message.strip()}?", session_id=sid,
                              needs_confirmation=f"{message.strip()} (fake action, cannot be undone)",
                              tool_calls=[{"tool": "mcp__actions__fake_destructive", "server": "actions", "input": {"text": message}, "is_error": False}])
        return TurnResult(reply=f"Done: {message.strip()} (fake, confirmed).", session_id=sid, refresh=[f"{entity or 'record'}Changed"],
                          tool_calls=[{"tool": "mcp__actions__fake_destructive", "server": "actions", "input": {"text": message, "confirmed": True}, "is_error": False}])
    if re.match(r"^(record|log|add|create|set|make it|change) ", text):
        event = f"{entity}Changed" if entity else "recordChanged"
        return TurnResult(reply=f"Logged: {message.strip()} (fake).", session_id=sid, undo_id=f"fake-{digest}", refresh=[event],
                          tool_calls=[{"tool": "mcp__actions__fake_create", "server": "actions", "input": {"text": message}, "is_error": False}])
    source = "activity" if re.search(r"\b(who|when did|what did .* do|happened|yesterday|opened)\b", text) else "records"
    if surface == "ama":
        reply = (f"This is a fake answer to “{message.strip()}”. With an API key the assistant answers from the "
                 f"{source} MCP server.\n\nSource: {source} memory (fake mode)")
    else:
        reply = f"Fake answer from {source} memory."
    return TurnResult(reply=reply, session_id=sid, sources=[source],
                      tool_calls=[{"tool": f"mcp__{source}__fake_lookup", "server": source, "input": {"q": message[:80]}, "is_error": False}])
