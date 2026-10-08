-- 021_os_adoption.sql — ProcessCore beside the MaluDB Business OS kernel (os-adopt, 2026-10-04). Run as processcore_app.
-- The application keeps its users table and links each user to the kernel's member (users.os_member_id);
-- the kernel's roles for a member are a SET (users.os_roles); the sign-on kit's tables sit beside
-- (php-sign-on-kit.md §2); the roles-and-rights catalogue the records MCP publishes as app_roles.
SET search_path = app, public;

-- 1. The link, the kernel's roles and capability on this application ---------------------------------
ALTER TABLE app.users
    ADD COLUMN IF NOT EXISTS os_member_id  bigint UNIQUE,                       -- the kernel's member id
    ADD COLUMN IF NOT EXISTS os_roles      text[] NOT NULL DEFAULT '{}',         -- every role the kernel granted here
    ADD COLUMN IF NOT EXISTS os_capability text CHECK (os_capability IN ('read', 'write', 'admin')),  -- NULL = no access
    ADD COLUMN IF NOT EXISTS os_synced_at  timestamptz,
    ADD COLUMN IF NOT EXISTS os_member_kind text NOT NULL DEFAULT 'human' CHECK (os_member_kind IN ('human', 'agent'));

-- 2. The sign-on kit's tables ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app.sso_nonces (              -- single use: kept until the token would have expired
    nonce       text PRIMARY KEY,
    member_id   bigint NOT NULL,
    expires_at  timestamptz NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sso_nonces_expires_idx ON app.sso_nonces (expires_at);

CREATE TABLE IF NOT EXISTS app.member_sessions (         -- every session opened, so a sign-out notice ends them all
    session_hash  text PRIMARY KEY,                      -- sha256 of the PHP session id
    member_id     bigint NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    last_seen_at  timestamptz NOT NULL DEFAULT now(),
    ended_at      timestamptz,
    ended_by      text CHECK (ended_by IN ('member', 'kernel', 'expired', 'directory'))
);
CREATE INDEX IF NOT EXISTS member_sessions_member_idx ON app.member_sessions (member_id) WHERE ended_at IS NULL;

CREATE TABLE IF NOT EXISTS app.directory_sync_state (    -- the change feed's cursor, one row
    id           smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    next_cursor  text,
    full_at      timestamptz,
    last_run_at  timestamptz,
    last_error   text,
    updated_at   timestamptz NOT NULL DEFAULT now()
);
INSERT INTO app.directory_sync_state (id) VALUES (1) ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS app.activity_ingest_state (   -- the tenant-MaluDB bridge's checkpoint (memory.md §2)
    id         smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    last_id    bigint NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO app.activity_ingest_state (id, last_id) VALUES (1, 0) ON CONFLICT DO NOTHING;

-- 3. Activity sources the kernel's contract names (memory.md §2): an agent's action, a timer, an API read.
ALTER TABLE app.activity_log DROP CONSTRAINT IF EXISTS activity_log_source_check;
ALTER TABLE app.activity_log ADD CONSTRAINT activity_log_source_check
    CHECK (source IN ('screen', 'command_bar', 'ama', 'mcp', 'system', 'agent', 'cron', 'api', 'web'));
ALTER TABLE app.activity_log ADD COLUMN IF NOT EXISTS agent_run_id bigint;   -- the kernel's run id when an agent acted (no FK)

-- 4. The roles and rights catalogue (roles-and-rights.md): what the kernel grants, in ProcessCore's words -------
CREATE TABLE IF NOT EXISTS app.app_rights (
    right_key   text PRIMARY KEY CHECK (right_key ~ '^[a-z][a-z0-9_.]{0,59}$'),
    description text NOT NULL,
    sort_order  int  NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS app.app_roles (
    role_key    text PRIMARY KEY CHECK (role_key ~ '^[a-z][a-z0-9_]{0,39}$'),
    name        text NOT NULL,
    description text NOT NULL,
    capability  text NOT NULL CHECK (capability IN ('read', 'write', 'admin')),
    is_admin    boolean NOT NULL DEFAULT false,
    sort_order  int NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS app_roles_one_admin ON app.app_roles ((true)) WHERE is_admin;
CREATE TABLE IF NOT EXISTS app.app_role_rights (
    role_key  text NOT NULL REFERENCES app.app_roles (role_key) ON DELETE CASCADE,
    right_key text NOT NULL REFERENCES app.app_rights (right_key) ON DELETE CASCADE,
    PRIMARY KEY (role_key, right_key)
);

INSERT INTO app.app_rights (right_key, description, sort_order) VALUES
    ('records.read',     'See every screen and report: inventory, receiving, production, packaging, quality, compliance, customer orders',   10),
    ('purchasing.write', 'Receiving and purchasing: items, item classes, vendors, purchase orders, receipts, lots, transfers, adjustments, counts', 20),
    ('production.write', 'Production: products, recipes, vessels, production orders, press runs, batches, packaging runs, kegs',         30),
    ('quality.write',    'Quality: lab readings, sensory, specifications, releases and dispositions',                                     40),
    ('compliance.write', 'Compliance: removals, TTB reports, reason codes, standard-cost approvals, finished lots',                       50),
    ('sales.write',      'Sales: customers, customer orders, standing orders, planning, removals to customers',                           60),
    ('processcore.admin',     'Run ProcessCore: users, organization settings, AI access tokens — everything',                                  90)
ON CONFLICT (right_key) DO UPDATE SET description = EXCLUDED.description, sort_order = EXCLUDED.sort_order;

INSERT INTO app.app_roles (role_key, name, description, capability, is_admin, sort_order) VALUES
    ('viewer',     'Viewer',     'Reads everything, changes nothing.',                                           'read',  false, 10),
    ('receiving',  'Receiving',  'Receives fruit and materials, keeps items, vendors, purchase orders and stock counts.', 'write', false, 20),
    ('production', 'Production', 'Makes the cider: production orders, press runs, batches, packaging, kegs.',   'write', false, 30),
    ('quality',    'Quality',    'Lab and sensory readings, specifications, releases.',                            'write', false, 40),
    ('compliance', 'Compliance', 'Removals, TTB reports, reason codes, approvals.',                                'write', false, 50),
    ('sales',      'Sales',      'Customers, customer orders, planning.',                                          'write', false, 60),
    ('owner',      'Owner',      'Runs ProcessCore: everything, plus users, settings and AI access tokens.',       'admin', true,  90)
ON CONFLICT (role_key) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description, capability = EXCLUDED.capability,
                                     is_admin = EXCLUDED.is_admin, sort_order = EXCLUDED.sort_order;

INSERT INTO app.app_role_rights (role_key, right_key) VALUES
    ('viewer', 'records.read'),
    ('receiving', 'records.read'), ('receiving', 'purchasing.write'),
    ('production', 'records.read'), ('production', 'production.write'),
    ('quality', 'records.read'), ('quality', 'quality.write'),
    ('compliance', 'records.read'), ('compliance', 'compliance.write'),
    ('sales', 'records.read'), ('sales', 'sales.write'),
    ('owner', 'records.read'), ('owner', 'purchasing.write'), ('owner', 'production.write'), ('owner', 'quality.write'),
    ('owner', 'compliance.write'), ('owner', 'sales.write'), ('owner', 'processcore.admin')
ON CONFLICT DO NOTHING;

-- One read for the records MCP server's app_roles tool (os.app-roles/1).
CREATE OR REPLACE VIEW app.mcp_app_roles AS
    SELECT r.role_key, r.name, r.description, r.capability, r.is_admin, r.sort_order,
           COALESCE((SELECT array_agg(rr.right_key ORDER BY ri.sort_order) FROM app.app_role_rights rr JOIN app.app_rights ri USING (right_key)
                      WHERE rr.role_key = r.role_key), '{}'::text[]) AS rights
      FROM app.app_roles r;
