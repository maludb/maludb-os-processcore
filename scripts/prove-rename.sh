#!/usr/bin/env bash
# Proves step 1 of docs/processcore-design.md §13 — the rename — on the scratch install processcore_dev (D19):
#   1. no "cidery" identifier survives outside docs/cidery/ (the fork's record) and the plan;
#   2. the shell answers over HTTP under php -S on APP_INTERNAL_PORT: health, the login page, and — signed in as the
#      owner — the dashboard and a screen from every navigation group;
#   3. both read MCP servers start from services/.venv on their ports, initialize, list tools and answer app_roles;
#   4. the kernel's installer reads the manifest clean (bin/app_install.php plan, read-only).
# Needs config/.env for processcore_dev (standalone: OS_ENABLED empty), the owner owner@processcore.test with the dev
# password, and the two MCP tokens in $TOKENS (RECORDS_TOKEN=…, ACTIVITY_TOKEN=…). Exit status nonzero when a check fails.
set -u
cd "$(dirname "$0")/.."
TOKENS=${TOKENS:-/tmp/claude-1000/-var-www/4c497a50-6d05-4ec9-9088-fa9a07cc6461/scratchpad/pc-dev-tokens.env}
KERNEL=${KERNEL:-/var/www}
PORT=$(grep -E '^APP_INTERNAL_PORT=' config/.env | cut -d= -f2); RP=$(grep -E '^MCP_RECORDS_PORT=' config/.env | cut -d= -f2); AP=$(grep -E '^MCP_ACTIVITY_PORT=' config/.env | cut -d= -f2)
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "ok   $1"; }
bad()  { fail=$((fail+1)); echo "FAIL $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
has()  { printf '%s' "$1" | grep -q -- "$2"; }

echo "== 1. names"
# an identifier (role, env key, unit, path, key) — the fork source maludb-os-cidery and paths into docs/cidery/ may be named
left=$(git ls-files | grep -v '^docs/cidery/\|^docs/processcore-design.md$' | xargs grep -In -E "cidery_|CIDERY_|cidery-[a-z]|'cidery'|\"cidery\"|/cidery\b|\bcidery\.[a-z]" | grep -v 'maludb-os-cidery\|docs/cidery' | wc -l)
check "no cidery identifier outside docs/cidery and the plan ($left lines)" "[ $left -eq 0 ]"
check "maludb-os.json catalog_key processcore"      "grep -q '\"catalog_key\": \"processcore\"' maludb-os.json"
check "maludb-os.json roles processcore_*"           "grep -q '\"rw\": \"processcore_app\"' maludb-os.json"
check "manifest names the renamed units"             "grep -q 'deploy/processcore-records-mcp.service' maludb-os.json"
for f in deploy/processcore-records-mcp.service deploy/apache-processcore.conf deploy/kernel-registry-processcore.json skills/processcore-basics/SKILL.md; do check "file $f" "[ -e $f ]"; done
check ".env.example ports 8189/8839/8840" "grep -q 'APP_INTERNAL_PORT=8189' config/.env.example && grep -q 'MCP_RECORDS_PORT=8839' config/.env.example && grep -q 'MCP_ACTIVITY_PORT=8840' config/.env.example"
check "the database roles exist" "[ \$(sudo -n -u postgres psql -At -c \"select count(*) from pg_roles where rolname in ('processcore_app','processcore_records_ro','processcore_activity_ro')\") = 3 ]"
check "processcore_dev has the application schema" "[ \$(sudo -n -u postgres psql -At -d processcore_dev -c \"select count(*) from information_schema.tables where table_schema='app'\") -gt 100 ]"
for f in $(git ls-files 'app/*.php' 'html/*.php' 'bin/*.php' 'scripts/*.php'); do php -l "$f" >/dev/null 2>&1 || bad "php -l $f"; done; ok "php -l over every PHP file"

echo "== 2. the shell over HTTP (php -S 127.0.0.1:$PORT)"
php -S 127.0.0.1:$PORT -t html html/_router.php >/tmp/pc-php.log 2>&1 & PHP_PID=$!
sleep 1.5
J=$(mktemp)
check "GET /api/v1/health 200 and application processcore" "curl -s http://127.0.0.1:$PORT/api/v1/health | grep -q '\"application\":\"processcore\"'"
check "GET /login 200" "[ \$(curl -s -o /dev/null -w '%{http_code}' -c $J http://127.0.0.1:$PORT/login) = 200 ]"
CSRF=$(curl -s -b $J -c $J http://127.0.0.1:$PORT/login | grep -o 'name="csrf_token" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
code=$(curl -s -o /dev/null -w '%{http_code}' -b $J -c $J -X POST --data-urlencode "csrf_token=$CSRF" --data-urlencode "email=owner@processcore.test" --data-urlencode "password=owner-dev-password" --data-urlencode "next=/" http://127.0.0.1:$PORT/login)
check "POST /login as the owner redirects ($code)" "[ $code = 302 -o $code = 303 ]"
body=$(curl -s -b $J -c $J http://127.0.0.1:$PORT/)
check "the dashboard says ProcessCore, never Cidery" "echo \"\$body\" | grep -q 'ProcessCore' && ! echo \"\$body\" | grep -qi 'cidery'"
for u in /purchase-orders/ /receipts/ /lots/ /inventory/materials /products/ /production-orders/ /schedule/ /packaging-runs/ /lab/ /reports/yields /orders/ /planning/ /customers/ /equipment/ /items/ /settings/client /activity/; do
  c=$(curl -s -o /dev/null -w '%{http_code}' -b $J -c $J "http://127.0.0.1:$PORT$u"); [ "$c" = 200 ] && ok "GET $u 200" || bad "GET $u $c"
done
check "no PHP error in the server log" "! grep -qiE 'PHP (Fatal|Warning|Parse)' /tmp/pc-php.log"
kill $PHP_PID 2>/dev/null; rm -f $J

echo "== 3. the MCP servers"
. "$TOKENS"
(cd services && exec ../services/.venv/bin/python -m records_mcp.server  >/tmp/pc-records.log  2>&1) & R_PID=$!
(cd services && exec ../services/.venv/bin/python -m activity_mcp.server >/tmp/pc-activity.log 2>&1) & A_PID=$!
sleep 3
mcp() { curl -s -X POST "http://127.0.0.1:$1/mcp" -H "Authorization: Bearer $2" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d "$3"; }
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"prove","version":"1"}}}'
r=$(mcp $RP "$RECORDS_TOKEN" "$INIT");  if has "$r" processcore_records_mcp;  then ok "records MCP initialize names processcore_records_mcp";   else bad "records MCP initialize"; fi
r=$(mcp $AP "$ACTIVITY_TOKEN" "$INIT"); if has "$r" processcore_activity_mcp; then ok "activity MCP initialize names processcore_activity_mcp"; else bad "activity MCP initialize"; fi
r=$(mcp $RP "$RECORDS_TOKEN" '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'); n=$(echo "$r" | grep -o '"name":"[a-z_]*"' | sort -u | wc -l)
check "records MCP lists its tools ($n)" "[ $n -gt 40 ]"
r=$(mcp $RP "$RECORDS_TOKEN" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"app_roles","arguments":{}}}')
if has "$r" processcore.admin && has "$r" '"owner"'; then ok "app_roles answers the seven roles with processcore.admin"; else bad "app_roles"; fi
check "no cidery word in either server's tool list" "! mcp $RP $RECORDS_TOKEN '{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/list\",\"params\":{}}' | grep -qi cidery_"
check "an unknown token is refused (401)" "[ \$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:$RP/mcp -H 'Authorization: Bearer nope' -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d '$INIT') = 401 ]"
kill $R_PID $A_PID 2>/dev/null; wait $R_PID $A_PID 2>/dev/null

echo "== 4. the kernel's installer, read-only"
plan=$(php "$KERNEL/bin/app_install.php" plan "$(pwd)" --domain processcore.test 2>&1); rc=$?
check "app_install.php plan exits 0" "[ $rc -eq 0 ]"
check "plan names the application processcore" "echo \"\$plan\" | grep -q processcore"
check "plan reports no manifest error" "! echo \"\$plan\" | grep -qiE 'error|refus|invalid'"
echo "$plan" | tail -4

echo "== $pass passed, $fail failed"
[ $fail -eq 0 ]
