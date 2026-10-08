"""Run services/assistant/EVAL.md against the live assistant service and record results.

    cd /var/www/services
    .venv/bin/python -m assistant.run_eval [--only screens|actions|questions] [--ids S001-S040,R1]
                                           [--no-undo] [--user-id 5] [--url http://127.0.0.1:8765] [--list]

Each utterance is a fresh assistant session with a PHP-minted action token (Python never
mints tokens: the runner asks PHP's mint_action_token() through the php CLI). Results:
services/assistant/eval-results/<timestamp>.jsonl plus a summary on stdout. See EVAL.md
for the scoring rules."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx

from common.config import ROOT

HERE = Path(__file__).resolve().parent
EVAL_FILE = HERE / "EVAL.md"
RESULTS_DIR = HERE / "eval-results"
MANIFEST_FILE = ROOT / "config" / "manifest.json"
SECTIONS = {"1": "screens", "2": "actions", "3": "questions"}


@dataclass
class Case:
    id: str
    section: str
    context: str
    utterance: str
    expect: str

    @property
    def surface(self) -> str:
        return "ama" if self.section == "questions" else "command_bar"


def parse_eval(path: Path = EVAL_FILE) -> list[Case]:
    cases: list[Case] = []
    section = None
    for line in path.read_text().splitlines():
        m = re.match(r"^## (\d)\.", line)
        if m:
            section = SECTIONS.get(m.group(1))
            continue
        if section is None or not line.startswith("| "):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 4 or not re.fullmatch(r"[SAR]\d+", cells[0]):
            continue
        cases.append(Case(cells[0], section, cells[1], cells[2], cells[3]))
    return cases


def select(cases: list[Case], ids: str | None) -> list[Case]:
    if not ids:
        return cases
    order = [c.id for c in cases]
    keep: set[str] = set()
    for part in ids.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-", 1)
            if a in order and b in order:
                keep.update(order[order.index(a): order.index(b) + 1])
        elif part:
            keep.add(part)
    return [c for c in cases if c.id in keep]


def load_manifest() -> dict[str, Any]:
    try:
        return json.loads(MANIFEST_FILE.read_text())
    except (OSError, ValueError):
        return {"screens": [], "actions": []}


def mint_token(user_id: int) -> str:
    code = f'require "{ROOT}/app/bootstrap.php"; echo mint_action_token({int(user_id)}, 600);'
    out = subprocess.run(["php", "-r", code], capture_output=True, text=True, timeout=20)
    token = out.stdout.strip().splitlines()[-1] if out.stdout.strip() else ""
    if out.returncode != 0 or "." not in token:
        raise SystemExit(f"Could not mint an action token through PHP: {out.stderr.strip() or out.stdout.strip()}")
    return token


def context_fields(context: str) -> dict[str, Any]:
    if context in ("", "-"):
        return {"screen": "dashboard", "entity": None, "record_id": None}
    parts = context.split(":")
    return {"screen": parts[0], "entity": parts[1] if len(parts) > 1 else None,
            "record_id": int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else None}


def url_regex(url: str) -> re.Pattern[str]:
    path = url.split("?", 1)[0]
    return re.compile("^" + re.escape(path).replace(re.escape("{id}"), r"\d+") + "$")


def called(result: dict[str, Any], tool: str) -> list[dict[str, Any]]:
    return [c for c in result.get("tool_calls", []) if str(c.get("tool", "")).endswith("__" + tool)]


def score(case: Case, result: dict[str, Any], manifest: dict[str, Any]) -> tuple[str, str]:
    """(verdict, note): verdict is pass, soft, or fail."""
    kind, _, arg = case.expect.partition(" ")
    nav = result.get("navigate") or {}
    nav_path = str(nav.get("path", "")).split("?", 1)[0]
    if kind == "navigate":
        screen = next((s for s in manifest.get("screens", []) if s.get("id") == arg), None)
        if screen and nav_path and url_regex(screen["url"]).match(nav_path):
            return "pass", nav_path
        if any((c.get("input") or {}).get("screen") == arg for c in called(result, "navigate")):
            return "pass", f"navigate({arg}) called; path {nav_path or 'none'}"
        return "fail", f"navigated to {nav_path or 'nothing'}"
    if kind in ("action", "confirm"):
        meta = next((a for a in manifest.get("actions", []) if a.get("name") == arg), {})
        tool = meta.get("exposed_by")
        if not tool:
            if nav_path:
                return "soft", f"navigate-fallback to {nav_path} (no voice tool for {arg} yet)"
            return "fail", f"no voice tool for {arg} and no navigation"
        calls = called(result, tool)
        if not calls:
            return "fail", f"{tool} not called; tools: {[c.get('tool') for c in result.get('tool_calls', [])]}"
        if kind == "confirm":
            return ("pass", "needs_confirmation") if result.get("needs_confirmation") else ("fail", "executed or failed without asking to confirm")
        if result.get("needs_confirmation"):
            return "pass", "needs_confirmation"
        if result.get("undo_id") or result.get("refresh"):
            return "pass", f"undo_id {result.get('undo_id')}, refresh {result.get('refresh')}"
        if all(c.get("is_error") is False for c in calls):
            return "soft", "tool called, no undo/refresh directive"
        return "fail", "tool returned an error"
    if kind == "ask":
        acted = result.get("undo_id") or result.get("refresh")
        return ("pass", "asked") if not acted and str(result.get("reply", "")).rstrip().endswith("?") else ("fail", "did not ask")
    if kind == "tools":
        wanted = [t.strip() for t in arg.split(",") if t.strip()]
        hit = [t for t in wanted if called(result, t)]
        if not hit:
            return "fail", f"none of {wanted} called; tools: {[c.get('tool') for c in result.get('tool_calls', [])]}"
        if case.surface == "ama" and "source:" not in str(result.get("reply", "")).lower():
            return "soft", f"{hit} called but no Source line"
        return "pass", ",".join(hit)
    return "fail", f"unknown expectation {case.expect!r}"


def turn(client: httpx.Client, url: str, user: dict[str, Any], case: Case, message: str, session_id: str | None) -> dict[str, Any]:
    body = {"user": user, "session_id": session_id, "surface": case.surface, "message": message,
            "action_token": mint_token(user["id"]), **context_fields(case.context)}
    started = time.perf_counter()
    resp = client.post(url.rstrip("/") + "/message", json=body)
    data = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {"reply": resp.text}
    data["http_status"] = resp.status_code
    data["wall_ms"] = int((time.perf_counter() - started) * 1000)
    return data


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", choices=["screens", "actions", "questions"])
    ap.add_argument("--ids", help="comma list and ranges of case ids, e.g. S001-S040,R1,A11")
    ap.add_argument("--no-undo", action="store_true", help="keep the changes action utterances make")
    ap.add_argument("--user-id", type=int, default=5)
    ap.add_argument("--display-name", default="Ed Honour")
    ap.add_argument("--role", default="owner")
    ap.add_argument("--url", default="http://127.0.0.1:8765")
    ap.add_argument("--list", action="store_true", help="parse EVAL.md and print the cases without running")
    args = ap.parse_args()

    cases = parse_eval()
    if args.only:
        cases = [c for c in cases if c.section == args.only]
    cases = select(cases, args.ids)
    if args.list:
        for c in cases:
            print(f"{c.id:5} {c.surface:11} {c.context:28} {c.expect:40} {c.utterance}")
        print(f"{len(cases)} cases")
        return 0

    manifest = load_manifest()
    user = {"id": args.user_id, "display_name": args.display_name, "role": args.role}
    with httpx.Client(timeout=90) as client:
        health = client.get(args.url.rstrip("/") + "/health").json()
        print(f"service mode: {health.get('mode')}  router {health.get('router_model')}@{health.get('router_effort')}  ama {health.get('ama_model')}")
        if health.get("mode") == "unconfigured":
            print("ANTHROPIC_API_KEY is not set; every turn would answer 'not configured'. Set it and restart processcore-assistant.")
            return 2
        RESULTS_DIR.mkdir(exist_ok=True)
        out_path = RESULTS_DIR / (dt.datetime.now().strftime("%Y%m%d-%H%M%S") + ".jsonl")
        tally: dict[str, dict[str, int]] = {}
        latencies: dict[str, list[int]] = {}
        with out_path.open("w") as out:
            for case in cases:
                result = turn(client, args.url, user, case, case.utterance, None)
                verdict, note = score(case, result, manifest)
                record = {"id": case.id, "section": case.section, "surface": case.surface, "context": case.context,
                          "utterance": case.utterance, "expect": case.expect, "verdict": verdict, "note": note,
                          "reply": result.get("reply"), "navigate": result.get("navigate"), "undo_id": result.get("undo_id"),
                          "refresh": result.get("refresh"), "needs_confirmation": result.get("needs_confirmation"),
                          "tool_calls": result.get("tool_calls"), "duration_ms": result.get("duration_ms"),
                          "wall_ms": result.get("wall_ms"), "cost_usd": result.get("cost_usd"), "error": result.get("error"),
                          "mode": result.get("mode"), "http_status": result.get("http_status")}
                if result.get("undo_id") and not args.no_undo and case.section == "actions":
                    undo = turn(client, args.url, user, case, "undo that", result.get("session_id"))
                    record["undo_followup"] = {"reply": undo.get("reply"), "tool_calls": undo.get("tool_calls"),
                                               "undid": any(str(c.get("tool", "")).endswith("__undo_last") for c in undo.get("tool_calls", []))}
                out.write(json.dumps(record, default=str) + "\n")
                out.flush()
                tally.setdefault(case.section, {"pass": 0, "soft": 0, "fail": 0})[verdict] += 1
                latencies.setdefault(case.section, []).append(int(result.get("wall_ms") or 0))
                print(f"{verdict.upper():4} {case.id:5} {int(result.get('wall_ms') or 0):6} ms  {case.utterance[:60]:60}  {note[:90]}")
                sys.stdout.flush()
        print("\nsection     pass  soft  fail  median ms")
        for section, t in tally.items():
            lat = sorted(latencies[section])
            print(f"{section:10} {t['pass']:5} {t['soft']:5} {t['fail']:5}  {lat[len(lat) // 2] if lat else 0:9}")
        print(f"\nresults: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
