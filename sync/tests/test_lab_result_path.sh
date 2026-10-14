#!/usr/bin/env bash
# Lab results entered at the hub reach the clinic whose patient they belong to,
# and nothing else moves with them (hub/tables.conf, `patient=` rows).
#
#   - the readers of hub/tables.conf accept the role: the hub source captures
#     encounter and obs, the clinic gets their sinks and grants, the master-data
#     checksum leaves them out, the verdict check passes;
#   - the hub's source still refuses orders and drug_order, and refuses obs
#     without the role;
#   - the rendered hub source and clinic sinks, run through Kafka Connect's own
#     transform chain in the pinned Debezium image with the scripting jars:
#     the hub publishes only its own rows for a clinic's patients, and a clinic
#     keeps only its own patients' rows. Skipped (not failed) without docker,
#     the image or the jars, unless REQUIRE_FILTER_RUN=1.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# --- the readers ------------------------------------------------------------------
inc="$(bash "$R/clinic/scripts/generate-table-config.sh" cloud | sed -n 's/^TABLE_INCLUDE_LIST=//p')"
case ",$inc," in *,openmrs.encounter,*openmrs.obs,*) ok_ "the hub source's table list carries encounter and obs" ;; *) bad "hub table list: $inc" ;; esac
case ",$inc," in *,openmrs.person,*) bad "the hub source publishes person without --include-relay" ;; *) ok_ "the relay rows still need --include-relay" ;; esac
bash "$R/clinic/scripts/check-table-verdicts.sh" >/dev/null 2>&1 && ok_ "the table verdicts accept the patient rows (both are UP: the clinics write them)" || bad "check-table-verdicts: $(bash "$R/clinic/scripts/check-table-verdicts.sh" 2>&1 | tail -2)"
lists="$(REPO_DIR="$R" bash -c '. "$0/clinic/install/lib.sh"; echo "DOWN $(down_tables | tr "\n" " ")"; echo "MASTER $(master_down_tables | tr "\n" " ")"' "$R")"
printf '%s\n' "$lists" | grep '^DOWN' | grep -q ' obs ' && ok_ "the down tables (sink grants) include obs" || bad "down tables: $lists"
printf '%s\n' "$lists" | grep '^MASTER' | grep -qE ' (obs|encounter) ' && bad "the master-data checksum would compare encounter or obs: $lists" || ok_ "the master-data checksum leaves encounter and obs out"

# --- the hub source ----------------------------------------------------------------
gen_hub(){ DEBEZIUM_DB_PASSWORD=x REPO_DIR="$1" HUB_DIR="$1/hub" bash "$1/hub/scripts/generate-cloud-source-connector.sh" "$T/src.json" 2>&1; }
out="$(gen_hub "$R")"; rc=$?
[ "$rc" = 0 ] && ok_ "the hub source renders" || bad "hub source: rc=$rc $out"
copy(){ rm -rf "$T/r"; mkdir -p "$T/r"; (cd "$R" && tar cf - hub clinic/scripts sync) | (cd "$T/r" && tar xf -); }
copy; printf 'orders:order_id:patient=patient_id\n' >> "$T/r/hub/tables.conf"
out="$(gen_hub "$T/r")"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "only encounter and obs carry the hub's lab results" && [ ! -s "$T/src.json.x" ] && ok_ "orders is refused, even with the role" || bad "orders with role: rc=$rc $out"
copy; sed -i.bak 's/^obs:obs_id:patient=person_id$/obs:obs_id/' "$T/r/hub/tables.conf"
out="$(gen_hub "$T/r")"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "never publishes \['obs'\]" && ok_ "obs without the role is refused" || bad "obs without role: rc=$rc $out"
gen_hub "$R" >/dev/null 2>&1
python3 - "$T/src.json" > "$T/hub.cfg" <<'EOF'
import json, sys
for k, v in json.load(open(sys.argv[1]))['config'].items(): print(f"{k}\t{v}")
EOF

# --- the clinic sinks --------------------------------------------------------------
( cd "$R/clinic" && LOCAL_MYSQL_PASSWORD=x RESIDUE=3 bash scripts/generate-local-sink-connectors.sh "$T/sinks" >/dev/null 2>&1 ) || bad "the clinic sinks did not render"
[ -f "$T/sinks/mysql-local-sink-obs.json" ] && [ -f "$T/sinks/mysql-local-sink-encounter.json" ] && ok_ "the clinic gets sinks for encounter and obs" || bad "no lab-result sinks: $(ls "$T/sinks" 2>/dev/null | tr '\n' ' ')"
grep -q thisClinicsPatients "$T/sinks/mysql-local-sink-users.json" && bad "a master table's sink carries the patient filter" || ok_ "master-table sinks are unchanged"
out="$( cd "$R/clinic" && LOCAL_MYSQL_PASSWORD=x RESIDUE= MYSQL_AUTO_INCREMENT_OFFSET= bash scripts/generate-local-sink-connectors.sh "$T/none" 2>&1 )"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "residue (RESIDUE, 1-9) is not set" && [ ! -d "$T/none" ] && ok_ "without this clinic's residue nothing is generated" || bad "no residue: rc=$rc $out"
python3 - "$T/sinks/mysql-local-sink-obs.json" > "$T/sink.cfg" <<'EOF'
import json, sys
c = json.load(open(sys.argv[1]))['config']
# the sink's topic rename runs first; the probe feeds records already named for the table
c['transforms'] = ','.join(t for t in c['transforms'].split(',') if t != 'dropPrefix')
for k, v in c.items(): print(f"{k}\t{v}")
EOF

# --- the records, through Kafka Connect's transform chain --------------------------
#   topic   key column   key   op   row column   row value   want   why
cat > "$T/hub.cases" <<'EOF'
bahmni-cloud.openmrs.obs	obs_id	9000000	c	person_id	230003	kept	the hub's result obs for clinic 3's patient
bahmni-cloud.openmrs.obs	obs_id	9000003	c	person_id	230003	dropped	an obs clinic 3 sent up (its residue, not the hub's)
bahmni-cloud.openmrs.obs	obs_id	9000010	c	person_id	120001	dropped	the hub's obs for a central patient (below the person base)
bahmni-cloud.openmrs.obs	obs_id	9000020	c	person_id	230010	dropped	the hub's obs for a patient the hub registered
bahmni-cloud.openmrs.obs	obs_id	9000030	d	person_id	230004	kept	the delete of the hub's result obs for clinic 4's patient
bahmni-cloud.openmrs.obs	obs_id	9000030	t	person_id	230004	dropped	a tombstone (no row)
bahmni-cloud.openmrs.encounter	encounter_id	530000	c	patient_id	230004	kept	the hub's lab-result encounter for clinic 4's patient
bahmni-cloud.openmrs.encounter	encounter_id	530004	u	patient_id	230004	dropped	an encounter clinic 4 sent up
bahmni-cloud.openmrs.users	user_id	50	u	person_id	50	kept	a master table passes unchanged
EOF
cat > "$T/sink.cases" <<'EOF'
remote.bahmni-cloud.openmrs.obs	obs_id	9000000	c	person_id	230003	kept	clinic 3 keeps its own patient's result
remote.bahmni-cloud.openmrs.obs	obs_id	9000010	c	person_id	230004	dropped	clinic 3 drops clinic 4's patient's result
remote.bahmni-cloud.openmrs.obs	obs_id	9000020	c	person_id	120003	dropped	clinic 3 drops a central patient below the base
remote.bahmni-cloud.openmrs.obs	obs_id	9000030	d	person_id	230003	kept	clinic 3 applies the delete of its patient's result
remote.bahmni-cloud.openmrs.obs	obs_id	9000030	t	person_id	230003	dropped	a tombstone (no row)
EOF
judge(){ # LABEL CASES GOT
  local n w g
  n="$(grep -c . "$2")"; [ "$(grep -c . "$3")" = "$n" ] || { bad "$1: $(head -3 "$3" | tr '\n' ' ')"; return; }
  paste "$2" "$3" | while IFS='	' read -r _t _k key op _c rv want why got; do
    if [ "$got" = "$want" ]; then printf '  ok   %s: %s (%s)\n' "$1" "$why" "$got"; else printf '  FAIL %s: %s -> %s, want %s\n' "$1" "$why" "$got" "$want"; fi
  done > "$T/judged"
  cat "$T/judged"; fails=$((fails + $(grep -c '^  FAIL' "$T/judged")))
}
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
if [ "$have_jars" != 1 ]; then
  skipped "the scripting jars are not in ${EXT#$R/} (clinic/config/kafka-connect/ext/fetch-scripting-jars.sh fetches them)"
elif ! docker_answers || ! docker image inspect "$IMG" >/dev/null 2>&1; then
  skipped "docker with $IMG is not here"
else
  cp "$R/clinic/install/tests/probes/RowFilterChainProbe.java" "$T/"
  run(){ # PLUGIN-DIR CONFIG CASES -> one line per record
    local m="" j
    for j in $JARS; do m="$m -v $EXT/$j:/kafka/connect/$1/$j:ro"; done
    cut -f1-6 "$3" > "$T/records.tsv"
    # shellcheck disable=SC2086
    docker run --rm --entrypoint java -v "$T:/probe:ro" $m "$IMG" \
      -cp "/kafka/libs/*:/kafka/connect/$1/*" /probe/RowFilterChainProbe.java "/probe/$(basename "$2")" /probe/records.tsv 2>&1
  }
  run debezium-connector-mysql "$T/hub.cfg" "$T/hub.cases" > "$T/hub.got"
  judge "hub source" "$T/hub.cases" "$T/hub.got"
  run debezium-connector-jdbc "$T/sink.cfg" "$T/sink.cases" > "$T/sink.got"
  judge "clinic 3's sink" "$T/sink.cases" "$T/sink.got"
fi
printf '\n%s failure(s)\n' "$fails"
exit $((fails > 0))
