#!/usr/bin/env bash
# Boots the Kafka node (broker and controller in one), then proves two
# things a green `compose up` does not: the broker actually answers with the
# cluster id hub/.env expects, and the SASL_PLAINTEXT listener published for
# remote clinics authenticates the mirrormaker user. That SASL check runs from
# the HOST network on the PUBLISHED port (127.0.0.1:9092), never by dialing
# REMOTE_KAFKA_HOST from inside the broker's own container -- an Azure VM
# cannot reach its own public IP. Because it dials loopback, it cannot tell a
# listener published to the world from one published to loopback only, so the
# binding itself is read back separately (sasl_bind_ok).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "60 · kafka"
[ "${DRY}" = 1 ] && { info "would: compose up -d kafka; wait for the broker on kafka:29092; check its controller role is live (metadata.version finalized); check cluster id; read back which host interface port 9092 is published on and compare it with hub/.env's KAFKA_SASL_BIND; prove the SASL listener on the published 9092 from the host network"; exit 0; }
setup_compose
[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"
# shellcheck disable=SC1091
set -a; . "${HUB_DIR}/.env"; set +a

compose up -d kafka >/dev/null

# $KAFKA_CONTAINER, never a literal `kafka`: the
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

# A broker can answer while its controller role never came up; a finalized
# metadata.version exists only once the node's own quorum elected it.
mv="$(ct exec "$KAFKA_CONTAINER" kafka-features --bootstrap-server kafka:29092 describe 2>/dev/null | grep 'metadata.version' | sed -nE 's/.*FinalizedVersionLevel:[[:space:]]*([^[:space:]]+).*/\1/p' || true)"
[ -n "$mv" ] && ok "metadata.version finalized at ${mv} (the controller role is live)" || fail "kafka answers but metadata.version is not finalized: its controller role did not come up -- ${CT} logs ${KAFKA_CONTAINER} | grep -i -E 'raft|controller'"

cid="$(ct exec "$KAFKA_CONTAINER" cat /var/lib/kafka/data/meta.properties 2>/dev/null | sed -n 's/^cluster.id=//p' || true)"
check_eq "cluster id" "$cid" "$KAFKA_CLUSTER_ID"

# sasl_listener_ok (hub/install/lib.sh) -- extracted so this check and task
# 090's own re-check of the same listener at the end of the install share one
# definition. Its own password never
# touches a command line, a log, or a tracked file: written by the printf
# builtin (no subprocess ever sees it in argv) to a mode-600 temp file under
# HUB_DIR, removed before it returns on every path.
# The clinic-facing port is published where hub/.env says it is.
# sasl_bind_ok (hub/install/lib.sh) reads the binding
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
