"""Compliance and traceability tools (R47, R48, R51, R53, R54) and the guarded long-tail records_search."""
from __future__ import annotations

import calendar
import datetime as dt
import re
from typing import Literal
from zoneinfo import ZoneInfo

from pydantic import Field, model_validator

from common import db, sql_guard

from . import fmt, queries as Q
from .registry import Input, Paged, ToolFailure, page, records_tool
from .resolve import echo, resolve, resolve_opt, rid
from .tools_receiving import check_range, std

DESTINATIONS = Literal["tax_paid_sale", "taproom_transfer", "in_bond_transfer", "export", "sample_testing", "destroyed", "breakage",
                       "family_use", "return_from_customer"]


def gal(liters) -> float | None:
    return fmt.gallons(liters)


def parse_period(period: str) -> tuple[dt.date, dt.date]:
    m = re.fullmatch(r"(\d{4})-(0[1-9]|1[0-2])", period)
    if m:
        y, mo = int(m[1]), int(m[2])
        return dt.date(y, mo, 1), dt.date(y, mo, calendar.monthrange(y, mo)[1])
    m = re.fullmatch(r"(\d{4})-Q([1-4])", period, re.IGNORECASE)
    if m:
        y, q = int(m[1]), int(m[2])
        end_month = q * 3
        return dt.date(y, end_month - 2, 1), dt.date(y, end_month, calendar.monthrange(y, end_month)[1])
    m = re.fullmatch(r"(\d{4})", period)
    if m:
        return dt.date(int(m[1]), 1, 1), dt.date(int(m[1]), 12, 31)
    raise ToolFailure(f"Period '{period}' is not understood; use YYYY-MM, YYYY-Qn or YYYY, or give period_start and period_end.")


class PeriodMixin(Input):
    period: str | None = Field(None, max_length=10, description="Reporting period: '2026-10' (month), '2026-Q4' (quarter) or '2026' (year).")
    period_start: dt.date | None = Field(None, description="First day of the period (instead of period).")
    period_end: dt.date | None = Field(None, description="Last day of the period (instead of period).")
    premises: str | None = Field(None, max_length=120, description="Premises; default all.")

    def bounds(self) -> tuple[dt.date, dt.date] | None:
        if self.period:
            return parse_period(self.period)
        if self.period_start or self.period_end:
            if not (self.period_start and self.period_end):
                raise ToolFailure("Give both period_start and period_end, or a period such as '2026-10'.")
            check_range(self.period_start, self.period_end)
            return self.period_start, self.period_end
        return None


@records_tool("compliance_period_summary", "Gallons produced, removed and lost in a period",
              """Call for how many gallons were produced, bottled, removed tax paid, removed in bond, exported, returned and lost in
              a period (R47), by tax class, with the TTB 5120.17 line each figure feeds. Derived live from stage events (produced
              by fermentation), the ledger (bottled), posted removals and reportable loss events; also lists any period report
              already generated for the period. Default period: the current month.""")
async def compliance_period_summary(p: PeriodMixin) -> dict:
    premises = await resolve_opt("premises", p.premises)
    today = fmt.today()
    start, end = p.bounds() or (today.replace(day=1), today.replace(day=calendar.monthrange(today.year, today.month)[1]))
    args = {"premises_id": rid(premises), "start": start, "end": end, "tz": fmt.tz()}
    produced = await db.fetch_all("records", Q.PERIOD_PRODUCED, args)
    bottled = await db.fetch_all("records", Q.PERIOD_BOTTLED, args)
    removals = await db.fetch_all("records", Q.PERIOD_REMOVALS, args)
    losses = await db.fetch_all("records", Q.PERIOD_LOSSES, args)
    taxes = await db.fetch_all("records", Q.PERIOD_TAX, args)
    reports = await db.fetch_all("records", Q.PERIOD_REPORTS_COVERING, args)
    lines = await db.fetch_all("records", Q.TTB_LINES)

    def line_for(source: str, key: str, value: str, bulk: bool | None = None) -> str | None:
        for l in lines:
            m = l["match"]
            if l["source"] == source and m.get(key) == value and (bulk is None or "bulk" not in m or m["bulk"] == bulk):
                return f"{l['section']}{l['line_code']}"
        return None

    def row(tax_class, liters, **extra):
        return fmt.drop_none({"tax_class": tax_class or "(undetermined)", "liters": round(float(liters or 0), 2), "gallons": gal(liters), **extra})

    removed_groups: dict[str, float] = {}
    rem_rows = []
    for r in removals:
        group = {"tax_paid_sale": "removed_tax_paid", "taproom_transfer": "removed_tax_paid", "in_bond_transfer": "removed_in_bond",
                 "export": "exported", "return_from_customer": "returned_to_bond"}.get(r["destination_kind"], "other_removals")
        removed_groups[group] = removed_groups.get(group, 0.0) + float(r["liters"] or 0) * (1 if group != "returned_to_bond" else 1)
        rem_rows.append(row(r["tax_class"], r["liters"], destination=r["destination_kind"], group=group, removals=r["removals"],
                            ttb_line=line_for("removal", "destination_kind", r["destination_kind"], False)))
    loss_rows = [row(l["tax_class"], l["liters"], ttb_category=l["ttb_category"], bulk=l["target_kind"] == "batch", events=l["events"],
                     ttb_line=line_for("loss", "ttb_category", l["ttb_category"], l["target_kind"] == "batch")) for l in losses]
    total = lambda rows: gal(sum(float(r["liters"] or 0) for r in rows))
    return {
        "resolved": echo(premises=premises), "period": [start, end],
        "totals_gal": {"produced": total(produced), "bottled": total(bottled), **{k: gal(v) for k, v in removed_groups.items()}, "lost": total(losses)},
        "produced_by_fermentation": [row(r["tax_class"], r["liters"], events=r["events"], ttb_line="A2") for r in produced],
        "bottled_or_packed": [row(r["tax_class"], r["liters"], events=r["events"], ttb_line="A13/B2") for r in bottled],
        "removals": rem_rows, "losses": loss_rows,
        "tax": [fmt.drop_none({"tax_class": t["tax_class"] or "(undetermined)", "tax_amount": fmt.money(t["tax_amount"]), "taxed_gallons": t["taxed_gallons"]}) for t in taxes],
        "period_reports": [dict(r) for r in reports],
        "note": "Removed tax paid includes taproom transfers. Returns to bond add back to bottled inventory. Reversed removals still count in their "
                "period; the reversal is its own document. For the filed figures use compliance_report.",
    }


class BulkVsBottledInput(Input):
    as_of: dt.date | None = Field(None, description="At the end of this date (ISO); default the end of today.")
    premises: str | None = Field(None, max_length=120, description="Premises; default all.")


@records_tool("compliance_bulk_vs_bottled", "Gallons in bulk versus packaged",
              """Call for how many gallons are in bulk versus packaged, by tax class (R48). Bulk is cider in vessels (open batch
              occupancies); packaged is finished-lot stock from the ledger, split bonded and tax-paid. Juice in vessels that is not yet
              fermented is listed separately.""")
async def compliance_bulk_vs_bottled(p: BulkVsBottledInput) -> dict:
    premises = await resolve_opt("premises", p.premises)
    zone = ZoneInfo(fmt.tz())
    at = dt.datetime.combine((p.as_of or fmt.today()) + dt.timedelta(days=1), dt.time(), zone)  # end of the day
    args = {"premises_id": rid(premises), "at": at}
    bulk = await db.fetch_all("records", Q.BULK_AT, args)
    juice = await db.fetch_all("records", Q.JUICE_AT, args)
    packaged = await db.fetch_all("records", Q.PACKAGED_AT, args)
    classes: dict[str, dict] = {}
    for b in bulk:
        c = classes.setdefault(b["tax_class"] or "(undetermined)", {"bulk_l": 0.0, "packaged_bonded_l": 0.0, "packaged_tax_paid_l": 0.0})
        c["bulk_l"] += float(b["liters"] or 0)
    for k in packaged:
        c = classes.setdefault(k["tax_class"] or "(undetermined)", {"bulk_l": 0.0, "packaged_bonded_l": 0.0, "packaged_tax_paid_l": 0.0})
        c["packaged_bonded_l" if k["tax_state"] == "bonded" else "packaged_tax_paid_l"] += float(k["liters"] or 0)
    by_class = [{"tax_class": k, "bulk_gal": gal(v["bulk_l"]), "packaged_bonded_gal": gal(v["packaged_bonded_l"]),
                 "packaged_tax_paid_gal": gal(v["packaged_tax_paid_l"]), "bulk_l": round(v["bulk_l"], 2),
                 "packaged_l": round(v["packaged_bonded_l"] + v["packaged_tax_paid_l"], 2)} for k, v in classes.items()]
    return {"resolved": echo(premises=premises), "as_of": at, "by_tax_class": by_class,
            "bulk_batches": [fmt.drop_none({"tax_class": b["tax_class"], "gallons": gal(b["liters"]), "batches": b["batch_numbers"]}) for b in bulk],
            "packaged_lots": [fmt.drop_none({"tax_class": k["tax_class"], "tax_state": k["tax_state"], "units": k["units"], "gallons": gal(k["liters"]), "lots": k["lots"]}) for k in packaged],
            "juice_not_yet_wine": [{"item": j["item_name"], "gallons": gal(j["liters"]), "lots": j["lot_numbers"]} for j in juice],
            "totals_gal": {"bulk": gal(sum(v["bulk_l"] for v in classes.values())),
                           "packaged": gal(sum(v["packaged_bonded_l"] + v["packaged_tax_paid_l"] for v in classes.values()))}}


class RemovalsInput(Paged):
    destination_kind: DESTINATIONS | None = Field(None, description="e.g. taproom_transfer, tax_paid_sale, in_bond_transfer, export, return_from_customer.")
    customer: str | None = Field(None, max_length=120, description="Customer name.")
    date_from: dt.date | None = Field(None, description="Removed on or after (ISO date). For 'last month' pass its first day.")
    date_to: dt.date | None = Field(None, description="Removed on or before (ISO date).")
    status: Literal["draft", "posted", "reversed", "cancelled"] | None = Field(None, description="Only this status (default all).")


@records_tool("compliance_removals", "Removals from the premises",
              """Call for what was removed (sold tax paid, moved to the taproom, transferred in bond, exported, sampled, destroyed)
              or returned in a period, e.g. what went to the taproom last month (R51). Each removal: number, date, destination,
              customer, status, reference, lines (lot, product, package, units, liters and gallons, keg), tax class, rate and tax;
              plus totals by destination and status.""")
async def compliance_removals(p: RemovalsInput) -> dict:
    check_range(p.date_from, p.date_to)
    customer = await resolve_opt("customer", p.customer)
    args = std(p, destination_kind=p.destination_kind, customer_id=rid(customer), status=p.status, date_from=p.date_from, date_to=p.date_to)
    rows = await db.fetch_all("records", Q.REMOVALS, args)
    totals = await db.fetch_all("records", Q.REMOVAL_TOTALS, args)
    return page([fmt.drop_none(dict(r)) for r in rows], p, resolved=echo(customer=customer),
                totals=[fmt.drop_none({**dict(t), "volume_l": None, "volume": fmt.liters(t["volume_l"]), "tax_amount": fmt.money(t["tax_amount"])}) for t in totals])


class ReportInput(PeriodMixin):
    report_number: str | None = Field(None, max_length=40, description="Report number such as RPT-00001.")
    include_source_ids: bool = Field(False, description="Include the ledger, loss and removal ids behind each line.")


@records_tool("compliance_report", "Generated TTB period report",
              """Call for a generated TTB 5120.17 report (R47): its header, status (draft, final, filed), totals and tax by class,
              reconciliation, and every line (section, line code, label, tax class, value, unit, count of source rows). Give a
              report number or a period; with neither, lists recent reports.""")
async def compliance_report(p: ReportInput) -> dict:
    premises = await resolve_opt("premises", p.premises)
    bounds = p.bounds()
    if p.report_number:
        report_id = (await resolve("report", p.report_number))["id"]
    elif bounds:
        r = await db.fetch_one("records", Q.REPORT_FOR_PERIOD, {"premises_id": rid(premises), "start": bounds[0], "end": bounds[1]})
        if r is None:
            listed = await db.fetch_all("records", Q.REPORT_LIST, {"premises_id": rid(premises), "lim": 10, "off": 0})
            raise ToolFailure(f"No report covers exactly {bounds[0]} to {bounds[1]}. Reports on file: "
                              + (", ".join(f"{x['number']} ({x['period_start']} to {x['period_end']}, {x['status']})" for x in listed) or "none")
                              + ". compliance_period_summary computes the figures for any period.")
        report_id = r["id"]
    else:
        rows = await db.fetch_all("records", Q.REPORT_LIST, {"premises_id": rid(premises), "lim": 51, "off": 0})
        return {"count": len(rows[:50]), "reports": [fmt.drop_none(dict(r)) for r in rows[:50]]}
    header = await db.fetch_one("records", Q.REPORT_HEADER, {"report_id": report_id})
    lines = await db.fetch_all("records", Q.REPORT_LINES, {"report_id": report_id})
    out_lines = []
    for l in lines:
        d = fmt.drop_none(dict(l))
        if not p.include_source_ids:
            d.pop("source_ids", None)
        if d.get("is_adjustment") is False:
            d.pop("is_adjustment")
        out_lines.append(d)
    return {"report": fmt.drop_none(dict(header)), "lines": out_lines}


class TraceForwardInput(Input):
    lot_number: str = Field(..., min_length=2, max_length=60, description="The suspect lot: supplier lot number or our lot number (fruit, juice, yeast, additive...).")


@records_tool("trace_forward", "Forward trace from a lot (recall)",
              """Call when a supplier lot is bad and you need which batches, which packages and which customers it reached (R53).
              Follows consumption into batches (also through press runs for fruit), through splits and blends to every descendant
              batch, to finished lots (units still on hand), to posted removals and the customers who received them; also kegs
              currently holding those lots.""")
async def trace_forward(p: TraceForwardInput) -> dict:
    lot = await resolve("lot", p.lot_number)
    rows = await db.fetch_all("records", Q.TRACE_FORWARD, {"lot_id": lot["id"]})
    batches = [fmt.drop_none({"level": r["level"], "batch": r["label"], **(r["detail"] or {})}) for r in rows if r["kind"] == "batch"]
    finished = [fmt.drop_none({"level": r["level"], "lot_number": r["label"], "units_on_hand": r["units_on_hand"], "quality_status": r["quality_status"],
                               **(r["detail"] or {})}) for r in rows if r["kind"] == "finished_lot"]
    agg: dict[str, dict] = {}
    for r in rows:
        if r["kind"] != "removal":
            continue
        d = r["detail"] or {}
        e = agg.setdefault(r["label"], fmt.drop_none({"removal": r["label"], "customer": r["customer_name"], "destination": d.get("destination"),
                                                      "removed_at": d.get("removed_at"), "units": 0}))
        e["units"] += int(d.get("units") or 0)
    removals = sorted(agg.values(), key=lambda e: e.get("removed_at") or "")
    kegs = await db.fetch_all("records", Q.KEGS_HOLDING_LOTS, {"lot_numbers": [f["lot_number"] for f in finished]}) if finished else []
    customers = sorted({r["customer"] for r in removals if r.get("customer")})
    return {"resolved": echo(lot=lot), "batches": batches, "finished_lots": finished, "removals": removals, "customers": customers,
            "kegs_holding_affected_lots": [dict(k) for k in kegs],
            "summary": {"batches": len({b["batch"] for b in batches}), "finished_lots": len({f["lot_number"] for f in finished}),
                        "units_still_on_hand": sum(float(f.get("units_on_hand") or 0) for f in finished), "removals": len(removals), "customers": len(customers)},
            "note": None if rows else "Nothing downstream: the lot has not been consumed by any batch or press run."}


class TraceBackwardInput(Input):
    lot_number: str | None = Field(None, max_length=60, description="Finished lot (the code on the returned can, case or keg).")
    batch_number: str | None = Field(None, max_length=40, description="Or a batch.")

    @model_validator(mode="after")
    def one_of(self):
        if bool(self.lot_number) == bool(self.batch_number):
            raise ValueError("Give exactly one of lot_number (finished) or batch_number.")
        return self


@records_tool("trace_backward", "Backward trace from a can or batch",
              """Call when a customer returns a bad can or keg: which batch it came from, which ingredient lots and suppliers went in,
              and which other packages share them (R54). Returns the batch and its ancestors, every consumed lot with supplier and
              supplier lot, the fruit lots behind pressed juice, and other finished lots from the same batch tree or sharing an
              ingredient lot, with units on hand.""")
async def trace_backward(p: TraceBackwardInput) -> dict:
    exclude = None
    if p.lot_number:
        lot = await resolve("lot", p.lot_number)
        fl = await db.fetch_one("records", Q.FINISHED_LOT, {"lot_id": lot["id"]})
        if fl is None:
            raise ToolFailure(f"{lot['label']} ({lot['detail']}) is not a finished lot. For an ingredient lot use trace_forward; for a batch give batch_number.")
        batch_id, exclude, resolved = fl["batch_id"], lot["id"], echo(lot=lot)
        start = {"finished_lot": fl["lot_number"], "batch": fl["batch_number"], "product": fl["product_name"], "packaged_on": fl["packaged_on"]}
    else:
        batch = await resolve("batch", p.batch_number)
        batch_id, resolved, start = batch["id"], echo(batch=batch), {"batch": batch["label"]}
    rows = await db.fetch_all("records", Q.TRACE_BACKWARD, {"batch_id": batch_id})
    batch_rows = [r for r in rows if r["kind"] == "batch"]
    lots = [r for r in rows if r["kind"] == "lot"]
    lot_ids = [x["id"] for x in await db.fetch_all("records", Q.LOT_IDS_BY_NUMBER, {"n": [l["label"] for l in lots]})] if lots else []
    batch_ids = [x["id"] for x in await db.fetch_all("records", Q.BATCH_IDS_BY_NUMBER, {"n": [b["label"] for b in batch_rows]})]
    siblings = await db.fetch_all("records", Q.SIBLING_FINISHED_LOTS, {"batch_ids": batch_ids, "lot_ids": lot_ids, "exclude_lot_id": exclude})
    as_lot = lambda r: fmt.drop_none({"level": r["level"], "lot_number": r["label"], "supplier": r["supplier_name"], "supplier_lot_number": r["supplier_lot_number"],
                                       "quality_status": r["quality_status"], **(r["detail"] or {})})
    return {"resolved": resolved, "start": start,
            "batches": [fmt.drop_none({"level": b["level"], "batch": b["label"], **(b["detail"] or {})}) for b in batch_rows],
            "ingredient_lots": [as_lot(r) for r in lots], "fruit_lots": [as_lot(r) for r in rows if r["kind"] == "fruit_lot"],
            "suppliers": sorted({r["supplier_name"] for r in rows if r["supplier_name"]}),
            "other_finished_lots": [fmt.drop_none(dict(s)) for s in siblings]}


class SearchInput(Input):
    sql: str = Field(..., min_length=8, max_length=8000, description="One SELECT (or WITH ... SELECT) over the app schema. No semicolons or comments.")
    limit: int = Field(100, ge=1, le=200, description="Row cap (at most 200).")


SEARCH_DESCRIPTION = """Call only when no purpose-built records tool answers the question. Runs one read-only SELECT (or WITH ... SELECT)
over ProcessCore's record tables and views (schema app) as the read-only role with a 15 second timeout and a row cap; writes,
multiple statements, comments and session functions are refused. Quantities are base units (L, kg, ea): divide liters by 3.785411784
for gallons, kg by 0.45359237 for pounds, kg by 907.18474 for tons. Timestamps are UTC timestamptz; the client time zone is {tz}.
Status columns hold codes such as 'posted', 'released', 'active'. Schema (table: column:type ...):
{schema}"""


@records_tool("records_search", "Read-only SQL over the records (long tail)", "placeholder; replaced at startup")
async def records_search(p: SearchInput) -> dict:
    try:
        sql = sql_guard.validate_select(p.sql, max_rows=p.limit + 1)
    except ValueError as exc:
        raise ToolFailure(str(exc))
    rows = await db.fetch_all("records", sql)
    more = len(rows) > p.limit
    rows = rows[:p.limit]
    return {"count": len(rows), "truncated": more, "columns": list(rows[0].keys()) if rows else [], "rows": rows}
