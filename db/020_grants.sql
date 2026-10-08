-- 020_grants.sql — read-only roles for the MCP servers. Run as superuser in
-- the client database after every schema file. Idempotent.

-- Records MCP server: read every app table and view, nothing else.
GRANT USAGE ON SCHEMA app TO processcore_records_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA app TO processcore_records_ro;
ALTER DEFAULT PRIVILEGES FOR ROLE processcore_app IN SCHEMA app GRANT SELECT ON TABLES TO processcore_records_ro;
GRANT EXECUTE ON FUNCTION app.trace_forward(bigint), app.trace_backward(bigint),
                          app.derive_tax_class(text, numeric, numeric, numeric, boolean, boolean, boolean, date),
                          app.standing_order_occurrences(date, date)
    TO processcore_records_ro;
-- The records server must never see auth material.
REVOKE SELECT ON app.users, app.auth_identities, app.totp_recovery_codes, app.login_attempts,
                 app.one_time_tokens, app.mcp_access_tokens FROM processcore_records_ro;
GRANT SELECT (id, display_name, role, status) ON app.users TO processcore_records_ro;

-- Activity MCP server: the memory schema plus the raw log and user names.
GRANT USAGE ON SCHEMA memory, app TO processcore_activity_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA memory TO processcore_activity_ro;
ALTER DEFAULT PRIVILEGES FOR ROLE processcore_app IN SCHEMA memory GRANT SELECT ON TABLES TO processcore_activity_ro;
GRANT SELECT ON app.activity_log TO processcore_activity_ro;
GRANT SELECT (id, display_name, role, status) ON app.users TO processcore_activity_ro;
GRANT maludb_read TO processcore_activity_ro;

-- Both read roles: statement timeout and no writes, belt and braces.
ALTER ROLE processcore_records_ro  SET statement_timeout = '15s';
ALTER ROLE processcore_activity_ro SET statement_timeout = '15s';
ALTER ROLE processcore_records_ro  SET default_transaction_read_only = on;
ALTER ROLE processcore_activity_ro SET default_transaction_read_only = on;

-- MaluDB facade views are security_invoker and filtered by a row policy on
-- owner_schema = current_schema(). The activity reader therefore needs SELECT on
-- the base tables and a search_path that starts at the memory schema. One database
-- per client (SaaS Plus+) means these tables hold only this client's memory.
GRANT USAGE ON SCHEMA maludb_core TO processcore_activity_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA maludb_core TO processcore_activity_ro;
ALTER ROLE processcore_activity_ro SET search_path = memory, maludb_core, public;
ALTER ROLE processcore_records_ro SET search_path = app, public;

-- Activity reader: the client's time zone and display units, so answers use local
-- time. (MaluDB's internal lookup functions are not granted: the reader role reads
-- through the facade views and text search, as MaluDB intends for maludb_read.)
GRANT SELECT (id, client_name, timezone, volume_display_unit, mass_display_unit, fruit_display_unit) ON app.client_settings TO processcore_activity_ro;

-- os-adoption (db/021): the sign-on tables are auth material too.
REVOKE SELECT ON app.sso_nonces, app.member_sessions, app.directory_sync_state, app.activity_ingest_state FROM processcore_records_ro;
REVOKE SELECT ON app.sso_nonces, app.member_sessions FROM processcore_activity_ro;

-- Equipment scheduling (db/023): the clash function and the time zone helper, for the records server's schedule tools.
GRANT EXECUTE ON FUNCTION app.equipment_clashes(text, bigint, timestamptz, timestamptz, bigint), app.client_timezone() TO processcore_records_ro;
