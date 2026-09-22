#!/usr/bin/env bash
# Local smoke test: does the hub's KRaft controller + broker actually boot
# from hub/docker-compose.yml end to end, on THIS machine, with a throwaway
# cluster id and a throwaway network -- no base stack, no clinic, nothing but
# the two services under test. This is what stands in for the live rehearsal
# (superseded on the Azure hub -- Debezium 3.6.2 does not support that base's
# MySQL 5.6). Distinct from test_compose.sh (static `compose config`
# validation only, no docker) and from install/tasks/060-kafka.sh (the real
# install, against the real base network and real hub/.env).
#
# The compose file pins
# container_name: kafka / kafka-controller -- fixed names, not namespaced by
# -p hubtest -- and this Mac runs a real bahmni-local clinic stack under
# exactly those names on 127.0.0.1:9092/9093, so the happy path never ran.
# boot-override.yml (this directory) renames the two boot containers to
# hubtest-kafka / hubtest-kafka-controller and resets kafka's published ports
# to nothing, so this test now runs its real happy path beside that stack
# instead of skipping around it. Only docker-level identifiers (exec/inspect/
# logs) use the renamed names -- compose service names, hostnames and every
# internal reference in hub/docker-compose.yml (KAFKA_CONTROLLER_QUORUM_VOTERS,
# the advertised listeners, --bootstrap-server kafka:29092) are unchanged.
#
# It runs against a temp COPY of hub/: this test
# used to write its throwaway JAAS file over the real hub/kafka_server_jaas.conf
# and restore it from a backup in its EXIT trap -- a kill -9 between the two
# left a live broker's credentials replaced by testadmin/testfleet. HUB_DIR is
# pointed at the copy BEFORE lib.sh is sourced, and the compose file it runs is
# the copy's, so the relative bind mount (./kafka_server_jaas.conf) resolves
# inside the copy too.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_HUB="$(cd "$HERE/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
export HUB_DIR="${TMP_ROOT}/hub"
mkdir -p "$HUB_DIR"
for item in docker-compose.yml connectors; do
  [ -e "${REAL_HUB}/${item}" ] && cp -R "${REAL_HUB}/${item}" "${HUB_DIR}/${item}"
done
. "$HERE/../lib.sh"
fails=0
bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }

docker info >/dev/null 2>&1 || { skip "docker is not available/running on this host -- test_broker_boot.sh needs a real docker to boot the broker"; exit 0; }

NET=hubtest_net
PROJ=hubtest
COMPOSE_F="${HUB_DIR}/docker-compose.yml"
OVERRIDE_F="${HERE}/boot-override.yml"
CKAFKA=hubtest-kafka
CCTRL=hubtest-kafka-controller
tmp_env="${TMP_ROOT}/broker-boot.env"
up_log="${TMP_ROOT}/broker-boot-up.log"
jaas_path="${HUB_DIR}/kafka_server_jaas.conf"
dc(){ docker compose -p "$PROJ" -f "$COMPOSE_F" -f "$OVERRIDE_F" --env-file "$tmp_env" "$@"; }

cleanup(){
  dc down -v >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  # The throwaway hub tree, JAAS file included. The real hub/'s own JAAS was
  # never touched, so there is nothing to restore.
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

if docker network create "$NET" >/dev/null 2>&1; then ok "throwaway network ${NET} created"; else bad "could not create network ${NET}"; fi

# The image pins compose needs to INTERPOLATE the file (every service's
# ${VAR:?} is resolved even though only kafka-controller/kafka are started)
# plus the cluster id and the throwaway network -- nothing else in hub/.env
# is referenced by docker-compose.yml itself, EXCEPT kafka-ui's
# KAFKA_UI_USER/KAFKA_UI_PASSWORD: compose interpolates the WHOLE
# file before deciding which services to start, so even though kafka-ui is
# never brought up here, its two required vars still need a value or `up`
# refuses outright (found live: "required variable KAFKA_UI_USER is missing
# a value") -- dummy values, since nothing in this test ever dials kafka-ui.
# versions_put (not a raw env_get loop) because sync/versions.env's values
# carry inline "# comment" text that only versions_put strips -- confirmed
# live: a plain env_get read of KAFKA_IMAGE came back as
# 'confluentinc/cp-kafka:8.3.2    # Apache Kafka 4.3.x...', which env_put
# then quoted whole and docker compose would have tried to pull as a literal
# image reference, comment included.
: > "$tmp_env"
versions_put "$tmp_env" || bad "versions_put failed to copy sync/versions.env into the temp .env"
CID="$(kafka_cluster_id)"
env_put "$tmp_env" KAFKA_CLUSTER_ID "$CID"
env_put "$tmp_env" KAFKA_BASE_NETWORK "$NET"
env_put "$tmp_env" KAFKA_UI_USER admin
env_put "$tmp_env" KAFKA_UI_PASSWORD "$(gen_secret)"
# KAFKA_SASL_BIND: kafka's ports entry interpolates
# it, and boot-override.yml resets that list to empty anyway -- but compose
# interpolates the WHOLE file before deciding what to start, so it still needs
# a valid value or `up` refuses outright.
env_put "$tmp_env" KAFKA_SASL_BIND 127.0.0.1
ok "temp .env written with the fleet's image pins + cluster id ${CID} + network ${NET}"

write_jaas "$jaas_path" testadmin testfleet
ok "temp JAAS written at ${jaas_path} (a throwaway copy; the real hub/kafka_server_jaas.conf is never written)"

if dc up -d kafka-controller kafka >"$up_log" 2>&1; then
  ok "docker compose up -d kafka-controller kafka (containers ${CCTRL}, ${CKAFKA})"
else
  bad "docker compose up failed: $(tail -5 "$up_log" | tr '\n' ' ')"
fi

answered=0
for i in $(seq 1 24); do
  docker exec "$CKAFKA" kafka-broker-api-versions --bootstrap-server kafka:29092 >/dev/null 2>&1 && { answered=1; break; }
  sleep 5
done
if [ "$answered" = 1 ]; then
  ok "broker answers kafka-broker-api-versions on kafka:29092 within 120s"
  got="$(docker exec "$CKAFKA" cat /var/lib/kafka/data/meta.properties 2>/dev/null | sed -n 's/^cluster.id=//p' || true)"
  [ "$got" = "$CID" ] && ok "meta.properties cluster.id matches the generated ${CID}" || bad "meta.properties cluster.id='${got}' want '${CID}'"
else
  bad "broker did not answer kafka-broker-api-versions on kafka:29092 within 120s -- $(docker logs --tail 30 "$CKAFKA" 2>&1 | tr '\n' ' ')"
fi

printf '%s\n' "$fails failure(s)"
exit $((fails>0))
