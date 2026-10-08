#!/usr/bin/env bash
# Proves step 2 of docs/processcore-design.md §13 — the schema written in place (D2) — on the scratch install (D19):
#   scripts/prove-schema.sh [db]        (default processcore_dev; the database is DROPPED and rebuilt from db/*.sql
#                                        and db/profiles/steel/seed.sql by deploy/os-provision.sh, never a live one)
# Then scripts/prove-schema.sql runs as processcore_app (the worked steel example of the plan's §5: a coil received
# with a ticket and an MTR, cut to length into sheets, a remnant and scrap, packed on skids, released, ordered,
# shipped — every table, trigger, interlock, view and function), and a few checks run as the two read roles.
# Exit status is nonzero when a check fails. KEEP_DATA=1 leaves the example rows in the database.
set -u
cd "$(dirname "$0")/.."
DB=${1:-processcore_dev}
case "$DB" in *_dev|*_prove*) ;; *) echo "refusing to drop $DB: only a *_dev or *_prove* database" >&2; exit 2;; esac
PGPW=${PGPASSWORD:-processcore-dev}
PG="sudo -n -u postgres"
echo "== rebuild $DB from db/ (dropped first)"
$PG psql -q -c "DROP DATABASE IF EXISTS $DB" && $PG createdb -O processcore_app "$DB" || exit 2
DB_NAME=$DB APP_DIR=$(pwd) APP_KEY=processcore APP_NAME=ProcessCore DB_RW_ROLE=processcore_app TENANT=dev deploy/os-provision.sh >/tmp/pc-provision.log 2>&1 \
  || { echo "FAIL provisioning (see /tmp/pc-provision.log)"; tail -5 /tmp/pc-provision.log; exit 1; }
grep -q "== profile steel" /tmp/pc-provision.log && echo "ok   provisioned from empty with the steel profile" || { echo "FAIL the profile did not apply"; exit 1; }

echo "== the checks, as processcore_app"
out=$(PGPASSWORD=$PGPW psql -h 127.0.0.1 -U processcore_app -d "$DB" -v ON_ERROR_STOP=1 -q -At -v keep="${KEEP_DATA:-0}" -f scripts/prove-schema.sql 2>&1); rc=$?
echo "$out" | grep -E '^(ok|FAIL)' | sed 's/^ok/ok  /'
if [ $rc -ne 0 ]; then echo "FAIL prove-schema.sql stopped:"; echo "$out" | grep -vE '^(ok|FAIL)' | tail -8; fi

echo "== the read roles"
pass=0; fail=0
r() { if PGPASSWORD=$PGPW psql -h 127.0.0.1 -U "$1" -d "$DB" -At -v ON_ERROR_STOP=1 -c "$3" >/dev/null 2>&1; then [ "$4" = yes ] && { echo "ok   $2"; pass=$((pass+1)); } || { echo "FAIL $2 (should have been refused)"; fail=$((fail+1)); }
     else [ "$4" = no ] && { echo "ok   $2"; pass=$((pass+1)); } || { echo "FAIL $2"; fail=$((fail+1)); }; fi; }
r processcore_records_ro  "records reader selects v_lot_balances"            "select * from app.v_lot_balances limit 1" yes
r processcore_records_ro  "records reader selects v_run_yields"              "select * from app.v_run_yields limit 1" yes
r processcore_records_ro  "records reader runs trace_forward"                "select * from app.trace_forward(1)" yes
r processcore_records_ro  "records reader runs equipment_fits"               "select * from app.equipment_fits(1, 1, null)" yes
r processcore_records_ro  "records reader reads mcp_app_roles"               "select * from app.mcp_app_roles" yes
r processcore_records_ro  "records reader never sees password hashes"        "select password_hash from app.users limit 1" no
r processcore_records_ro  "records reader never sees MCP tokens"             "select * from app.mcp_access_tokens limit 1" no
r processcore_records_ro  "records reader never sees sso nonces"             "select * from app.sso_nonces limit 1" no
r processcore_records_ro  "records reader cannot write"                      "insert into app.sites (code, name) values ('x', 'x')" no
r processcore_activity_ro "activity reader reads the activity log"           "select * from app.activity_log limit 1" yes
r processcore_activity_ro "activity reader reads the time zone and profile"  "select timezone, profile, mass_display_unit from app.client_settings" yes
r processcore_activity_ro "activity reader never reads lots"                 "select * from app.lots limit 1" no
r processcore_activity_ro "activity reader cannot write"                     "insert into app.activity_log (actor_label, action) values ('x', 'x')" no

okn=$(echo "$out" | grep -c '^ok'); failn=$(echo "$out" | grep -c '^FAIL')
total_ok=$((okn + pass + 1)); total_fail=$((failn + fail + rc))
echo "== $total_ok passed, $total_fail failed"
[ $total_fail -eq 0 ]
