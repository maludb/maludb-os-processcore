"""Shared helpers: client time zone, time windows, JSON shaping, tool errors."""
from __future__ import annotations

import re
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from functools import lru_cache
from typing import Any
from zoneinfo import ZoneInfo

from mcp.server.mcpserver.exceptions import ToolError

from common import config

LITERS_PER_GALLON = 3.785411784
KG_PER_POUND = 0.45359237
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

PERIOD_HELP = ("today, yesterday, this_week, last_week, last_7_days, last_30_days, this_month, last_month, this_year, "
               "a weekday name ('tuesday' = the most recent Tuesday, 'last tuesday' = the Tuesday of last week)")

_tz_name: str | None = None


def set_timezone(name: str | None) -> None:
    global _tz_name
    _tz_name = name


@lru_cache(maxsize=4)
def _zone(name: str) -> ZoneInfo:
    return ZoneInfo(name)


def tz() -> ZoneInfo:
    """Client time zone: app.client_settings when readable (set at startup), else
    PROCESSCORE_TIMEZONE, else the application default America/New_York."""
    return _zone(_tz_name or config.get("PROCESSCORE_TIMEZONE", "America/New_York") or "America/New_York")


def now() -> datetime:
    return datetime.now(tz())


def fail(message: str) -> None:
    raise ToolError(message)


def _start_of(d: date) -> datetime:
    return datetime.combine(d, time.min, tzinfo=tz())


def period_bounds(period: str) -> tuple[datetime, datetime]:
    """Expand a period keyword into [start, end) in the client time zone."""
    p = period.strip().lower().replace("-", "_").replace(" ", "_")
    today = now().date()
    if p == "today":
        return _start_of(today), _start_of(today + timedelta(days=1))
    if p == "yesterday":
        return _start_of(today - timedelta(days=1)), _start_of(today)
    if p == "this_week":
        start = today - timedelta(days=today.weekday())
        return _start_of(start), _start_of(today + timedelta(days=1))
    if p == "last_week":
        start = today - timedelta(days=today.weekday() + 7)
        return _start_of(start), _start_of(start + timedelta(days=7))
    m = re.fullmatch(r"last_(\d{1,4})_days?", p)
    if m:
        return _start_of(today - timedelta(days=int(m.group(1)) - 1)), _start_of(today + timedelta(days=1))
    if p == "this_month":
        return _start_of(today.replace(day=1)), _start_of(today + timedelta(days=1))
    if p == "last_month":
        first = today.replace(day=1)
        prev = (first - timedelta(days=1)).replace(day=1)
        return _start_of(prev), _start_of(first)
    if p == "this_year":
        return _start_of(today.replace(month=1, day=1)), _start_of(today + timedelta(days=1))
    last = p.startswith("last_")
    name = p[5:] if last else p
    if name in WEEKDAYS:
        target = WEEKDAYS.index(name)
        if last:  # the named day in the previous calendar week
            monday_last_week = today - timedelta(days=today.weekday() + 7)
            d = monday_last_week + timedelta(days=target)
        else:     # the most recent such day, today included
            d = today - timedelta(days=(today.weekday() - target) % 7)
        return _start_of(d), _start_of(d + timedelta(days=1))
    fail(f"Unknown period '{period}'. Use one of: {PERIOD_HELP}; or give date_from/date_to as ISO dates.")
    raise AssertionError


def parse_when(value: str, *, end: bool = False) -> datetime:
    """ISO date or datetime (client time zone when no offset). A bare date used as
    an end bound means the end of that day."""
    text = value.strip()
    try:
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
            d = date.fromisoformat(text)
            return _start_of(d + timedelta(days=1)) if end else _start_of(d)
        dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        try:
            start, stop = period_bounds(text)
            return stop if end else start
        except ToolError:
            fail(f"'{value}' is not a date. Use an ISO date (2026-10-01), an ISO datetime (2026-10-01T14:00), or a period: {PERIOD_HELP}.")
            raise
    return dt if dt.tzinfo else dt.replace(tzinfo=tz())


def window(date_from: str | None, date_to: str | None, period: str | None) -> tuple[datetime | None, datetime | None]:
    start = end = None
    if period:
        start, end = period_bounds(period)
    if date_from:
        start = parse_when(date_from)
    if date_to:
        end = parse_when(date_to, end=True)
    if start and end and start >= end:
        fail("date_from must be before date_to.")
    return start, end


def window_out(start: datetime | None, end: datetime | None) -> dict[str, Any]:
    return {"from": iso(start), "to": iso(end), "time_zone": str(tz())}


def iso(value: Any) -> Any:
    if isinstance(value, datetime):
        return value.astimezone(tz()).isoformat(timespec="seconds")
    if isinstance(value, date):
        return value.isoformat()
    return value


def with_display(value: Any) -> Any:
    """Recursively add display values beside base-unit keys in payloads:
    *_l (liters) gains *_gal, *_kg gains *_lb."""
    if isinstance(value, dict):
        out: dict[str, Any] = {}
        for k, v in value.items():
            out[k] = with_display(v)
            num = _num(v)
            if num is not None and isinstance(k, str):
                if k.endswith("_l") or k == "liters":
                    out[(k[:-2] if k.endswith("_l") else k) + "_gal"] = round(num / LITERS_PER_GALLON, 3)
                elif k.endswith("_kg"):
                    out[k[:-3] + "_lb"] = round(num / KG_PER_POUND, 3)
        return out
    if isinstance(value, list):
        return [with_display(v) for v in value]
    return value


def _num(v: Any) -> float | None:
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float, Decimal)):
        return float(v)
    if isinstance(v, str) and re.fullmatch(r"-?\d+(\.\d+)?", v):
        return float(v)
    return None


def clean(value: Any) -> Any:
    """JSON-safe: datetimes to ISO in the client zone, Decimals to floats."""
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [clean(v) for v in value]
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime, date)):
        return iso(value)
    return value


def human_duration(seconds: float | None) -> str | None:
    if seconds is None:
        return None
    if seconds < 1:
        return "under 1s"
    seconds = int(round(seconds))
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, secs = divmod(rem, 60)
    parts = [f"{days}d"] if days else []
    if hours:
        parts.append(f"{hours}h")
    if minutes:
        parts.append(f"{minutes}m")
    if secs and not days:
        parts.append(f"{secs}s")
    return " ".join(parts) or "0s"
