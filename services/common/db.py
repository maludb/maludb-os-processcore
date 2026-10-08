"""Async connection pools. The read servers query through their read-only role;
the 'app' pool (processcore_app) is used only for token checks and activity logging."""
from __future__ import annotations

from typing import Any

from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

from . import config

_pools: dict[str, AsyncConnectionPool] = {}


async def pool(role: str) -> AsyncConnectionPool:
    if role not in _pools:
        p = AsyncConnectionPool(config.dsn(role), min_size=1, max_size=8, open=False,
                                kwargs={"row_factory": dict_row, "autocommit": True})
        await p.open()
        _pools[role] = p
    return _pools[role]


async def fetch_all(role: str, sql: str, params: dict[str, Any] | tuple | None = None, *, timeout_ms: int = 15000) -> list[dict[str, Any]]:
    p = await pool(role)
    async with p.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(f"SET statement_timeout = {int(timeout_ms)}")
            await cur.execute(sql, params)
            return list(await cur.fetchall()) if cur.description else []


async def fetch_one(role: str, sql: str, params: dict[str, Any] | tuple | None = None) -> dict[str, Any] | None:
    rows = await fetch_all(role, sql, params)
    return rows[0] if rows else None


async def execute(role: str, sql: str, params: dict[str, Any] | tuple | None = None) -> None:
    p = await pool(role)
    async with p.connection() as conn:
        await conn.execute(sql, params)


async def close_all() -> None:
    for p in _pools.values():
        await p.close()
    _pools.clear()
