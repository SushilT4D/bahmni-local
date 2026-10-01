#!/usr/bin/env bash
# Boots the clinic's Kafka exactly as compose defines it -- one node holding
# both roles -- from an empty data directory under throwaway names, and proves
# the controller role is live and a record round-trips. Skips without docker.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$(cd "${HERE}/../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
# A daemon that is installed but not running can make `docker info` hang
# rather than fail; wait for it on a named budget (DOCKER_PROBE_S).
docker_answers(){
  docker info >/dev/null 2>&1 & local p=$! i=0
  while kill -0 "$p" 2>/dev/null; do
    [ "$i" -ge "${DOCKER_PROBE_S:-15}" ] && { kill "$p" 2>/dev/null; return 1; }
    sleep 1; i=$((i+1))
  done
  wait "$p"
}
docker_answers || { printf '  skip docker does not answer here within %ss; this test needs a real docker\n' "${DOCKER_PROBE_S:-15}"; exit 0; }
TMP="$(mktemp -d)"; P=kboottest; CK=kboottest-kafka
mkdir -p "$TMP/clinic" "$TMP/sync"
cp "$C/.env.example" "$TMP/clinic/.env.example"; cp "$C/../sync/versions.env" "$TMP/sync/"
env -i PATH="$PATH" HOME="$HOME" DRY=1 ENV_SKIP_COMPOSE=1 INSTALL_DIR="$C/install" CLINIC_DIR="$TMP/clinic" REPO_DIR="$TMP" PLATFORM=linux RUNTIME=docker \
  CLINIC_SLUG=kboot RESIDUE=9 MRN_PREFIX=KBT SITE_NUMBER=9 CLINIC_PHONE=+910000000000 CERT_HOSTNAME=kboot.test \
  REMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.test:9092 REMOTE_KAFKA_USERNAME=m REMOTE_KAFKA_PASSWORD=p \
  OPENMRS_ATOMFEED_PASSWORD=a OPENELIS_ATOMFEED_PASSWORD=b ODOO_ATOMFEED_PASSWORD=c \
  BHS_LOCATION=kboot COMPOSE_PROJECT_NAME=$P MYSQL_SERVER_NAME=bahmni-kboot LOCAL_CLUSTER_ALIAS=kboot MYSQL_AUTO_INCREMENT_OFFSET=9 MYSQL_SERVER_ID=9 DEBEZIUM_SERVER_ID=184059 ODOO_DB_VOLUME_NAME=${P}_o ODOO_APP_VOLUME_NAME=${P}_a \
  bash "$C/install/tasks/020-env.sh" >/dev/null 2>&1 || { bad "could not render a .env to boot with"; rm -rf "$TMP"; exit 1; }
sed -i.bak '1{/^# DRY-RUN RENDER/d;}' "$TMP/clinic/.env"; rm -f "$TMP/clinic/.env.bak"
mkdir -p "$TMP/clinic/data/kafka"; chmod 777 "$TMP/clinic/data/kafka"
dc(){ docker compose -p "$P" --project-directory "$C" -f "$C/docker-compose.yml" -f "$HERE/kafka-boot-override.yml" --env-file "$TMP/clinic/.env" --profile debezium "$@"; }
cleanup(){ dc down -v >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT
dc up -d kafka >"$TMP/up.log" 2>&1 && ok_ "compose up -d kafka (one node, both roles)" || { bad "up failed: $(tail -5 "$TMP/up.log" | tr '\n' ' ')"; exit 1; }
up=0; for i in $(seq 1 36); do docker exec "$CK" kafka-broker-api-versions --bootstrap-server kafka:29092 >/dev/null 2>&1 && { up=1; break; }; sleep 5; done
[ "$up" = 1 ] && ok_ "broker answers on kafka:29092" || { bad "no answer in 180 s: $(docker logs --tail 20 "$CK" 2>&1 | tr '\n' ' ')"; exit 1; }
mv="$(docker exec "$CK" kafka-features --bootstrap-server kafka:29092 describe 2>/dev/null | grep 'metadata.version' | sed -nE 's/.*FinalizedVersionLevel:[[:space:]]*([^[:space:]]+).*/\1/p')"
[ -n "$mv" ] && ok_ "metadata.version finalized at ${mv} (the controller role is live)" || bad "metadata.version not finalized"
docker exec "$CK" kafka-topics --bootstrap-server kafka:29092 --create --topic kboot.probe --partitions 1 --replication-factor 1 >/dev/null 2>&1
printf 'kboot-%s\n' "$$" | docker exec -i "$CK" kafka-console-producer --bootstrap-server kafka:29092 --topic kboot.probe >/dev/null 2>&1
got="$(docker exec "$CK" kafka-console-consumer --bootstrap-server kafka:29092 --topic kboot.probe --from-beginning --max-messages 1 --timeout-ms 20000 2>/dev/null)"
[ "$got" = "kboot-$$" ] && ok_ "a record makes the produce/consume round trip" || bad "round trip read '${got}'"
exit $((fails > 0))
