-- db/host/000_host.sql — the operator registry: one row per client. Lives in
-- ProcessCore_host database, owned by processcore_app. Holds no client data.
CREATE TABLE IF NOT EXISTS clients (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug           text NOT NULL UNIQUE,                     -- subdomain and db suffix: [a-z0-9-]
    name           text NOT NULL,
    db_name        text NOT NULL UNIQUE,                     -- processcore_{slug}
    status         text NOT NULL DEFAULT 'provisioning' CHECK (status IN ('provisioning','active','suspended','retired')),
    owner_email    text NOT NULL,
    schema_version text,                                     -- last db/ file applied
    settings       jsonb NOT NULL DEFAULT '{}'::jsonb,
    provisioned_at timestamptz,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,40}$')
);
