#!/usr/bin/env bash
# The source connector's signal table (lib.sh signal_table_ddl, created by seed
# task 050):
#   - its structure is the one Debezium documents for the source signal channel
#     (id varchar(42) primary key, type varchar(32) not null, data
#     varchar(2048) null), and the debezium user may write it;
#   - the read-back refuses a node without it, with another structure, or
#     where the connector cannot write it;
#   - it is in the source connector's include list, which names it as its
#     signal collection, and the check refuses a registered connector without it;
#   - it travels nowhere: no up topic in MirrorMaker's list, no hub sink, no
#     line in hub/tables.conf, and a sync/local/tables.conf line for it is refused.
# With docker and the pinned MySQL image, the DDL and the read-back run on a
# throwaway server; without them that part is skipped.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; MYC=""
cleanup(){ [ -n "$MYC" ] && docker rm -f -v "$MYC" >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT
. "${HERE}/../lib.sh"

# --- the structure ---------------------------------------------------------------
[ "$(signal_table_ddl)" = 'CREATE TABLE IF NOT EXISTS openmrs.debezium_signal (id VARCHAR(42) PRIMARY KEY, type VARCHAR(32) NOT NULL, data VARCHAR(2048) NULL)' ] \
  && ok_ "DDL: id VARCHAR(42) PRIMARY KEY, type VARCHAR(32) NOT NULL, data VARCHAR(2048) NULL" || bad "DDL: $(signal_table_ddl)"
# the database the source connector names (DATABASE_NAME), not a fixed one
case "$(DATABASE_NAME=clinicdb signal_table_ddl)|$(DATABASE_NAME=clinicdb signal_table_grant)|$(DATABASE_NAME=clinicdb signal_table_read_sql)" in
  "CREATE TABLE IF NOT EXISTS clinicdb.debezium_signal "*"|GRANT "*" ON clinicdb.debezium_signal TO "*"|"*"table_schema='clinicdb' and table_name='debezium_signal'"*"table_schema='clinicdb'"*) ok_ "DDL, grant and read-back follow DATABASE_NAME" ;;
  *) bad "the signal table SQL ignores DATABASE_NAME: $(DATABASE_NAME=clinicdb signal_table_ddl)" ;;
esac
grep -q 'openmrs\.debezium_signal' "${HERE}/../tasks/050-databases.sh" && bad "task 50 names openmrs.debezium_signal outright" || ok_ "task 50 names no database outright"
case "$(signal_table_grant)" in *SELECT*INSERT*UPDATE*DELETE*"openmrs.debezium_signal TO 'debezium'@'%'") ok_ "the debezium user may read and write it (the connector writes its snapshot window markers there)" ;; *) bad "grant: $(signal_table_grant)" ;; esac
S50="${HERE}/../tasks/050-databases.sh"
blk="$(sed -n '/^# signal-table:begin/,/^# signal-table:end/p' "$S50")"
printf '%s' "$blk" | grep -q 'signal_table_ddl' && printf '%s' "$blk" | grep -q 'signal_table_verdict' && ok_ "task 50 creates it and reads it back" || bad "task 50 has no signal-table block"
awk '/PHASE:-install}" = seed \]; then/ && !s {s=NR} /^# signal-table:begin/ {b=NR} /^fi$/ && b && !f {f=NR} END {exit !(s && b > s && f > b)}' "$S50" && ok_ "it is created at seed, where the debezium user is" || bad "the signal table is not created inside task 50's seed block"

# --- the read-back verdict on fixture rows ----------------------------------------
T="$(printf '\t')"
good="col${T}id${T}varchar(42)${T}NO${T}PRI
col${T}type${T}varchar(32)${T}NO${T}
col${T}data${T}varchar(2048)${T}YES${T}
priv${T}DELETE
priv${T}INSERT
priv${T}SELECT
priv${T}UPDATE"
out="$(printf '%s\n' "$good" | signal_table_verdict)" && ok_ "read-back: ${out#ok }" || bad "good rows refused: $out"
out="$(printf '' | signal_table_verdict)"; [ $? = 1 ] && case "$out" in *"does not exist"*) true ;; *) false ;; esac && ok_ "read-back: a node without the table is refused" || bad "no table: $out"
out="$(printf '%s\n' "$good" | sed 's/varchar(2048)/text/' | signal_table_verdict)"; [ $? = 1 ] && ok_ "read-back: another structure is refused" || bad "data text: $out"
out="$(printf '%s\n' "$good" | grep -v INSERT | signal_table_verdict)"; [ $? = 1 ] && case "$out" in *INSERT*) true ;; *) false ;; esac && ok_ "read-back: a connector user that cannot insert there is refused" || bad "no INSERT: $out"

# --- in the include list, nowhere else --------------------------------------------
C="$TMP/repo"; mkdir -p "$C/clinic/config" "$C/hub"
cp -R "$RP/clinic/scripts" "$C/clinic/"; cp -R "$RP/clinic/config/mirrormaker" "$C/clinic/config/"; cp -R "$RP/sync" "$C/"
cp -R "$RP/hub/scripts" "$RP/hub/connectors" "$C/hub/"; cp "$RP/hub/tables.conf" "$C/hub/"
printf 'MYSQL_SERVER_NAME=bahmni-t\nBHS_LOCATION=alpha\nRESIDUE=3\nREMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.invalid:9092\nMYSQL_ROOT_PASSWORD=x\n' > "$C/clinic/.env"
printf 'REMOTE_MYSQL_HOST=h\nREMOTE_MYSQL_PORT=3306\nREMOTE_MYSQL_DATABASE=openmrs\nREMOTE_MYSQL_USER=u\nREMOTE_MYSQL_PASSWORD=p\nDEBEZIUM_DB_PASSWORD=x\n' > "$C/hub/.env"
printf 'alpha:mysql-sink-alpha-:alpha:bahmni-alpha\n' > "$TMP/clinics.conf"
printf 'FLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$TMP/manifest.env"
printf 'visit:visit_id:625000\nobs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\nidgen_seq_id_gen:id\n' > "$C/sync/local/tables.conf"
hub_tables_before="$(cat "$C/hub/tables.conf")"
bash "$C/clinic/scripts/generate-table-config.sh" local > "$TMP/tc" 2>&1 || bad "generate-table-config refused: $(tail -2 "$TMP/tc")"
SEED_MANIFEST="$TMP/manifest.env" bash "$C/clinic/scripts/generate-connectors.sh" > "$TMP/gc" 2>&1 || bad "generate-connectors refused: $(tail -2 "$TMP/gc")"
inc="$(sed -n 's/^TABLE_INCLUDE_LIST=//p' "$TMP/tc")"
case ",$inc," in *",openmrs.debezium_signal,"*) ok_ "generate-table-config: the include list carries openmrs.debezium_signal" ;; *) bad "include list: $inc" ;; esac
case "$(sed -n 's/^KAFKA_TOPICS=//p' "$TMP/tc")$(grep PRIMARY_KEYS "$TMP/tc")" in *signal*) bad "generate-table-config lists a topic or key for the signal table" ;; *) ok_ "generate-table-config: no up topic and no key for it" ;; esac
python3 - "$C/clinic/connectors/mysql-local-source-connector.json" "$inc" > "$TMP/src" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))["config"]
inc = c["table.include.list"].split(",")
print("coll", c["signal.data.collection"])
print("chan", c["signal.enabled.channels"])
print("incl", "yes" if c["signal.data.collection"] in inc else "no")
print("same", "yes" if c["table.include.list"] == sys.argv[2] else "no")
PY
grep -qx 'coll openmrs.debezium_signal' "$TMP/src" && grep -qx 'chan source' "$TMP/src" && grep -qx 'incl yes' "$TMP/src" \
  && ok_ "source connector: reads signals from openmrs.debezium_signal and captures it" || bad "source connector: $(tr '\n' ' ' < "$TMP/src")"
grep -qx 'same yes' "$TMP/src" && ok_ "source connector and generate-table-config agree on the include list" || bad "the two include lists differ"
reg="$TMP/reg.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); c=d["config"]; c["name"]=d["name"]; json.dump(c, open(sys.argv[2],"w"))' "$C/clinic/connectors/mysql-local-source-connector.json" "$reg"
out="$(signal_capture_verdict "$reg")" && ok_ "registered-config check: ${out#ok }" || bad "registered check refused a good config: $out"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); c["table.include.list"]=",".join(x for x in c["table.include.list"].split(",") if "signal" not in x); json.dump(c, open(sys.argv[1],"w"))' "$reg"
out="$(signal_capture_verdict "$reg")"; [ $? = 1 ] && case "$out" in *"does not capture its signal table"*) true ;; *) false ;; esac && ok_ "registered-config check: a connector that does not capture it is refused" || bad "no signal in include: $out"
for t in 090-local-sync.sh 100-exit-checks.sh; do grep -q 'signal_capture_check' "${HERE}/../tasks/$t" && ok_ "task ${t%%-*} checks the registered connector captures it" || bad "task $t does not check it"; done
if command -v envsubst >/dev/null 2>&1; then
  bash "$C/clinic/scripts/setup-mirrormaker.sh" > "$TMP/mm" 2>&1 || bad "setup-mirrormaker refused: $(tail -2 "$TMP/mm")"
  grep -E -- '->remote\.topics' "$C/clinic/config/mirrormaker/mm2.properties" | grep -q 'signal' && bad "MirrorMaker sends the signal table's topic up" || ok_ "MirrorMaker: no up topic for the signal table"
fi
CLINICS_CONF="$TMP/clinics.conf" bash "$C/hub/scripts/generate-sink-connectors.sh" > "$TMP/hs" 2>&1 || bad "hub sink generator refused: $(tail -2 "$TMP/hs")"
ls "$C/hub/connectors"/mysql-sink-alpha-* >/dev/null 2>&1 && ok_ "hub sinks rendered: $(ls "$C/hub/connectors"/mysql-sink-alpha-* | wc -l | tr -d ' ')" || bad "no hub sinks rendered"
grep -l 'debezium_signal' "$C/hub/connectors"/mysql-sink-alpha-* >/dev/null 2>&1 && bad "a hub sink names the signal table" || ok_ "no hub sink for the signal table"
[ "$(cat "$C/hub/tables.conf")" = "$hub_tables_before" ] && ! grep -q 'debezium_signal' "$RP/hub/tables.conf" && ok_ "hub/tables.conf has no line for it" || bad "hub/tables.conf names the signal table"
. "$RP/sync/local/tables-conf.sh"
printf 'visit:visit_id:625000\ndebezium_signal:id\n' > "$TMP/sig.conf"
out="$(up_tables_read "$TMP/sig.conf" 2>&1)"; [ $? = 1 ] && case "$out" in *"signal table"*) true ;; *) false ;; esac && ok_ "a sync/local/tables.conf line for it is refused" || bad "a tables.conf line for the signal table was accepted: $out"

# --- the DDL and read-back on a real server -----------------------------------------
. "$RP/sync/versions.env"
docker_answers(){
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 & local p=$! i=0
  while kill -0 "$p" 2>/dev/null; do
    [ "$i" -ge "${DOCKER_PROBE_S:-15}" ] && { kill "$p" 2>/dev/null; return 1; }
    sleep 1; i=$((i+1))
  done
  wait "$p"
}
if docker_answers && docker image inspect "${MYSQL_IMAGE}" >/dev/null 2>&1; then
  MYC="sigtest$$"
  docker run -d --name "$MYC" -e MYSQL_ROOT_PASSWORD=x -e MYSQL_DATABASE=openmrs "${MYSQL_IMAGE}" >/dev/null 2>&1 || bad "could not start ${MYSQL_IMAGE}"
  my(){ docker exec -i "$MYC" sh -c 'MYSQL_PWD=x mysql -h127.0.0.1 -uroot -N' 2>/dev/null; }
  # a first start initialises the data directory and restarts the server: on a
  # busy machine that takes minutes (MYSQL_BOOT_S, default 300)
  up=0; for i in $(seq 1 $(( ${MYSQL_BOOT_S:-300} / 2 ))); do [ "$(echo 'select 1' | my)" = 1 ] && { up=1; break; }; sleep 2; done
  if [ "$up" = 1 ]; then
    out="$(printf '%s\n' "$(signal_table_read_sql)" | my | signal_table_verdict)"; [ $? = 1 ] && ok_ "${MYSQL_IMAGE}: the read-back refuses a server without the table" || bad "${MYSQL_IMAGE}, no table: $out"
    printf "CREATE USER 'debezium'@'%%' IDENTIFIED BY 'x';\n%s;\n%s;\nFLUSH PRIVILEGES;\n" "$(signal_table_ddl)" "$(signal_table_grant)" | my >/dev/null || bad "${MYSQL_IMAGE}: the DDL or grant failed"
    out="$(printf '%s\n' "$(signal_table_read_sql)" | my | signal_table_verdict)" && ok_ "${MYSQL_IMAGE}: created and granted, the read-back passes" || bad "${MYSQL_IMAGE}, created: $out"
    printf "%s;\n%s;\n" "$(signal_table_ddl)" "$(signal_table_grant)" | my >/dev/null && ok_ "${MYSQL_IMAGE}: running it twice is harmless" || bad "${MYSQL_IMAGE}: a second run failed"
    printf "INSERT INTO openmrs.debezium_signal VALUES ('probe-1', 'execute-snapshot', '{\"data-collections\": [\"openmrs.obs\"], \"type\": \"incremental\"}');\n" | docker exec -i "$MYC" sh -c 'MYSQL_PWD=x mysql -h127.0.0.1 -udebezium' >/dev/null 2>&1 \
      && ok_ "${MYSQL_IMAGE}: the debezium user can insert a signal row" || bad "${MYSQL_IMAGE}: the debezium user cannot insert into the signal table"
  else
    bad "${MYSQL_IMAGE} did not answer within ${MYSQL_BOOT_S:-300} s (MYSQL_BOOT_S)"
  fi
else
  printf '  skip docker with %s is not here; the DDL was not run on a server\n' "${MYSQL_IMAGE}"
fi
exit $((fails > 0))
