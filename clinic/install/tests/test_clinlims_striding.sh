#!/usr/bin/env bash
# The OpenELIS sequence striding, clinic (clinic/openelis/apply-sequence-striding.sql,
# task 060 and the upgrade's numbering step) and hub
# (hub/openelis/apply-sequence-striding.sql, hub/scripts/stride-openelis.sh),
# against a real PostgreSQL:
#   - a sequence restarts above the largest id of every table OpenELIS numbers
#     from it: a catalogue sequence standing below its rows, a sequence whose
#     mapped name is not <table>_seq, a sequence two tables share;
#   - a clinic sequence already on its residue and clear of its rows is kept, one
#     behind its rows is lifted, so a second run changes nothing;
#   - a residue that is not one digit from 1 to 9 is refused, changing nothing;
#   - the hub's run lifts an already-strided sequence standing at or below its
#     rows, keeps one clear of them, strides an unstrided one, and refuses
#     another node's striding, changing nothing;
#   - hub/openelis/down-sequence-state.sql reports, for each down table, the
#     restart the hub's run then gives its sequence;
#   - the three files carry the same list of sequences OpenELIS names otherwise.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "${HERE}/../../.." && pwd)"
CL="$R/clinic/openelis/apply-sequence-striding.sql"; HB="$R/hub/openelis/apply-sequence-striding.sql"; DS="$R/hub/openelis/down-sequence-state.sql"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
PGC=""
cleanup(){ [ -n "$PGC" ] && docker rm -f -v "$PGC" >/dev/null 2>&1; }
trap cleanup EXIT

names(){ sed -n '/openelis-sequence-names:begin/,/openelis-sequence-names:end/p' "$1"; }
[ -n "$(names "$CL")" ] && [ "$(names "$CL")" = "$(names "$HB")" ] && [ "$(names "$CL")" = "$(names "$DS")" ] \
  && ok_ "the clinic striding, the hub striding and the hub's sequence read carry one list of the sequences OpenELIS names otherwise ($(names "$CL" | grep -c "_seq'\|idseq'") entries)" \
  || bad "the lists of sequences OpenELIS names otherwise differ between $(basename "$CL"), hub $(basename "$HB") and $(basename "$DS")"

# pg_get_serial_sequence raises on a table without an id column, and on a large
# schema the planner may call it before the column test: every call sits in a
# CASE on the column name
for f in "$CL" "$HB"; do
  n="$(grep -v '^ *--' "$f" | grep -c "pg_get_serial_sequence")"; g="$(grep -v '^ *--' "$f" | grep -c "CASE WHEN c.column_name = 'id' THEN pg_get_serial_sequence")"
  [ "$n" -ge 1 ] && [ "$n" = "$g" ] && ok_ "$(basename "$(dirname "$(dirname "$f")")")/openelis: each pg_get_serial_sequence call is guarded by a CASE on the column" || bad "$f: $g of $n pg_get_serial_sequence calls guarded by a CASE on the column"
done

docker_answers(){
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 & local p=$! i=0
  while kill -0 "$p" 2>/dev/null; do [ "$i" -ge "${DOCKER_PROBE_S:-15}" ] && { kill "$p" 2>/dev/null; return 1; }; sleep 1; i=$((i+1)); done
  wait "$p"
}
if ! docker_answers || ! docker image inspect postgres:16 >/dev/null 2>&1; then
  ok_ "live PostgreSQL proof skipped (no docker or no postgres:16 image here)"
  exit $((fails > 0))
fi
PGC="clinlims-striding-test-$$"
docker run -d --name "$PGC" --tmpfs /var/lib/postgresql/data -e POSTGRES_PASSWORD=x postgres:16 >/dev/null 2>&1 || { bad "could not start postgres:16"; exit 1; }
for i in $(seq 1 60); do docker exec "$PGC" psql -U postgres -Atc 'select 1' >/dev/null 2>&1 && break; sleep 1; done
P(){ docker exec -i "$PGC" psql -U postgres -v ON_ERROR_STOP=1 -At "$@"; }
# the id a sequence issues next, read without using it
nx(){ P -c "select case when s.is_called then s.last_value + p.increment_by else s.last_value end || ':' || p.increment_by from clinlims.$1 s, pg_sequences p where p.schemaname = 'clinlims' and p.sequencename = '$1'"; }

# --- clinic, residue 3, from a seed: the hub's sequences step by 10 from multiples of 10
P -q >/dev/null <<'SQL'
CREATE SCHEMA clinlims;
CREATE TABLE clinlims.analyte (id numeric(10) PRIMARY KEY);            INSERT INTO clinlims.analyte VALUES (100), (110), (123), (150), (276);
CREATE TABLE clinlims.label (id numeric(10) PRIMARY KEY);              INSERT INTO clinlims.label VALUES (10), (20), (71);
CREATE TABLE clinlims.method (id numeric(10) PRIMARY KEY);             INSERT INTO clinlims.method VALUES (10), (37);
CREATE TABLE clinlims.source_of_sample (id numeric(10) PRIMARY KEY);   INSERT INTO clinlims.source_of_sample VALUES (5), (205);
CREATE TABLE clinlims.system_user_module (id numeric(10) PRIMARY KEY); INSERT INTO clinlims.system_user_module VALUES (40);
CREATE TABLE clinlims.system_role_module (id numeric(10) PRIMARY KEY); INSERT INTO clinlims.system_role_module VALUES (95);
CREATE TABLE clinlims.sample (id numeric(10) PRIMARY KEY);
CREATE TABLE clinlims.sample_type_link (a int, b int);
CREATE SEQUENCE clinlims.analyte_seq INCREMENT BY 10;            SELECT setval('clinlims.analyte_seq', 100, false);
CREATE SEQUENCE clinlims.label_seq INCREMENT BY 10;              SELECT setval('clinlims.label_seq', 10, false);
CREATE SEQUENCE clinlims.method_seq INCREMENT BY 10;             SELECT setval('clinlims.method_seq', 40, false);
CREATE SEQUENCE clinlims.src_of_sample_seq INCREMENT BY 10;      SELECT setval('clinlims.src_of_sample_seq', 210, false);
CREATE SEQUENCE clinlims.system_user_module_seq INCREMENT BY 10; SELECT setval('clinlims.system_user_module_seq', 50, false);
CREATE SEQUENCE clinlims.sample_seq;                             SELECT setval('clinlims.sample_seq', 7, true);
CREATE SEQUENCE clinlims.orphan_seq INCREMENT BY 10;             SELECT setval('clinlims.orphan_seq', 1000, true);
SQL
out="$(P -q -v residue=3 -f /dev/stdin < "$CL" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qx 'clinlims sequences step 10 on residue 3 above their rows: 7 of 7' \
  && ok_ "clinic: every sequence strided onto residue 3, the summary line says so" || bad "clinic run: rc=$rc $out"
[ "$(nx analyte_seq)" = 283:10 ] && ok_ "clinic: analyte's sequence stood at 100 under rows to 276: next id 283" || bad "analyte next $(nx analyte_seq)"
[ "$(nx label_seq)" = 83:10 ] && [ "$(nx method_seq)" = 53:10 ] && ok_ "clinic: label (rows to 71) next 83; method, already above its rows at 40, next 53" || bad "label $(nx label_seq) method $(nx method_seq)"
[ "$(nx src_of_sample_seq)" = 223:10 ] && ok_ "clinic: source_of_sample takes ids from src_of_sample_seq, at 210 above rows to 205: next 223" || bad "src_of_sample $(nx src_of_sample_seq)"
[ "$(nx system_user_module_seq)" = 103:10 ] && ok_ "clinic: system_user_module_seq numbers two tables, the larger (system_role_module, 95) decides: next 103" || bad "shared sequence $(nx system_user_module_seq)"
[ "$(nx sample_seq)" = 13:10 ] && [ "$(nx orphan_seq)" = 1013:10 ] && ok_ "clinic: an unstrided sequence and one with no table restart from their last values (13, 1013)" || bad "sample $(nx sample_seq) orphan $(nx orphan_seq)"
before="$(for q in analyte_seq label_seq method_seq src_of_sample_seq system_user_module_seq sample_seq orphan_seq; do nx $q; done | tr '\n' ' ')"
out="$(P -q -v residue=3 -f /dev/stdin < "$CL" 2>&1)"; rc=$?
after="$(for q in analyte_seq label_seq method_seq src_of_sample_seq system_user_module_seq sample_seq orphan_seq; do nx $q; done | tr '\n' ' ')"
[ "$rc" = 0 ] && [ "$before" = "$after" ] && printf '%s\n' "$out" | grep -q 'strided 0 clinlims sequences; lifted 0 above their rows; 7 already on residue 3' \
  && ok_ "clinic: a second run keeps every sequence" || bad "clinic second run: rc=$rc before [$before] after [$after] $out"

# an upgraded clinic: sequences on residue 3 that were strided from their last values
P -q -c "SELECT setval('clinlims.analyte_seq', 123, false); SELECT setval('clinlims.method_seq', 33, false)" >/dev/null
out="$(P -q -v residue=3 -f /dev/stdin < "$CL" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(nx analyte_seq)" = 283:10 ] && [ "$(nx method_seq)" = 43:10 ] && [ "$(nx label_seq)" = 83:10 ] \
  && printf '%s\n' "$out" | grep -q 'strided 0 clinlims sequences; lifted 2 above their rows; 5 already on residue 3' \
  && ok_ "clinic: on residue 3 but behind their rows, analyte (123) and method (33) are lifted to 283 and 43; the rest are kept" || bad "clinic lift: rc=$rc analyte $(nx analyte_seq) method $(nx method_seq) label $(nx label_seq) $out"
before="$(nx analyte_seq)"; out="$(P -q -v residue=0 -f /dev/stdin < "$CL" 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'residue must be this clinic' && [ "$(nx analyte_seq)" = "$before" ] \
  && ok_ "clinic: residue 0 is refused and nothing is changed" || bad "clinic residue 0: rc=$rc $out"

# --- hub, residue 0
P -q >/dev/null <<'SQL'
DROP SCHEMA clinlims CASCADE; CREATE SCHEMA clinlims;
CREATE TABLE clinlims.analyte (id numeric(10) PRIMARY KEY);     INSERT INTO clinlims.analyte VALUES (100), (110), (150), (276);
CREATE TABLE clinlims.provider (id numeric(10) PRIMARY KEY);    INSERT INTO clinlims.provider VALUES (10);
CREATE TABLE clinlims.test (id numeric(10) PRIMARY KEY);        INSERT INTO clinlims.test VALUES (1413);
CREATE TABLE clinlims.system_user (id numeric(10) PRIMARY KEY); INSERT INTO clinlims.system_user VALUES (163);
CREATE TABLE clinlims.sampletype_test (id numeric(10) PRIMARY KEY); INSERT INTO clinlims.sampletype_test VALUES (88);
CREATE SEQUENCE clinlims.analyte_seq INCREMENT BY 10;     SELECT setval('clinlims.analyte_seq', 100, false);
CREATE SEQUENCE clinlims.provider_seq INCREMENT BY 10;    SELECT setval('clinlims.provider_seq', 10, false);
CREATE SEQUENCE clinlims.test_seq;                        SELECT setval('clinlims.test_seq', 1400, true);
CREATE SEQUENCE clinlims.system_user_seq INCREMENT BY 10; SELECT setval('clinlims.system_user_seq', 170, false);
CREATE SEQUENCE clinlims.sample_type_test_seq;            SELECT setval('clinlims.sample_type_test_seq', 12, true);
SQL
ds="$(P -q -v tables=analyte,provider,test,system_user,sampletype_test -f /dev/stdin < "$DS" 2>&1)"
[ "$ds" = "$(printf 'analyte|280|100|10\nprovider|20|10|10\ntest|1420|1401|1\nsystem_user|180|170|10\nsampletype_test|90|13|1')" ] \
  && ok_ "hub: the sequence read restarts each above its rows: analyte 280, provider 20, test 1420, sampletype_test (from sample_type_test_seq) 90" || bad "hub sequence read: $ds"
out="$(P -q -f /dev/stdin < "$HB" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qx 'sequences step 10: 5 of 5' && printf '%s\n' "$out" | grep -q 'strided 2 sequence(s); lifted 2 above their rows; 1 already stepped by 10' \
  && ok_ "hub: two strided, two lifted, one kept; the summary line says so" || bad "hub run: rc=$rc $out"
[ "$(nx analyte_seq)" = 280:10 ] && [ "$(nx provider_seq)" = 20:10 ] && [ "$(nx test_seq)" = 1420:10 ] && [ "$(nx sample_type_test_seq)" = 90:10 ] && [ "$(nx system_user_seq)" = 170:10 ] \
  && ok_ "hub: each next id is where the sequence read said it restarts (analyte 280, provider 20, test 1420, sample_type_test 90); system_user, clear of its rows, stays at 170" \
  || bad "hub next ids: analyte $(nx analyte_seq) provider $(nx provider_seq) test $(nx test_seq) sample_type_test $(nx sample_type_test_seq) system_user $(nx system_user_seq)"
before="$(for q in analyte_seq provider_seq test_seq system_user_seq sample_type_test_seq; do nx $q; done | tr '\n' ' ')"
out="$(P -q -f /dev/stdin < "$HB" 2>&1)"; rc=$?
after="$(for q in analyte_seq provider_seq test_seq system_user_seq sample_type_test_seq; do nx $q; done | tr '\n' ' ')"
[ "$rc" = 0 ] && [ "$before" = "$after" ] && ok_ "hub: a second run moves nothing" || bad "hub second run: rc=$rc before [$before] after [$after] $out"
P -q -c "ALTER SEQUENCE clinlims.provider_seq RESTART WITH 13" >/dev/null
P -q -c "SELECT setval('clinlims.analyte_seq', 100, false)" >/dev/null
out="$(P -q -f /dev/stdin < "$HB" 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "not the hub's striding (residue 0): provider_seq" && [ "$(nx analyte_seq)" = 100:10 ] \
  && ok_ "hub: a sequence on another node's residue is refused, naming it, and nothing is changed (analyte stays behind at 100)" || bad "hub refusal: rc=$rc analyte $(nx analyte_seq) $out"

exit $((fails > 0))
