-- 001_extensions.sql — run as superuser inside the client database.
-- maludb_core pulls in vector, btree_gist, pg_trgm and pgcrypto.

CREATE EXTENSION IF NOT EXISTS maludb_core CASCADE;

-- Two schemas, one database per client (SaaS Plus+):
--   app     record memory — every table in db/002..010
--   memory  activity memory — MaluDB facade, enabled in 011_activity_log.sql
CREATE SCHEMA IF NOT EXISTS app    AUTHORIZATION processcore_app;
CREATE SCHEMA IF NOT EXISTS memory AUTHORIZATION processcore_app;

-- search_path is set per database by the provisioning script:
-- ALTER DATABASE {db} SET search_path = app, memory, maludb_core, public;
