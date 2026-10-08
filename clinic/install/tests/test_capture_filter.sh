#!/usr/bin/env bash
# The clinic's capture filter on obs, orders and drug_order (sync/origin-filter.sh,
# rendered by clinic/scripts/generate-connectors.sh):
#   - the rendered source carries one Filter step per table whose floor comes
#     from the seed or from another table, each limited to that table's topic;
#     drug_order's step reads the orders floor; other tables have none;
#   - run on made-up change records, the steps keep a change to a row at or
#     above the floor on this clinic's residue and drop a change below the
#     floor, on another residue, and the tombstone of a below-floor delete;
#   - no path renders the source without the filter: a missing residue or
#     floor writes nothing, and a worker without the scripting jars fails
#     the step at configuration instead of passing records through.
# The records run through Kafka Connect's own Filter step and topic test in the
# pinned Debezium Connect image when docker has it, otherwise through a JSR-223
# Groovy engine on this machine's Java; with neither, that half is skipped.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
C="$TMP/repo"; mkdir -p "$C/clinic"
cp -R "$RP/clinic/scripts" "$C/clinic/"; cp -R "$RP/sync" "$C/"
printf 'FLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$TMP/manifest.env"
TODAY="$(grep -E '^[a-z_]+:' "$RP/sync/local/tables.conf" | grep -vE '^(obs|orders|drug_order):')"
CLINICAL='obs:obs_id:seed
orders:order_id:seed
drug_order:order_id:floor=orders'
OUT="$C/clinic/connectors/mysql-local-source-connector.json"

# render LIST ENV_LINES [MANIFEST] : runs the generator; its status in $TMP/rc, its output in $TMP/out
render(){
  printf '%s\n' "$1" > "$C/sync/local/tables.conf"
  printf 'MYSQL_SERVER_NAME=bahmni-t\n%s\n' "$2" > "$C/clinic/.env"
  SEED_MANIFEST="${3-$TMP/manifest.env}" bash "$C/clinic/scripts/generate-connectors.sh" > "$TMP/out" 2>&1; echo $? > "$TMP/rc"
}
cfg(){ python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["config"]; print(c.get(sys.argv[2], ""))' "$OUT" "$1" 2>/dev/null; }

# --- today's list: no table needs the filter, the source is as it was -----------
rm -rf "$C/clinic/connectors"; render "$TODAY" 'RESIDUE=3'
[ "$(cat "$TMP/rc")" = 0 ] && [ -z "$(cfg transforms)" ] && [ -z "$(cfg predicates)" ] && ok_ "today's list: no transform, no predicate" || bad "today's list: rc=$(cat "$TMP/rc") transforms='$(cfg transforms)' $(tail -2 "$TMP/out")"

# --- the three clinical tables: one step each, on its own topic ---------------
rm -rf "$C/clinic/connectors"; render "$TODAY
$CLINICAL" 'RESIDUE=3
MYSQL_AUTO_INCREMENT_OFFSET=3'
[ "$(cat "$TMP/rc")" = 0 ] || bad "the generator refused the clinical list: $(tail -3 "$TMP/out")"
[ "$(cfg transforms)" = 'origin_obs,origin_orders,origin_drug_order' ] && ok_ "a filter step for obs, orders and drug_order, and none for another table" || bad "transforms: '$(cfg transforms)'"
[ "$(cfg predicates)" = 'topic_obs,topic_orders,topic_drug_order' ] && ok_ "each step has its own topic test" || bad "predicates: '$(cfg predicates)'"
for t in obs orders drug_order; do
  [ "$(cfg "transforms.origin_${t}.type")" = io.debezium.transforms.Filter ] && [ "$(cfg "transforms.origin_${t}.language")" = jsr223.groovy ] \
    && ok_ "${t}: Debezium's Filter step, in Groovy" || bad "${t}: type '$(cfg "transforms.origin_${t}.type")' language '$(cfg "transforms.origin_${t}.language")'"
  [ "$(cfg "transforms.origin_${t}.null.handling.mode")" = evaluate ] && ok_ "${t}: tombstones are judged by the condition, not passed" || bad "${t}: null.handling.mode '$(cfg "transforms.origin_${t}.null.handling.mode")'"
  [ "$(cfg "transforms.origin_${t}.predicate")" = "topic_${t}" ] && [ "$(cfg "predicates.topic_${t}.type")" = org.apache.kafka.connect.transforms.predicates.TopicNameMatches ] \
    && [ "$(cfg "predicates.topic_${t}.pattern")" = "bahmni-t\\.openmrs\\.${t}" ] \
    && ok_ "${t}: applied to bahmni-t.openmrs.${t} only" || bad "${t}: predicate '$(cfg "transforms.origin_${t}.predicate")' pattern '$(cfg "predicates.topic_${t}.pattern")'"
  case "$(cfg "transforms.origin_${t}.condition")" in *value*) bad "${t}: the condition reads the record value, which a tombstone lacks" ;; *) ok_ "${t}: the condition reads the record key only" ;; esac
done
case "$(cfg transforms.origin_drug_order.condition)" in *"key.get('order_id')"*'>= 300000L'*'% 10 == 3') ok_ "drug_order: its order_id at or above the orders floor 300000, residue 3" ;; *) bad "drug_order condition: $(cfg transforms.origin_drug_order.condition)" ;; esac
case "$(cfg transforms.origin_obs.condition)" in *"key.get('obs_id')"*'>= 5000000L'*'% 10 == 3') ok_ "obs: its obs_id at or above the obs floor 5000000, residue 3" ;; *) bad "obs condition: $(cfg transforms.origin_obs.condition)" ;; esac
python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["config"]; [print("%s\t%s" % (k, v)) for k, v in c.items()]' "$OUT" > "$TMP/config.tsv"
good="$(cat "$OUT")"
cond(){ awk -F'\t' -v k="transforms.origin_$1.condition" '$1==k {print $2}' "$TMP/config.tsv"; }

# --- no path writes the source without the filter -----------------------------
render "$TODAY
$CLINICAL" ''
[ "$(cat "$TMP/rc")" != 0 ] && grep -q 'RESIDUE' "$TMP/out" && [ "$(cat "$OUT")" = "$good" ] && ok_ "no RESIDUE: refused, the earlier configuration left as it was" || bad "no RESIDUE: rc=$(cat "$TMP/rc") $(tail -2 "$TMP/out")"
render "$TODAY
$CLINICAL" 'RESIDUE=3
MYSQL_AUTO_INCREMENT_OFFSET=4'
[ "$(cat "$TMP/rc")" != 0 ] && grep -q 'MYSQL_AUTO_INCREMENT_OFFSET=4' "$TMP/out" && [ "$(cat "$OUT")" = "$good" ] && ok_ "a residue MySQL is not started with: refused" || bad "residue 3, offset 4: rc=$(cat "$TMP/rc") $(tail -2 "$TMP/out")"
printf 'FLOOR_OBS=5000000\n' > "$TMP/obs-only.env"
render "$TODAY
$CLINICAL" 'RESIDUE=3' "$TMP/obs-only.env"
[ "$(cat "$TMP/rc")" != 0 ] && grep -q 'FLOOR_ORDERS' "$TMP/out" && [ "$(cat "$OUT")" = "$good" ] && ok_ "no orders floor: refused, naming FLOOR_ORDERS" || bad "no orders floor: rc=$(cat "$TMP/rc") $(tail -2 "$TMP/out")"
rm -rf "$C/clinic/connectors"; render "$TODAY
$CLINICAL" 'RESIDUE=3' "$TMP/none.env"
[ "$(cat "$TMP/rc")" != 0 ] && [ ! -f "$OUT" ] && ok_ "no floors at all: refused, nothing written" || bad "no manifest: rc=$(cat "$TMP/rc"), file written: $([ -f "$OUT" ] && echo yes || echo no)"

# --- the condition on change records ------------------------------------------
# topic, key column, key, op (c/u/d; t = tombstone), and what must happen to it
cat > "$TMP/cases" <<'EOF'
bahmni-t.openmrs.obs	obs_id	5000003	c	kept	a new obs of this clinic
bahmni-t.openmrs.obs	obs_id	5000013	u	kept	an edit of this clinic's obs
bahmni-t.openmrs.obs	obs_id	5000003	d	kept	a delete of this clinic's obs
bahmni-t.openmrs.obs	obs_id	5000003	t	kept	its tombstone
bahmni-t.openmrs.obs	obs_id	4999993	u	dropped	an edit below the floor, on this residue
bahmni-t.openmrs.obs	obs_id	4999993	d	dropped	a delete below the floor
bahmni-t.openmrs.obs	obs_id	4999993	t	dropped	the tombstone of a delete below the floor
bahmni-t.openmrs.obs	obs_id	5000004	u	dropped	an edit of another clinic's obs
bahmni-t.openmrs.obs	obs_id	5000000	u	dropped	an edit of the hub's obs above the floor
bahmni-t.openmrs.orders	order_id	300003	c	kept	a new order of this clinic
bahmni-t.openmrs.orders	order_id	300001	u	dropped	an edit of another clinic's order
bahmni-t.openmrs.orders	order_id	299993	u	dropped	an edit of an order below the floor
bahmni-t.openmrs.drug_order	order_id	300003	c	kept	a drug order above the orders floor (below the obs floor)
bahmni-t.openmrs.drug_order	order_id	299993	u	dropped	a drug order below the orders floor
bahmni-t.openmrs.drug_order	order_id	300003	t	kept	the tombstone of this clinic's drug order
bahmni-t.openmrs.drug_order	order_id	299993	t	dropped	the tombstone of a drug order below the floor
bahmni-t.openmrs.visit	visit_id	12	u	kept	another table passes unchanged
bahmni-t.openmrs.obs_group	obs_id	4999993	u	kept	a topic whose name only begins like obs passes unchanged
EOF
cut -f1-4 "$TMP/cases" > "$TMP/records.tsv"
cut -f5 "$TMP/cases" > "$TMP/want"
judge(){ # LABEL GOT-FILE
  if [ "$(grep -c . "$2")" != "$(grep -c . "$TMP/want")" ]; then bad "$1: $(head -3 "$2" | tr '\n' ' ')"; return; fi
  paste "$TMP/cases" "$2" | while IFS='	' read -r topic col key op want why got; do
    if [ "$got" = "$want" ]; then printf '  ok   %s: %s %s %s %s -> %s (%s)\n' "$1" "${topic##*.}" "$key" "$op" "$why" "$got" "$want"
    else printf '  FAIL %s: %s %s %s %s -> %s, want %s\n' "$1" "${topic##*.}" "$key" "$op" "$why" "$got" "$want"; fi
  done > "$TMP/judged"
  cat "$TMP/judged"; fails=$((fails + $(grep -c '^  FAIL' "$TMP/judged")))
}
. "$RP/sync/versions.env"
EXT="$RP/clinic/config/kafka-connect/ext"
JARS="groovy-${GROOVY_VERSION}.jar groovy-jsr223-${GROOVY_VERSION}.jar debezium-scripting-${DEBEZIUM_SCRIPTING_VERSION}.jar"
have_jars=1; for j in $JARS; do [ -f "$EXT/$j" ] || have_jars=0; done
docker_answers(){
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 & local p=$! i=0
  while kill -0 "$p" 2>/dev/null; do
    [ "$i" -ge "${DOCKER_PROBE_S:-15}" ] && { kill "$p" 2>/dev/null; return 1; }
    sleep 1; i=$((i+1))
  done
  wait "$p"
}
host_java(){ # a java that runs, 11 or newer (single-file programs)
  local j
  for j in ${JAVA:-} ${JAVA_HOME:+$JAVA_HOME/bin/java} java /opt/homebrew/opt/openjdk*/bin/java /usr/local/opt/openjdk*/bin/java /usr/lib/jvm/*/bin/java; do
    [ -n "$j" ] || continue
    "$j" -version 2>&1 | grep -qE 'version "(1[1-9]|[2-9][0-9])' && { printf '%s\n' "$j"; return 0; }
  done
  return 1
}
cp "$HERE/probes/FilterChainProbe.java" "$HERE/probes/Jsr223Probe.java" "$TMP/"
IMG="${DEBEZIUM_CONNECT_IMAGE%% *}"
if docker_answers && docker image inspect "$IMG" >/dev/null 2>&1; then
  # the jars mounted where clinic/docker-compose.yml mounts them
  chain(){ # MOUNT-JARS... : runs the rendered chain on the records
    local m="" j
    for j in "$@"; do m="$m -v $EXT/$j:/kafka/connect/debezium-connector-mysql/$j:ro"; done
    # shellcheck disable=SC2086
    docker run --rm --entrypoint java -v "$TMP:/probe:ro" $m "$IMG" \
      -cp '/kafka/libs/*:/kafka/connect/debezium-connector-mysql/*' /probe/FilterChainProbe.java /probe/config.tsv /probe/records.tsv 2>&1
  }
  if [ "$have_jars" = 1 ]; then
    # shellcheck disable=SC2086
    chain $JARS > "$TMP/got.chain"
    judge "Connect chain in ${IMG##*/}" "$TMP/got.chain"
  else
    printf '  skip the scripting jars are not in %s (config/kafka-connect/ext/fetch-scripting-jars.sh fetches them); the records were not run\n' "${EXT#$RP/}"
  fi
  out="$(chain)"
  case "$out" in configure-failed*) ok_ "a worker with none of the scripting jars: the step fails at configuration ($(printf '%s' "$out" | head -1 | cut -c1-110))" ;; *) bad "a worker without the scripting jars: $(printf '%s' "$out" | head -3 | tr '\n' ' ')" ;; esac
  if [ "$have_jars" = 1 ]; then
    out="$(chain "debezium-scripting-${DEBEZIUM_SCRIPTING_VERSION}.jar")"
    case "$out" in configure-failed*) ok_ "a worker with the Filter step but no Groovy engine: the step fails at configuration ($(printf '%s' "$out" | head -1 | cut -c1-110))" ;; *) bad "a worker without the Groovy engine: $(printf '%s' "$out" | head -3 | tr '\n' ' ')" ;; esac
  fi
elif J="$(host_java)" && [ "$have_jars" = 1 ]; then
  : > "$TMP/got.engine"
  while IFS='	' read -r topic col key op; do
    t="${topic##*.}"
    case "$topic" in bahmni-t.openmrs.obs|bahmni-t.openmrs.orders|bahmni-t.openmrs.drug_order) ;; *) echo kept >> "$TMP/got.engine"; continue ;; esac
    printf '%s\t%s\t%s\t%s\n' "$topic" "$col" "$key" "$op" > "$TMP/one.tsv"
    "$J" -cp "$EXT/groovy-${GROOVY_VERSION}.jar:$EXT/groovy-jsr223-${GROOVY_VERSION}.jar" "$TMP/Jsr223Probe.java" groovy "$(cond "$t")" "$TMP/one.tsv" >> "$TMP/got.engine" 2>&1
  done < "$TMP/records.tsv"
  judge "JSR-223 Groovy on this machine's Java" "$TMP/got.engine"
  out="$("$J" "$TMP/Jsr223Probe.java" groovy "$(cond obs)" "$TMP/records.tsv" 2>&1)"
  case "$out" in configure-failed*) ok_ "without the Groovy jars there is no engine to run the condition: $(printf '%s' "$out" | head -1)" ;; *) bad "no Groovy jars, yet: $(printf '%s' "$out" | head -2 | tr '\n' ' ')" ;; esac
else
  printf '  skip neither docker with %s nor a Java 11+ with the scripting jars is here; the condition was not run on records\n' "$IMG"
fi
exit $((fails > 0))
