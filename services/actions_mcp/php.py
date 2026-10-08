"""Calls to the app's own PHP endpoints with an action token, and response parsing.

Success = 2xx with HX-Location and/or HX-Trigger headers; validation failure = 422
with the re-rendered form (invalid-feedback divs next to their inputs, error lists
in alert-danger blocks); 403/404/409 render shared/error.php (#error-message).
"""
from __future__ import annotations

import html as html_lib
import json
import re
from dataclasses import dataclass, field
from typing import Any
from urllib.parse import urlencode

import httpx

from common import config

_client: httpx.AsyncClient | None = None


def client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(base_url=config.get("PROCESSCORE_APP_BASE_URL", "http://127.0.0.1"), timeout=30.0,
                                    follow_redirects=False)
    return _client


@dataclass
class PhpResponse:
    status: int
    location: str | None
    triggers: list[str]
    html: str
    cookies: httpx.Cookies = field(default_factory=httpx.Cookies)

    @property
    def ok(self) -> bool:
        return 200 <= self.status < 300


def _headers(token: str) -> dict[str, str]:
    return {"X-Action-Token": token, "HX-Request": "true", "Accept": "text/html"}


def _parse(resp: httpx.Response) -> PhpResponse:
    location = None
    raw = resp.headers.get("hx-location")
    if raw:
        try:
            location = json.loads(raw).get("path")
        except (ValueError, AttributeError):
            location = raw
    triggers = [t.strip() for t in resp.headers.get("hx-trigger", "").split(",") if t.strip()]
    return PhpResponse(resp.status_code, location, triggers, resp.text, resp.cookies)


async def post(path: str, fields: list[tuple[str, Any]], token: str) -> PhpResponse:
    body = urlencode([(k, "" if v is None else str(v)) for k, v in fields])
    resp = await client().post(path, content=body, headers={**_headers(token), "Content-Type": "application/x-www-form-urlencoded"})
    return _parse(resp)


async def get(path: str, token: str, cookies: httpx.Cookies | None = None, htmx: bool = True) -> PhpResponse:
    headers = _headers(token) if htmx else {"X-Action-Token": token}
    resp = await client().get(path, headers=headers, cookies=cookies)
    return _parse(resp)


def _text(fragment: str) -> str:
    return re.sub(r"\s+", " ", html_lib.unescape(re.sub(r"<[^>]+>", " ", fragment))).strip()


def field_errors(page: str) -> list[dict[str, str | None]]:
    """[{field, message}] from a re-rendered form: each invalid-feedback div is attributed to the
    nearest preceding input/select/textarea name; list items in alert-danger blocks have field None."""
    errors: list[dict[str, str | None]] = []
    for match in re.finditer(r'<div class="invalid-feedback[^"]*">(.*?)</div>', page, re.S):
        before = page[: match.start()]
        names = re.findall(r'<(?:input|select|textarea)[^>]*\bname="([^"]+)"', before)
        errors.append({"field": html_lib.unescape(names[-1]) if names else None, "message": _text(match.group(1))})
    for block in re.finditer(r'<div class="alert alert-danger[^"]*"[^>]*>(.*?)</div>', page, re.S):
        items = re.findall(r"<li>(.*?)</li>", block.group(1), re.S)
        for item in items or [block.group(1)]:
            message = _text(item)
            if message and not any(e["message"] == message for e in errors):
                errors.append({"field": None, "message": message})
    for match in re.finditer(r'id="error-message"[^>]*>(.*?)</p>', page, re.S):
        errors.append({"field": None, "message": _text(match.group(1))})
    # Pattern C partials (count sheet rows) render a small text-danger line.
    if not errors:
        for match in re.finditer(r'<div class="[^"]*text-danger[^"]*"[^>]*>(.*?)</div>', page, re.S):
            message = _text(match.group(1))
            if message:
                errors.append({"field": None, "message": message})
    return errors


def flash_messages(page: str) -> list[tuple[str, str]]:
    """[(kind, message)] from rendered flash alerts."""
    out = []
    for match in re.finditer(r'id="flash-(\w+)"[^>]*>(.*?)<button', page, re.S):
        out.append((match.group(1), _text(match.group(2))))
    return out


def error_message(page: str) -> str | None:
    match = re.search(r'id="error-message"[^>]*>(.*?)</p>', page, re.S)
    return _text(match.group(1)) if match else None


def screen_of(page: str) -> str | None:
    match = re.search(r'id="screen-context"[^>]*data-screen="([^"]*)"', page)
    return match.group(1) if match else None
