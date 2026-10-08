"""Customer orders, standing orders and planning tools (questions O1 to O8 in docs/cidery/12-customer-orders-design.md).

Prices and order values are left out unless the caller may see them (common.activity.current_show_prices:
owner and sales in the app's assistant; client tokens, which only owners create, always may). The planning
tools run the PHP projection engine (scripts/planning-json.php) under the read-only records role, so the
screens and the assistant give the same answer.
"""
from __future__ import annotations

import asyncio
import datetime as dt
import json
import os
from typing import Literal

from pydantic import Field

from common import db
from common.activity import current_show_prices
from common import config
from common.config import ROOT

from . import fmt
from .registry import Input, Paged, ToolFailure, page, records_tool
from .resolve import echo, resolve, resolve_opt, rid

ORDER_STATUS = Literal["open", "draft", "confirmed", "in_fulfillment", "shipped", "closed", "cancelled"]
LEVEL = Literal["firm", "standing", "all"]
LEVEL_HELP = "Demand counted: 'firm' (confirmed orders), 'standing' (firm plus standing-order dates, the default), 'all' (also the forecast)."
PRICE_KEYS = {"unit_price", "line_total", "order_value", "value", "value_each", "approx_cost", "demand_value_by_type"}


def _prices() -> bool:
    return current_show_prices.get()


def _strip_prices(obj):
    """Remove price and value fields, recursively, when the caller may not see them."""
    if _prices():
        return obj
    if isinstance(obj, dict):
        return {k: _strip_prices(v) for k, v in obj.items() if k not in PRICE_KEYS}
    if isinstance(obj, list):
        return [_strip_prices(v) for v in obj]
    return obj


ORDERS_SQL = """
SELECT so.number, so.status, so.origin, c.name AS customer, so.customer_reference, so.ordered_on, so.requested_on AS due_on,
       so.destination_kind, so.fulfilled_outside,
       (so.requested_on < current_date AND so.status IN ('confirmed', 'in_fulfillment')) AS overdue,
       SUM(l.units_ordered) AS units_ordered, SUM(l.units_shipped) AS units_shipped, SUM(l.units_open) AS units_open, SUM(l.line_total) AS order_value,
       json_agg(json_build_object('line', l.line_no, 'product', l.product_name, 'format', l.configuration_name, 'units_ordered', l.units_ordered,
                                  'units_shipped', l.units_shipped, 'units_in_packaging_runs', l.units_in_packaging_runs, 'units_open', l.units_open,
                                  'unit_price', l.unit_price, 'line_total', l.line_total, 'line_status', l.line_status) ORDER BY l.line_no) AS lines
FROM app.sales_orders so
JOIN app.customers c ON c.id = so.customer_id
JOIN app.v_sales_order_lines l ON l.sales_order_id = so.id
WHERE (%(customer_id)s::bigint IS NULL OR so.customer_id = %(customer_id)s)
  AND (%(product_id)s::bigint IS NULL OR EXISTS (SELECT 1 FROM app.v_sales_order_lines x WHERE x.sales_order_id = so.id AND x.product_id = %(product_id)s))
  AND (%(status)s::text IS NULL OR (%(status)s = 'open' AND so.status IN ('draft', 'confirmed', 'in_fulfillment')) OR so.status = %(status)s)
  AND (%(due_from)s::date IS NULL OR so.requested_on >= %(due_from)s)
  AND (%(due_to)s::date IS NULL OR so.requested_on <= %(due_to)s)
  AND (%(origin)s::text IS NULL OR so.origin = %(origin)s)
  AND (%(order_id)s::bigint IS NULL OR so.id = %(order_id)s)
GROUP BY so.id, c.name
ORDER BY so.requested_on, so.number
LIMIT %(lim)s OFFSET %(off)s
"""


class OrdersFindInput(Paged):
    customer: str | None = Field(None, max_length=120, description="Customer name (part is fine).")
    product: str | None = Field(None, max_length=120, description="Only orders with a line of this product.")
    status: ORDER_STATUS | None = Field("open", description="'open' (draft, confirmed, in fulfillment; the default), one status, or null for all.")
    due_from: dt.date | None = Field(None, description="Due on or after.")
    due_to: dt.date | None = Field(None, description="Due on or before.")
    origin: Literal["entered", "imported", "standing", "assistant"] | None = Field(None, description="How the order came in.")


@records_tool("orders_find", "Customer orders",
              """Call for which customer orders there are: "what orders does Joe's Taproom have?", "what's due this week?", "which orders
              are overdue?" (O1). Orders by due date with customer, reference, status, units ordered, shipped and open, and lines by
              product and format; value for owner and sales. Default: open orders.""")
async def orders_find(p: OrdersFindInput) -> dict:
    customer = await resolve_opt("customer", p.customer)
    product = await resolve_opt("product", p.product)
    rows = await db.fetch_all("records", ORDERS_SQL, {"customer_id": rid(customer), "product_id": rid(product), "status": p.status, "due_from": p.due_from,
                                                     "due_to": p.due_to, "origin": p.origin, "order_id": None, "lim": p.limit + 1, "off": p.offset})
    rows = [fmt.drop_none(_strip_prices(dict(r))) for r in rows]
    return page(rows, p, resolved=echo(customer=customer, product=product))


class OrderStatusInput(Input):
    order: str = Field(..., max_length=60, description="Order number (SO-00042) or the customer's PO reference.")


@records_tool("order_status", "Where is an order",
              """Call for where one customer order stands: "where is SO-00042?", "has Joe's PO 1042 shipped?" (O2). Lines with ordered,
              in packaging runs, shipped and open units; its packaging runs (number, status, units for the order) and shipments
              (removals, with returns and reversals).""")
async def order_status(p: OrderStatusInput) -> dict:
    order = await resolve("sales_order", p.order)
    rows = await db.fetch_all("records", ORDERS_SQL, {"customer_id": None, "product_id": None, "status": None, "due_from": None, "due_to": None,
                                                     "origin": None, "order_id": order["id"], "lim": 1, "off": 0})
    if not rows:
        raise ToolFailure(f"Order {order['label']} has no lines.")
    runs = await db.fetch_all("records", """
        SELECT pr.number, pr.status, pr.run_on, b.number AS batch, pc.name AS format, SUM(prol.units) AS units_for_order
        FROM app.packaging_run_order_lines prol JOIN app.sales_order_lines ol ON ol.id = prol.sales_order_line_id
        JOIN app.packaging_runs pr ON pr.id = prol.packaging_run_id JOIN app.batches b ON b.id = pr.batch_id
        JOIN app.packaging_configurations pc ON pc.id = pr.packaging_configuration_id
        WHERE ol.sales_order_id = %(id)s GROUP BY pr.id, b.number, pc.name ORDER BY pr.run_on""", {"id": order["id"]})
    shipments = await db.fetch_all("records", """
        SELECT r.number, r.direction, r.status, r.removed_at, (SELECT SUM(units) FROM app.removal_lines rl WHERE rl.removal_id = r.id) AS units
        FROM app.removals r WHERE r.sales_order_id = %(id)s ORDER BY r.removed_at""", {"id": order["id"]})
    return {"resolved": echo(order=order), "order": fmt.drop_none(_strip_prices(dict(rows[0]))),
            "packaging_runs": [fmt.drop_none(dict(r)) for r in runs], "shipments": [fmt.drop_none(dict(r)) for r in shipments]}


class OrdersHistoryInput(Input):
    group_by: Literal["customer", "product", "format", "month"] = Field("customer", description="How to group.")
    customer: str | None = Field(None, max_length=120, description="Only this customer.")
    date_from: dt.date | None = Field(None, description="Due on or after (default 12 months ago).")
    date_to: dt.date | None = Field(None, description="Due on or before (default today).")


@records_tool("orders_history", "Order history",
              """Call for what customers ordered over a period: "what did we sell to Green Mountain last quarter?", "best-selling format this
              year?", "orders by month" (O3). Groups confirmed, in-fulfillment, shipped and closed orders (history fulfilled outside the
              system included) by customer, product, format or month: orders, units ordered and shipped, and value for owner and sales.""")
async def orders_history(p: OrdersHistoryInput) -> dict:
    customer = await resolve_opt("customer", p.customer)
    today = fmt.today()
    d_from = p.date_from or today.replace(year=today.year - 1)
    d_to = p.date_to or today
    label, key = {
        "product": ("l.product_name", "l.product_id"),
        "format": ("l.product_name || ' — ' || l.configuration_name", "l.packaging_configuration_id"),
        "month": ("to_char(date_trunc('month', l.requested_on), 'YYYY-MM')", "date_trunc('month', l.requested_on)"),
    }.get(p.group_by, ("l.customer_name", "l.customer_id"))
    rows = await db.fetch_all("records", f"""
        SELECT {label} AS group_label, COUNT(DISTINCT l.sales_order_id) AS orders, SUM(l.units_ordered) AS units_ordered,
               SUM(l.units_shipped) AS units_shipped, SUM(l.line_total) AS value
        FROM app.v_sales_order_lines l
        WHERE l.order_status IN ('confirmed', 'in_fulfillment', 'shipped', 'closed') AND l.line_status <> 'cancelled'
          AND l.requested_on BETWEEN %(f)s AND %(t)s AND (%(c)s::bigint IS NULL OR l.customer_id = %(c)s)
        GROUP BY {label}, {key} ORDER BY {'1' if p.group_by == 'month' else 'units_ordered DESC'}""", {"f": d_from, "t": d_to, "c": rid(customer)})
    return {"resolved": echo(customer=customer), "period": [d_from, d_to], "group_by": p.group_by,
            "rows": [fmt.drop_none(_strip_prices(dict(r))) for r in rows]}


class StandingFindInput(Input):
    customer: str | None = Field(None, max_length=120, description="Only this customer.")
    include_paused: bool = Field(False, description="Also paused and ended standing orders.")


@records_tool("standing_orders_find", "Standing orders",
              """Call for recurring customer orders: "what are our standing orders?", "when does the taproom order next?" (O4). Each standing
              order: customer, schedule (weekly on a day, every N weeks, monthly on a day), start and end, whether it is running, lines per
              delivery, and its next dates with the order already made from a date, if any.""")
async def standing_orders_find(p: StandingFindInput) -> dict:
    customer = await resolve_opt("customer", p.customer)
    rows = await db.fetch_all("records", """
        SELECT s.id, s.number, c.name AS customer, s.frequency, s.interval_weeks, s.weekday, s.day_of_month, s.starts_on, s.ends_on,
               (s.active AND (s.ends_on IS NULL OR s.ends_on >= current_date)) AS running,
               (SELECT json_agg(json_build_object('product', p.name, 'format', pc.name, 'units', l.units, 'unit_price', COALESCE(l.unit_price, pc.default_unit_price)) ORDER BY l.line_no)
                  FROM app.standing_order_lines l JOIN app.packaging_configurations pc ON pc.id = l.packaging_configuration_id JOIN app.products p ON p.id = pc.product_id
                 WHERE l.standing_order_id = s.id) AS lines,
               (SELECT json_agg(json_build_object('date', o.occurs_on, 'order', so.number) ORDER BY o.occurs_on)
                  FROM (SELECT * FROM app.standing_order_occurrences(current_date, current_date + 60) x WHERE x.standing_order_id = s.id ORDER BY x.occurs_on LIMIT 6) o
                  LEFT JOIN app.sales_orders so ON so.standing_order_id = s.id AND so.standing_occurrence_on = o.occurs_on AND so.status <> 'cancelled') AS next_dates
        FROM app.standing_orders s JOIN app.customers c ON c.id = s.customer_id
        WHERE (%(c)s::bigint IS NULL OR s.customer_id = %(c)s) AND (%(all)s OR (s.active AND (s.ends_on IS NULL OR s.ends_on >= current_date)))
        ORDER BY c.name, s.number""", {"c": rid(customer), "all": p.include_paused})
    days = {1: "Monday", 2: "Tuesday", 3: "Wednesday", 4: "Thursday", 5: "Friday", 6: "Saturday", 7: "Sunday"}
    out = []
    for r in rows:
        d = dict(r)
        d["schedule"] = {"weekly": f"every week on {days.get(d['weekday'])}", "every_n_weeks": f"every {d['interval_weeks']} weeks on {days.get(d['weekday'])}",
                         "monthly": f"every month on day {d['day_of_month']}"}[d["frequency"]]
        for k in ("id", "frequency", "interval_weeks", "weekday", "day_of_month"):
            d.pop(k, None)
        out.append(fmt.drop_none(_strip_prices(d)))
    return {"resolved": echo(customer=customer), "count": len(out), "standing_orders": out}


async def _projection(level: str, weeks: int) -> dict:
    """Run the PHP projection engine under the read-only role and return its JSON."""
    keys = ("PROCESSCORE_DB_HOST", "PROCESSCORE_DB_PORT", "PROCESSCORE_DB_NAME", "PROCESSCORE_RECORDS_DB_USER", "PROCESSCORE_RECORDS_DB_PASSWORD")
    env = {**os.environ, **{k: config.get(k) or "" for k in keys}}
    proc = await asyncio.create_subprocess_exec("php", str(ROOT / "scripts" / "planning-json.php"), level, str(weeks), env=env,
                                                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=20)
    except asyncio.TimeoutError:
        proc.kill()
        raise ToolFailure("The projection took too long; try fewer weeks.")
    if proc.returncode != 0:
        raise ToolFailure("The projection failed: " + (err.decode().strip()[:300] or "no detail"))
    return _strip_prices(json.loads(out))


class ProjectionInput(Input):
    level: LEVEL = Field("standing", description=LEVEL_HELP)
    weeks: int = Field(12, ge=1, le=26, description="Weeks ahead from this week (1 to 26).")


@records_tool("demand_projection", "Demand and packaging projection",
              """Call for what customers need over the coming weeks and what must be packaged: "what do we need to deliver in the next 4
              weeks?", "how many cases do we have to can next week?" (O5). Units by week and demand type (firm, standing, forecast), value
              for owner and sales, and by format: released units on hand, demand and units to package after stock and draft runs, by week.
              Also the data notes that weaken the numbers.""")
async def demand_projection(p: ProjectionInput) -> dict:
    data = await _projection(p.level, p.weeks)
    return {k: data.get(k) for k in ("level_label", "weeks", "demand_units_by_type", "demand_value_by_type", "packaging", "notes") if k in data}


@records_tool("production_projection", "What to brew and when",
              """Call for which batches must be started to meet demand: "what do we need to brew and when?", "do we have enough cider for
              next month's orders?" (O6). Bulk needed, available (active batches at their ready dates, unstarted production orders) and short
              by product and week, and suggested batches (count, volume rounded to the recipe's batch size, needed by, pitch by, late flag,
              what drives it: planned, firm, standing or forecast).""")
async def production_projection(p: ProjectionInput) -> dict:
    data = await _projection(p.level, p.weeks)
    return {k: data.get(k) for k in ("level_label", "weeks", "production", "bulk", "bulk_supply", "notes") if k in data}


@records_tool("purchase_projection", "What to buy and by when",
              """Call for which materials must be bought for coming packaging and production: "what do we need to order this week?", "do we
              have enough cans?", "how much juice do we need?" (O7). Per item short: first week short and quantity, total short over the
              weeks, preferred supplier with lead time, order-by date and late flag, suggested order in the supplier's unit (approximate
              cost for owner and sales), what it is needed for, fruit equivalent for juice, and what drives it.""")
async def purchase_projection(p: ProjectionInput) -> dict:
    data = await _projection(p.level, p.weeks)
    return {k: data.get(k) for k in ("level_label", "weeks", "purchasing", "notes") if k in data}
