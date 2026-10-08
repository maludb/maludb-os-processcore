#!/usr/bin/env bash
# Mechanical per-slice conformance checks (docs/cidery/07-phase3-conventions.md, new-app skill).
# Usage: scripts/conformance.sh <feature-dir> [<feature-dir> ...]   (names under html/ and app/views/)
set -u
cd "$(dirname "$0")/.."
fail=0
for f in "$@"; do
  files=$(ls html/$f/*.php app/features/$f/*.php 2>/dev/null; find app/views/$f -name '*.php' 2>/dev/null)
  [ -z "$files" ] && { echo "FAIL $f: no files"; fail=1; continue; }
  for file in $files; do
    php -l "$file" >/dev/null 2>&1 || { echo "FAIL lint $file"; fail=1; }
  done
  if grep -n 'hx-push-url="true"' $files; then echo "FAIL $f: hx-push-url=\"true\""; fail=1; fi
  if grep -nE 'class="[^"]*\bmodal\b' $files; then echo "FAIL $f: .modal"; fail=1; fi
  if grep -nE '<\?=\s*\$[a-zA-Z_]+\[' $(find app/views/$f -name '*.php' 2>/dev/null) /dev/null | grep -v 'e(' ; then echo "WARN $f: unescaped array output above (check)"; fi
  for file in html/$f/*.php; do
    [ -e "$file" ] || continue
    if grep -q 'beginTransaction\|INSERT\|UPDATE' "$file" || grep -qE 'insert_|update_|delete_|post_[a-z]+\(\$pdo|approve_|cancel_|release_|replace_' "$file"; then
      grep -qE "require_post\(\)|REQUEST_METHOD'\] === 'POST'" "$file" || { echo "FAIL $file: writes without require_post()"; fail=1; }
      grep -q 'verify_csrf()' "$file" || { echo "FAIL $file: writes without verify_csrf()"; fail=1; }
      # Self-service screens (own profile, own 2FA) authorize by session; everything else by role.
      grep -qE 'require_role\(|conformance: self-service' "$file" || { echo "FAIL $file: writes without require_role()"; fail=1; }
      grep -q 'log_activity(' "$file" || { echo "FAIL $file: writes without log_activity()"; fail=1; }
    elif grep -q 'render_screen(' "$file"; then
      grep -q 'log_screen_entered(' "$file" || grep -q 'http_response_code(422)' "$file" || { echo "FAIL $file: screen without log_screen_entered()"; fail=1; }
      grep -qE 'require_login\(|require_role\(' "$file" || { echo "FAIL $file: screen without authentication"; fail=1; }
    fi
  done
  # Query functions take PDO first and never touch the request.
  if [ -e app/features/$f/queries.php ]; then
    grep -nE '\$_(GET|POST|REQUEST|SERVER|SESSION)|header\(|http_response_code' app/features/$f/*.php && { echo "FAIL $f: queries touch request/response"; fail=1; }
    grep -nP '^function [a-z_]+\((?!PDO )' app/features/$f/*.php | while read -r line; do echo "INFO function without PDO first: $line"; done
  fi
  # Duplicate ids inside each view file (static ids only).
  for file in $(find app/views/$f -name '*.php' 2>/dev/null); do
    dups=$(grep -oE 'id="[a-z0-9-]+"' "$file" | sort | uniq -d)
    [ -n "$dups" ] && { echo "WARN duplicate static ids in $file: $dups"; }
  done
  # Interpolated SQL identifiers must come from order_by() allowlists.
  grep -nE 'ORDER BY .*\$_|ORDER BY .*\$(sort|order)\b' app/features/$f/*.php 2>/dev/null | grep -v 'order_by(' && { echo "FAIL $f: raw ORDER BY interpolation"; fail=1; }
done
[ $fail -eq 0 ] && echo "PASS $*" || exit 1
