#!/usr/bin/env bash
# The concept dictionary comes down from the hub as changes only (hub/tables.conf
# rows marked `changes`): the OpenMRS half of the lab test catalogue.
#
#   - the readers of hub/tables.conf accept the role: the hub source and the
#     clinic sinks take the ten tables, the sink grants and the master-data
#     checksum include them, the verdict check passes; a `changes` row whose
#     verdict is not the hub's own (DOWN) and an unknown role are refused;
#   - the rendered hub source snapshots each of the ten with no rows and
#     carries no row filter for them (the hub writes every row, its edits of
#     rows older than its residue included);
#   - each clinic sink writes with binary logging off, upserts on the record
#     key, never applies a delete (delete.enabled=false and a filter that drops
#     deletes and tombstones), errors not tolerated; the other down sinks keep
#     applying deletes;
#   - the table list an old-stack clinic passes to the sink generator (the lab
#     results and the ten concept tables) renders exactly twelve sinks;
#   - with docker, the pinned Debezium image and the scripting jars, through
#     Kafka Connect's own transform chain: the hub source passes every concept
#     change, any key, deletes included; a clinic sink keeps inserts and
#     updates and drops deletes and tombstones (skipped, not failed, without
#     them unless REQUIRE_FILTER_RUN=1).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
TEN="concept_class concept_reference_source concept concept_name concept_description concept_numeric concept_answer concept_set concept_reference_term concept_reference_map"
got="$(sed -e 's/#.*//' "$R/hub/tables.conf" | awk -F: 'NF == 3 && $3 == "changes" { print $1 }' | tr '\n' ' ' | sed 's/ $//')"
[ "$got" = "$TEN" ] && ok_ "hub/tables.conf marks the ten concept tables changes, parents first" || bad "changes rows: [$got]"
for t in concept_complex concept_attribute concept_attribute_type concept_reference_term_map concept_datatype concept_map_type concept_name_tag concept_name_tag_map; do
  grep -qE "^${t}:" "$R/hub/tables.conf" && bad "hub/tables.conf carries $t, which is not in this set"
done
ok_ "nothing outside the ten (concept_complex, attributes, term maps, datatypes, map types, name tags) comes down"

# --- the readers ---------------------------------------------------------------------
inc="$(bash "$R/clinic/scripts/generate-table-config.sh" cloud | sed -n 's/^TABLE_INCLUDE_LIST=//p')"
miss=""; for t in $TEN; do case ",$inc," in *",openmrs.$t,"*) ;; *) miss="$miss $t";; esac; done
[ -z "$miss" ] && ok_ "the hub source's table list carries the ten" || bad "hub table list lacks:$miss"
bash "$R/clinic/scripts/check-table-verdicts.sh" >/dev/null 2>&1 && ok_ "the table verdicts accept the changes rows (each is DOWN)" || bad "check-table-verdicts: $(bash "$R/clinic/scripts/check-table-verdicts.sh" 2>&1 | tail -2)"
lists="$(REPO_DIR="$R" bash -c '. "$0/clinic/install/lib.sh"; echo "DOWN $(down_tables | tr "\n" " ")"; echo "MASTER $(master_down_tables | tr "\n" " ")"; sink_grant_sql' "$R")"
miss=""; for t in $TEN; do printf '%s\n' "$lists" | grep '^DOWN' | grep -q " $t " || miss="$miss $t"; printf '%s\n' "$lists" | grep -qxF "GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.$t TO 'sink'@'%';" || miss="$miss grant:$t"; done
[ -z "$miss" ] && ok_ "the down tables and the sink user's grants include the ten" || bad "down tables / grants lack:$miss"
printf '%s\n' "$lists" | grep '^MASTER' | grep -q ' concept_name ' && ok_ "the master-data checksum compares them" || bad "master tables: $lists"
copy(){ rm -rf "$T/r"; mkdir -p "$T/r"; (cd "$R" && tar cf - hub clinic/scripts clinic/install/lib.sh clinic/install/state.sh sync) | (cd "$T/r" && tar xf -); }
copy; awk '$1 == "concept_name" { $2 = "UP"; print; next } { print }' "$R/hub/table-verdicts.conf" > "$T/r/hub/table-verdicts.conf"
out="$(bash "$T/r/clinic/scripts/check-table-verdicts.sh" "$T/r" 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'marks concept_name changes, but its verdict is UP' && ok_ "a changes row whose verdict is not DOWN is refused" || bad "changes row with UP verdict: rc=$rc $out"
gen_hub(){ DEBEZIUM_DB_PASSWORD=x REPO_DIR="$1" HUB_DIR="$1/hub" bash "$1/hub/scripts/generate-cloud-source-connector.sh" "$T/src.json" 2>&1; }
copy; sed -i.bak 's/^concept_set:concept_set_id:changes$/concept_set:concept_set_id:snapshot/' "$T/r/hub/tables.conf"
out="$(gen_hub "$T/r")"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "unknown role 'snapshot'" && ok_ "an unknown role is refused by the hub source generator" || bad "unknown role: rc=$rc $out"

# --- the hub source ----------------------------------------------------------------------
out="$(gen_hub "$R")"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'changes only, no existing rows: concept, concept_answer' && ok_ "the hub source renders, naming the changes-only tables" || bad "hub source: rc=$rc $out"
python3 - "$T/src.json" "$TEN" <<'EOF' && ok_ "each of the ten is snapshotted with no rows (SELECT * ... WHERE 1 = 0) and carries no row filter" || bad "hub source config: $(grep -o '"transforms[^,]*' "$T/src.json" | head -3 | tr '\n' ' ')"
import json, sys
c = json.load(open(sys.argv[1]))['config']
ten = sys.argv[2].split()
ov = set(c.get("snapshot.select.statement.overrides", "").split(","))
for t in ten:
    assert "openmrs." + t in ov, t
    assert c["snapshot.select.statement.overrides.openmrs." + t] == "SELECT * FROM `openmrs`.`%s` WHERE 1 = 0" % t, t
    for n in [x for x in c.get("transforms", "").split(",") if x]:
        pat = c.get("predicates.%s.pattern" % c.get("transforms.%s.predicate" % n, ""), "")
        assert not (n.endswith("_" + t) or pat.rstrip("$").endswith(r"\." + t) or pat.rstrip("$").endswith("." + t)), (t, n)
assert [x for x in c.get("transforms", "").split(",") if x.endswith("_obs")], "the check sees no filter at all: it would pass anything"
EOF
python3 - "$T/src.json" > "$T/hub.cfg" <<'EOF'
import json, sys
for k, v in json.load(open(sys.argv[1]))['config'].items(): print(f"{k}\t{v}")
EOF

# --- the clinic sinks ----------------------------------------------------------------------
( cd "$R/clinic" && LOCAL_MYSQL_PASSWORD=x RESIDUE=3 FLOOR_ORDERS=441560 bash scripts/generate-local-sink-connectors.sh "$T/sinks" >/dev/null 2>&1 ) || bad "the clinic sinks did not render"
python3 - "$T/sinks" "$TEN" <<'EOF' && ok_ "each of the ten clinic sinks: binary logging off, upsert on the record key, deletes never applied (delete.enabled=false and a filter dropping deletes and tombstones), errors not tolerated, schema never changed" || bad "concept sink settings"
import json, sys, os
for t in sys.argv[2].split():
    c = json.load(open(os.path.join(sys.argv[1], "mysql-local-sink-%s.json" % t)))["config"]
    assert "sessionVariables=sql_log_bin=0" in c["connection.url"], t
    assert (c["insert.mode"], c["primary.key.mode"], c["delete.enabled"], c["errors.tolerance"], c["schema.evolution"]) == ("upsert", "record_key", "false", "none", "none"), t
    assert c["transforms"] == "dropPrefix,noDeletes", t
    assert c["transforms.noDeletes.type"] == "io.debezium.transforms.Filter" and c["transforms.noDeletes.null.handling.mode"] == "drop", t
    assert c["transforms.noDeletes.condition"] == "value.get('op') != 'd'", t
    assert c["table.name.format"] == t and c["topics"] == "remote.bahmni-cloud.openmrs." + t, t
EOF
python3 - "$T/sinks" <<'EOF' && ok_ "the other down sinks still apply deletes (a revoked user or role must reach the clinic)" || bad "users/role sinks changed"
import json, sys, os
for t in ("users", "role", "form"):
    c = json.load(open(os.path.join(sys.argv[1], "mysql-local-sink-%s.json" % t)))["config"]
    assert c["delete.enabled"] == "true" and "noDeletes" not in c["transforms"], t
EOF
# the old-stack clinic's list: the lab results and the ten concept tables
{ printf 'encounter:encounter_id:clinic=visit_id\nobs:obs_id:clinic=order_id\n'; grep -E ':changes$' "$R/hub/tables.conf"; } > "$T/old-stack.conf"
( cd "$R/clinic" && TABLES_CONF="$T/old-stack.conf" LOCAL_MYSQL_PASSWORD=x RESIDUE=3 FLOOR_ORDERS=441560 bash scripts/generate-local-sink-connectors.sh "$T/old" >/dev/null 2>&1 ) || bad "the old-stack list did not render"
want="$(for t in encounter obs $TEN; do echo "mysql-local-sink-$t.json"; done | sort | tr '\n' ' ')"
[ "$(ls "$T/old" 2>/dev/null | sort | tr '\n' ' ')" = "$want" ] && ok_ "the old-stack clinic's list renders exactly twelve sinks: encounter, obs and the ten concept tables" || bad "old-stack sinks: $(ls "$T/old" 2>/dev/null | tr '\n' ' ')"
cfg_of(){ python3 - "$1" <<'EOF'
import json, sys
c = json.load(open(sys.argv[1]))['config']
c['transforms'] = ','.join(t for t in c['transforms'].split(',') if t != 'dropPrefix')
for k, v in c.items(): print(f"{k}\t{v}")
EOF
}
cfg_of "$T/sinks/mysql-local-sink-concept_name.json" > "$T/sink.cfg"

# --- the records, through Kafka Connect's transform chain ---------------------------------
cat > "$T/hub.cases" <<'EOF'
bahmni-cloud.openmrs.concept	concept_id	63170	c	class_id	1	kept	a concept the hub created (residue 0)
bahmni-cloud.openmrs.concept	concept_id	5007	u	class_id	1	kept	the hub's edit of a legacy concept (residue 7, below its watermark)
bahmni-cloud.openmrs.concept_name	concept_name_id	170801	c	concept_id	63170	kept	the new concept's name
bahmni-cloud.openmrs.concept_set	concept_set_id	10203	u	concept_id	63170	kept	a set row on any residue
bahmni-cloud.openmrs.concept	concept_id	63170	d	class_id	1	kept	a delete leaves the hub as it is (the clinic sink decides)
EOF
cat > "$T/sink.cases" <<'EOF'
remote.bahmni-cloud.openmrs.concept_name	concept_name_id	170801	c	concept_id	63170	kept	a name the hub created
remote.bahmni-cloud.openmrs.concept_name	concept_name_id	1003	u	concept_id	5007	kept	the hub's edit of a legacy name
remote.bahmni-cloud.openmrs.concept_name	concept_name_id	170801	d	concept_id	63170	dropped	a name the hub deleted: never applied here
remote.bahmni-cloud.openmrs.concept_name	concept_name_id	170801	t	concept_id	63170	dropped	its tombstone
EOF
judge(){ # LABEL CASES GOT
  local n; n="$(grep -c . "$2")"; [ "$(grep -c . "$3")" = "$n" ] || { bad "$1: $(head -3 "$3" | tr '\n' ' ')"; return; }
  paste "$2" "$3" | while IFS='	' read -r _t _k _key _op _c _rv want why got; do
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
  judge "clinic concept_name sink" "$T/sink.cases" "$T/sink.got"
fi
printf '\n%s failure(s)\n' "$fails"
exit $((fails > 0))
