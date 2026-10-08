# The database

One PostgreSQL 17 database per business, two schemas, three roles (`db/000_roles.sql`):

| Schema | Holds | Owner | Readers |
|---|---|---|---|
| `app` | Record memory: every table in 002 to 016 | `processcore_app` | `processcore_records_ro` (MCP records server) |
| `memory` | Activity memory: the MaluDB facade (`maludb_core.enable_memory_schema`) | `processcore_app` | `processcore_activity_ro` (MCP activity server) |

The files, in order (written in place for ProcessCore on 2026-10-08, docs/processcore-design.md D2):

| File | What |
|---|---|
| `000_roles.sql` | the three cluster roles (superuser, once per cluster) |
| `001_extensions.sql` | `maludb_core` and the two schemas (superuser, per database) |
| `002_common.sql` | helpers, number sequences, reference tables, theoretical weight |
| `003_auth.sql` | users (seven roles), identities, 2FA, throttling, MCP tokens |
| `004_foundation.sql` | the business, sites, units, item classes with lot nouns, the attribute dictionary, items, suppliers, locations and racks, reason codes, equipment kinds and equipment with capabilities, attachments |
| `005_purchasing_receiving.sql` | purchase orders, receipts, lots with weight, lot attributes and `lot_attributes_fill()`, weigh tickets, certificates, release decisions |
| `006_ledger.sql` | the inventory ledger with weight, balances, the two interlocks, transfers, adjustments, counts |
| `007_products_process_specs.sql` | operations, measurement types, products with attributes, process specs (steps, inputs), specs, packaging configurations, standard costs, overhead rates |
| `008_production.sql` | production orders, allocations, runs (inputs, outputs, consumables), consumptions, lot lineage, losses, readings, co-product dispositions |
| `009_packaging.sql` | packaging runs (inputs, materials) and finished lots |
| `010_quality.sql` | inspections, the spec evaluation of readings |
| `011_shipping_reports.sql` | customers, shipments and lines, the report line map, period reports |
| `012_views.sql` | stock, yield, cost and valuation views; `trace_forward`, `trace_backward`, `heat_where_used` |
| `013_activity_log.sql` | the activity log and its MaluDB ingestion |
| `014_customer_orders.sql` | customer orders with the price basis, standing orders, imports, forecasts, demand |
| `015_equipment_schedule.sql` | equipment reservations, the schedule, clashes, `equipment_fits()` |
| `016_os_adoption.sql` | the Business OS kernel's link, sign-on tables, roles and rights |
| `020_grants.sql` | the read roles' grants (superuser, last, after every file) |
| `profiles/<name>/seed.sql` | an industry's seed data (`steel` the default): classes, attributes, operations, measurements, equipment kinds, reason codes, reference tables, number formats, display units |

Provisioning: `deploy/os-provision.sh` (beside the kernel, idempotent, records each file and the profile in
`app.schema_migrations`) or `deploy/provision-client.sh` (standalone, one client at a time). A change after the first
install is a new numbered file; a profile is only ever appended to. Activity rows reach MaluDB through
`app.activity_ingest_pending()`, run every minute by `deploy/processcore-activity-ingest.timer`.
