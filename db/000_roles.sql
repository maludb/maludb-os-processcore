-- 000_roles.sql — cluster-level roles shared by every client database.
-- Run once per cluster as a superuser; idempotent. Passwords are set by the
-- provisioning script from environment, never stored here.
--
--   processcore_app          the PHP application and the ingestion job (read/write)
--   processcore_records_ro   the records MCP server (SELECT on app.*)
--   processcore_activity_ro  the activity MCP server (SELECT on memory.* and app.activity_log)

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'processcore_app') THEN
        CREATE ROLE processcore_app LOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'processcore_records_ro') THEN
        CREATE ROLE processcore_records_ro LOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'processcore_activity_ro') THEN
        CREATE ROLE processcore_activity_ro LOGIN;
    END IF;
END $$;

-- The application role writes into the MaluDB memory schema it owns.
GRANT maludb_user TO processcore_app;
