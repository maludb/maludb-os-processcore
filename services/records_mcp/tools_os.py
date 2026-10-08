"""The Business OS kernel's tools on the records server (os-adoption 2026-10-04).

- app_roles: the roles this application offers and the rights each gives (os.app-roles/1), from db/021's catalogue —
  the one tool the kernel's own token may call (roles-and-rights.md).
- find_<kind>: one resolver per entity kind the kernel's actions server must turn a label into an id for
  (deploy/kernel-registry-processcore.json). Answers {"rows": [{"<kind>_id", "label", "detail"}]} for `q`.
"""
from __future__ import annotations

from pydantic import Field

from common import db

from . import resolve
from .registry import Input, records_tool


class NoInput(Input):
    pass


@records_tool("app_roles", "Roles and rights",
              """The roles ProcessCore offers and the rights each gives (os.app-roles/1), read by the Business OS kernel to grant
              people and agents. Not for answering questions about records.""")
async def app_roles(p: NoInput) -> dict:
    rights = await db.fetch_all("records", "SELECT right_key, description FROM app.app_rights ORDER BY sort_order")
    roles = await db.fetch_all("records", "SELECT role_key, name, description, capability, is_admin, rights FROM app.mcp_app_roles ORDER BY sort_order")
    return {"schema": "os.app-roles/1",
            "rights": [{"key": r["right_key"], "description": r["description"]} for r in rights],
            "roles": [{"key": r["role_key"], "name": r["name"], "description": r["description"], "capability": r["capability"],
                       "is_admin": bool(r["is_admin"]), "rights": list(r["rights"] or [])} for r in roles]}


class FindInput(Input):
    q: str = Field(..., min_length=1, max_length=120, description="A number (B-26-001, L-261001-004, PO-00001), a name, a fragment, or id:<n>.")
    limit: int = Field(6, ge=1, le=25, description="At most this many candidates.")


def _make(kind: str):
    k = resolve.KINDS[kind]

    async def find(p: FindInput) -> dict:
        rows = await resolve.candidates(kind, p.q, p.limit)
        return {"rows": [{f"{kind}_id": r["id"], "label": r["label"], "detail": r["detail"]} for r in rows], "hint": k.hint}

    find.__name__ = f"find_{kind}"
    find.__annotations__ = {"p": FindInput, "return": dict}
    records_tool(f"find_{kind}", f"Find a {k.noun}",
                 f"""Resolve what a person means by a {k.noun}: a number, a name or a fragment → the matching {k.noun}s with
                 their ids ({kind}_id) and labels. The Business OS kernel calls this before an action that names a {k.noun};
                 call it yourself when a label is ambiguous. {k.hint}""")(find)


for _kind in ("batch", "customer", "item", "keg", "lot", "order", "packaging_run", "po", "product", "receipt", "report", "sales_order", "supplier", "vessel", "location", "premises", "standing_order", "reason",
              "equipment", "press_run", "reservation"):
    _make(_kind)
