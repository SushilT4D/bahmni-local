#!/usr/bin/env bash
# Starts the sync layer: Kafka, Kafka Connect and the connectors, and MirrorMaker to the hub.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "90 · local sync"
[ "${DRY}" = 1 ] && { info "would: debezium profile up; generate+register source, retention, heartbeat, odoo/clinlims connectors, local sinks; setup-mirrormaker; mirrormaker-connect up"; exit 0; }
setup_compose; cd "${CLINIC_DIR}"; E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
. "${INSTALL_DIR}/state.sh"

( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium up -d kafka kafka-connect >/dev/null )
connect_s="${CONNECT_BOOT_TIMEOUT_S:-1800}"
info "waiting up to $((connect_s/60)) min for Kafka Connect's REST port (it scans every plugin first; CONNECT_BOOT_TIMEOUT_S overrides)"
up=0; for i in $(seq 1 $((connect_s/5))); do curl -sf --max-time 5 localhost:8083/connector-plugins >/dev/null 2>&1 && { up=1; break; }; sleep 5; done
[ "$up" = 1 ] || fail "Kafka Connect's REST port did not answer within $((connect_s/60)) min: ${COMPOSE_CMD} logs kafka-connect"

if [ "${CLINIC_KAFKA_UI:-0}" = 1 ]; then
  ( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium up -d kafka-ui >/dev/null 2>&1 ) || warn "kafka-ui did not start (a convenience, not part of the sync path): ${COMPOSE_CMD} --profile debezium up -d kafka-ui"
else
  info "kafka-ui not started (CLINIC_KAFKA_UI=1 starts it; or later: ${COMPOSE_CMD} --profile debezium up -d kafka-ui)"
fi

plugins="$(curl -s localhost:8083/connector-plugins | jq -r '.[].class' | grep -cE 'MySqlConnector|PostgresConnector|JdbcSinkConnector')"
[ "$plugins" = 3 ] && ok "connect plugins: MySql, Postgres, JdbcSink" || fail "connect plugins missing (${plugins}/3) -- are the jars mounted as files?"

SEED_MANIFEST="${STATE_FILE}" bash scripts/generate-connectors.sh >/dev/null \
  || fail "the connector configs could not be generated (reason above)"
bash scripts/register-connectors.sh mysql-source-connector >/dev/null

v="$(capture_filter_check)" || fail "$v"
while IFS= read -r l; do if [ -n "$l" ]; then ok "${l#ok }"; fi; done <<EOF
$v
EOF
v="$(signal_capture_check)" || fail "$v"
ok "${v#ok }"
bash scripts/set-schema-history-retention.sh "${CT}" >/dev/null

bash scripts/register-connectors.sh odoo-source-connector clinlims-source-connector odoo-clinic-sink-all clinlims-clinic-sink-all >/dev/null
ok "OpenELIS down sink registered: keeps the hub's lab test catalogue and lab accounts, and the result, analysis and sample rows routed to this clinic (residue ${BHS_SITE_NUMBER})"

bash scripts/apply-slot-heartbeat.sh "${CT}" "${COMPOSE_PROJECT_NAME}-bahmni-postgres-1" postgres odoo-source-connector clinlims-source-connector >/dev/null
bash scripts/register-connectors.sh 'mysql-local-sink-*' >/dev/null

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

JQ_NOT_RUNNING='to_entries[] | select((.value.status.tasks | length) == 0 or (.value.status.tasks | any(.state != "RUNNING"))) | .key'
JQ_FAILED='to_entries[] | select(.value.status.tasks | any(.state == "FAILED")) | .key'
tasks_s="${CONNECT_TASKS_TIMEOUT_S:-600}"
bad=""
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
ret="$(ct exec kafka kafka-configs --bootstrap-server kafka:29092 --entity-type topics --entity-name "schema-changes.${MYSQL_SERVER_NAME}" --describe 2>/dev/null | grep -oE 'retention.ms=-1' | head -1)"
[ "$ret" = "retention.ms=-1" ] && ok "schema-changes.${MYSQL_SERVER_NAME} retention -1" || fail "schema-changes topic retention is not -1 -- the schema-history topic must never expire"

# twin-guard:begin
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
TS="${CLINIC_DIR}/certs/kafka/kafka.truststore.p12"
if cloud_tls; then cloud_truststore "$TS" "${MM2_IMAGE}"; ok "hub link $(cloud_protocol): truststore made from ${CLOUD_CA#${REPO_DIR}/}"
else warn "hub link $(cloud_protocol): no TLS, so the hub password and every record cross the network unencrypted"; fi
bash scripts/setup-mirrormaker.sh >/dev/null
grep -qE "^clusters *= *${BHS_LOCATION}, *cloud" config/mirrormaker/mm2.properties && ok "mm2.properties: clusters = ${BHS_LOCATION}, cloud" || fail "mm2.properties does not carry this node's alias"

# mm2-topics:begin
mm2_up_topics(){ # MM2_PROPERTIES ALIAS -> one plain topic name per line
  awk -v k="$2->cloud.topics" -F' *= *' '$1==k{print $2}' "$1" \
    | tr -d '()' | tr '|' '\n' | sed 's/\\\././g' | grep -v '^$'
}

# mm2-topics:end
up_topics="$(mm2_up_topics config/mirrormaker/mm2.properties "${BHS_LOCATION}")"
[ -n "$up_topics" ] || fail "mm2.properties carries no ${BHS_LOCATION}->cloud.topics pattern"

if [ "${TWIN_GUARD_SKIP:-0}" = 1 ]; then
  warn "twin guard skipped (TWIN_GUARD_SKIP=1): not checking whether another node named ${BHS_LOCATION} is already mirroring into the hub"
else
  hb_topic="${BHS_LOCATION}.heartbeats"

  # own-mm2:begin
  if [ "$(ct inspect --format '{{.State.Running}}' mirrormaker-connect 2>/dev/null || true)" = true ]; then
    info "this node's own MirrorMaker is running from an earlier run; stopping it so the twin check reads only other nodes"
    ( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium stop mirrormaker-connect >/dev/null )
    sleep 5
  fi

  # own-mm2:end
  if cloud_tls; then ct exec -i kafka sh -c 'umask 077; cat > /tmp/twin-guard.p12' < "$TS"; fi
  { printf 'security.protocol=%s\nsasl.mechanism=PLAIN\nsasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="%s" password="%s";\n' "$(cloud_protocol)" "${REMOTE_KAFKA_USERNAME}" "${REMOTE_KAFKA_PASSWORD}"
    if cloud_tls; then printf 'ssl.truststore.location=/tmp/twin-guard.p12\nssl.truststore.type=PKCS12\nssl.truststore.password=%s\n' "${REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD}"; fi
  } | ct exec -i kafka sh -c 'umask 077; cat > /tmp/twin-guard.properties'
  hb_read(){ ct exec kafka kafka-get-offsets --bootstrap-server "${REMOTE_KAFKA_BOOTSTRAP_SERVERS}" --command-config /tmp/twin-guard.properties --topic "$hb_topic" 2>&1 | twin_offset "$hb_topic"; }
  o1="$(hb_read || true)"; sleep 20; o2="$(hb_read || true)"
  twin_quiet=0
  case "$(twin_state "$o1" "$o2")" in
    quiet)   twin_quiet=1; ok "no other node named ${BHS_LOCATION} is mirroring into the hub (${hb_topic} end offset ${o1:-0}, unchanged over 20 s)" ;;
    alive)   fail "another node named ${BHS_LOCATION} is alive and mirroring into the hub right now (${hb_topic} advanced ${o1} -> ${o2} in 20 s). Two nodes under one slug mint the same ids and write the same hub topics. Stop the other node's stack first (on it: cd <its clinic dir> && docker compose --profile local --profile openelis --profile debezium down), then resume with --from 090. TWIN_GUARD_SKIP=1 overrides, knowingly." ;;
    *)       warn "could not read ${hb_topic} on the hub (${REMOTE_KAFKA_BOOTSTRAP_SERVERS}); the twin check is not proven -- MirrorMaker's own two-minute check below will show whether the hub is reachable at all" ;;
  esac

  # mm2-reset:begin
  mm2_reset_needed(){ # TWIN_QUIET(0|1) LOCAL_EVENTS HUB_HAS_OFFSETS(0|1) [FORCE(0|1)] -> yes | no

    case "${2:-x}" in ''|*[!0-9]*) echo no; return ;; esac
    if [ "$1" = 1 ] && [ "$3" = 1 ] && { [ "$2" -eq 0 ] || [ "${4:-0}" = 1 ]; }; then echo yes; else echo no; fi
  }

  # mm2-reset:end
  offsets_topic="mm2-offsets.${BHS_LOCATION}.internal"
  if [ "${MM2_OFFSET_RESET_SKIP:-0}" = 1 ]; then
    warn "MirrorMaker offset reset skipped (MM2_OFFSET_RESET_SKIP=1): if the hub remembers a previous node under ${BHS_LOCATION}, this node's first events may never be mirrored"
  else
    hub_has="$(ct exec kafka kafka-topics --bootstrap-server "${REMOTE_KAFKA_BOOTSTRAP_SERVERS}" --command-config /tmp/twin-guard.properties --list 2>/dev/null | grep -cx "$offsets_topic" || true)"
    local_events=0
    for t in $up_topics; do
      n="$(topic_events "$t")"
      local_events=$(( local_events + n ))
    done

    [ "${MM2_OFFSET_RESET_FORCE:-0}" = 1 ] && warn "MM2_OFFSET_RESET_FORCE=1: the hub's position for ${BHS_LOCATION} is treated as a previous node's even though this node has mirrored ${local_events} event(s); MirrorMaker re-reads this node's topics from their first event"
    case "$(mm2_reset_needed "$twin_quiet" "$local_events" "${hub_has:-0}" "${MM2_OFFSET_RESET_FORCE:-0}")" in
      yes)
        info "the hub remembers a previous node under ${BHS_LOCATION} (${offsets_topic}) and this node's up topics are empty: dropping that position so MirrorMaker reads this node from its first event"
        ct exec kafka kafka-topics --bootstrap-server "${REMOTE_KAFKA_BOOTSTRAP_SERVERS}" --command-config /tmp/twin-guard.properties --delete --topic "$offsets_topic" >/dev/null 2>&1 \
          || fail "could not delete ${offsets_topic} on the hub (${REMOTE_KAFKA_BOOTSTRAP_SERVERS})"
        gone=0
        for i in $(seq 1 12); do
          ct exec kafka kafka-topics --bootstrap-server "${REMOTE_KAFKA_BOOTSTRAP_SERVERS}" --command-config /tmp/twin-guard.properties --list 2>/dev/null | grep -qx "$offsets_topic" || { gone=1; break; }
          sleep 5
        done

        [ "$gone" = 1 ] && ok "hub position for ${BHS_LOCATION} reset (${offsets_topic} removed; MirrorMaker recreates it)" || fail "${offsets_topic} still listed on the hub after 60 s"
        ;;
      no)
        if [ "${hub_has:-0}" = 1 ] && [ "$local_events" -gt 0 ]; then ok "hub keeps its position for ${BHS_LOCATION}: this node has already mirrored ${local_events} event(s) under it"
        elif [ "${hub_has:-0}" = 0 ]; then ok "the hub holds no position for ${BHS_LOCATION} yet (first node under this alias)"
        else warn "not resetting the hub's position for ${BHS_LOCATION}: the twin check did not prove the alias quiet"; fi
        ;;
    esac
  fi

  ct exec kafka rm -f /tmp/twin-guard.properties /tmp/twin-guard.p12 >/dev/null 2>&1 || true
fi

printf '%s\n' "$up_topics" | while read -r t; do
  ct exec kafka kafka-topics --bootstrap-server kafka:29092 --create --if-not-exists --partitions 1 --replication-factor 1 --topic "$t" >/dev/null 2>&1 \
    || fail "could not create topic ${t} on the local broker"
done

ok "up topics exist before MirrorMaker starts ($(printf '%s\n' "$up_topics" | grep -c .))"
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium up -d mirrormaker-connect >/dev/null )
sleep 120
exp="$(ct logs mirrormaker-connect 2>&1 | grep -c Expiring || true)"
[ "${exp:-0}" = 0 ] && ok "mirrormaker: 0 expiring records after two minutes" || fail "mirrormaker is expiring records (${exp}) -- the hub is not reachable at ${REMOTE_KAFKA_BOOTSTRAP_SERVERS}"

odoo_topic="$(printf '%s\n' "$up_topics" | grep '\.odoo\.all$' | head -1)"
assigned=0
for i in $(seq 1 12); do
  ct logs mirrormaker-connect 2>&1 | grep -E "replicating [0-9]+ topic-partitions ${BHS_LOCATION}->cloud:.*${odoo_topic}-0" >/dev/null 2>&1 && { assigned=1; break; }
  sleep 10
done

[ "$assigned" = 1 ] && ok "mirrormaker replicates ${odoo_topic} (assigned at start)" || fail "mirrormaker has not reported ${odoo_topic} assigned within 2 more minutes: ${COMPOSE_CMD} logs mirrormaker-connect | grep 'topic-partitions'"
