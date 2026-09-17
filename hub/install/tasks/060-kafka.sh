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

# The SASL check's password never touches a command line, a log, or a tracked
# file: written by the printf builtin (no subprocess ever sees it in argv) to
# a mode-600 temp file under HUB_DIR, removed by the trap below whether the
# check passes, fails, or this script dies unexpectedly.
tmp="$(mktemp "${HUB_DIR}/.sasl-check.XXXXXX")"
chmod 600 "$tmp"
trap 'rm -f "$tmp"' EXIT
printf 'security.protocol=SASL_PLAINTEXT\nsasl.mechanism=PLAIN\nsasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="mirrormaker" password="%s";\n' "$REMOTE_KAFKA_PASSWORD" > "$tmp"
if ct run --rm --network host -v "${tmp}:/tmp/c.properties:ro" "$KAFKA_IMAGE" kafka-broker-api-versions --bootstrap-server 127.0.0.1:9092 --command-config /tmp/c.properties >/dev/null 2>&1; then
  ok "SASL listener answers on the published 9092 as mirrormaker (advertised as ${REMOTE_KAFKA_HOST})"
else
  fail "SASL listener did not answer on 127.0.0.1:9092 as mirrormaker (image ${KAFKA_IMAGE}) -- check kafka_server_jaas.conf and REMOTE_KAFKA_PASSWORD"
fi

answered=0
for i in $(seq 1 60); do
  curl -sf --max-time 5 localhost:8082/subjects >/dev/null 2>&1 && { answered=1; break; }
  sleep 5
done
[ "$answered" = 1 ] && ok "schema registry answers on localhost:8082/subjects" || fail "schema registry did not answer at localhost:8082/subjects within 300s"
