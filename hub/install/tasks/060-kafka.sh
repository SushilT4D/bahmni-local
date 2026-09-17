#!/usr/bin/env bash
# Boots the KRaft controller + broker + Schema Registry, then proves two
# things a green `compose up` does not: the broker actually answers with the
# cluster id hub/.env expects, and the SASL_PLAINTEXT listener published for
# remote clinics authenticates the mirrormaker user. That SASL check runs from
# the HOST network on the PUBLISHED port (127.0.0.1:9092), never by dialing
# REMOTE_KAFKA_HOST from inside the broker's own container -- an Azure VM
# cannot reach its own public IP.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "60 · kafka"
[ "${DRY}" = 1 ] && { info "would: compose up -d kafka-controller kafka schema-registry; wait for the broker on kafka:29092; check cluster id; prove the SASL listener on the published 9092 from the host network; check schema registry on :8082"; exit 0; }
setup_compose
[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"
# shellcheck disable=SC1091
set -a; . "${HUB_DIR}/.env"; set +a

compose up -d kafka-controller kafka schema-registry >/dev/null

answered=0
for i in $(seq 1 60); do
  ct exec kafka kafka-broker-api-versions --bootstrap-server kafka:29092 >/dev/null 2>&1 && { answered=1; break; }
  sleep 5
done
[ "$answered" = 1 ] || fail "broker did not answer kafka-broker-api-versions --bootstrap-server kafka:29092 within 300s"
ok "broker answers on kafka:29092"

cid="$(ct exec kafka cat /var/lib/kafka/data/meta.properties 2>/dev/null | sed -n 's/^cluster.id=//p' || true)"
check_eq "cluster id" "$cid" "$KAFKA_CLUSTER_ID"

# sasl_listener_ok (hub/install/lib.sh) -- extracted so this check and task
# 090's own re-check of the same listener at the end of the install share one
# definition (code review fold-in, Task 6/7 review). Its own password never
# touches a command line, a log, or a tracked file: written by the printf
# builtin (no subprocess ever sees it in argv) to a mode-600 temp file under
# HUB_DIR, removed before it returns on every path.
reason="$(sasl_listener_ok)" \
  && ok "SASL listener answers on the published ${SASL_LISTENER_PORT:-9092} as mirrormaker (advertised as ${REMOTE_KAFKA_HOST})" \
  || fail "${reason} -- check kafka_server_jaas.conf and REMOTE_KAFKA_PASSWORD"

answered=0
for i in $(seq 1 60); do
  curl -sf --max-time 5 localhost:8082/subjects >/dev/null 2>&1 && { answered=1; break; }
  sleep 5
done
[ "$answered" = 1 ] && ok "schema registry answers on localhost:8082/subjects" || fail "schema registry did not answer at localhost:8082/subjects within 300s"
