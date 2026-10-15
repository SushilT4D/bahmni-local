#!/usr/bin/env bash
# Lab rows a hub lab user writes for a clinic's sample come down to that clinic
# only: the result, and the analysis and sample the hub moved on. The hub's lab
# accounts, which a sample it moved on names, come down to every clinic.
#
#   - the down list's reader (sync/hub-down.sh) prints the four OpenELIS rows,
#     the three routes and the one unrouted table, and refuses every other
#     OpenELIS table by name, a lab row without a route, an account or Odoo row
#     with one, and a route whose column names no routed table;
#   - the hub's OpenELIS floors are recorded just before its OpenELIS ids are
#     strided (record-clinlims-down-floors.sh), once, and refused on a hub
#     strided before unless given --from-file values that check out;
#   - the hub's OpenELIS source, as register-odoo.sh renders it, captures
#     exactly those tables and its heartbeat, decodes with origin=none, sends
#     nothing written before it started (snapshot.mode=no_data), and a template
#     that adds another table is refused before anything is registered;
#   - the clinic's filter (clinic/scripts/clinlims-down-filter.sh) is written
#     only from a residue and a floor per routed table, and names what is
#     missing otherwise;
#   - the clinic's OpenELIS down sink, as the clinic's register-odoo.sh renders
#     it: one ordered stream, one record per statement, one task on one
#     connection claiming replication origin hub_2 (the Odoo down sink holds
#     hub_1), deletes not applied, errors not tolerated, and the filter as its
#     one transform; refused when no filter was given; the installer registers
#     it only through the filter;
#   - with docker, the pinned Debezium image and the scripting jars: the
#     rendered sink's transform chain keeps exactly this clinic's rows
#     (skipped, not failed, without them unless REQUIRE_FILTER_RUN=1);
#   - with docker and postgres:16: the hub publication holds the three lab
#     tables with no row filter, system_user on the hub's floor, and the
#     heartbeat, no TRUNCATE; refuses a table without a replica identity and
#     a filtered table without a floor; and logical decoding with origin=none
#     sends what a hub session wrote (a clinic's analysis moved on, a result, a
#     hub account) but nothing a clinic's up-sink applied under its origin and
#     no account a clinic minted.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
PGC=""; T="$(mktemp -d)"
cleanup(){ [ -n "$PGC" ] && docker rm -f -v "$PGC" >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT
words(){ tr '\n' ' ' | sed 's/ $//'; }
C="$T/repo"; mkdir -p "$C"
(cd "$R" && tar cf - sync hub/connectors hub/scripts hub/openelis clinic/connectors clinic/scripts clinic/install/tasks) | (cd "$C" && tar xf -)

# --- the down list's reader --------------------------------------------------------
[ "$(bash "$C/sync/hub-down.sh" clinlims | words)" = "system_user result analysis sample" ] && ok_ "the OpenELIS rows of the down list: system_user (first), result, analysis, sample" || bad "clinlims down rows: $(bash "$C/sync/hub-down.sh" clinlims 2>&1 | words)"
[ "$(bash "$C/sync/hub-down.sh" --routes clinlims | words)" = "result analysis_id analysis analysis id analysis sample id sample" ] \
  && ok_ "routes: a result by its analysis (the analysis floor), an analysis and a sample by their own id" || bad "routes: $(bash "$C/sync/hub-down.sh" --routes clinlims 2>&1 | words)"
[ "$(bash "$C/sync/hub-down.sh" --unrouted clinlims | words)" = system_user ] && ok_ "the one OpenELIS table that goes to every clinic, filtered on the hub's floor: system_user" || bad "unrouted: $(bash "$C/sync/hub-down.sh" --unrouted clinlims 2>&1 | words)"
[ "$(bash "$C/sync/hub-down.sh" --subsystems | words)" = "odoo clinlims" ] && ok_ "Odoo and OpenELIS send down" || bad "subsystems: $(bash "$C/sync/hub-down.sh" --subsystems 2>&1 | words)"
plant(){ # LINE : the reader on the list with LINE added; output in $pout, status in $prc
  { cat "$R/sync/hub-down.conf"; printf '%s\n' "$1"; } > "$C/sync/hub-down.conf"
  pout="$(bash "$C/sync/hub-down.sh" clinlims 2>&1)"; prc=$?
  cp "$R/sync/hub-down.conf" "$C/sync/hub-down.conf"; }
for t in sample_item patient person sample_human result_signature; do
  plant "clinlims:$t:clinic=id"
  [ "$prc" != 0 ] && printf '%s' "$pout" | grep -q "clinlims:$t is written at the clinics and never goes down" && ! printf '%s' "$pout" | grep -qx result \
    && ok_ "clinlims:$t planted in the list is refused by name, and nothing is printed" || bad "planted clinlims:$t: rc=$prc $pout"
done
replace(){ # FROM TO : the reader on the list with one line changed
  sed "s/^$1\$/$2/" "$R/sync/hub-down.conf" > "$C/sync/hub-down.conf"
  pout="$(bash "$C/sync/hub-down.sh" clinlims 2>&1)"; prc=$?
  cp "$R/sync/hub-down.conf" "$C/sync/hub-down.conf"; }
replace 'clinlims:result:clinic=analysis_id' 'clinlims:result'
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'must name the column that routes it' && ok_ "an OpenELIS row without clinic=<column> is refused" || bad "unrouted result: rc=$prc $pout"
replace 'clinlims:result:clinic=analysis_id' 'clinlims:result:clinic=sample_item_id'
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'clinlims:sample_item is not a routed down row here' && ok_ "a route through a table that is not routed down is refused" || bad "route by sample_item_id: rc=$prc $pout"
replace 'clinlims:result:clinic=analysis_id' 'clinlims:result:clinic=value'
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'the column is id or <table>_id' && ok_ "a route by a column that names no table is refused" || bad "route by value: rc=$prc $pout"
replace 'clinlims:result:clinic=analysis_id' 'clinlims:result:analysis_id'
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'the third field is clinic=<column> or nothing' && ok_ "a third field that is not clinic=<column> is refused" || bad "bad third field: rc=$prc $pout"
replace 'clinlims:system_user' 'clinlims:system_user:clinic=id'
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'clinlims:system_user goes to every clinic, filtered on the hub' && ok_ "the lab accounts with clinic= are refused (they go to every clinic)" || bad "routed system_user: rc=$prc $pout"
replace 'odoo:uom_uom' 'odoo:uom_uom:clinic=id'
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'only an OpenELIS row is routed by clinic=<column>' && ok_ "an Odoo row with clinic= is refused (Odoo rows go to every clinic)" || bad "odoo with clinic=: rc=$prc $pout"
replace 'clinlims:sample:clinic=id' 'clinlims:sample:clinic=id\nclinlims:sample:clinic=id'
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'clinlims:sample is listed twice' && ok_ "an OpenELIS row listed twice is refused" || bad "duplicate: rc=$prc $pout"
[ "$(bash "$C/sync/hub-down.sh" odoo | grep -c .)" = "$(sed 's/#.*//' "$R/sync/hub-down.conf" | grep -c '^odoo:')" ] && ok_ "the Odoo rows read as before" || bad "odoo rows changed"

# --- the hub's OpenELIS source, rendered for registration -------------------------
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'SH'
#!/bin/sh
cat > "$FAKE_BODY"; echo PUT >> "$FAKE_BODY.log"; printf '\n201'
SH
chmod +x "$T/bin/curl"
printf 'CLINLIMS_SOURCE_PASSWORD=x\nREMOTE_SERVER_NAME=bahmni-cloud\nBASE_ELIS_CONTAINER=hub-elisdb\n' > "$C/hub/.env"
reg_hub(){ rm -f "$T/body" "$T/body.log"; rout="$(PATH="$T/bin:$PATH" FAKE_BODY="$T/body" NODE=cloud bash "$C/hub/connectors/register-odoo.sh" clinlims-cloud-source 2>&1)"; rrc=$?; }
reg_hub
cfg(){ python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], "<absent>"))' "$T/body" "$1" 2>/dev/null; }
[ "$rrc" = 0 ] && [ "$(cfg table.include.list)" = "clinlims.system_user,clinlims.result,clinlims.analysis,clinlims.sample,clinlims.dbz_heartbeat" ] \
  && ok_ "the hub's OpenELIS source captures exactly the four down tables and its heartbeat" || bad "hub source include list: rc=$rrc [$(cfg table.include.list)] $rout"
[ "$(cfg transforms.agg.regex)" = 'bahmni-cloud\.clinlims\.(system_user|result|analysis|sample)$' ] && [ "$(cfg transforms.agg.replacement)" = bahmni-cloud.clinlims.all ] \
  && ok_ "its aggregate regex is the down list, routed into bahmni-cloud.clinlims.all" || bad "hub source regex: $(cfg transforms.agg.regex) -> $(cfg transforms.agg.replacement)"
[ "$(cfg slot.stream.params)|$(cfg snapshot.mode)|$(cfg publication.name)|$(cfg slot.name)|$(cfg publication.autocreate.mode)" = "origin=none|no_data|dbz_clinlims_owned|dbz_clinlims_down|disabled" ] \
  && ok_ "it decodes with origin=none, sends nothing written before it started, and reads dbz_clinlims_owned through slot dbz_clinlims_down" || bad "hub source settings: $(cfg slot.stream.params)|$(cfg snapshot.mode)|$(cfg publication.name)|$(cfg slot.name)|$(cfg publication.autocreate.mode)"
case "$(cfg heartbeat.action.query)|$(cfg heartbeat.interval.ms)" in *clinlims.dbz_heartbeat*"|60000") ok_ "it heartbeats into clinlims.dbz_heartbeat every minute" ;; *) bad "hub source heartbeat: $(cfg heartbeat.action.query)|$(cfg heartbeat.interval.ms)" ;; esac
[ "$(cfg database.hostname)|$(cfg database.dbname)|$(cfg database.user)" = "hub-elisdb|openelis|clinlims" ] && ok_ "it reads the hub's openelis database as clinlims" || bad "hub source database: $(cfg database.hostname)|$(cfg database.dbname)|$(cfg database.user)"
python3 - "$C/hub/connectors/clinlims-cloud-source.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); c = d['config']
c['table.include.list'] = c['table.include.list'] + ',clinlims.sample_item'
json.dump(d, open(sys.argv[1], 'w'))
PY
reg_hub
[ "$rrc" != 0 ] && printf '%s' "$rout" | grep -q 'table.include.list differs from the down list (not down tables: sample_item' && [ ! -s "$T/body.log" ] \
  && ok_ "a template that adds sample_item to the hub's OpenELIS source is refused, and nothing is registered" || bad "edited hub template: rc=$rrc $rout"
cp "$R/hub/connectors/clinlims-cloud-source.json" "$C/hub/connectors/"
{ cat "$R/sync/hub-down.conf"; echo 'clinlims:sample_item:clinic=id'; } > "$C/sync/hub-down.conf"; reg_hub
[ "$rrc" != 0 ] && printf '%s' "$rout" | grep -q 'nothing was registered' && [ ! -s "$T/body.log" ] && ok_ "a down list the reader refuses stops the hub source's registration" || bad "refused list at registration: rc=$rrc $rout"
cp "$R/sync/hub-down.conf" "$C/sync/hub-down.conf"

# --- the clinic's filter ------------------------------------------------------------
CD="$C/clinic"
filt(){ fout="$(env -i PATH="$PATH" CLINIC_DIR="$CD" REPO_DIR="$C" "$@" bash "$CD/scripts/clinlims-down-filter.sh" 2>&1)"; frc=$?; }
rm -f "$CD/.env" "$CD/.install-state"
filt RESIDUE=3
[ "$frc" != 0 ] && printf '%s' "$fout" | grep -q 'no OpenELIS floor for this clinic: CLINLIMS_FLOOR_ANALYSIS CLINLIMS_FLOOR_SAMPLE' && ! printf '%s' "$fout" | grep -q 'value.get' \
  && ok_ "without OpenELIS floors no filter is written, and both missing floors are named once" || bad "no floors: rc=$frc $fout"
filt CLINLIMS_FLOOR_ANALYSIS=1200 CLINLIMS_FLOOR_SAMPLE=800
[ "$frc" != 0 ] && printf '%s' "$fout" | grep -q "residue (RESIDUE, 1-9) is not set" && ok_ "without a residue no filter is written" || bad "no residue: rc=$frc $fout"
filt RESIDUE=3 CLINLIMS_FLOOR_ANALYSIS=1205 CLINLIMS_FLOOR_SAMPLE=800
[ "$frc" != 0 ] && printf '%s' "$fout" | grep -q 'CLINLIMS_FLOOR_ANALYSIS is 1205, not a multiple of 10' && ok_ "a floor off residue 0 is refused" || bad "floor 1205: rc=$frc $fout"
printf 'RESIDUE=3\n' > "$CD/.env"; printf 'CLINLIMS_FLOOR_ANALYSIS=1200\nCLINLIMS_FLOOR_SAMPLE=800\n' > "$CD/.install-state"
filt
COND="$fout"
[ "$frc" = 0 ] && case "$COND" in "def a = value.get('after'); def t = value.get('source').get('table'); value.get('op') != 'd' && a != null && ("*) true ;; *) false ;; esac \
  && ok_ "from clinic/.env and the recorded floors: a filter that drops deletes and tombstones" || bad "filter: rc=$frc $fout"
case "$COND" in *"&& (t == 'system_user' || (t == 'result'"*) ok_ "filter term: system_user, every row the hub sends (its own accounts)" ;; *) bad "filter does not keep system_user: $COND" ;; esac
for term in "t == 'result' && a.get('analysis_id') instanceof Number && a.get('analysis_id').longValue() >= 1200L && a.get('analysis_id').longValue() % 10 == 3" \
            "t == 'analysis' && a.get('id') instanceof Number && a.get('id').longValue() >= 1200L && a.get('id').longValue() % 10 == 3" \
            "t == 'sample' && a.get('id') instanceof Number && a.get('id').longValue() >= 800L && a.get('id').longValue() % 10 == 3"; do
  case "$COND" in *"($term)"*) ok_ "filter term: ${term%% &&*}: on the floor of the table its column names, residue 3" ;; *) bad "filter lacks ($term): $COND" ;; esac
done

# --- the clinic's OpenELIS down sink, rendered for registration -----------------------
printf 'MYSQL_SERVER_NAME=bahmni-t\nCLINLIMS_SINK_PASSWORD=pw\nRESIDUE=3\n' > "$CD/.env"
reg_clinic(){ rm -f "$T/body" "$T/body.log"; rout="$(PATH="$T/bin:$PATH" FAKE_BODY="$T/body" NODE=alpha "$@" bash "$CD/connectors/register-odoo.sh" clinlims-clinic-sink-all 2>&1)"; rrc=$?; }
reg_clinic
[ "$rrc" != 0 ] && printf '%s' "$rout" | grep -q 'unset env for: transforms.rowsForThisClinic.condition' && [ ! -s "$T/body.log" ] \
  && ok_ "without a filter the clinic's OpenELIS down sink is refused, and nothing is registered" || bad "sink without filter: rc=$rrc $rout"
reg_clinic env CLINLIMS_DOWN_CONDITION="$COND"
[ "$rrc" = 0 ] && [ "$(cfg transforms.rowsForThisClinic.condition)" = "$COND" ] && ok_ "with the filter: registered, the condition as the filter script wrote it" || bad "sink with filter: rc=$rrc $rout"
got="$(for k in topics collection.name.format batch.size tasks.max connection.pool.max_size hibernate.agroal.initialSQL insert.mode primary.key.mode delete.enabled errors.tolerance transforms transforms.rowsForThisClinic.type transforms.rowsForThisClinic.language transforms.rowsForThisClinic.null.handling.mode schema.evolution connection.username; do printf '%s=%s\n' "$k" "$(cfg "$k")"; done)"
want="topics=remote.bahmni-cloud.clinlims.all
collection.name.format=clinlims.\${source.table}
batch.size=1
tasks.max=1
connection.pool.max_size=1
hibernate.agroal.initialSQL=SELECT pg_replication_origin_session_setup('hub_2')
insert.mode=upsert
primary.key.mode=record_key
delete.enabled=false
errors.tolerance=none
transforms=rowsForThisClinic
transforms.rowsForThisClinic.type=io.debezium.transforms.Filter
transforms.rowsForThisClinic.language=jsr223.groovy
transforms.rowsForThisClinic.null.handling.mode=drop
schema.evolution=none
connection.username=clinlims_sink"
[ "$got" = "$want" ] && ok_ "the sink: one ordered stream, one record per statement, one task on one connection claiming hub_2, upsert on the record key, deletes not applied, errors not tolerated, the filter its one transform" \
  || bad "sink settings:$(diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^/ /' | tr '\n' ' ')"
o="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["config"]["hibernate.agroal.initialSQL"])' "$R/clinic/connectors/odoo-clinic-sink-all.json")"
[ "$o" != "SELECT pg_replication_origin_session_setup('hub_2')" ] && ok_ "the Odoo down sink claims another origin ($o): one session holds an origin at a time" || bad "both down sinks claim hub_2"
reg="$(sed -n '/^# clinlims-down:begin/,/^# clinlims-down:end/p' "$R/clinic/install/tasks/090-local-sync.sh")"
printf '%s' "$reg" | grep -q 'scripts/clinlims-down-filter.sh' && printf '%s' "$reg" | grep -q 'CLINLIMS_DOWN_CONDITION="$cond" .*register-odoo.sh clinlims-clinic-sink-all' \
  && ! grep -E '^[^#]*register-odoo\.sh' "$R/clinic/install/tasks/090-local-sync.sh" | grep -v CLINLIMS_DOWN_CONDITION | grep -q clinlims-clinic-sink-all \
  && ok_ "the installer registers the OpenELIS down sink only with the filter script's condition" || bad "090 registration: $reg"

# --- the transform chain, in the pinned Debezium image ------------------------------------
skipped(){ if [ "${REQUIRE_FILTER_RUN:-0}" = 1 ]; then bad "the records were not run, and REQUIRE_FILTER_RUN=1: $1"; else printf '  skip %s\n' "$1"; fi; }
. "$R/sync/versions.env"
EXT="${SCRIPTING_JARS_DIR:-$R/clinic/config/kafka-connect/ext}"
JARS="groovy-${GROOVY_VERSION}.jar groovy-jsr223-${GROOVY_VERSION}.jar debezium-scripting-${DEBEZIUM_SCRIPTING_VERSION}.jar"
have_jars=1; for j in $JARS; do [ -f "$EXT/$j" ] || have_jars=0; done
IMG="${DEBEZIUM_CONNECT_IMAGE%% *}"
docker_answers(){
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 & local p=$! i=0
  while kill -0 "$p" 2>/dev/null; do [ "$i" -ge "${DOCKER_PROBE_S:-15}" ] && { kill "$p" 2>/dev/null; return 1; }; sleep 1; i=$((i+1)); done
  wait "$p"
}
TOP=remote.bahmni-cloud.clinlims.all
cat > "$T/cases" <<EOF
$TOP	result	c	5000	analysis_id	1203	double	kept	the hub's result for this clinic's analysis
$TOP	result	u	5000	analysis_id	1203	double	kept	the hub's edit of that result
$TOP	result	r	5000	analysis_id	1203	double	kept	the same row read in a snapshot
$TOP	result	c	5010	analysis_id	1204	double	dropped	a result for clinic 4's analysis
$TOP	result	c	5020	analysis_id	1210	double	dropped	a result for an analysis the hub created
$TOP	result	c	5030	analysis_id	1193	double	dropped	a result for an analysis below the analysis floor, on residue 3
$TOP	result	c	5040	analysis_id	null	double	dropped	a result with no analysis
$TOP	result	d	5000	analysis_id	1203	double	dropped	the hub's delete of this clinic's result
$TOP	result	t	5000	analysis_id	1203	double	dropped	a tombstone (no row)
$TOP	analysis	u	1213	id	1213	double	kept	this clinic's analysis, moved on by the hub
$TOP	analysis	u	1223	id	1223	long	kept	the same, read as a whole number
$TOP	analysis	u	1214	id	1214	double	dropped	clinic 4's analysis
$TOP	analysis	u	1183	id	1183	double	dropped	an analysis below the floor on residue 3 (the hub's, from before striding)
$TOP	analysis	d	1213	id	1213	double	dropped	the hub's delete of this clinic's analysis
$TOP	sample	u	803	id	803	double	kept	this clinic's sample, moved on by the hub
$TOP	sample	u	793	id	793	double	dropped	a sample below the sample floor on residue 3
$TOP	sample	u	1210	id	1210	double	dropped	a sample the hub created
$TOP	system_user	c	170	id	170	double	kept	a lab account the hub created
$TOP	system_user	u	42	id	42	long	kept	the hub's edit of a seeded lab account
$TOP	system_user	d	170	id	170	double	dropped	the hub's delete of a lab account
EOF
if [ "$have_jars" != 1 ]; then
  skipped "the scripting jars are not in ${EXT} (clinic/config/kafka-connect/ext/fetch-scripting-jars.sh fetches them; SCRIPTING_JARS_DIR points elsewhere)"
elif ! docker_answers || ! docker image inspect "$IMG" >/dev/null 2>&1; then
  skipped "docker with $IMG is not here"
else
  python3 -c 'import json,sys; [print("%s\t%s" % (k, v)) for k, v in json.load(open(sys.argv[1])).items()]' "$T/body" > "$T/sink.cfg"
  cut -f1-7 "$T/cases" > "$T/records.tsv"
  cp "$R/clinic/install/tests/probes/EnvelopeFilterProbe.java" "$T/"
  m=""; for j in $JARS; do m="$m -v $EXT/$j:/kafka/connect/debezium-connector-jdbc/$j:ro"; done
  # shellcheck disable=SC2086
  docker run --rm --entrypoint java -v "$T:/probe:ro" $m "$IMG" \
    -cp "/kafka/libs/*:/kafka/connect/debezium-connector-jdbc/*" /probe/EnvelopeFilterProbe.java /probe/sink.cfg /probe/records.tsv > "$T/got" 2>&1
  if [ "$(grep -c . "$T/got")" != "$(grep -c . "$T/cases")" ]; then bad "the probe did not judge every record: $(head -5 "$T/got" | tr '\n' ' ')"
  else
    paste "$T/cases" "$T/got" | while IFS='	' read -r _t _tab _op _id _c _v _ty want why got; do
      if [ "$got" = "$want" ]; then printf '  ok   clinic 3, floors analysis 1200 / sample 800: %s (%s)\n' "$why" "$got"; else printf '  FAIL clinic 3: %s -> %s, want %s\n' "$why" "$got" "$want"; fi
    done > "$T/judged"
    cat "$T/judged"; fails=$((fails + $(grep -c '^  FAIL' "$T/judged")))
  fi
fi

# --- the publication and origin=none, on a real PostgreSQL 16 -------------------------------
PIMG=postgres:16
if ! docker_answers || ! docker image inspect "$PIMG" >/dev/null 2>&1; then
  printf '  skip docker with %s is not here; the publication was not built on a server\n' "$PIMG"
  exit $((fails > 0))
fi
PGC="clinlims-down-test-$$"
docker run -d --name "$PGC" --tmpfs /var/lib/postgresql/data -e POSTGRES_PASSWORD=x "$PIMG" -c wal_level=logical >/dev/null 2>&1 || { bad "could not start $PIMG"; exit 1; }
for i in $(seq 1 60); do docker exec "$PGC" pg_isready -U postgres -q >/dev/null 2>&1 && docker exec "$PGC" psql -U postgres -Atc 'select 1' >/dev/null 2>&1 && break; sleep 1; done
docker exec "$PGC" createdb -U postgres openelis
PSQL="docker exec -i $PGC psql -U postgres -d openelis"
$PSQL -q -v ON_ERROR_STOP=1 >/dev/null <<'SQL' || bad "fixture schema refused"
CREATE SCHEMA clinlims;
CREATE TABLE clinlims.sample (id numeric(10) PRIMARY KEY, status_id numeric(10));
CREATE TABLE clinlims.sample_item (id numeric(10) PRIMARY KEY, samp_id numeric(10));
CREATE TABLE clinlims.analysis (id numeric(10) PRIMARY KEY, sampitem_id numeric(10), status_id numeric(10));
CREATE TABLE clinlims.result (id numeric(10) PRIMARY KEY, analysis_id numeric(10), value text);
CREATE TABLE clinlims.dbz_heartbeat (id int PRIMARY KEY, ts timestamptz);
CREATE TABLE clinlims.system_user (id numeric(10) PRIMARY KEY, login_name text);
CREATE SEQUENCE clinlims.system_user_seq;
INSERT INTO clinlims.system_user SELECT nextval('clinlims.system_user_seq'), 'u' || g FROM generate_series(1, 163) g;
INSERT INTO clinlims.sample VALUES (803, 1);
INSERT INTO clinlims.analysis VALUES (1213, 1, 1);
SELECT pg_replication_origin_create('clinic_t_clinlims');
CREATE PUBLICATION dbz_clinlims_owned FOR TABLE clinlims.sample_item;
SQL
pubrows(){ $PSQL -Atc "select tablename || ':' || coalesce(rowfilter, '-') from pg_publication_tables where pubname = 'dbz_clinlims_owned'" | LC_ALL=C sort | words; }
FL="$T/clinlims-floors.local"
out="$(bash "$C/hub/scripts/apply-clinlims-down-publication.sh" "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'no floors file at' && ok_ "the publication is refused while the hub's OpenELIS floors are not recorded" || bad "publication without floors: rc=$rc $out"
# the floors: recorded just before the hub's OpenELIS ids are strided
out="$(bash "$C/hub/scripts/record-clinlims-down-floors.sh" --out "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$FL" 2>/dev/null | words)" = "system_user 170" ] && ok_ "before the stride: system_user's floor recorded where the stride restarts it (last value 163 -> 170)" || bad "record floors: rc=$rc $out"
out="$(bash "$C/hub/scripts/record-clinlims-down-floors.sh" --out "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'already exists' && ok_ "the floors file is never rewritten" || bad "rewrite: rc=$rc $out"
$PSQL -q -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
DO $$ DECLARE r record; lv bigint; BEGIN
  FOR r IN SELECT schemaname s, sequencename q FROM pg_sequences WHERE schemaname='clinlims' LOOP
    EXECUTE format('SELECT last_value FROM %I.%I', r.s, r.q) INTO lv;
    EXECUTE format('ALTER SEQUENCE %I.%I INCREMENT BY 10 RESTART WITH %s', r.s, r.q, ((COALESCE(lv,0) / 10) + 1) * 10);
  END LOOP; END $$;
SQL
[ "$($PSQL -Atc "select nextval('clinlims.system_user_seq')")" = "$(cut -d' ' -f2 "$FL")" ] && ok_ "the hub's stride restarts system_user at the recorded floor" || bad "stride restart differs from the floor"
out="$(bash "$C/hub/scripts/record-clinlims-down-floors.sh" --out "$T/fl2" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'were strided before: system_user (steps by 10)' && [ ! -e "$T/fl2" ] && ok_ "on a hub strided before, a first recording is refused, naming --from-file" || bad "strided before: rc=$rc $out"
printf 'system_user 9990\n' > "$T/src"; out="$(bash "$C/hub/scripts/record-clinlims-down-floors.sh" --from-file "$T/src" --out "$T/fl2" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'is above the id its sequence issues next' && [ ! -e "$T/fl2" ] && ok_ "--from-file refuses a floor above the sequence" || bad "from-file too high: rc=$rc $out"
printf 'system_user 170\n' > "$T/src"; out="$(bash "$C/hub/scripts/record-clinlims-down-floors.sh" --from-file "$T/src" --out "$T/fl2" -- $PSQL 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$T/fl2")" = "system_user 170" ] && ok_ "--from-file records values that check out against the strided sequence" || bad "from-file: rc=$rc $out"
out="$(bash "$C/hub/scripts/apply-clinlims-down-publication.sh" "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(pubrows)" = "analysis:- dbz_heartbeat:- result:- sample:- system_user:((id < (170)::numeric) OR ((id % (10)::numeric) = (0)::numeric))" ] \
  && ok_ "dbz_clinlims_owned: result, analysis, sample unfiltered, system_user on the hub's floor, the heartbeat; sample_item, held before, is gone" || bad "publication: rc=$rc [$(pubrows)] $out"
[ "$($PSQL -Atc "select pubinsert::text || pubupdate::text || pubdelete::text || pubtruncate::text from pg_publication where pubname = 'dbz_clinlims_owned'")" = truetruetruefalse ] \
  && ok_ "it publishes insert, update and delete, never truncate" || bad "publish flags"
$PSQL -q -c "SELECT pg_create_logical_replication_slot('t_elis', 'pgoutput')" >/dev/null
$PSQL -q -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
UPDATE clinlims.analysis SET status_id = 6 WHERE id = 1213;                   -- a hub lab user completes the clinic's analysis
INSERT INTO clinlims.result VALUES (5000, 1213, '12.5');                     -- and enters its result
INSERT INTO clinlims.system_user VALUES (180, 'hub lab user');               -- a hub account, minted after the stride
UPDATE clinlims.system_user SET login_name = 'renamed' WHERE id = 47;        -- the hub's edit of a seeded account
INSERT INTO clinlims.system_user VALUES (183, 'clinic 3 account');           -- an account a clinic minted, edited at the hub
SELECT pg_replication_origin_session_setup('clinic_t_clinlims');
INSERT INTO clinlims.analysis VALUES (1223, 1, 1);                           -- a clinic's analysis, applied by its up-sink
UPDATE clinlims.sample SET status_id = 2 WHERE id = 803;                     -- a clinic's own edit, applied by its up-sink
SELECT pg_replication_origin_session_reset();
SQL
msgs="$($PSQL -Atc "select string_agg(chr(get_byte(data, 0)), '' order by lsn) from pg_logical_slot_get_binary_changes('t_elis', NULL, NULL, 'proto_version', '4', 'publication_names', 'dbz_clinlims_owned', 'origin', 'none') where chr(get_byte(data, 0)) in ('I', 'U', 'D')")"
[ "$msgs" = UIIU ] && ok_ "decoded with origin=none: the hub session's update of the clinic's analysis, its new result, its new account and its edit of a seeded account are sent; a clinic-minted account the hub wrote and the rows a clinic's up-sink applied are not" || bad "decoded row messages '$msgs', want UIIU"
$PSQL -q -c "SELECT pg_drop_replication_slot('t_elis')" >/dev/null
$PSQL -q -v ON_ERROR_STOP=1 -c "ALTER TABLE clinlims.result DROP CONSTRAINT result_pkey" >/dev/null
before="$(pubrows)"
out="$(bash "$C/hub/scripts/apply-clinlims-down-publication.sh" "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'clinlims.result has no replica identity' && [ "$(pubrows)" = "$before" ] \
  && ok_ "a down table without a replica identity is refused before the publication changes" || bad "replica identity: rc=$rc $out"
exit $((fails > 0))
