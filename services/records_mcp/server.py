"""processcore_records_mcp: records-memory MCP server, stateless JSON streamable HTTP at /mcp on
127.0.0.1:$PROCESSCORE_RECORDS_MCP_PORT (8701), bearer tokens of scope 'records', read-only role."""
from __future__ import annotations

import logging

from mcp.server.mcpserver import MCPServer

from common import config, serve

from . import fmt, schema_summary
from . import tools_compliance, tools_inventory, tools_orders, tools_os, tools_packaging, tools_production, tools_quality_cost, tools_receiving, tools_recipes  # noqa: F401 (register tools)
from .registry import REGISTRY, register_all

INSTRUCTIONS = """Records memory of ProcessCore: inventory, receiving, recipes, production and batches, packaging and kegs, quality,
costing, compliance (TTB 5120.17), recall traceability, customer orders and planning projections, read-only. Call a purpose-built tool first; each description names the
questions it answers. Pass arguments as {"params": {...}}. Use human labels: lot numbers (L-261001-004), batch numbers (B-26-001),
item codes or names, supplier, product, vessel, customer and location names; "id:123" also works. When a label is ambiguous the
result has ambiguous=true and candidates: call again with one of them. Quantities come in base units (_l, _kg, _units) with display
units beside them (_gal, _lb, _ton, _bushel); times are ISO in the client's time zone. Use records_search (one guarded SELECT)
only for questions no tool covers."""


def build_server() -> MCPServer:
    fmt.load_sync()
    summary = schema_summary.build()
    search = next(s for s in REGISTRY if s.name == "records_search")
    search.description = tools_compliance.SEARCH_DESCRIPTION.format(tz=fmt.tz(), schema=summary)
    server = MCPServer(name="processcore_records_mcp", title="ProcessCore records", instructions=INSTRUCTIONS, version="1.0.0")
    register_all(server)
    return server


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    server = build_server()
    logging.getLogger("records_mcp").info("registered %d tools", len(REGISTRY))
    app = serve.build_app(server, scope="records", server_name="processcore_records_mcp")
    serve.run(app, int(config.get("PROCESSCORE_RECORDS_MCP_PORT", "8701")))


if __name__ == "__main__":
    main()
