"""End-to-end MCP client for the records server (streamable HTTP, bearer token).

    .venv/bin/python -m records_mcp.test_client [URL] [--token T] [--no-token] [--list] [--call TOOL JSON] [--suite] [--full]

Default URL http://127.0.0.1:8701/mcp, default token PROCESSCORE_SERVICE_RECORDS_TOKEN. --suite calls every tool at least once
against the real data (tagged with the question it answers) and checks the expected refusals."""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
from typing import Any

from mcp.client.session import ClientSession
from mcp.client.streamable_http import streamable_http_client
from mcp.shared._httpx_utils import create_mcp_http_client

from common import config

SUITE: list[tuple[str, str, dict[str, Any]]] = [
    ("O1", "orders_find", {"status": None, "limit": 5}),
    ("O2", "order_status", {"order": "SO-00001"}),
    ("O3", "orders_history", {"group_by": "customer"}),
    ("O4", "standing_orders_find", {"include_paused": True}),
    ("O5", "demand_projection", {"level": "all", "weeks": 8}),
    ("O6", "production_projection", {"weeks": 8}),
    ("O7", "purchase_projection", {"level": "firm", "weeks": 8}),
    ("R1", "receiving_open_orders", {"date_from": "2026-09-28", "date_to": "2026-10-04"}),
    ("R5", "receiving_open_orders", {"overdue_only": True}),
    ("R2", "receiving_receipt_vs_order", {"receipt_number": "GR-00001"}),
    ("R2", "receiving_receipt_vs_order", {"po_number": "PO-00001"}),
    ("R3", "receiving_receipt_lots", {"receipt_number": "GR-00002"}),
    ("R4", "receiving_lot_status", {"lot_number": "L-261001-002"}),
    ("R6", "receiving_price_history", {"item_class": "fruit", "group_by": "year"}),
    ("R7", "receiving_supplier_performance", {}),
    ("R8", "receiving_fruit_intake", {"season_year": 2026}),
    ("R9", "inventory_rack_stock", {"product": "Hill Dry Cider", "released_only": True}),
    ("R9", "inventory_rack_stock", {"area": "Packaged goods"}),
    ("R9", "inventory_on_hand", {"item": "JCE-APL"}),
    ("R10", "inventory_available_after_orders", {}),
    ("R11", "inventory_pick_order", {"item": "EC-1118", "qty": 0.6, "unit": "kg"}),
    ("R11", "inventory_pick_order", {"expiring_within_days": 365}),
    ("R12", "inventory_below_reorder", {}),
    ("R13", "production_order_shortages", {}),
    ("R14", "inventory_adjustments", {"date_from": "2026-10-01", "date_to": "2026-10-31"}),
    ("R14", "inventory_movements", {"txn_type": "adjustment", "limit": 5}),
    ("R15", "inventory_last_count", {"location": "Cold room"}),
    ("R16", "cost_inventory_valuation", {"group_by": "item_class"}),
    ("R17", "inventory_slow_movers", {"months": 6}),
    ("R18", "recipe_current", {"product": "Hill Dry Cider", "batch_volume_gal": 300}),
    ("R19", "recipe_diff", {"product": "DRY"}),
    ("R20", "recipe_batches_made", {"product": "DRY", "version": 2}),
    ("R21", "recipe_can_make", {"product": "DRY", "batch_volume_gal": 200}),
    ("R22", "recipe_standard_cost", {"product": "DRY"}),
    ("R23", "production_tank_board", {}),
    ("R23", "batch_stage_history", {"batch_number": "B-26-001"}),
    ("R24", "production_batches_in_progress", {}),
    ("R25", "production_press_runs", {"date_from": "2026-09-28", "date_to": "2026-10-04"}),
    ("R26", "production_orders_by_status", {"status": "released", "not_started_only": True}),
    ("E1", "equipment_schedule", {"date_from": "2026-11-01", "date_to": "2026-11-30"}),
    ("E1", "equipment_schedule", {"equipment": "canning line", "date_from": "2026-11-01", "date_to": "2026-12-31"}),
    ("E2", "equipment_free", {"kind": "fermenter", "days": 14, "date_from": "2026-11-01", "date_to": "2027-01-31"}),
    ("E3", "find_equipment", {"q": "canning"}),
    ("E3", "find_reservation", {"q": "FV-A"}),
    ("R27", "batch_consumptions", {"batch_number": "B-26-001"}),
    ("R28", "batch_consumptions", {"batch_number": "B-26-004", "after_stage": "primary"}),
    ("R29", "batch_blends", {"batch_number": "B-26-004"}),
    ("R29", "batch_blends", {}),
    ("R30", "batch_genealogy", {"vessel": "Tank-3"}),
    ("R31", "batch_readings", {"batch_number": "B-26-001", "measurement": "brix"}),
    ("R32", "cost_stage_yields", {"product": "DRY", "last_n": 5}),
    ("R33", "batch_losses", {"batch_number": "B-26-001"}),
    ("R34", "cost_juice_yield_by_variety", {"season_year": 2026}),
    ("R35", "packaging_run_losses", {"package_kind": "can", "last_n": 1}),
    ("R36", "packaging_finished_stock", {"product": "DRY"}),
    ("R37", "packaging_material_needs", {}),
    ("R38", "packaging_lots_for_batch", {"batch_number": "B-26-004"}),
    ("R38", "packaging_lots_for_batch", {"lot_number": "L-261001-019"}),
    ("R39", "keg_fleet", {}),
    ("R39", "keg_history", {"serial": "KEG-0003"}),
    ("R40", "cost_batch", {"batch_number": "B-26-004"}),
    ("R41", "batch_readings", {"batch_number": "B-26-006"}),
    ("R41", "quality_out_of_spec", {"days": 30}),
    ("R42", "quality_release_queue", {}),
    ("R42", "quality_release_history", {"batch_number": "B-26-006"}),
    ("R43", "batch_readings", {"lot_number": "L-261001-001", "measurement": "so2"}),
    ("R44", "quality_sensory", {"lot_number": "L-261001-002"}),
    ("R45", "cost_batch", {"batch_number": "B-26-001"}),
    ("R46", "cost_inventory_valuation", {"group_by": "tax_state"}),
    ("R47", "compliance_period_summary", {"period": "2026-10"}),
    ("R47", "compliance_report", {"report_number": "RPT-00003"}),
    ("R47", "compliance_report", {}),
    ("R48", "compliance_bulk_vs_bottled", {}),
    ("R49", "packaging_tax_class_check", {"lot_number": "L-261001-019"}),
    ("R49", "packaging_tax_class_check", {"batch_number": "B-26-006"}),
    ("R50", "product_approvals_needed", {}),
    ("R51", "compliance_removals", {"destination_kind": "taproom_transfer", "date_from": "2026-10-01", "date_to": "2026-10-31"}),
    ("R52", "co_product_dispositions", {}),
    ("R53", "trace_forward", {"lot_number": "LAL-77"}),
    ("R53", "trace_forward", {"lot_number": "L-261001-001"}),
    ("R54", "trace_backward", {"lot_number": "L-261001-019"}),
    ("helper", "product_find", {"query": "dry"}),
    ("helper", "batch_find", {"status": "active"}),
    ("long-tail", "records_search", {"sql": "SELECT i.item_class, count(*) AS lots FROM app.lots l JOIN app.items i ON i.id = l.item_id GROUP BY 1 ORDER BY 2 DESC"}),
    ("long-tail", "records_search", {"sql": "SELECT id, display_name, role FROM app.users"}),
    ("ambiguous", "inventory_on_hand", {"item": "apple"}),
    ("ambiguous", "receiving_lot_status", {"lot_number": "261001"}),
    ("refuse", "records_search", {"sql": "DELETE FROM app.lots"}),
    ("refuse", "records_search", {"sql": "UPDATE app.items SET name = 'x'"}),
    ("refuse", "records_search", {"sql": "SELECT 1; DROP TABLE app.lots"}),
    ("refuse", "records_search", {"sql": "WITH x AS (DELETE FROM app.lots RETURNING *) SELECT * FROM x"}),
    ("refuse", "records_search", {"sql": "SELECT password_hash FROM app.users"}),
    ("refuse", "records_search", {"sql": "SELECT * FROM app.mcp_access_tokens"}),
    ("error", "receiving_lot_status", {"lot_number": "ZZ-NOPE-999"}),
    ("error", "inventory_on_hand", {"item": "JCE-APL", "bogus": 1}),
    ("error", "inventory_on_hand", {"limit": 500}),
    ("error", "packaging_lots_for_batch", {"lot_number": "L-261001-001"}),
]


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("url", nargs="?", default="http://127.0.0.1:8701/mcp")
    ap.add_argument("--token", default=None)
    ap.add_argument("--no-token", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--call", nargs=2, metavar=("TOOL", "JSON"))
    ap.add_argument("--suite", action="store_true")
    ap.add_argument("--full", action="store_true", help="print full results")
    ap.add_argument("--json-out", default=None, help="write every suite result to this JSON file")
    a = ap.parse_args()
    token = None if a.no_token else (a.token or config.get("PROCESSCORE_SERVICE_RECORDS_TOKEN"))
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    async with create_mcp_http_client(headers=headers) as probe_client:
        probe = await probe_client.post(a.url, json={"jsonrpc": "2.0", "id": 0, "method": "ping"},
                                        headers={"Accept": "application/json, text/event-stream"})
    if probe.status_code == 401:
        print(f"HTTP 401 from {a.url}: {probe.text}")
        return 2
    http = create_mcp_http_client(headers=headers)
    async with http, streamable_http_client(a.url, http_client=http) as (read, write), ClientSession(read, write) as s:
        init = await s.initialize()
        print(f"connected: {init.server_info.name} {init.server_info.version}")
        tools = (await s.list_tools()).tools
        print(f"{len(tools)} tools; all readOnlyHint: {all(t.annotations and t.annotations.read_only_hint for t in tools)}")
        if a.list:
            for t in tools:
                print(f"  {t.name}: {t.title}")
        calls = SUITE if a.suite else ([("call", a.call[0], json.loads(a.call[1]))] if a.call else [])
        failures, results, called = 0, [], set()
        for tag, name, args in calls:
            res = await s.call_tool(name, {"params": args})
            called.add(name)
            text = res.content[0].text if res.content else ""
            expect_error = tag in ("error", "refuse")
            ok = bool(res.is_error) == expect_error
            if tag == "ambiguous":
                ok = '"ambiguous":true' in text
            if not res.is_error and res.structured_content is None:
                ok = False
            failures += 0 if ok else 1
            results.append({"tag": tag, "tool": name, "args": args, "is_error": bool(res.is_error), "ok": ok, "text": text})
            body = text if a.full else (text[:500] + ("..." if len(text) > 500 else ""))
            print(f"\n[{tag}] {name} {json.dumps(args)} -> {'ERROR ' if res.is_error else ''}{'ok' if ok else 'UNEXPECTED'}\n{body}")
        if calls:
            print(f"\n{len(calls) - failures}/{len(calls)} behaved as expected")
            missing = sorted({t.name for t in tools} - called)
            if a.suite:
                print("tools not called:", missing or "none")
        if a.json_out:
            with open(a.json_out, "w") as f:
                json.dump(results, f, indent=1)
        return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
