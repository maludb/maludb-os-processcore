-- 003_auth.sql — users, identities, 2FA, login throttling, MCP tokens.
-- Shapes follow the php-session-auth skill references exactly. The seven roles of docs/processcore-design.md §8.
SET search_path = app, public;

CREATE TABLE app.users (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email               text NOT NULL,                       -- stored lower(trim())
    display_name        text NOT NULL,
    password_hash       text,                                -- NULL = Google-only account
    role                text NOT NULL DEFAULT 'viewer'
                        CHECK (role IN ('owner','production','receiving','quality','shipping','sales','viewer')),
    status              text NOT NULL DEFAULT 'invited'
                        CHECK (status IN ('invited','active','disabled')),
    email_verified_at   timestamptz,
    totp_secret         text,                                -- libsodium secretbox, key in env
    totp_enabled_at     timestamptz,                         -- NULL = 2FA off
    totp_last_timestep  bigint,                              -- replay guard
    last_login_at       timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_key ON app.users (lower(email));
CREATE TRIGGER users_touch BEFORE UPDATE ON app.users FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.auth_identities (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id           bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    provider          text   NOT NULL,                       -- 'google'
    provider_user_id  text   NOT NULL,                       -- Google's stable 'sub'
    email_at_provider text   NOT NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_user_id)
);

CREATE TABLE app.totp_recovery_codes (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    code_hash  text   NOT NULL,                              -- password_hash() of the code
    used_at    timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX totp_recovery_codes_user_idx ON app.totp_recovery_codes (user_id) WHERE used_at IS NULL;

-- Brute-force throttling: counted per normalized email AND per IP.
CREATE TABLE app.login_attempts (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email        text,
    ip           inet,
    kind         text NOT NULL DEFAULT 'password' CHECK (kind IN ('password','google','totp','recovery','reset')),
    succeeded    boolean NOT NULL,
    attempted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX login_attempts_email_idx ON app.login_attempts (email, attempted_at DESC);
CREATE INDEX login_attempts_ip_idx    ON app.login_attempts (ip, attempted_at DESC);

-- One-time tokens for password reset, email verification and invitations.
CREATE TABLE app.one_time_tokens (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    purpose    text NOT NULL CHECK (purpose IN ('password_reset','email_verify','invite')),
    token_hash text NOT NULL,                                -- sha256 of the random token
    expires_at timestamptz NOT NULL,
    used_at    timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX one_time_tokens_hash_key ON app.one_time_tokens (token_hash);

-- Client-facing MCP endpoint tokens (SaaS Plus+). Checked by the MCP services.
CREATE TABLE app.mcp_access_tokens (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         text NOT NULL,
    scope        text NOT NULL CHECK (scope IN ('records','activity')),
    token_prefix text NOT NULL,                              -- first 8 chars, for display
    token_hash   text NOT NULL,                              -- sha256 of the bearer token
    created_by   bigint NOT NULL REFERENCES app.users(id),
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz,
    revoked_at   timestamptz,
    revoked_by   bigint REFERENCES app.users(id)
);
CREATE UNIQUE INDEX mcp_access_tokens_hash_key ON app.mcp_access_tokens (token_hash);
