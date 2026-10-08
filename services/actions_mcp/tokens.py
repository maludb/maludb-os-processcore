"""Action tokens (minted by PHP's mint_action_token, never here).

The actions server only *reads* the token: it decodes the user id so it can find
that user's activity rows (undo ids) and refuses calls without a valid token
before anything reaches PHP. PHP verifies the token again on every request.
Format: base64url("{user_id}.{expires_unix}.{nonce16hex}") . "." . base64url(hmac_sha256(payload, key)).
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import re
import time
from dataclasses import dataclass

from common import config

HEADER = "x-action-token"


class TokenError(Exception):
    pass


@dataclass(frozen=True)
class ActionToken:
    raw: str
    user_id: int
    expires_at: int


def _b64decode(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def _b64encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def parse(raw: str | None) -> ActionToken:
    if not raw:
        raise TokenError("This call carries no action token. The assistant passes the X-Action-Token header minted by the app for each message; the actions server refuses calls without one.")
    parts = raw.strip().split(".")
    if len(parts) != 2:
        raise TokenError("The action token is malformed.")
    payload, signature = parts
    key = config.require("PROCESSCORE_ACTION_TOKEN_KEY").encode()
    expected = _b64encode(hmac.new(key, payload.encode(), hashlib.sha256).digest())
    if not hmac.compare_digest(expected, signature):
        raise TokenError("The action token is not valid.")
    try:
        decoded = _b64decode(payload).decode()
    except Exception as exc:  # noqa: BLE001
        raise TokenError("The action token is malformed.") from exc
    match = re.fullmatch(r"(\d+)\.(\d+)\.[a-f0-9]{16}", decoded)
    if not match:
        raise TokenError("The action token is malformed.")
    expires = int(match.group(2))
    if expires < time.time():
        raise TokenError("The action token has expired; send the message again.")
    return ActionToken(raw=raw.strip(), user_id=int(match.group(1)), expires_at=expires)
