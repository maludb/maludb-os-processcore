"""Generate config/manifest.json from docs/05-action-manifest.md and the exposed action tools.

    cd /var/www/services && .venv/bin/python -m actions_mcp.build_manifest [--user-id N] [--no-http]

For every screen it finds the controller the router would run, checks that the prefill
parameters the doc promises are read by that controller, and (unless --no-http) GETs the
screen as the user through an action token minted by scripts/mint-action-token.php: a 404,
an error, or the "arrives with build slice" stub is FLAGGED and the screen is marked not
navigable rather than silently included. (Each GET writes one screen_entered activity row
with source command_bar, as any screen render does.)

Actions: every action row of docs/05 appears, with the tool that exposes it (or exposed:
false); every exposed tool carries its JSON input schema (types, units in field names,
bounds), role, confirm rule, undo kind and how it is performed, events and refresh triggers.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx

from common import config, db
from common.config import ROOT

from . import catalog, core, resolve, screens

HTML = ROOT / "html"
FIXED = {"/login": "login.php", "/logout": "logout.php", "/login/2fa": "auth/2fa.php", "/password/reset": "auth/reset.php",
         "/settings/profile": "settings/profile.php", "/settings/2fa": "settings/2fa.php", "/assistant/message": "assistant/message.php",
         "/assistant/transcript": "assistant/transcript.php", "/assistant/undo": "assistant/undo.php"}


def controller_for(url: str, method: str = "GET") -> Path | None:
    """The file html/_router.php would run for this URL (None = stub or 404)."""
    path = "/" + url.split("?")[0].strip("/")
    if path == "/":
        return HTML / "index.php"
    if path in FIXED:
        return HTML / FIXED[path]
    segments = path.strip("/").split("/")
    feature_dir = HTML / segments[0]
    if not feature_dir.is_dir():
        return None
    rest = segments[1:]
    has_id = bool(rest) and (rest[0].isdigit() or rest[0] in ("{id}", "{line}"))
    if has_id:
        rest = rest[1:]
    words = [w for w in rest if w and not (w.isdigit() or w.startswith("{"))]
    if not words:
        name = "view" if has_id else "index"
    else:
        if words[-1] == "new":
            words[-1] = "form"
        if words == ["edit"]:
            words = ["form"]
        name = "-".join(words)
    candidates = [name + "-save", name] if method == "POST" and name != "save" else [name]
    for c in candidates:
        if (feature_dir / f"{c}.php").is_file():
            return feature_dir / f"{c}.php"
    return None


def reads_param(code: str, param: str) -> bool:
    return re.search(r"""(\w*(request|param|post_)\w*\(|\$_GET\[)\s*['"]%s['"]""" % re.escape(param), code) is not None


def mint_token(user_id: int) -> str:
    out = subprocess.run(["php", str(ROOT / "scripts" / "mint-action-token.php"), str(user_id), "900"], capture_output=True, text=True, check=True)
    return out.stdout.strip()


async def sample_ids() -> dict[str, int | None]:
    ids: dict[str, int | None] = {}
    for kind, k in resolve.KINDS.items():
        row = await db.fetch_one("records", f"SELECT min(id) AS id FROM ({k.sql}) rec")
        ids[kind] = row["id"] if row else None
    return ids


async def default_user() -> int:
    row = await db.fetch_one("activity", "SELECT actor_id FROM app.activity_log WHERE action IN ('login', 'login_google', 'login_2fa') AND actor_id IS NOT NULL ORDER BY id DESC LIMIT 1")
    if not row:
        raise SystemExit("No signed-in user found in the activity log; pass --user-id.")
    return int(row["actor_id"])


async def check_screens(doc_screens: list[dict[str, Any]], http: bool, user_id: int) -> tuple[list[dict[str, Any]], list[str]]:
    flagged: list[str] = []
    samples = await sample_ids()
    token = mint_token(user_id) if http else None
    out = []
    async with httpx.AsyncClient(base_url=config.get("PROCESSCORE_APP_BASE_URL", "http://127.0.0.1"), timeout=30) as client:
        for s in doc_screens:
            kind = screens.record_kind(s["url"])
            entry = {**s, "record_kind": kind, "search": False, "navigable": True, "route": {}}
            ctrl = controller_for(s["url"])
            entry["route"]["controller"] = str(ctrl.relative_to(ROOT)) if ctrl else None
            if ctrl is not None:
                code = ctrl.read_text()
                entry["search"] = "list_params(" in code or "list_search(" in code or "'q'" in code
                missing = [p for p in s["prefill"] if not reads_param(code, p)]
                if missing:
                    entry["route"]["prefill_not_read"] = missing
                    flagged.append(f"{s['id']}: prefill {', '.join(missing)} not read by {entry['route']['controller']} (dropped from the manifest's prefill)")
                    entry["prefill"] = [p for p in s["prefill"] if p not in missing]
            if http:
                record_id = None
                if "{id}" in s["url"]:
                    record_id = samples.get(kind) if kind else user_id
                if "{id}" in s["url"] and record_id is None:
                    entry["route"]["http"] = "no sample record"
                    status = None
                else:
                    path = screens.build_path(s["url"], record_id, None)
                    resp = await client.get(path, headers={"X-Action-Token": token, "HX-Request": "true"})
                    status = resp.status_code
                    entry["route"]["http"] = status
                    entry["route"]["sample_path"] = path
                    stub = "arrives with build slice" in resp.text
                    data_screen = (re.search(r'id="screen-context"[^>]*data-screen="([^"]*)"', resp.text) or [None, None])[1]
                    if stub:
                        entry["route"]["status"] = "stub"
                    elif status == 404:
                        entry["route"]["status"] = "missing"
                    elif status in (200, 403) or (status == 409):
                        entry["route"]["status"] = "ok"
                    else:
                        entry["route"]["status"] = "error"
                    if data_screen and data_screen != s["id"] and not stub:
                        entry["route"]["renders_screen"] = data_screen
            else:
                status = None
                entry["route"]["status"] = "ok" if ctrl else "missing"
            if ctrl is None and entry["route"].get("status") == "ok":
                entry["route"]["status"] = "stub"
            if entry["route"].get("status") not in (None, "ok"):
                flagged.append(f"{s['id']} {s['url']}: {entry['route']['status']} (HTTP {status}, controller {entry['route']['controller']}) — not navigable")
                entry["navigable"] = False
                entry["not_navigable_reason"] = f"the screen is not built yet ({entry['route']['status']})"
            if entry["route"].get("renders_screen"):
                flagged.append(f"{s['id']}: the controller stamps data-screen=\"{entry['route']['renders_screen']}\" (doc id differs)")
            if s["id"] in screens.NOT_NAVIGABLE:
                entry["navigable"] = False
                entry["not_navigable_reason"] = screens.NOT_NAVIGABLE[s["id"]]
            out.append(entry)
    return out, flagged


def tool_entries(manifest_screens: list[dict[str, Any]]) -> list[dict[str, Any]]:
    from .server import create_server   # imports actions (registers the tools)
    server = create_server({"screens": manifest_screens})
    tools = []
    for t in server._tool_manager.list_tools():  # noqa: SLF001
        meta = core.ACTIONS.get(t.name)
        entry: dict[str, Any] = {"name": t.name, "title": t.title, "description": t.description, "input_schema": t.parameters}
        if meta:
            ctrl = controller_for(re.sub(r"^POST\s+", "", meta.endpoint).split(" ")[0], "POST")
            entry.update(kind="action", doc_actions=meta.doc_actions, endpoint=meta.endpoint, method=meta.method, role=meta.role,
                         confirm=meta.confirm, undo={"kind": meta.undo_kind, "how": meta.undo_how}, events=meta.events, refresh=meta.refresh,
                         controller=str(ctrl.relative_to(ROOT)) if ctrl else None)
        else:
            entry["kind"] = "assistant"
        tools.append(entry)
    return tools


async def build(args: argparse.Namespace) -> int:
    doc = screens.parse_doc()
    await catalog.load()
    user_id = args.user_id or await default_user()
    checked, flagged = await check_screens(doc["screens"], not args.no_http, user_id)
    tools = tool_entries(checked)
    exposed = {a: t["name"] for t in tools if t.get("kind") == "action" for a in t["doc_actions"]}
    doc_names = {a["name"] for a in doc["actions"]}
    actions = []
    for a in doc["actions"]:
        actions.append({**a, "exposed_by": exposed.get(a["name"]), "exposed": a["name"] in exposed})
    for t in tools:
        if t.get("kind") == "action":
            for d in t["doc_actions"]:
                if d not in doc_names:
                    flagged.append(f"tool {t['name']}: doc action {d} is not in docs/05")
            if t.get("controller") is None:
                flagged.append(f"tool {t['name']}: endpoint {t['endpoint']} has no controller")
    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "generated_by": "services/actions_mcp/build_manifest.py",
        "source": "docs/05-action-manifest.md",
        "screens": checked,
        "actions": actions,
        "tools": tools,
        "flagged": flagged,
    }
    screens.MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False, default=str) + "\n")
    nav = sum(1 for s in checked if s["navigable"])
    print(f"Wrote {screens.MANIFEST}: {len(checked)} screens ({nav} navigable), {len(actions)} doc actions "
          f"({sum(1 for a in actions if a['exposed'])} exposed), {len(tools)} tools.")
    if flagged:
        print("FLAGGED:")
        for f in flagged:
            print("  - " + f)
    await db.close_all()
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--user-id", type=int, default=None, help="User to mint the action token for (default: the latest signed-in user)")
    parser.add_argument("--no-http", action="store_true", help="Static checks only (no GETs, no activity rows)")
    sys.exit(asyncio.run(build(parser.parse_args())))


if __name__ == "__main__":
    main()
