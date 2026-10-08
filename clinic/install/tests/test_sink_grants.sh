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
# a grant on the whole openmrs database or a global one also lets the sink write
# every table; the read-back reports each as a "*" row
rb="$(lib eval 'printf "%s\n" "$SINK_GRANTS_READ_SQL"')"
printf '%s' "$rb" | grep -q 'from mysql.tables_priv' && printf '%s' "$rb" | grep -q "from mysql.db where User='sink' and Host='%' and Db='openmrs'" && printf '%s' "$rb" | grep -q "from mysql.user where User='sink' and Host='%'" \
  && ok_ "the read-back reads table, database and global grants" || bad "read-back SQL: $rb"
[ -z "$(printf '*\tSelect,Insert,Update,Delete\n' | lib sink_grants_missing)" ] && ok_ "a grant on the whole database (or a global one) covers every down table" || bad "database-level grant: $(printf '*\tSelect,Insert,Update,Delete\n' | lib sink_grants_missing | tr '\n' ' ')"
m="$(printf '*\tSelect,Insert,Update\nform\tDelete\n' | lib sink_grants_missing form form_resource | tr '\n' ' ')"
[ "$m" = "form_resource " ] && ok_ "levels add up: SELECT, INSERT, UPDATE on the database and DELETE on form cover form only" || bad "levels combined: '$m'"
m="$(printf '%s\n*\t\n*\t\n' "$full" | lib sink_grants_missing | tr '\n' ' ')"
[ "$m" = " " ] || [ -z "$m" ] && ok_ "an empty database or global row takes nothing away from table grants" || bad "empty level rows: '$m'"

# --- task 050 at seed --------------------------------------------------------------------
code="$(grep -vE '^[[:space:]]*#' "$T50")"
printf '%s' "$code" | grep -qE "GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs\.[a-z_]+ TO" && bad "050 still grants a hard-coded table" || ok_ "050 names no down table itself"
blk="$(sed -n '/# sink-grants:begin/,/# sink-grants:end/p' "$T50")"
[ -n "$blk" ] || bad "050 has no sink-grants block"
run50(){ # GRANTED-ROWS : runs 050's block with a fake mysql_root
  printf '%s\n' "$1" > "$TMP/granted"; : > "$TMP/sql50"
  env -i PATH="$PATH" REPO_DIR="$RP" G="$TMP/granted" L="$TMP/sql50" DEBEZIUM_DB_PASSWORD=d LOCAL_MYSQL_PASSWORD=s bash -c ". '${HERE}/../lib.sh'
fail(){ printf 'FAIL %s\n' \"\$*\"; exit 1; }; ok(){ printf 'OK %s\n' \"\$*\"; }
mysql_root(){ q=\"\$(cat)\"; printf '%s\n' \"\$q\" >> \"\$L\"; case \"\$q\" in *tables_priv*) cat \"\$G\" ;; *'from mysql.user'*) echo 2 ;; esac; }
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
  *tables_priv*) cat "$FAKE_GRANTED" ;;
  *"from mysql.user"*) echo "${FAKE_USERS:-1}" ;;
  *information_schema.tables*) printf '%s\n' $FAKE_TABLES ;;
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

# --- registration refuses a sink whose table the sink user cannot write ------------------------
REG="${HERE}/../../scripts/register-local-sink-connectors.sh"
mkdir -p "$TMP/gen" "$TMP/cbin"
for t in users form form_resource; do
  printf '{"name": "mysql-local-sink-%s", "config": {"table.name.format": "%s", "topics": "remote.bahmni-cloud.openmrs.%s"}}\n' "$t" "$t" "$t" > "$TMP/gen/mysql-local-sink-${t}.json"
done
# a fake curl: logs every call; no connector exists yet, so each one is created
cat > "$TMP/cbin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "curl $*" >> "$CURL_LOG"
case "$*" in
  *http_code*) printf 201 ;;
  *-sf*/connectors/mysql-local-sink-*) exit 22 ;;
  *-sf*/connectors) printf '[]' ;;
esac
exit 0
SH
chmod +x "$TMP/cbin/curl"
reg(){ env PATH="$TMP/cbin:$PATH" CLINIC_DIR="$TMP/node" CT="$TMP/bin/fakect" COMPOSE_CMD=true FAKE_LOG="$TMP/log" FAKE_GRANTED="$TMP/granted" \
         CURL_LOG="$TMP/curl" SINK_SETTLE_S=0 LOCAL_CONNECT_URL=http://connect.invalid:8083 bash "$REG" "$TMP/gen" 2>&1; }
printf '%s\n' "$short" > "$TMP/granted"; : > "$TMP/log"; : > "$TMP/curl"
out="$(reg)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'REFUSING to register the down sinks: the sink user lacks SELECT, INSERT, UPDATE or DELETE on: form form_resource' \
  && ok_ "registration refuses when the sink user lacks a grant, naming the tables" || bad "short grants at registration: rc=$rc out=$out"
[ ! -s "$TMP/curl" ] && ok_ "and makes no Kafka Connect call" || bad "Connect was called despite the refusal: $(tr '\n' ' ' < "$TMP/curl")"
grep -q '^ct exec -i bahmni-t-bahmni-mysql-1 ' "$TMP/log" && grep -q 'tables_priv' "$TMP/log" && ! grep -q '^GRANT' "$TMP/log" \
  && ok_ "the grants are read in the node's MySQL container, and nothing is granted" || bad "grant read at registration: $(tr '\n' ' ' < "$TMP/log")"
printf 'users\tSelect,Insert,Update,Delete\nform\tSelect,Insert,Update,Delete\nform_resource\tSelect,Insert,Update,Delete\n' > "$TMP/granted"; : > "$TMP/curl"
out="$(reg)"; rc=$?
[ "$(grep -c -- '-X POST .*--data @.*mysql-local-sink-' "$TMP/curl")" = 3 ] && printf '%s' "$out" | grep -q 'sink user holds SELECT, INSERT, UPDATE, DELETE on all 3 down sink table(s)' \
  && ok_ "with every grant held, all three sinks are registered" || bad "full grants at registration: rc=$rc out=$out curl=$(tr '\n' ' ' < "$TMP/curl")"
printf 'users\tSelect,Insert,Update,Delete\nform\tSelect,Insert,Update,Delete\nform_resource\tSelect,Insert,Update\n' > "$TMP/granted"; : > "$TMP/curl"
out="$(reg)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'lacks .*on: form_resource' && [ ! -s "$TMP/curl" ] \
  && ok_ "one missing privilege on one table is enough to refuse" || bad "missing DELETE at registration: rc=$rc out=$out"
printf '%s\n' "$full" > "$TMP/granted"; : > "$TMP/curl"
out="$(env PATH="$TMP/cbin:$PATH" CLINIC_DIR="$TMP/nowhere" CT="$TMP/bin/fakect" CURL_LOG="$TMP/curl" SINK_SETTLE_S=0 bash "$REG" "$TMP/gen" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "grants cannot be read, so nothing was registered" && [ ! -s "$TMP/curl" ] \
  && ok_ "a node whose grants cannot be read registers nothing" || bad "no .env at registration: rc=$rc out=$out"
printf '*\tSelect,Insert,Update,Delete\n' > "$TMP/granted"; : > "$TMP/curl"
out="$(reg)"; rc=$?
[ "$(grep -c -- '-X POST .*--data @.*mysql-local-sink-' "$TMP/curl")" = 3 ] && ok_ "a grant on the whole openmrs database is enough to register" || bad "database-level grant at registration: rc=$rc out=$out"
printf '*\tSelect,Insert,Update\n' > "$TMP/granted"; : > "$TMP/curl"
out="$(reg)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'lacks .*on: .*users' && printf '%s' "$out" | grep -q 'lacks .*on: .*form ' && printf '%s' "$out" | grep -q 'lacks .*on: .*form_resource' && [ ! -s "$TMP/curl" ] \
  && ok_ "a database-level grant without DELETE refuses every sink" || bad "short database-level grant at registration: rc=$rc out=$out"

# --- the read-back against a real MySQL, when one can be started without a download ----------
IMG="$(sed -n 's/^MYSQL_IMAGE=\([^[:space:]#]*\).*/\1/p' "$RP/sync/versions.env")"
if [ "${TEST_NO_CONTAINERS:-0}" = 1 ] || ! command -v docker >/dev/null 2>&1 || ! docker image inspect "$IMG" >/dev/null 2>&1; then
  ok_ "no container runtime or no local ${IMG:-MySQL image}: the real-MySQL grant checks are skipped"
  exit "$fails"
fi
CNAME="sg-test-$$"; trap 'docker rm -f "$CNAME" >/dev/null 2>&1; rm -rf "$TMP"' EXIT
docker run -d --name "$CNAME" --tmpfs /var/lib/mysql -e MYSQL_ROOT_PASSWORD=t -e MYSQL_DATABASE=openmrs "$IMG" \
  --skip-log-bin --innodb-buffer-pool-size=16M --performance-schema=OFF >/dev/null 2>&1 || { bad "could not start ${IMG}"; exit "$fails"; }
up=0; for i in $(seq 1 120); do docker logs "$CNAME" 2>&1 | grep -q 'ready for connections.*port: 3306' && { up=1; break; }; sleep 1; done
[ "$up" = 1 ] || { bad "${IMG} was not ready within 120 s"; exit "$fails"; }
rq(){ docker exec -i "$CNAME" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N'; }
printf "CREATE TABLE openmrs.users (user_id int PRIMARY KEY); CREATE TABLE openmrs.form (form_id int PRIMARY KEY); CREATE USER 'sink'@'%%' IDENTIFIED BY 's';\n" | rq
live(){ printf '%s\n' "$(lib eval 'printf "%s\n" "$SINK_GRANTS_READ_SQL"')" | rq | lib sink_grants_missing users form | tr '\n' ' '; }
[ "$(live)" = "users form " ] && ok_ "real MySQL: a user with no grant lacks both tables" || bad "real MySQL, no grant: '$(live)'"
printf "GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.* TO 'sink'@'%%';\n" | rq
[ -z "$(live)" ] && ok_ "real MySQL: a grant on openmrs.* covers both tables" || bad "real MySQL, database grant: '$(live)'"
printf "REVOKE ALL ON openmrs.* FROM 'sink'@'%%'; GRANT SELECT, INSERT, UPDATE, DELETE ON *.* TO 'sink'@'%%';\n" | rq
[ -z "$(live)" ] && ok_ "real MySQL: a global grant covers both tables" || bad "real MySQL, global grant: '$(live)'"
printf "REVOKE SELECT, INSERT, UPDATE, DELETE ON *.* FROM 'sink'@'%%'; GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.form TO 'sink'@'%%';\n" | rq
[ "$(live)" = "users " ] && ok_ "real MySQL: a table grant on form covers form only" || bad "real MySQL, table grant: '$(live)'"
exit "$fails"
