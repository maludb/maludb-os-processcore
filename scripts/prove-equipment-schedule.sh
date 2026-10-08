#!/usr/bin/env bash
# Proves db/023_equipment_schedule.sql on a scratch copy of a ProcessCore installation database, never on the database itself.
#   scripts/prove-equipment-schedule.sh [source_db]      (default subello_processcore; KEEP=1 keeps the scratch database)
# Copies the source's app schema with pg_dump -n app | psql (a template copy needs the source idle; the MCP servers hold
# connections; the whole dump collides with the extension's seed rows),
# seeds production orders with a vessel plan that overlaps, applies 023 then 020 exactly as deploy/os-provision.sh
# does (SET ROLE processcore_app), and runs scripts/prove-equipment-schedule.sql. Exit status is nonzero when a check fails.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=${1:-subello_processcore}
SCRATCH=processcore_prove_023
PG="sudo -n -u postgres"
$PG psql -Atc "select 1 from pg_database where datname='$SRC'" | grep -q 1 || { echo "no database $SRC"; exit 2; }

echo "== scratch copy of $SRC → $SCRATCH"
$PG psql -q -c "DROP DATABASE IF EXISTS $SCRATCH"
$PG createdb -O processcore_app "$SCRATCH"
# The extension seeds its own rows, so the copy is the app schema only, over a fresh extension and an empty memory schema.
$PG psql -q -v ON_ERROR_STOP=1 -d "$SCRATCH" -c "CREATE EXTENSION IF NOT EXISTS maludb_core CASCADE; CREATE SCHEMA memory AUTHORIZATION processcore_app;"
$PG pg_dump -n app "$SRC" | $PG psql -q -v ON_ERROR_STOP=1 -d "$SCRATCH" >/dev/null
$PG psql -q -c "ALTER DATABASE $SCRATCH SET search_path = app, memory, maludb_core, public"
P="$PG psql -v ON_ERROR_STOP=1 -q -d $SCRATCH"

echo "== seed: a product, a recipe, three vessels, orders with a vessel plan that overlaps"
$P -c "SET ROLE processcore_app;" -f scripts/prove-equipment-schedule-seed.sql

echo "== apply db/023 as processcore_app, then db/020"
$P -c "SET ROLE processcore_app;" -f db/023_equipment_schedule.sql
$P -f db/020_grants.sql

echo "== checks"
set +e
$P -f scripts/prove-equipment-schedule.sql
FAILED=$?
set -e
if [ "${KEEP:-0}" != 1 ]; then $PG psql -q -c "DROP DATABASE $SCRATCH"; echo "== $SCRATCH dropped"; else echo "== $SCRATCH kept"; fi
exit $FAILED
