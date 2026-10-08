# Database files

One PostgreSQL 17 database per client (SaaS Plus+), two schemas inside it:

| Schema | Holds | Owner | Readers |
|---|---|---|---|
| `app` | Record memory: every table in 002 to 013 | `processcore_app` | `processcore_records_ro` (MCP records server) |
| `memory` | Activity memory: the MaluDB facade (`maludb_core.enable_memory_schema`) | `processcore_app` | `processcore_activity_ro` (MCP activity server) |

An operator registry database `processcore_host` (see `host/000_host.sql`) lists the clients and holds no client data.

## Run order

`deploy/provision-client.sh <slug> "<name>" <owner email>` does all of this for a new client:

1. `000_roles.sql` once per cluster (superuser, idempotent).
2. `createdb processcore_<slug>` owned by `processcore_app`, then `001_extensions.sql` (superuser: installs `maludb_core`, creates the schemas).
3. `SELECT maludb_core.enable_memory_schema('memory')` as `processcore_app`.
4. `002_common.sql` through the highest numbered file (`015_...` today) in numeric order as `processcore_app`.
5. `020_grants.sql` (superuser).
6. Seed `app.client_settings` and mark the client active in `processcore_host`.

## Conventions

- Primary keys are `bigint GENERATED ALWAYS AS IDENTITY`; every mutable table has `created_at` and `updated_at` (trigger `app.touch_updated_at`).
- Quantities are stored in base units (`L`, `kg`, `ea`) as `numeric`; display conversion happens in PHP from `app.units`, `app.item_units` and `app.client_settings`.
- `app.inventory_transactions` and `app.activity_log` are immutable (trigger `app.forbid_change`); corrections are compensating rows.
- Ledger interlocks live in `app.ledger_before_insert` (quarantine, negative stock) and `app.ledger_check_tax_state_group` (bonded to tax-paid moves only through removals and returns).
- Document numbers come from `app.next_number('<key>')` (keys in `002_common.sql`).
- Reporting derivations are views in `012_costing_views.sql`; the TTB line mapping is data in `app.ttb_line_map`.
- Activity rows reach MaluDB through `app.activity_ingest_pending()`, run every minute by `deploy/processcore-activity-ingest.timer`.

## Changing the schema after Phase 1

Schema changes during Phase 3 are exceptional and need owner sign-off. Add a new numbered file (`016_...sql`) rather than editing an applied one, and record it in `clients.schema_version`.
