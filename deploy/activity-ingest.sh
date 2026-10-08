#!/usr/bin/env bash
# For every active client in processcore_host, ingest pending activity rows into that
# client's MaluDB memory schema. Reads credentials from config/services.env.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
set -a; . "$HERE/config/services.env"; set +a
export PGHOST="$PROCESSCORE_DB_HOST" PGPORT="$PROCESSCORE_DB_PORT" PGUSER="$PROCESSCORE_APP_DB_USER" PGPASSWORD="$PROCESSCORE_APP_DB_PASSWORD"
for db in $(psql -d processcore_host -Atc "select db_name from clients where status='active'"); do
    total=0
    while :; do
        n=$(psql -d "$db" -Atc "select app.activity_ingest_pending(500)")
        total=$((total + n))
        [ "$n" -lt 500 ] && break
    done
    [ "$total" != "0" ] && echo "$db: ingested $total activity rows"
done
exit 0
