#!/usr/bin/env bash
# The clinic's own sync layer, in the order the repo scripts expect. Judged on
# TASK state, never connector state.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "90 · local sync"
[ "${DRY}" = 1 ] && { info "would: debezium profile up; generate+register source, retention, heartbeat, odoo/clinlims connectors, local sinks; setup-mirrormaker; mirrormaker-connect up"; exit 0; }
setup_compose; mk_podman_shim; cd "${CLINIC_DIR}"; E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
# kafka-ui is NOT in this first up: it is gated on kafka-connect's health, and
# compose gives up on a slow Connect long before Connect does (manpur, 1 vCPU:
# "dependency failed to start: container kafka-connect is unhealthy"). The wait
# for Connect is ours, on a named budget; the UI follows and is never fatal.
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium up -d kafka-controller kafka schema-registry kafka-connect >/dev/null )
connect_s="${CONNECT_BOOT_TIMEOUT_S:-1800}"
info "waiting up to $((connect_s/60)) min for Kafka Connect's REST port (it scans every plugin first; CONNECT_BOOT_TIMEOUT_S overrides)"
up=0; for i in $(seq 1 $((connect_s/5))); do curl -sf --max-time 5 localhost:8083/connector-plugins >/dev/null 2>&1 && { up=1; break; }; sleep 5; done
[ "$up" = 1 ] || fail "Kafka Connect's REST port did not answer within $((connect_s/60)) min: ${COMPOSE_CMD} logs kafka-connect"
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium up -d kafka-ui >/dev/null 2>&1 ) || warn "kafka-ui did not start (a convenience, not part of the sync path): ${COMPOSE_CMD} --profile debezium up -d kafka-ui"
plugins="$(curl -s localhost:8083/connector-plugins | jq -r '.[].class' | grep -cE 'MySqlConnector|PostgresConnector|JdbcSinkConnector')"
[ "$plugins" = 3 ] && ok "connect plugins: MySql, Postgres, JdbcSink" || fail "connect plugins missing (${plugins}/3) -- are the jars mounted as files?"
til="$(bash scripts/generate-table-config.sh local | grep -E '^TABLE_INCLUDE_LIST=' | cut -d= -f2-)"
[ -n "$til" ] && env_put "$E" TABLE_INCLUDE_LIST "$til"
bash scripts/generate-connectors.sh >/dev/null
bash scripts/register-source-connector.sh >/dev/null
bash scripts/set-schema-history-retention.sh "${CT}" >/dev/null
NODE="${CLINIC_SLUG}" bash connectors/register-odoo.sh odoo-source-connector clinlims-source-connector odoo-clinic-sink-all clinlims-clinic-sink-all >/dev/null
# after register-odoo.sh, not before: the heartbeat script patches the two PG
# source connectors' configs (GET then PUT), so they must exist, and it takes
# BOTH source names (first live clinic, manpur: it was called with one name
# and one line too early -- "$5: unbound variable"). Its DB half (heartbeat
# table + publication membership) is idempotent; the seed already carries both.
bash scripts/apply-slot-heartbeat.sh "${CT}" "${COMPOSE_PROJECT_NAME}-bahmni-postgres-1" postgres odoo-source-connector clinlims-source-connector >/dev/null
bash scripts/generate-local-sink-connectors.sh >/dev/null
bash scripts/register-local-sink-connectors.sh >/dev/null
# Restart FAILED tasks ONCE before anything judges them (manpur, 2026-09-21):
# nine mysql-local-sink-* tasks FAILED on a bad pool setting; the template was
# fixed and the connectors re-registered (HTTP 200) -- eight recovered,
# mysql-local-sink-role_role stayed FAILED for hours, because Connect does not
# restart a FAILED task when a PUT leaves that connector's config unchanged
# from its own point of view, and nothing else here restarts it. This round
# runs once, by connector+task id, strictly before the poll below can judge a
# FAILED task -- and the poll's own first iteration sleeps 15s before its
# first read, so a task restarted here always gets at least one poll interval
# before the poll can call it FAILED again.
JQ_FAILED_TASK_IDS='to_entries[] | .key as $c | (.value.status.tasks[]? | select(.state=="FAILED") | "\($c) \(.id)")'
restart_status="$(curl -s --max-time 10 'localhost:8083/connectors?expand=status' 2>/dev/null || true)"
if [ -n "$restart_status" ] && [ "$restart_status" != "{}" ]; then
  failed_tasks="$(printf '%s' "$restart_status" | jq -r "$JQ_FAILED_TASK_IDS" 2>/dev/null || true)"
  if [ -n "$failed_tasks" ]; then
    info "restarting FAILED task(s) once before judging: $(printf '%s' "$failed_tasks" | tr '\n' ' ')"
    printf '%s\n' "$failed_tasks" | while IFS=' ' read -r rname rid; do
      [ -n "$rname" ] || continue
      curl -s -o /dev/null --max-time 10 -X POST "localhost:8083/connectors/${rname}/tasks/${rid}/restart" 2>/dev/null || true
    done
  fi
fi
# Judged on TASK state, polled: a small host needs more than the old
# fixed 30 s to start fourteen connectors. A connector with no task at all is
# NOT running (any() over an empty list is false and used to pass). A FAILED
# task never heals by waiting, so it ends the wait at once.
JQ_NOT_RUNNING='to_entries[] | select((.value.status.tasks | length) == 0 or (.value.status.tasks | any(.state != "RUNNING"))) | .key'
JQ_FAILED='to_entries[] | select(.value.status.tasks | any(.state == "FAILED")) | .key'
tasks_s="${CONNECT_TASKS_TIMEOUT_S:-600}"; bad=""
for i in $(seq 1 $((tasks_s/15))); do
  sleep 15
  st="$(curl -s --max-time 10 'localhost:8083/connectors?expand=status' || true)"
  [ -n "$st" ] && [ "$st" != "{}" ] || { bad="(Connect's REST gave no connector status)"; continue; }
  bad="$(printf '%s' "$st" | jq -r "$JQ_NOT_RUNNING" 2>/dev/null | tr '\n' ' ' || printf 'unreadable ')"
  [ -z "$bad" ] && break
  failed="$(printf '%s' "$st" | jq -r "$JQ_FAILED" 2>/dev/null | tr '\n' ' ' || true)"
  [ -n "$failed" ] && { bad="$failed(FAILED)"; break; }
done
[ -z "$bad" ] && ok "every connector task RUNNING ($(curl -s localhost:8083/connectors | jq length))" || fail "tasks not RUNNING: ${bad}"
ret="$(ct exec kafka kafka-configs --bootstrap-server localhost:9092 --entity-type topics --entity-name "schema-changes.${MYSQL_SERVER_NAME}" --describe 2>/dev/null | grep -oE 'retention.ms=-1' | head -1)"
[ "$ret" = "retention.ms=-1" ] && ok "schema-changes.${MYSQL_SERVER_NAME} retention -1" || fail "schema-changes topic retention is not -1 (F-045)"
# twin-guard:begin
# Two nodes installed under one clinic slug are exact twins -- same residue,
# same topic prefix, same MirrorMaker alias -- so both would mint the same ids
# and both would mirror into the hub's topics for this clinic. The ledger
# cannot see a second live host; the hub can: a live node's MirrorMaker
# heartbeat topic <alias>.heartbeats advances about once a second. Read its
# end offset on the hub twice, before this node's MirrorMaker exists, and
# refuse if it moved. TWIN_GUARD_SKIP=1 is the conscious override.
twin_offset(){ # TOPIC ; kafka-get-offsets output on stdin -> end offset, 0 for an absent topic, empty when unreadable
  local t="$1" out; out="$(cat)"
  case "$out" in
    *"$t:0:"*) printf '%s\n' "$out" | sed -nE "s/^.*$(printf '%s' "$t" | sed 's/[.[\*^$]/\\&/g'):0:([0-9]+).*$/\1/p" | head -1 ;;
    *"Could not match any topic-partitions"*|*"does not exist"*) printf '0\n' ;;
    *) printf '\n' ;;
  esac
}
twin_state(){ # FIRST SECOND -> alive | quiet | unknown
  local a="$1" b="$2"
  case "$a$b" in *[!0-9]*|'') echo unknown; return ;; esac
  [ -z "$a" ] || [ -z "$b" ] && { echo unknown; return; }
  [ "$b" -gt "$a" ] && echo alive || echo quiet
}
# twin-guard:end
if [ "${TWIN_GUARD_SKIP:-0}" = 1 ]; then
  warn "twin guard skipped (TWIN_GUARD_SKIP=1): not checking whether another node named ${LOCAL_CLUSTER_ALIAS} is already mirroring into the hub"
else
  hb_topic="${LOCAL_CLUSTER_ALIAS}.heartbeats"
  # own-mm2:begin
  # On a rerun of this task the node's OWN MirrorMaker from the earlier run is
  # still producing heartbeats, which would read as a twin. Stop it before the
  # two reads; it is started again below with the freshly rendered properties.
  if [ "$(ct inspect --format '{{.State.Running}}' mirrormaker-connect 2>/dev/null || true)" = true ]; then
    info "this node's own MirrorMaker is running from an earlier run; stopping it so the twin check reads only other nodes"
    ( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium stop mirrormaker-connect >/dev/null )
    sleep 5
  fi
  # own-mm2:end
  # the client properties live only inside the kafka container, for the two reads
  printf 'security.protocol=SASL_PLAINTEXT\nsasl.mechanism=PLAIN\nsasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="%s" password="%s";\n' "${REMOTE_KAFKA_USERNAME}" "${REMOTE_KAFKA_PASSWORD}" \
    | ct exec -i kafka sh -c 'umask 077; cat > /tmp/twin-guard.properties'
  hb_read(){ ct exec kafka kafka-get-offsets --bootstrap-server "${REMOTE_KAFKA_BOOTSTRAP_SERVERS}" --command-config /tmp/twin-guard.properties --topic "$hb_topic" 2>&1 | twin_offset "$hb_topic"; }
  o1="$(hb_read || true)"; sleep 20; o2="$(hb_read || true)"
  ct exec kafka rm -f /tmp/twin-guard.properties >/dev/null 2>&1 || true
  case "$(twin_state "$o1" "$o2")" in
    quiet)   ok "no other node named ${LOCAL_CLUSTER_ALIAS} is mirroring into the hub (${hb_topic} end offset ${o1:-0}, unchanged over 20 s)" ;;
    alive)   fail "another node named ${LOCAL_CLUSTER_ALIAS} is alive and mirroring into the hub right now (${hb_topic} advanced ${o1} -> ${o2} in 20 s). Two nodes under one slug mint the same ids and write the same hub topics. Stop the other node's stack first (on it: cd <its clinic dir> && docker compose --profile local --profile openelis --profile debezium down), then resume with --from 090. TWIN_GUARD_SKIP=1 overrides, knowingly." ;;
    *)       warn "could not read ${hb_topic} on the hub (${REMOTE_KAFKA_BOOTSTRAP_SERVERS}); the twin check is not proven -- MirrorMaker's own two-minute check below will show whether the hub is reachable at all" ;;
  esac
fi
bash scripts/setup-mirrormaker.sh >/dev/null
grep -qE "^clusters *= *${LOCAL_CLUSTER_ALIAS}, *remote" config/mirrormaker/mm2.properties && ok "mm2.properties: clusters = ${LOCAL_CLUSTER_ALIAS}, remote" || fail "mm2.properties does not carry this node's alias"
# mm2-topics:begin
# MirrorMaker assigns a topic that appears after it started only on its next
# topic refresh, so a fresh node's first event (the install probe, minutes
# from now) would sit unmirrored until then. Create the node's up topics
# first, from the same pattern MirrorMaker is given, so they are assigned at
# start; the source connectors then write into existing topics.
mm2_up_topics(){ # MM2_PROPERTIES ALIAS -> one plain topic name per line
  awk -v k="$2->remote.topics" -F' *= *' '$1==k{print $2}' "$1" \
    | tr -d '()' | tr '|' '\n' | sed 's/\\\././g' | grep -v '^$'
}
# mm2-topics:end
up_topics="$(mm2_up_topics config/mirrormaker/mm2.properties "${LOCAL_CLUSTER_ALIAS}")"
[ -n "$up_topics" ] || fail "mm2.properties carries no ${LOCAL_CLUSTER_ALIAS}->remote.topics pattern"
printf '%s\n' "$up_topics" | while read -r t; do
  ct exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --partitions 1 --replication-factor 1 --topic "$t" >/dev/null 2>&1 \
    || fail "could not create topic ${t} on the local broker"
done
ok "up topics exist before MirrorMaker starts ($(printf '%s\n' "$up_topics" | grep -c .))"
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium up -d mirrormaker-connect >/dev/null )
sleep 120
exp="$(ct logs mirrormaker-connect 2>&1 | grep -c Expiring || true)"
[ "${exp:-0}" = 0 ] && ok "mirrormaker: 0 expiring records after two minutes" || fail "mirrormaker is expiring records (${exp}) -- the hub is not reachable at ${REMOTE_KAFKA_BOOTSTRAP_SERVERS}"
# MirrorMaker must have taken the node's own Odoo topic, not only heartbeats
odoo_topic="$(printf '%s\n' "$up_topics" | grep '\.odoo\.all$' | head -1)"
assigned=0
for i in $(seq 1 12); do
  ct logs mirrormaker-connect 2>&1 | grep -E "replicating [0-9]+ topic-partitions ${LOCAL_CLUSTER_ALIAS}->remote:.*${odoo_topic}-0" >/dev/null 2>&1 && { assigned=1; break; }
  sleep 10
done
[ "$assigned" = 1 ] && ok "mirrormaker replicates ${odoo_topic} (assigned at start)" || fail "mirrormaker has not reported ${odoo_topic} assigned within 2 more minutes: ${COMPOSE_CMD} logs mirrormaker-connect | grep 'topic-partitions'"
