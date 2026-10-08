#!/usr/bin/env bash
# Provision one client database: create it, install maludb_core, run every
# db/*.sql file in order, enable the MaluDB memory schema, apply grants, and
# register the client in processcore_host. Idempotent for re-runs of unchanged files
# is NOT guaranteed; use for new clients (dev: ./provision-client.sh dev "Dev ProcessCore" you@example.com).
#
# Usage: provision-client.sh <slug> <client name> <owner email> [subdomain]
set -euo pipefail
SLUG="${1:?slug}"; NAME="${2:?client name}"; OWNER_EMAIL="${3:?owner email}"; SUBDOMAIN="${4:-$1}"
DB="processcore_${SLUG//-/_}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PSQL="sudo -u postgres psql -v ON_ERROR_STOP=1 -q"

echo "== cluster roles"
$PSQL -f "$HERE/db/000_roles.sql"

echo "== host registry"
if ! sudo -u postgres psql -Atc "select 1 from pg_database where datname='processcore_host'" | grep -q 1; then
    sudo -u postgres createdb -O processcore_app processcore_host
fi
$PSQL -d processcore_host -f "$HERE/db/host/000_host.sql"
$PSQL -d processcore_host -c "insert into clients (slug, name, db_name, owner_email) values ('$SLUG', \$\$$NAME\$\$, '$DB', '$OWNER_EMAIL') on conflict (slug) do nothing"

echo "== database $DB"
if sudo -u postgres psql -Atc "select 1 from pg_database where datname='$DB'" | grep -q 1; then
    echo "database $DB already exists; aborting (drop it first to re-provision)"; exit 1
fi
sudo -u postgres createdb -O processcore_app "$DB"
$PSQL -d "$DB" -f "$HERE/db/001_extensions.sql"
$PSQL -d "$DB" -c "ALTER DATABASE $DB SET search_path = app, memory, maludb_core, public"

echo "== memory schema (MaluDB facade, owned by processcore_app)"
$PSQL -d "$DB" -c "SET ROLE processcore_app; SET search_path TO memory, maludb_core, public; SELECT * FROM maludb_core.enable_memory_schema('memory');" >/dev/null

echo "== application schema"
for f in $(ls "$HERE"/db/0*.sql | sort); do
    case "$(basename "$f")" in 000_*|001_*|020_*) continue;; esac
    echo "   $(basename "$f")"
    $PSQL -d "$DB" -c "SET ROLE processcore_app;" -f "$f"
done
$PSQL -d "$DB" -f "$HERE/db/020_grants.sql"

echo "== seed client settings"
$PSQL -d "$DB" -c "SET ROLE processcore_app; INSERT INTO app.client_settings (id, client_name, subdomain) VALUES (1, \$\$$NAME\$\$, '$SUBDOMAIN') ON CONFLICT (id) DO NOTHING;"
PROFILE=${PROCESS_PROFILE:-steel}
echo "== profile $PROFILE"
$PSQL -d "$DB" -c "SET ROLE processcore_app;" -f "$HERE/db/profiles/$PROFILE/seed.sql"
$PSQL -d processcore_host -c "update clients set status='active', provisioned_at=now(), schema_version='020_grants.sql' where slug='$SLUG'"
echo "== done: $DB"
