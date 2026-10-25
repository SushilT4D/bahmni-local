#!/usr/bin/env bash
# The hub's lab test catalogue comes down to every clinic: the OpenELIS tables a
# lab test, a panel, a sample type, a department and a result option are stored
# in, and every table they point to by a foreign key.
#
#   - the down list's reader (sync/hub-down.sh) prints the catalogue tables,
#     all unrouted, and refuses the OpenELIS feed tables and the per-site
#     tables by name, a catalogue table with clinic=<column>, and a catalogue
#     table that is also on the up list;
#   - the hub's OpenELIS source, as register-odoo.sh renders it, captures the
#     catalogue and no feed or per-site table, in its table list and in its
#     aggregate regex; the clinic MirrorMaker's down regex names none of them;
#   - the clinic's OpenELIS down filter keeps every catalogue table whole and,
#     with docker, the pinned Debezium image and the scripting jars, the
#     rendered sink's transform chain keeps a catalogue row of every kind and
#     drops a catalogue delete and a feed-table row (skipped, not failed,
#     without them unless REQUIRE_FILTER_RUN=1);
#   - with docker and postgres:16, on the hub's catalogue shapes (sequences
#     named apart from their table, a table with no sequence, a sequence that
#     stands below its rows, two link tables without an id): the floors are
#     recorded before the stride (the restart value, or above the rows where
#     the sequence lags them); on a hub strided before, --derive reads them
#     from the rows and --from-file adds them to the floors file without
#     changing the line it held, refusing a floor below a row the hub owns, a
#     floor above both sequence and rows, and a changed recorded floor; the
#     publication filters every catalogue table with an id on its floor and
#     publishes the link tables whole; logical decoding sends the hub's new
#     rows in the order it wrote them (a test before its sample type link, a
#     panel before its item), a legacy row's edit and a link-table row, and
#     nothing above a floor on another residue.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
PGC=""; T="$(mktemp -d)"
cleanup(){ [ -n "$PGC" ] && docker rm -f -v "$PGC" >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT
words(){ tr '\n' ' ' | sed 's/ $//'; }
CAT="scriptlet label method test_formats test_trailer type_of_test_result org_mls_lab_type organization organization_type organization_organization_type dictionary_category dictionary unit_of_measure test_section type_of_sample analyte test test_result test_analyte result_limits panel panel_item sampletype_test sampletype_panel"
NEVER="event_records event_records_queue markers failed_events site_information login_user"
C="$T/repo"; mkdir -p "$C"
(cd "$R" && tar cf - sync hub/connectors hub/scripts hub/openelis clinic/connectors clinic/scripts clinic/config/mirrormaker clinic/install/tasks) | (cd "$C" && tar xf -)

# --- the down list's reader ----------------------------------------------------------
[ "$(bash "$C/sync/hub-down.sh" clinlims | words)" = "system_user result analysis sample $CAT" ] \
  && ok_ "the OpenELIS down rows: the lab accounts, the three lab rows, then the $(echo $CAT | wc -w | tr -d ' ') catalogue tables parents first" || bad "clinlims down rows: $(bash "$C/sync/hub-down.sh" clinlims 2>&1 | words)"
[ "$(bash "$C/sync/hub-down.sh" --unrouted clinlims | words)" = "system_user $CAT" ] && ok_ "every catalogue table goes to every clinic (unrouted)" || bad "unrouted: $(bash "$C/sync/hub-down.sh" --unrouted clinlims 2>&1 | words)"
[ "$(bash "$C/sync/hub-down.sh" --routes clinlims | words)" = "result analysis_id analysis analysis id analysis sample id sample" ] && ok_ "the routes are unchanged" || bad "routes: $(bash "$C/sync/hub-down.sh" --routes clinlims 2>&1 | words)"
up="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$R/sync/subsystems.conf" | sed -n 's/^clinlims://p' | words)"
n=0; for t in $CAT; do case " $up " in *" $t "*) bad "catalogue table $t is on the up list";; *) n=$((n+1));; esac; done
[ "$n" = "$(echo $CAT | wc -w | tr -d ' ')" ] && ok_ "no catalogue table is on the up list (sync/subsystems.conf)"
plant(){ { cat "$R/sync/hub-down.conf"; printf '%s\n' "$1"; } > "$C/sync/hub-down.conf"; pout="$(bash "$C/sync/hub-down.sh" clinlims 2>&1)"; prc=$?; cp "$R/sync/hub-down.conf" "$C/sync/hub-down.conf"; }
for t in $NEVER; do
  plant "clinlims:$t"
  [ "$prc" != 0 ] && printf '%s' "$pout" | grep -q "clinlims:$t is written at the clinics and never goes down" && ! printf '%s' "$pout" | grep -qx test \
    && ok_ "clinlims:$t planted in the list is refused by name, and nothing is printed" || bad "planted clinlims:$t: rc=$prc $pout"
done
sed 's/^clinlims:test$/clinlims:test:clinic=id/' "$R/sync/hub-down.conf" > "$C/sync/hub-down.conf"; pout="$(bash "$C/sync/hub-down.sh" clinlims 2>&1)"; prc=$?; cp "$R/sync/hub-down.conf" "$C/sync/hub-down.conf"
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'clinlims:test goes to every clinic' && ok_ "a catalogue table with clinic=<column> is refused" || bad "routed test: rc=$prc $pout"
{ cat "$R/sync/subsystems.conf"; echo clinlims:panel; } > "$C/sync/subsystems.conf"; pout="$(bash "$C/sync/hub-down.sh" clinlims 2>&1)"; prc=$?; cp "$R/sync/subsystems.conf" "$C/sync/subsystems.conf"
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'clinlims:panel is the hub.s lab test catalogue, which only the hub writes' && ok_ "a catalogue table that is also on the up list is refused" || bad "panel both ways: rc=$prc $pout"

# --- the hub's OpenELIS source and the clinic MirrorMaker ---------------------------------
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'SH'
#!/bin/sh
cat > "$FAKE_BODY"; echo PUT >> "$FAKE_BODY.log"; printf '\n201'
SH
chmod +x "$T/bin/curl"
printf 'CLINLIMS_SOURCE_PASSWORD=x\nREMOTE_SERVER_NAME=bahmni-cloud\nBASE_ELIS_CONTAINER=hub-elisdb\n' > "$C/hub/.env"
rm -f "$T/body"; rout="$(PATH="$T/bin:$PATH" FAKE_BODY="$T/body" NODE=cloud bash "$C/hub/connectors/register-odoo.sh" clinlims-cloud-source 2>&1)"; rrc=$?
cfg(){ python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], "<absent>"))' "$T/body" "$1" 2>/dev/null; }
inc="$(cfg table.include.list | tr ',' '\n' | sed 's/^clinlims\.//' | words)"; agg="$(cfg transforms.agg.regex | sed -E 's/^.*\(([^()]*)\)\$$/\1/' | tr '|' ' ')"
[ "$rrc" = 0 ] && [ "$inc" = "system_user result analysis sample $CAT dbz_heartbeat" ] && ok_ "the hub's OpenELIS source captures the catalogue with the lab rows and its heartbeat" || bad "hub source include list: rc=$rrc [$inc] $rout"
[ "$agg" = "system_user result analysis sample $CAT" ] && ok_ "its aggregate regex carries the catalogue onto the one ordered topic" || bad "hub source regex: [$agg]"
for t in $NEVER; do case " $inc $agg " in *" $t "*) bad "the hub source carries $t";; esac; done
ok_ "neither its table list nor its regex names a feed table or a per-site table ($NEVER)"
printf 'BHS_LOCATION=testclinic\nREMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.example:9092\nMYSQL_SERVER_NAME=bahmni-test\nREMOTE_SERVER_NAME=bahmni-cloud\n' > "$C/clinic/.env"
if command -v envsubst >/dev/null 2>&1; then
  rm -f "$C/clinic/config/mirrormaker/mm2.properties"; mout="$(bash "$C/clinic/scripts/setup-mirrormaker.sh" 2>&1)"; mrc=$?
  down="$(sed -n 's/^remote->[a-z_]*\.topics = //p' "$C/clinic/config/mirrormaker/mm2.properties" 2>/dev/null | tr -d '()\\' | tr '|' '\n')"
  printf '%s\n' "$down" | grep -qx 'bahmni-cloud.clinlims.all' && [ "$mrc" = 0 ] && ok_ "the clinic MirrorMaker takes the ordered OpenELIS topic down" || bad "MirrorMaker down topics: rc=$mrc $(printf '%s' "$mout" | tail -2)"
  hit=""; for t in $NEVER; do printf '%s\n' "$down" | grep -qx "bahmni-cloud.clinlims.$t" && hit="$hit $t"; done
  [ -z "$hit" ] && ok_ "the MirrorMaker down regex names no feed or per-site table" || bad "MirrorMaker down regex names:$hit"
else
  printf '  skip envsubst is not here; the MirrorMaker render was not run\n'
fi

# --- the clinic's filter, and its sink's transform chain -------------------------------------
CD="$C/clinic"
printf 'RESIDUE=3\n' > "$CD/.env"; printf 'CLINLIMS_FLOOR_ANALYSIS=1200\nCLINLIMS_FLOOR_SAMPLE=800\n' > "$CD/.install-state"
COND="$(env -i PATH="$PATH" CLINIC_DIR="$CD" REPO_DIR="$C" bash "$CD/scripts/clinlims-down-filter.sh" 2>&1)"; rc=$?
miss=""; for t in $CAT; do case "$COND" in *"t == '$t' ||"*|*"t == '$t')"*) ;; *) miss="$miss $t";; esac; done
[ "$rc" = 0 ] && [ -z "$miss" ] && ok_ "the clinic's filter keeps every catalogue table whole" || bad "filter lacks:$miss (rc=$rc) $COND"
for t in $NEVER; do case "$COND" in *"'$t'"*) bad "the filter names $t";; esac; done
printf 'MYSQL_SERVER_NAME=bahmni-t\nCLINLIMS_SINK_PASSWORD=pw\nRESIDUE=3\n' > "$CD/.env"
rm -f "$T/body"; rout="$(PATH="$T/bin:$PATH" FAKE_BODY="$T/body" NODE=alpha CLINLIMS_DOWN_CONDITION="$COND" bash "$CD/connectors/register-odoo.sh" clinlims-clinic-sink-all 2>&1)"; rrc=$?
[ "$rrc" = 0 ] && [ "$(cfg batch.size)|$(cfg topics)|$(cfg delete.enabled)|$(cfg errors.tolerance)" = "1|remote.bahmni-cloud.clinlims.all|false|none" ] \
  && ok_ "the clinic's OpenELIS down sink: one ordered topic, one record per statement, deletes not applied, errors not tolerated" || bad "sink: rc=$rrc $(cfg batch.size)|$(cfg topics)|$(cfg delete.enabled)|$(cfg errors.tolerance) $rout"
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
$TOP	test	c	1420	id	1420	double	kept	a test the hub created (residue 0)
$TOP	test	u	1007	id	1007	double	kept	the hub's edit of a seeded test (below its floor, any residue)
$TOP	test	d	1007	id	1007	double	dropped	a test the hub deleted (the clinic keeps its copy; the hub retires tests)
$TOP	test	t	1007	id	1007	double	dropped	a tombstone (no row)
$TOP	sampletype_test	c	8250	test_id	1420	double	kept	the new test's sample type link
$TOP	panel	c	150	id	150	long	kept	a panel the hub created
$TOP	panel_item	c	5030	panel_id	150	double	kept	the panel's item
$TOP	sampletype_panel	c	860	panel_id	150	double	kept	the panel's sample type link
$TOP	test_section	u	236	id	236	double	kept	a department the hub renamed
$TOP	type_of_sample	c	130	id	130	double	kept	a sample type the hub created
$TOP	test_result	c	3040	test_id	1420	double	kept	a result option of the new test
$TOP	result_limits	c	700	test_id	1420	double	kept	the new test's normal range
$TOP	dictionary	c	1300	id	1300	double	kept	a coded answer
$TOP	unit_of_measure	c	130	id	130	double	kept	a unit
$TOP	organization	c	1290	id	1290	double	kept	a referral lab
$TOP	organization_organization_type	c	1290	org_id	1290	double	kept	the referral lab's type (a link table)
$TOP	event_records	c	77	id	77	double	dropped	a feed table row
$TOP	markers	u	3	id	3	double	dropped	a feed marker
$TOP	site_information	u	9	id	9	double	dropped	a per-site setting
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
      if [ "$got" = "$want" ]; then printf '  ok   clinic 3: %s (%s)\n' "$why" "$got"; else printf '  FAIL clinic 3: %s -> %s, want %s\n' "$why" "$got" "$want"; fi
    done > "$T/judged"
    cat "$T/judged"; fails=$((fails + $(grep -c '^  FAIL' "$T/judged")))
  fi
fi

# --- floors, publication and decoding on a real PostgreSQL 16 --------------------------------
PIMG=postgres:16
if ! docker_answers || ! docker image inspect "$PIMG" >/dev/null 2>&1; then
  printf '  skip docker with %s is not here; the floors and publication were not built on a server\n' "$PIMG"
  exit $((fails > 0))
fi
PGC="lab-catalogue-test-$$"
docker run -d --name "$PGC" --tmpfs /var/lib/postgresql/data -e POSTGRES_PASSWORD=x "$PIMG" -c wal_level=logical >/dev/null 2>&1 || { bad "could not start $PIMG"; exit 1; }
for i in $(seq 1 60); do docker exec "$PGC" pg_isready -U postgres -q >/dev/null 2>&1 && docker exec "$PGC" psql -U postgres -Atc 'select 1' >/dev/null 2>&1 && break; sleep 1; done
docker exec "$PGC" createdb -U postgres openelis
PSQL="docker exec -i $PGC psql -U postgres -d openelis"
# the hub's shapes: an id and a sequence of 37 legacy rows (every residue) per
# table, as on an unstrided hub; sampletype_test and sampletype_panel take ids
# from sample_type_*_seq; test_formats has no sequence and no rows; analyte's
# sequence stands below its rows; the two link tables have no id
{
  echo 'CREATE SCHEMA clinlims;'
  for t in system_user result analysis sample $CAT; do
    case "$t" in
      organization_organization_type) echo "CREATE TABLE clinlims.$t (org_id numeric(10), org_type_id numeric(10), PRIMARY KEY (org_id, org_type_id));"; continue ;;
      org_mls_lab_type) echo "CREATE TABLE clinlims.$t (org_mlt_id numeric(10) PRIMARY KEY, org_id numeric(10), mls_lab_id numeric(10));"; continue ;;
      test_formats) echo "CREATE TABLE clinlims.$t (id numeric(10) PRIMARY KEY);"; continue ;;
      sampletype_test) echo "CREATE TABLE clinlims.$t (id numeric(10) PRIMARY KEY, test_id numeric(10) REFERENCES clinlims.test(id), name text); CREATE SEQUENCE clinlims.sample_type_test_seq;" ;;
      sampletype_panel) echo "CREATE TABLE clinlims.$t (id numeric(10) PRIMARY KEY, panel_id numeric(10) REFERENCES clinlims.panel(id), name text); CREATE SEQUENCE clinlims.sample_type_panel_seq;" ;;
      panel_item) echo "CREATE TABLE clinlims.$t (id numeric(10) PRIMARY KEY, panel_id numeric(10) REFERENCES clinlims.panel(id), name text); CREATE SEQUENCE clinlims.${t}_seq;" ;;
      *) echo "CREATE TABLE clinlims.$t (id numeric(10) PRIMARY KEY, name text); CREATE SEQUENCE clinlims.${t}_seq;" ;;
    esac
    s="clinlims.${t}_seq"; case "$t" in sampletype_test) s=clinlims.sample_type_test_seq ;; sampletype_panel) s=clinlims.sample_type_panel_seq ;; esac
    case "$t" in
      system_user) echo "INSERT INTO clinlims.$t SELECT nextval('$s'), 'u' || g FROM generate_series(1, 163) g;" ;;
      analyte) echo "INSERT INTO clinlims.$t SELECT g, 'a' || g FROM generate_series(1, 276) g; SELECT setval('$s', 95);" ;;
      result|analysis|sample) ;;
      sampletype_test) echo "INSERT INTO clinlims.$t SELECT nextval('$s'), g, 's' || g FROM generate_series(1, 37) g;" ;;
      sampletype_panel|panel_item) echo "INSERT INTO clinlims.$t SELECT nextval('$s'), g, 's' || g FROM generate_series(1, 37) g;" ;;
      *) echo "INSERT INTO clinlims.$t SELECT nextval('$s'), 'r' || g FROM generate_series(1, 37) g;" ;;
    esac
  done
  echo 'CREATE TABLE clinlims.dbz_heartbeat (id int PRIMARY KEY, ts timestamptz);'
} > "$T/schema.sql"
$PSQL -q -v ON_ERROR_STOP=1 < "$T/schema.sql" >/dev/null 2>"$T/schema.err" || bad "fixture schema refused: $(head -3 "$T/schema.err")"
REC="$C/hub/scripts/record-clinlims-down-floors.sh"
# before the stride
FL="$T/before.local"; out="$(bash "$REC" --out "$FL" -- $PSQL 2>&1)"; rc=$?
fl(){ awk -v t="$1" '$1 == t { print $2 }' "$2"; }
[ "$rc" = 0 ] && [ "$(fl system_user "$FL")" = 170 ] && [ "$(fl test "$FL")" = 40 ] && [ "$(fl sampletype_test "$FL")" = 40 ] && [ "$(fl test_formats "$FL")" = 10 ] && [ "$(fl analyte "$FL")" = 280 ] \
  && ok_ "before the stride: system_user at the restart (170), a catalogue table at its restart (40, sampletype_test from sample_type_test_seq), test_formats with no sequence above its rows (10), analyte, whose sequence lags its 276 rows, above them (280)" \
  || bad "before the stride: rc=$rc [$(cat "$FL" 2>/dev/null | words)] $out"
[ -z "$(fl organization_organization_type "$FL")$(fl org_mls_lab_type "$FL")" ] && [ "$(grep -c . "$FL" 2>/dev/null)" = 23 ] \
  && ok_ "no floor for the two link tables; 23 floors in all" || bad "floors file: [$(cat "$FL" 2>/dev/null | words)]"
# the hub's stride, run with the floors already recorded, on a database as it was
# before the stride (the stride step repeated after going back to a backup): a
# lab-accounts floor its sequence would issue below is refused, changing nothing; a
# catalogue floor standing above its sequence (analyte) is no reason to refuse
sed 's/^system_user .*/system_user 9990/' "$FL" > "$T/high.local"
out="$(bash "$C/hub/scripts/stride-openelis.sh" --floors "$T/high.local" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'clinlims.system_user would issue .* below its recorded floor 9990' && [ "$($PSQL -Atc "select increment_by from pg_sequences where sequencename = 'analyte_seq'")" = 1 ] \
  && ok_ "the stride refuses a lab-accounts floor its sequence would issue below (clinics write those rows), striding nothing" || bad "stride, accounts below floor: rc=$rc $out"
out="$(bash "$C/hub/scripts/stride-openelis.sh" --floors "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'floors kept' && [ "$(grep -c . "$FL")" = 23 ] && [ "$($PSQL -Atc "select count(*) filter (where increment_by = 10) = count(*) from pg_sequences where schemaname = 'clinlims'")" = t ] \
  && ok_ "the stride keeps the 23 recorded floors and strides every sequence, though analyte's floor (280) stands above its sequence" || bad "stride with recorded floors: rc=$rc $out"
# a hub strided before the catalogue joined the list: only the lab accounts were recorded
FL="$T/strided.local"; printf 'system_user 170\n' > "$FL"
out="$(bash "$REC" --out "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'were strided before' && printf '%s' "$out" | grep -q -- '--derive' && [ "$(cat "$FL")" = "system_user 170" ] \
  && ok_ "on a strided hub the floors are not read from the sequences; the message names --derive" || bad "strided, no mode: rc=$rc $out"
der="$(bash "$REC" --derive --out "$FL" -- $PSQL 2>"$T/der.err")"; rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$der" | grep -q '^system_user ' && printf '%s\n' "$der" | grep -qx 'analyte 280' && printf '%s\n' "$der" | grep -qx 'test 40' && printf '%s\n' "$der" | grep -qx 'test_formats 10' \
  && [ "$(printf '%s\n' "$der" | grep -c .)" = 22 ] && [ "$(cat "$FL")" = "system_user 170" ] \
  && ok_ "--derive prints the 22 catalogue floors from the rows (analyte 280, test 40, test_formats 10), none for the recorded lab accounts, and writes nothing" || bad "derive: rc=$rc [$(printf '%s' "$der" | words)] $(cat "$T/der.err")"
printf '%s\n' "$der" | sed 's/^analyte 280$/analyte 100/' > "$T/low"
out="$(bash "$REC" --from-file "$T/low" --out "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'the floor given for analyte, 100, is not above its row 276' && [ "$(cat "$FL")" = "system_user 170" ] \
  && ok_ "--from-file refuses a catalogue floor below a row the hub owns (analyte 100 under row 276)" || bad "from-file low: rc=$rc $out"
printf '%s\n' "$der" | sed 's/^test 40$/test 9990/' > "$T/high"
out="$(bash "$REC" --from-file "$T/high" --out "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'the floor given for test, 9990, is above both' && ok_ "--from-file refuses a catalogue floor above both its sequence and its rows" || bad "from-file high: rc=$rc $out"
{ printf '%s\n' "$der"; echo 'system_user 180'; } > "$T/changed"
out="$(bash "$REC" --from-file "$T/changed" --out "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'holds 170 for it, and a recorded floor is never changed' && ok_ "--from-file refuses to change a recorded floor" || bad "from-file changed: rc=$rc $out"
{ printf '%s\n' "$der"; echo 'organization_organization_type 10'; } > "$T/link"
out="$(bash "$REC" --from-file "$T/link" --out "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && ok_ "--from-file refuses a floor for a link table" || bad "from-file link: rc=$rc $out"
printf '%s\n' "$der" > "$T/der"; out="$(bash "$REC" --from-file "$T/der" --out "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(head -1 "$FL")" = "system_user 170" ] && [ "$(grep -c . "$FL")" = 23 ] && printf '%s' "$out" | grep -q 'added 22 table(s)' \
  && ok_ "--from-file adds the 22 catalogue floors; the line it held (system_user 170) is unchanged" || bad "from-file add: rc=$rc [$(cat "$FL" | words)] $out"
out="$(bash "$REC" --derive --out "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'holds a floor for every OpenELIS table filtered on a floor' && ok_ "once every floor is recorded, --derive has nothing to print" || bad "derive again: rc=$rc $out"
# a clinic's rows reached the hub: a table clinics send up is not derived
$PSQL -q -v ON_ERROR_STOP=1 -c "SELECT pg_replication_origin_create('clinic_t_clinlims'); SELECT pg_replication_origin_advance('clinic_t_clinlims', '0/1000');" >/dev/null
out="$(bash "$REC" --derive --out "$T/none.local" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'clinlims.system_user is sent up by the clinics and 1 clinic replication origin(s) show progress' \
  && ok_ "with a clinic's origin showing progress, the floor of a table clinics send up (system_user) is not read from the rows" || bad "derive with progress: rc=$rc $out"
printf 'system_user 170\n' > "$T/up.local"
out="$(bash "$REC" --derive --out "$T/up.local" -- $PSQL 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c .)" = 22 ] && ok_ "with that progress, the catalogue floors are still derived: no clinic writes the catalogue" || bad "derive catalogue with progress: rc=$rc $out"
# the publication
P="$C/hub/scripts/apply-clinlims-down-publication.sh"
out="$(bash "$P" "$FL" -- $PSQL 2>&1)"; rc=$?
rows="$($PSQL -Atc "select tablename || ':' || coalesce(rowfilter, '-') from pg_publication_tables where pubname = 'dbz_clinlims_owned'" | LC_ALL=C sort)"
want="$( { for t in system_user $CAT; do case "$t" in (organization_organization_type|org_mls_lab_type) echo "$t:-" ;; (*) printf '%s:((id < (%s)::numeric) OR ((id %% (10)::numeric) = (0)::numeric))\n' "$t" "$(fl "$t" "$FL")" ;; esac; done; printf '%s\n' result:- analysis:- sample:- dbz_heartbeat:-; } | LC_ALL=C sort)"
[ "$rc" = 0 ] && [ "$rows" = "$want" ] && ok_ "dbz_clinlims_owned: every catalogue table with an id on its floor, the two link tables whole, the lab rows unfiltered, the heartbeat" \
  || bad "publication: rc=$rc $out$(diff <(printf '%s\n' "$want") <(printf '%s\n' "$rows") | head -8 | tr '\n' ' ')"
{ cat "$FL"; echo 'org_mls_lab_type 10'; } > "$T/linkfl"
out="$(bash "$P" "$T/linkfl" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && ok_ "a floors file giving a link table a floor is refused" || bad "link floor at the publication: rc=$rc $out"
grep -v '^panel ' "$FL" > "$T/nopanel"
before="$rows"; out="$(bash "$P" "$T/nopanel" -- $PSQL 2>&1)"; rc=$?
now="$($PSQL -Atc "select tablename || ':' || coalesce(rowfilter, '-') from pg_publication_tables where pubname = 'dbz_clinlims_owned'" | LC_ALL=C sort)"
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'no floor recorded for clinlims.panel' && [ "$now" = "$before" ] && ok_ "a catalogue table without a floor is refused, the publication untouched" || bad "missing panel floor: rc=$rc $out"
# what logical decoding sends, in what order
$PSQL -q -c "SELECT pg_create_logical_replication_slot('t_cat', 'pgoutput')" >/dev/null
$PSQL -q -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
BEGIN;
INSERT INTO clinlims.test VALUES (nextval('clinlims.test_seq'), 'ZZ new test');                                        -- the hub's new test (40)
INSERT INTO clinlims.sampletype_test VALUES (nextval('clinlims.sample_type_test_seq'), currval('clinlims.test_seq'), 'link'); -- its sample type link
INSERT INTO clinlims.panel VALUES (nextval('clinlims.panel_seq'), 'ZZ panel');                                          -- a panel
INSERT INTO clinlims.panel_item VALUES (nextval('clinlims.panel_item_seq'), currval('clinlims.panel_seq'), 'item');      -- its item
INSERT INTO clinlims.organization_organization_type VALUES (3, 3);                                                     -- a link row
COMMIT;
UPDATE clinlims.test SET name = 'legacy renamed' WHERE id = 7;                                                         -- a seeded test, below its floor
INSERT INTO clinlims.test VALUES (43, 'not the hub''s');                                                               -- above the floor, residue 3
SQL
seq="$($PSQL -Atc "select string_agg(chr(get_byte(data, 0)) || ':' || ((get_byte(data, 1)::bigint << 24) | (get_byte(data, 2) << 16) | (get_byte(data, 3) << 8) | get_byte(data, 4))::oid::regclass::text, ' ' order by lsn) from pg_logical_slot_get_binary_changes('t_cat', NULL, NULL, 'proto_version', '1', 'publication_names', 'dbz_clinlims_owned') where chr(get_byte(data, 0)) in ('I', 'U', 'D')")"
[ "$seq" = "I:clinlims.test I:clinlims.sampletype_test I:clinlims.panel I:clinlims.panel_item I:clinlims.organization_organization_type U:clinlims.test" ] \
  && ok_ "decoded: the new test before its sample type link, the panel before its item, the link row, then the legacy test's edit; nothing of the row above the floor on residue 3" || bad "decoded sequence: $seq"
$PSQL -q -c "SELECT pg_drop_replication_slot('t_cat')" >/dev/null
exit $((fails > 0))
