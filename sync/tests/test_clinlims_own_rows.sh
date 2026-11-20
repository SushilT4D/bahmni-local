#!/usr/bin/env bash
# A clinic's OpenELIS source publishes a lab account (system_user) or a result
# signature (result_signature) only when the clinic minted it: id at or above
# the clinic's floor for the table and on its residue. The seed copies the
# hub's accounts and signatures to every clinic, and a clinic's edit of one of
# those stays at the clinic.
#   - the tables are sync/tables/tables.sh's UP_CLINLIMS_OWN_ROWS, and the
#     source template carries one filter step for each, in that order, each on
#     its own table's topic, before the step that routes every table into the
#     one ordered topic; tombstones are judged too (the condition reads the key);
#   - installer task 060 records a floor for each (state.sh
#     clinlims_floor_tables), and clinic/scripts/generate/postgres.sh writes each
#     step's condition from it with sync/origin-filter.sh's condition and stops
#     when a floor is missing; task 090 generates before it registers;
#   - the template filler refuses the source without the conditions;
#   - the Connect worker carries the scripting jars in the Postgres plugin
#     directory (clinic/docker-compose.yml);
#   - with docker, the pinned Debezium image and the scripting jars: the
#     rendered chain keeps the clinic's rows and drops the hub's, tombstones
#     included, and leaves every other table untouched (skipped, not failed,
#     without them unless REQUIRE_FILTER_RUN=1).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
. "$R/sync/tables/tables.sh"; . "$R/sync/origin-filter.sh"
[ "$UP_CLINLIMS_OWN_ROWS" = "system_user result_signature" ] && ok_ "the own-rows tables: system_user, result_signature" || bad "UP_CLINLIMS_OWN_ROWS is '$UP_CLINLIMS_OWN_ROWS'"
for t in $UP_CLINLIMS_OWN_ROWS; do
  subsystems_list | grep -qx "clinlims:$t" || bad "$t is not a synced OpenELIS table (the [up] list of sync/tables/openelis.conf)"
done
TPL="$R/clinic/scripts/templates/clinlims-source-connector.json"
cfg(){ python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get("config") or d).get(sys.argv[2], "<absent>"))' "$1" "$2"; }
want="$(for t in $UP_CLINLIMS_OWN_ROWS; do printf 'ownRows_%s,' "$t"; done)agg"
[ "$(cfg "$TPL" transforms)" = "$want" ] && ok_ "the source's steps: one own-rows filter per table, in order, then the routing into the one topic ($want)" || bad "transforms: $(cfg "$TPL" transforms), want $want"
for t in $UP_CLINLIMS_OWN_ROWS; do
  u="$(printf '%s' "$t" | tr '[:lower:]' '[:upper:]')"
  got="$(cfg "$TPL" "transforms.ownRows_$t.type")|$(cfg "$TPL" "transforms.ownRows_$t.language")|$(cfg "$TPL" "transforms.ownRows_$t.condition")|$(cfg "$TPL" "transforms.ownRows_$t.null.handling.mode")|$(cfg "$TPL" "transforms.ownRows_$t.predicate")|$(cfg "$TPL" "predicates.topicIs_$t.type")|$(cfg "$TPL" "predicates.topicIs_$t.pattern")"
  [ "$got" = "io.debezium.transforms.Filter|jsr223.groovy|\${CLINLIMS_UP_CONDITION_$u}|evaluate|topicIs_$t|org.apache.kafka.connect.transforms.predicates.TopicNameMatches|\${MYSQL_SERVER_NAME}\\.clinlims\\.$t" ] \
    && ok_ "$t: a Groovy Filter on its own topic, tombstones judged, its condition filled at registration" || bad "$t step: $got"
done
case ",$(cfg "$TPL" predicates)," in *,topicIs_system_user,*topicIs_result_signature,*) ok_ "both predicates are declared" ;; *) bad "predicates: $(cfg "$TPL" predicates)" ;; esac

# --- the floors and the installer -----------------------------------------------------
ft="$(CLINIC_DIR="$T" REPO_DIR="$R" bash -c '. "$1/clinic/install/lib.sh"; . "$1/clinic/install/state.sh"; clinlims_floor_tables' _ "$R" | tr '\n' ' ')"
case " $ft" in *" system_user result_signature "*) ok_ "task 060 records a floor for each own-rows table ($ft)" ;; *) bad "060 floor tables: $ft" ;; esac
G="$R/clinic/scripts/generate/postgres.sh"; T90="$R/clinic/install/tasks/090-local-sync.sh"
gen_line="$(grep -n 'generate-connectors.sh postgres' "$T90" | head -1 | cut -d: -f1)"
reg_line="$(grep -n 'register-connectors.sh odoo-source-connector clinlims-source-connector' "$T90" | head -1 | cut -d: -f1)"
grep -q 'for t in ${UP_CLINLIMS_OWN_ROWS}' "$G" && grep -q 'origin_filter_condition id "$fl" "${RESIDUE}"' "$G" && grep -q 'die "no ${k} is recorded' "$G" \
  && [ -n "$gen_line" ] && [ -n "$reg_line" ] && [ "$gen_line" -lt "$reg_line" ] \
  && ok_ "generate/postgres.sh writes each condition from the recorded floor and the residue and stops on a missing floor; task 090 generates before it registers the source" || bad "postgres.sh / 090 order: generate ${gen_line:-none}, register ${reg_line:-none}"
for j in groovy groovy-jsr223 debezium-scripting; do
  grep -qE "/ext/${j}-\\$\\{[A-Z_]+:\\?\\}\\.jar:/kafka/connect/debezium-connector-postgres/" "$R/clinic/docker-compose.yml" || bad "clinic/docker-compose.yml does not mount ${j} into the Postgres plugin directory"
done
grep -q 'debezium-connector-postgres/debezium-scripting' "$R/clinic/docker-compose.yml" && ok_ "the Connect worker carries the scripting jars in the Postgres plugin directory"

# --- the source as the clinic generates it ------------------------------------------------
# generate/postgres.sh fills the template with _fill_template.py; what it writes
# is what register-connectors.sh uploads, passwords aside.
fill(){ rm -f "$T/out.json" "$T/body"; rout="$(env MYSQL_SERVER_NAME=bahmni-t "$@" python3 "$R/clinic/scripts/_fill_template.py" "$TPL" "$T/out.json" 2>&1)"; rrc=$?
  [ -f "$T/out.json" ] && python3 -c 'import json,sys; json.dump(json.load(open(sys.argv[1]))["config"], open(sys.argv[2], "w"))' "$T/out.json" "$T/body"; }
fill
[ "$rrc" != 0 ] && printf '%s' "$rout" | grep -q 'not set: .*CLINLIMS_UP_CONDITION_SYSTEM_USER' && [ ! -e "$T/out.json" ] && ok_ "without the conditions the source is refused, nothing written" || bad "source without conditions: rc=$rrc $rout"
CS="$(origin_filter_condition id 170 3)"; CR="$(origin_filter_condition id 4400 3)"
fill CLINLIMS_UP_CONDITION_SYSTEM_USER="$CS" CLINLIMS_UP_CONDITION_RESULT_SIGNATURE="$CR"
[ "$rrc" = 0 ] && [ "$(cfg "$T/body" transforms.ownRows_system_user.condition)" = "key != null && key.get('id') instanceof Number && key.get('id').longValue() >= 170L && key.get('id').longValue() % 10 == 3" ] \
  && [ "$(cfg "$T/body" predicates.topicIs_result_signature.pattern)" = 'bahmni-t\.clinlims\.result_signature' ] \
  && ok_ "registered with each condition (system_user: key id >= 170, residue 3) on its own topic" || bad "rendered source: rc=$rrc $(cfg "$T/body" transforms.ownRows_system_user.condition)"

# --- the chain, in the pinned Debezium image ---------------------------------------------
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
cat > "$T/cases" <<'EOF'
bahmni-t.clinlims.system_user	id	183	c	login	1	kept	an account this clinic minted
bahmni-t.clinlims.system_user	id	183	t	login	1	kept	the tombstone of this clinic's account
bahmni-t.clinlims.system_user	id	47	u	login	1	dropped	this clinic's edit of a seeded hub account
bahmni-t.clinlims.system_user	id	47	t	login	1	dropped	the tombstone of a seeded hub account
bahmni-t.clinlims.system_user	id	184	u	login	1	dropped	an account on clinic 4's residue
bahmni-t.clinlims.result_signature	id	4403	c	result_id	5003	kept	a signature this clinic wrote
bahmni-t.clinlims.result_signature	id	4383	u	result_id	5003	dropped	a seeded signature below the floor, on residue 3
bahmni-t.clinlims.sample	id	47	u	status_id	1	kept	any other table passes untouched
EOF
if [ "$have_jars" != 1 ]; then
  skipped "the scripting jars are not in ${EXT} (clinic/config/kafka-connect/ext/fetch-scripting-jars.sh fetches them; SCRIPTING_JARS_DIR points elsewhere)"
elif ! docker_answers || ! docker image inspect "$IMG" >/dev/null 2>&1; then
  skipped "docker with $IMG is not here"
else
  python3 -c 'import json,sys; [print("%s\t%s" % (k, v)) for k, v in json.load(open(sys.argv[1])).items()]' "$T/body" > "$T/src.cfg"
  cut -f1-6 "$T/cases" > "$T/records.tsv"; cp "$R/clinic/install/tests/probes/RowFilterChainProbe.java" "$T/"
  m=""; for j in $JARS; do m="$m -v $EXT/$j:/kafka/connect/debezium-connector-postgres/$j:ro"; done
  # shellcheck disable=SC2086
  docker run --rm --entrypoint java -v "$T:/probe:ro" $m "$IMG" \
    -cp "/kafka/libs/*:/kafka/connect/debezium-connector-postgres/*" /probe/RowFilterChainProbe.java /probe/src.cfg /probe/records.tsv > "$T/got" 2>&1
  if [ "$(grep -c . "$T/got")" != "$(grep -c . "$T/cases")" ]; then bad "the probe did not judge every record: $(head -5 "$T/got" | tr '\n' ' ')"
  else
    paste "$T/cases" "$T/got" | while IFS='	' read -r _t _k _id _op _c _v want why got; do
      if [ "$got" = "$want" ]; then printf '  ok   clinic 3, floors system_user 170 / result_signature 4400: %s (%s)\n' "$why" "$got"; else printf '  FAIL clinic 3: %s -> %s, want %s\n' "$why" "$got" "$want"; fi
    done > "$T/judged"
    cat "$T/judged"; fails=$((fails + $(grep -c '^  FAIL' "$T/judged")))
  fi
fi
exit $((fails > 0))
