#!/usr/bin/env bash
# Provision or upgrade ProcessCore's database beside the Business OS kernel (maludb-os.json → database.provision; os-adoption
# 2026-10-04). The kernel's installer (bin/app_install.php) creates the database (owner DB_RW_ROLE) and the three roles,
# then runs this as root with DB_NAME, DB_RW_ROLE, DB_RECORDS_ROLE, DB_ACTIVITY_ROLE, APP_DIR, APP_KEY, APP_NAME, TENANT in
# the environment — on a fresh database and again on every later apply. Idempotent: what db/*.sql files did is recorded
# in app.schema_migrations and never repeated; the extension, the memory schema, the grants and the seed row are checked.
# The standalone product keeps deploy/provision-client.sh (many clients, an operator registry); this is the one-business form.
set -euo pipefail
: "${DB_NAME:?DB_NAME}" "${APP_DIR:?APP_DIR}"
RW=${DB_RW_ROLE:-processcore_app}
NAME=${APP_NAME:-ProcessCore}
SUB=${APP_KEY:-processcore}
if [ "$(id -u)" = 0 ]; then AS_PG="runuser -u postgres --"; else AS_PG="sudo -n -u postgres"; fi
PSQL="$AS_PG psql -v ON_ERROR_STOP=1 -q -d $DB_NAME"
cd "$APP_DIR"

echo "== cluster roles (idempotent; maludb_user granted to $RW)"
$AS_PG psql -v ON_ERROR_STOP=1 -q -f db/000_roles.sql
if [ "$RW" != processcore_app ]; then $AS_PG psql -v ON_ERROR_STOP=1 -q -c "GRANT maludb_user TO $RW"; fi

echo "== extension and schemas (superuser)"
$PSQL -f db/001_extensions.sql
if [ "$RW" != processcore_app ]; then $PSQL -c "ALTER SCHEMA app OWNER TO $RW; ALTER SCHEMA memory OWNER TO $RW"; fi
$PSQL -c "ALTER DATABASE $DB_NAME SET search_path = app, memory, maludb_core, public"

echo "== MaluDB memory schema (once)"
if [ "$($PSQL -At -c "select count(*) from information_schema.tables where table_schema='memory'")" = 0 ]; then
    $PSQL -c "SET ROLE $RW; SET search_path TO memory, maludb_core, public; SELECT * FROM maludb_core.enable_memory_schema('memory');" >/dev/null
fi

echo "== application schema (each db/0NN file once, as $RW)"
$PSQL -c "CREATE TABLE IF NOT EXISTS app.schema_migrations (file text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now()); ALTER TABLE app.schema_migrations OWNER TO $RW;"
for f in $(ls db/0*.sql | sort); do
    b=$(basename "$f")
    case "$b" in 000_*|001_*|020_*) continue;; esac
    if [ "$($PSQL -At -c "select count(*) from app.schema_migrations where file='$b'")" = 1 ]; then continue; fi
    echo "   $b"
    $PSQL -c "SET ROLE $RW;" -f "$f"
    $PSQL -c "insert into app.schema_migrations (file) values ('$b')"
done

echo "== grants for the read roles (superuser, idempotent)"
$PSQL -f db/020_grants.sql

echo "== the business (one row)"
$PSQL -c "SET ROLE $RW; INSERT INTO app.client_settings (id, client_name, subdomain) VALUES (1, \$\$$NAME\$\$, '$SUB') ON CONFLICT (id) DO NOTHING;"

# The profile (docs/processcore-design.md D12): PROCESS_PROFILE from the environment, else config/.env, else steel.
# db/profiles/<name>/seed.sql is applied once as $RW and recorded as profile:<name>; a later apply skips it.
PROFILE=${PROCESS_PROFILE:-$( { grep -E "^PROCESS_PROFILE=" "$APP_DIR/config/.env" 2>/dev/null || true; } | head -1 | cut -d= -f2 | tr -d "\"' ")}
PROFILE=${PROFILE:-steel}
if [ ! -f "db/profiles/$PROFILE/seed.sql" ]; then echo "!! no profile db/profiles/$PROFILE/seed.sql" >&2; exit 2; fi
if [ "$($PSQL -At -c "select count(*) from app.schema_migrations where file='profile:$PROFILE'")" = 0 ]; then
    echo "== profile $PROFILE (once)"
    $PSQL -c "SET ROLE $RW;" -f "db/profiles/$PROFILE/seed.sql"
    $PSQL -c "insert into app.schema_migrations (file) values ('profile:$PROFILE')"
fi
echo "== done: $DB_NAME ($PROFILE)"
