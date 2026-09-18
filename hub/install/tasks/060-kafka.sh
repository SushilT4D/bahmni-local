#!/usr/bin/env bash
# Boots the KRaft controller + broker + Schema Registry, then proves two
# things a green `compose up` does not: the broker actually answers with the
# cluster id hub/.env expects, and the SASL_PLAINTEXT listener published for
# remote clinics authenticates the mirrormaker user. That SASL check runs from
# the HOST network on the PUBLISHED port (127.0.0.1:9092), never by dialing
# REMOTE_KAFKA_HOST from inside the broker's own container -- an Azure VM
# cannot reach its own public IP. Because it dials loopback, it cannot tell a
# listener published to the world from one published to loopback only, so the
# binding itself is read back separately (sasl_bind_ok, final review C2).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "60 · kafka"
[ "${DRY}" = 1 ] && { info "would: compose up -d kafka-controller kafka schema-registry; wait for the broker on kafka:29092; check cluster id; read back which host interface port 9092 is published on and compare it with hub/.env's KAFKA_SASL_BIND; prove the SASL listener on the published 9092 from the host network; check schema registry on :8082"; exit 0; }
setup_compose
[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"
# shellcheck disable=SC1091
set -a; . "${HUB_DIR}/.env"; set +a

compose up -d kafka-controller kafka schema-registry >/dev/null

# $KAFKA_CONTAINER, never a literal `kafka` (final review, Important 3b): the
# name is "kafka" in production -- hub/docker-compose.yml pins that exact
# container_name -- but this task is now run for real by the live smoke beside
# another stack that already owns the bare name on this host's docker daemon.
# The two reads below used to exec into whatever container was called "kafka",
# which in that situation is somebody else's broker. Same override lib.sh
# documents and 080-sources.sh already uses.
answered=0
for i in $(seq 1 60); do
  ct exec "$KAFKA_CONTAINER" kafka-broker-api-versions --bootstrap-server kafka:29092 >/dev/null 2>&1 && { answered=1; break; }
  sleep 5
done
[ "$answered" = 1 ] || fail "broker did not answer kafka-broker-api-versions --bootstrap-server kafka:29092 within 300s"
ok "broker answers on kafka:29092"

cid="$(ct exec "$KAFKA_CONTAINER" cat /var/lib/kafka/data/meta.properties 2>/dev/null | sed -n 's/^cluster.id=//p' || true)"
check_eq "cluster id" "$cid" "$KAFKA_CLUSTER_ID"

# sasl_listener_ok (hub/install/lib.sh) -- extracted so this check and task
# 090's own re-check of the same listener at the end of the install share one
# definition (code review fold-in, Task 6/7 review). Its own password never
# touches a command line, a log, or a tracked file: written by the printf
# builtin (no subprocess ever sees it in argv) to a mode-600 temp file under
# HUB_DIR, removed before it returns on every path.
# The clinic-facing port is published where hub/.env says it is (final
# review, Critical 2). sasl_bind_ok (hub/install/lib.sh) reads the binding
# docker/podman actually installed -- the check below it dials 127.0.0.1 and
# so cannot tell 0.0.0.0:9092 from 127.0.0.1:9092 apart, which is exactly how
# a hub no clinic could dial passed every check this task had.
if bind_published="$(sasl_bind_ok)"; then
  ok "clinic-facing 9092 published on ${bind_published} (declared KAFKA_SASL_BIND=${KAFKA_SASL_BIND:-0.0.0.0})"
else
  fail "$bind_published"
fi

reason="$(sasl_listener_ok)" \
  && ok "SASL listener answers on the published ${SASL_LISTENER_PORT:-9092} as mirrormaker (advertised as ${REMOTE_KAFKA_HOST})" \
  || fail "${reason} -- check kafka_server_jaas.conf and REMOTE_KAFKA_PASSWORD"

# HUB_SCHEMA_REGISTRY_URL_OVERRIDE: the same class of test-only override as
# KAFKA_CONTAINER and SASL_LISTENER_PORT (final review, Important 3b) -- the
# live smoke republishes the registry on a throwaway host port, because this
# host may already run a real one bound to 8082. Production never sets it.
SR_URL="${HUB_SCHEMA_REGISTRY_URL_OVERRIDE:-http://localhost:8082}"
answered=0
for i in $(seq 1 60); do
  curl -sf --max-time 5 "${SR_URL}/subjects" >/dev/null 2>&1 && { answered=1; break; }
  sleep 5
done
[ "$answered" = 1 ] && ok "schema registry answers on ${SR_URL}/subjects" || fail "schema registry did not answer at ${SR_URL}/subjects within 300s"
