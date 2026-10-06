#!/usr/bin/env bash
# The clinic's sink database user is granted table by table, and the list is
# hub/tables.conf's: a table added there (the form tables) is granted by seed
# task 050 and, on a node already seeded, by scripts/grant-down-tables.sh;
# both read the grants back. MySQL is a fake that logs every statement.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
T50="${HERE}/../tasks/050-databases.sh"; S="${HERE}/../../scripts/grant-down-tables.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
lib(){ env -i PATH="$PATH" REPO_DIR="${R:-$RP}" bash -c ". '${HERE}/../lib.sh'; \"\$@\"" _ "$@" 2>&1; }

# --- the list ------------------------------------------------------------------
want="$(grep -vE '^[[:space:]]*(#|$)' "$RP/hub/tables.conf" | cut -d: -f1)"
got="$(lib down_tables)"
[ -n "$got" ] && [ "$got" = "$want" ] && ok_ "down_tables is every hub/tables.conf row, in order ($(printf '%s' "$got" | tr '\n' ' '))" || bad "down_tables: '$(printf '%s' "$got" | tr '\n' ' ')' want '$(printf '%s' "$want" | tr '\n' ' ')'"
for t in form form_resource person person_name users; do printf '%s\n' "$got" | grep -qx "$t" || bad "down_tables lacks $t"; done
sql="$(lib sink_grant_sql)"
printf '%s\n' "$sql" | grep -qxF "GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.form TO 'sink'@'%';" \
  && printf '%s\n' "$sql" | grep -qxF "GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.form_resource TO 'sink'@'%';" \
  && ok_ "the sink user is granted form and form_resource" || bad "grants: $sql"
[ "$(printf '%s\n' "$sql" | grep -c '^GRANT ')" = "$(printf '%s\n' "$want" | grep -c .)" ] && ok_ "one GRANT per down table" || bad "grant count: $(printf '%s\n' "$sql" | grep -c '^GRANT ')"
RR="$TMP/r"; mkdir -p "$RR/hub"; { cat "$RP/hub/tables.conf"; printf 'concept_class:concept_class_id   # trailing comment\n'; } > "$RR/hub/tables.conf"
R="$RR" lib sink_grant_sql | grep -qxF "GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.concept_class TO 'sink'@'%';" && ok_ "a table added to hub/tables.conf is granted with no other change" || bad "added table not granted: $(R="$RR" lib sink_grant_sql | tail -2)"
printf 'Bad-Table:id\n' >> "$RR/hub/tables.conf"
out="$(R="$RR" lib sink_grant_sql)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "bad table name 'Bad-Table'" && ok_ "a malformed table name fails, by name" || bad "malformed name: rc=$rc out=$out"

# --- the read-back -------------------------------------------------------------------
full="$(printf '%s\n' "$want" | awk '{printf "%s\tSelect,Insert,Update,Delete\n", $1}')"
[ -z "$(printf '%s\n' "$full" | lib sink_grants_missing)" ] && ok_ "read-back: every table granted, nothing missing" || bad "read-back on full grants: $(printf '%s\n' "$full" | lib sink_grants_missing)"
short="$(printf '%s\n' "$full" | grep -v '^form_resource	' | sed 's/^form	.*/form	Select,Insert,Update/')"
m="$(printf '%s\n' "$short" | lib sink_grants_missing | tr '\n' ' ')"
[ "$m" = "form form_resource " ] && ok_ "read-back names a table missing DELETE and a table with no grant" || bad "read-back on partial grants: '$m'"

# --- task 050 at seed --------------------------------------------------------------------
code="$(grep -vE '^[[:space:]]*#' "$T50")"
printf '%s' "$code" | grep -qE "GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs\.[a-z_]+ TO" && bad "050 still grants a hard-coded table" || ok_ "050 names no down table itself"
blk="$(sed -n '/# sink-grants:begin/,/# sink-grants:end/p' "$T50")"
[ -n "$blk" ] || bad "050 has no sink-grants block"
run50(){ # GRANTED-ROWS : runs 050's block with a fake mysql_root
  printf '%s\n' "$1" > "$TMP/granted"; : > "$TMP/sql50"
  env -i PATH="$PATH" REPO_DIR="$RP" G="$TMP/granted" L="$TMP/sql50" DEBEZIUM_DB_PASSWORD=d LOCAL_MYSQL_PASSWORD=s bash -c ". '${HERE}/../lib.sh'
fail(){ printf 'FAIL %s\n' \"\$*\"; exit 1; }; ok(){ printf 'OK %s\n' \"\$*\"; }
mysql_root(){ q=\"\$(cat)\"; printf '%s\n' \"\$q\" >> \"\$L\"; case \"\$q\" in *'from mysql.user'*) echo 2 ;; *tables_priv*) cat \"\$G\" ;; esac; }
${blk}" 2>&1
}
out="$(run50 "$full")"; rc=$?
[ "$rc" -eq 0 ] && grep -qxF "GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.form_resource TO 'sink'@'%';" "$TMP/sql50" && grep -qxF "CREATE USER IF NOT EXISTS 'sink'@'%' IDENTIFIED BY 's';" "$TMP/sql50" \
  && printf '%s' "$out" | grep -q '^OK sink user granted on every down table: .*form form_resource' && ok_ "050 creates the sink user and grants it every down table, read back" || bad "050 grants: rc=$rc out=$out sql=$(tr '\n' ' ' < "$TMP/sql50")"
out="$(run50 "$short")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '^FAIL the sink user lacks .*on: form form_resource' && ok_ "050 fails when the read-back is short, naming the tables" || bad "050 short read-back: rc=$rc out=$out"

# --- scripts/grant-down-tables.sh on a seeded node ------------------------------------------
[ -f "$S" ] || { bad "no scripts/grant-down-tables.sh"; exit "$fails"; }
mkdir -p "$TMP/bin" "$TMP/node"; printf 'COMPOSE_PROJECT_NAME=bahmni-t\n' > "$TMP/node/.env"
cat > "$TMP/bin/fakect" <<'SH'
#!/usr/bin/env bash
q="$(cat)"; printf '%s\n' "ct $*" "$q" >> "$FAKE_LOG"
case "$q" in
  *"from mysql.user"*) echo "${FAKE_USERS:-1}" ;;
  *information_schema.tables*) printf '%s\n' $FAKE_TABLES ;;
  *tables_priv*) cat "$FAKE_GRANTED" ;;
esac
SH
chmod +x "$TMP/bin/fakect"
gs(){ env PATH="$PATH" CLINIC_DIR="$TMP/node" CT="$TMP/bin/fakect" COMPOSE_CMD=true FAKE_LOG="$TMP/log" FAKE_GRANTED="$TMP/granted" \
        FAKE_TABLES="${TABLES-$(printf '%s ' $want) obs concept}" FAKE_USERS="${USERS:-1}" bash "$S" "$@" 2>&1; }
printf '%s\n' "$full" > "$TMP/granted"; : > "$TMP/log"
out="$(gs)"; rc=$?
[ "$rc" -eq 0 ] && grep -q '^ct exec -i bahmni-t-bahmni-mysql-1 ' "$TMP/log" && grep -qxF "GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.form TO 'sink'@'%';" "$TMP/log" \
  && printf '%s' "$out" | grep -q 'ok   sink user holds SELECT, INSERT, UPDATE, DELETE on every down table' && ok_ "grant-down-tables.sh grants every down table in the node's MySQL and reads it back" || bad "grant-down-tables: rc=$rc out=$out"
printf '%s' "$out" | grep -q 'generate-local-sink-connectors.sh && bash scripts/register-local-sink-connectors.sh' && ok_ "it names the next step: regenerate and register the down sinks" || bad "no next step: $out"
: > "$TMP/log"; out="$(USERS=0 gs)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'has no sink user: this node has not been seeded' && ! grep -q '^GRANT' "$TMP/log" && ok_ "a node with no sink user is refused, nothing granted" || bad "no sink user: rc=$rc out=$out"
: > "$TMP/log"; out="$(TABLES="users obs" gs)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'has no table:.* form form_resource' && ! grep -q '^GRANT' "$TMP/log" && ok_ "a database without a listed table is refused before any grant, naming it" || bad "absent table: rc=$rc out=$out"
printf '%s\n' "$short" > "$TMP/granted"; : > "$TMP/log"; out="$(gs)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'still lacks .*on: form form_resource' && ok_ "a short read-back after granting fails, naming the tables" || bad "short read-back: rc=$rc out=$out"
: > "$TMP/log"; out="$(env PATH="$PATH" CLINIC_DIR="$TMP/nowhere" bash "$S" --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.form_resource TO 'sink'@'%';" && [ ! -s "$TMP/log" ] \
  && ok_ "--dry-run prints the grants and touches nothing" || bad "--dry-run: rc=$rc out=$out"
exit "$fails"
