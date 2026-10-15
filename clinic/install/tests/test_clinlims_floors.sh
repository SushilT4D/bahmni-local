#!/usr/bin/env bash
# The striding step records where this clinic's own ids of each table the
# hub's OpenELIS down rows are routed by begin (state.sh
# record_clinlims_floors), before it strides, and the OpenELIS down filter
# reads them back:
#   - the tables come from the down list's routes (today analysis and sample)
#     and the OpenELIS source's own-rows tables (system_user, result_signature);
#   - a first run records CLINLIMS_FLOOR_<TABLE> = (last_value / 10 + 1) * 10
#     in .install-state, the restart the stride gives the sequence, less the
#     residue;
#   - a second run keeps every recorded floor and does not read the sequences,
#     however far they moved;
#   - a table with no id sequence is refused, naming it, and no floor is
#     written for it; an unreadable database and a malformed recorded value
#     are refused too;
#   - task 060 records them before its OpenELIS stride and stops on a refusal,
#     and its dry run names them;
#   - clinic/scripts/clinlims-down-filter.sh writes its filter from them;
#   - with docker and postgres:16: the read on a real database gives the value
#     the stride restarts from, for a used sequence and for one set but never
#     used.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "${HERE}/../../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; PGC=""
cleanup(){ [ -n "$PGC" ] && docker rm -f -v "$PGC" >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT
CLINIC_DIR="$TMP/clinic"; mkdir -p "$CLINIC_DIR"; REPO_DIR="$R"
. "${HERE}/../lib.sh"; . "${HERE}/../state.sh"
SF="$CLINIC_DIR/.install-state"

[ "$(clinlims_floor_tables | tr '\n' ' ')" = "analysis sample system_user result_signature " ] && ok_ "the floor tables: the down list's routes (analysis, sample), then the tables the OpenELIS source publishes only above the clinic's floor (system_user, result_signature)" || bad "floor tables: $(clinlims_floor_tables 2>&1 | tr '\n' ' ')"

# a stand-in for the database: FAKE_<table> holds what the read prints; each read is logged
fake_read(){ echo "$1" >> "$TMP/reads"; [ -f "$TMP/err.$1" ] && return 2; cat "$TMP/FAKE_$1" 2>/dev/null; return 0; }
echo 'clinlims.analysis_seq|1203' > "$TMP/FAKE_analysis"; echo 'clinlims.sample_seq|790' > "$TMP/FAKE_sample"
echo 'clinlims.system_user_seq|163' > "$TMP/FAKE_system_user"; echo 'clinlims.result_signature_seq|4391' > "$TMP/FAKE_result_signature"
out="$(record_clinlims_floors fake_read)"; rc=$?
[ "$rc" = 0 ] && [ "$(stamp_get CLINLIMS_FLOOR_ANALYSIS)" = 1210 ] && [ "$(stamp_get CLINLIMS_FLOOR_SAMPLE)" = 800 ] \
  && [ "$(stamp_get CLINLIMS_FLOOR_SYSTEM_USER)" = 170 ] && [ "$(stamp_get CLINLIMS_FLOOR_RESULT_SIGNATURE)" = 4400 ] \
  && printf '%s' "$out" | grep -q '^ok CLINLIMS_FLOOR_ANALYSIS=1210 (recorded' \
  && ok_ "first run: analysis 1203 -> 1210, sample 790 -> 800, system_user 163 -> 170, result_signature 4391 -> 4400, recorded in .install-state" || bad "first run: rc=$rc $out | $(cat "$SF" 2>/dev/null)"
before="$(cat "$SF")"; rm -f "$TMP/reads"
echo 'clinlims.analysis_seq|1563' > "$TMP/FAKE_analysis"; echo 'clinlims.sample_seq|993' > "$TMP/FAKE_sample"
out="$(record_clinlims_floors fake_read)"; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$SF")" = "$before" ] && [ ! -s "$TMP/reads" ] && printf '%s' "$out" | grep -q '^ok CLINLIMS_FLOOR_SAMPLE=800 (kept' \
  && ok_ "second run, after the clinic minted ids: both floors kept, .install-state unchanged, no sequence read" || bad "second run: rc=$rc $out | reads: $(cat "$TMP/reads" 2>/dev/null)"

rm -f "$SF"; : > "$TMP/FAKE_sample"
out="$(record_clinlims_floors fake_read)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'no id sequence found for clinlims.sample' && [ -z "$(stamp_get CLINLIMS_FLOOR_SAMPLE)" ] \
  && ok_ "a table with no id sequence is refused, naming it, and no floor is written for it" || bad "missing sequence: rc=$rc $out | $(cat "$SF" 2>/dev/null)"
rm -f "$SF"; echo 'clinlims.sample_seq|790' > "$TMP/FAKE_sample"; touch "$TMP/err.analysis"
out="$(record_clinlims_floors fake_read)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'could not read the id sequence of clinlims.analysis' && [ ! -s "$SF" ] \
  && ok_ "a database that does not answer is refused, nothing recorded" || bad "unreadable: rc=$rc $out"
rm -f "$TMP/err.analysis" "$SF"; echo 'clinlims.analysis_seq|1200' > "$TMP/FAKE_analysis"
out="$(record_clinlims_floors fake_read)"; [ "$(stamp_get CLINLIMS_FLOOR_ANALYSIS)" = 1210 ] && ok_ "a last value ending in 0 (1200) gives floor 1210, where the stride restarts it" || bad "last value 1200: $out"
stamp_put CLINLIMS_FLOOR_SAMPLE 805
out="$(record_clinlims_floors fake_read)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'CLINLIMS_FLOOR_SAMPLE=805, not a multiple of 10' && ok_ "a recorded floor off residue 0 is refused, never rewritten" || bad "bad recorded floor: rc=$rc $out"

# --- the filter reads them --------------------------------------------------------
stamp_put CLINLIMS_FLOOR_SAMPLE 800
printf 'RESIDUE=3\n' > "$CLINIC_DIR/.env"
cond="$(env -i PATH="$PATH" CLINIC_DIR="$CLINIC_DIR" REPO_DIR="$R" bash "$R/clinic/scripts/clinlims-down-filter.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] && case "$cond" in *"a.get('analysis_id').longValue() >= 1210L"*"a.get('id').longValue() >= 800L"*) true ;; *) false ;; esac \
  && ok_ "clinlims-down-filter.sh writes its filter from the recorded floors" || bad "filter from .install-state: rc=$rc $cond"

# --- task 060 ----------------------------------------------------------------------
T60="${HERE}/../tasks/060-striding.sh"
nrec="$(grep -n 'record_clinlims_floors elis_seq' "$T60" | cut -d: -f1)"; nstr="$(grep -n 'ALTER SEQUENCE %I.%I INCREMENT BY 10' "$T60" | cut -d: -f1)"
[ -n "$nrec" ] && [ -n "$nstr" ] && [ "$nrec" -lt "$nstr" ] && grep -q 'v="$(record_clinlims_floors elis_seq)" || fail "$v"' "$T60" \
  && ok_ "060 records the floors before it strides the OpenELIS sequences, and stops on a refusal" || bad "060 order: record at ${nrec:-none}, stride at ${nstr:-none}"
[ "$(ls "${HERE}/../tasks" | grep -n '^060-' | cut -d: -f1)" -lt "$(ls "${HERE}/../tasks" | grep -n '^090-' | cut -d: -f1)" ] && ok_ "060 runs before 090, which registers the OpenELIS down sink" || bad "task order"
out="$(env -i PATH="$PATH" HOME="$TMP" DRY=1 INSTALL_DIR="${HERE}/.." CLINIC_DIR="$TMP/dry" REPO_DIR="$R" RESIDUE=3 bash "$T60" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'record CLINLIMS_FLOOR_ANALYSIS CLINLIMS_FLOOR_SAMPLE CLINLIMS_FLOOR_SYSTEM_USER CLINLIMS_FLOOR_RESULT_SIGNATURE in .install-state' && [ ! -e "$TMP/dry/.install-state" ] \
  && ok_ "060's dry run names the floors it would record, and records nothing" || bad "060 dry run: rc=$rc $out"

# --- a real PostgreSQL 16 ------------------------------------------------------------
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
PGC="clinlims-floors-test-$$"
docker run -d --name "$PGC" --tmpfs /var/lib/postgresql/data -e POSTGRES_PASSWORD=x postgres:16 >/dev/null 2>&1 || { bad "could not start postgres:16"; exit 1; }
for i in $(seq 1 60); do docker exec "$PGC" psql -U postgres -Atc 'select 1' >/dev/null 2>&1 && break; sleep 1; done
P(){ docker exec -i "$PGC" psql -U postgres -v ON_ERROR_STOP=1 -At "$@"; }
P -q >/dev/null <<'SQL'
CREATE SCHEMA clinlims;
CREATE TABLE clinlims.analysis (id numeric(10) PRIMARY KEY);
CREATE TABLE clinlims.sample (id numeric(10) PRIMARY KEY);
CREATE TABLE clinlims.system_user (id numeric(10) PRIMARY KEY);
CREATE TABLE clinlims.result_signature (id numeric(10) PRIMARY KEY);
CREATE SEQUENCE clinlims.system_user_seq; CREATE SEQUENCE clinlims.result_signature_seq;
CREATE SEQUENCE clinlims.analysis_seq; SELECT setval('clinlims.analysis_seq', 1203, true);
CREATE SEQUENCE clinlims.sample_seq;   SELECT setval('clinlims.sample_seq', 790, false);
SQL
live(){ clinlims_seq_sql "$1" | P; }
[ "$(live analysis)" = 'clinlims.analysis_seq|1203' ] && [ "$(live sample)" = 'clinlims.sample_seq|790' ] && [ -z "$(live sample_item 2>&1)" ] \
  && ok_ "postgres:16: the read names each sequence and its last value, a set-but-unused one too; a table without one gives no line" || bad "live read: [$(live analysis)] [$(live sample)] [$(live sample_item 2>&1)]"
rm -f "$SF"; out="$(record_clinlims_floors live)"; rc=$?
P -q >/dev/null <<'SQL'
DO $$ DECLARE r record; lv bigint; BEGIN
  FOR r IN SELECT schemaname s, sequencename q FROM pg_sequences WHERE schemaname='clinlims' LOOP
    EXECUTE format('SELECT last_value FROM %I.%I', r.s, r.q) INTO lv;
    EXECUTE format('ALTER SEQUENCE %I.%I INCREMENT BY 10 RESTART WITH %s', r.s, r.q, ((COALESCE(lv,0) / 10) + 1) * 10 + 3);
  END LOOP; END $$;
SQL
a="$(P -c "select nextval('clinlims.analysis_seq')")"; s="$(P -c "select nextval('clinlims.sample_seq')")"
[ "$rc" = 0 ] && [ "$a" = $(( $(stamp_get CLINLIMS_FLOOR_ANALYSIS) + 3 )) ] && [ "$s" = $(( $(stamp_get CLINLIMS_FLOOR_SAMPLE) + 3 )) ] \
  && ok_ "postgres:16: after 060's stride (residue 3) the first ids are floor + 3: analysis $a, sample $s" || bad "live floors: rc=$rc $out; first ids analysis $a sample $s; $(cat "$SF")"
exit $((fails > 0))
