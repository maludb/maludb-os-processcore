#!/usr/bin/env bash
# The scratch install's owner and MCP tokens (D19), recreated after scripts/prove-schema.sh rebuilt the database:
#   scripts/dev-owner.sh [db]     (default processcore_dev; writes the two tokens to $TOKENS, default the session scratchpad)
# owner@processcore.test / owner-dev-password, tokens dev-records and dev-activity. Idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${1:-processcore_dev}
TOKENS=${TOKENS:-/tmp/claude-1000/-var-www/4c497a50-6d05-4ec9-9088-fa9a07cc6461/scratchpad/pc-dev-tokens.env}
PGPW=${PGPASSWORD:-processcore-dev}
PWH=$(php -r "echo password_hash('owner-dev-password', PASSWORD_BCRYPT, ['cost' => 12]);")
RT=pc_records_$(openssl rand -hex 16); AT=pc_activity_$(openssl rand -hex 16)
PGPASSWORD=$PGPW psql -h 127.0.0.1 -U processcore_app -d "$DB" -v ON_ERROR_STOP=1 -q <<SQL
INSERT INTO app.users (email, display_name, password_hash, role, status, email_verified_at)
VALUES ('owner@processcore.test', 'Dev Owner', '$PWH', 'owner', 'active', now())
ON CONFLICT ((lower(email))) DO UPDATE SET password_hash = EXCLUDED.password_hash, status = 'active';
UPDATE app.mcp_access_tokens SET revoked_at = now(), revoked_by = (SELECT id FROM app.users WHERE email = 'owner@processcore.test') WHERE name IN ('dev-records','dev-activity') AND revoked_at IS NULL;
INSERT INTO app.mcp_access_tokens (name, scope, token_prefix, token_hash, created_by)
SELECT 'dev-records', 'records', left('$RT', 8), encode(sha256('$RT'::bytea), 'hex'), id FROM app.users WHERE email = 'owner@processcore.test';
INSERT INTO app.mcp_access_tokens (name, scope, token_prefix, token_hash, created_by)
SELECT 'dev-activity', 'activity', left('$AT', 8), encode(sha256('$AT'::bytea), 'hex'), id FROM app.users WHERE email = 'owner@processcore.test';
SQL
mkdir -p "$(dirname "$TOKENS")"
printf 'RECORDS_TOKEN=%s\nACTIVITY_TOKEN=%s\n' "$RT" "$AT" > "$TOKENS"
echo "owner and tokens written for $DB ($TOKENS)"
