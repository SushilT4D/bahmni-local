#!/usr/bin/env bash
# Every sync/app image the fleet runs is pinned in sync/versions.env and nowhere else.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"; fails=0
ok(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
V="$REPO/sync/versions.env"
[ -f "$V" ] && ok "versions.env exists" || bad "sync/versions.env missing"
for k in KAFKA_IMAGE SCHEMA_REGISTRY_IMAGE MM2_IMAGE DEBEZIUM_CONNECT_IMAGE DEBEZIUM_SCRIPTING_VERSION GROOVY_VERSION OPENMRS_IMAGE_NAME MYSQL_IMAGE POSTGRES_IMAGE ODOO_IMAGE_NAME ODOO_CONNECT_IMAGE_TAG OPENELIS_IMAGE_TAG; do
  grep -qE "^${k}=." "$V" && ok "key $k" || bad "key $k missing from versions.env"
done
# the exact pins the spec (§10.2) fixes -- value must match exactly, but the
# line may carry a trailing inline comment (versions.env documents each pin),
# so anchor on whitespace-or-EOL rather than a bare $
grep -qE '^KAFKA_IMAGE=confluentinc/cp-kafka:8\.3\.2([[:space:]]|$)' "$V" && ok "kafka 8.3.2" || bad "KAFKA_IMAGE is not confluentinc/cp-kafka:8.3.2"
grep -qE '^DEBEZIUM_CONNECT_IMAGE=quay\.io/debezium/connect:3\.6\.2\.Final([[:space:]]|$)' "$V" && ok "debezium 3.6.2" || bad "DEBEZIUM_CONNECT_IMAGE is not 3.6.2.Final"
grep -qE '^OPENMRS_IMAGE_NAME=infoiplitin/openmrs:iplit-1\.2\.0-1200-03([[:space:]]|$)' "$V" && ok "openmrs 1.2.0" || bad "OPENMRS_IMAGE_NAME is not iplit-1.2.0-1200-03"
# no literal tag for these images in either compose file (comments excluded)
for f in clinic/docker-compose.yml clinic/docker-compose.override.yml hub/docker-compose.yml; do
  hits="$(grep -nE '^\s*image:' "$REPO/$f" | grep -E 'cp-kafka:|cp-kafka-connect:|cp-schema-registry:|debezium/connect:|mysql:[0-9]|postgres:[0-9]|odoo-1[06]:|odoo-connect:|openmrs:iplit' | grep -vE '\$\{' || true)"
  [ -z "$hits" ] && ok "$f has no literal pins" || bad "$f still carries literal pins: $hits"
done
# Compose resolves to the pinned images when versions.env is the environment.
# Never load clinic/.env (a live node's real secrets file, mode 600): build a
# synthetic env file from clinic/.env.example's own (non-secret, schema-valid)
# defaults -- e.g. RESTART_POLICY and the proxy ports need more than an
# arbitrary stub to satisfy compose's own field validation -- with the fleet
# pins appended last so they win, and hand it to compose explicitly via
# --env-file so it never falls back to clinic/.env.
TMPENV="$(mktemp)"; TMPIMGS="$(mktemp)"
trap 'rm -f "$TMPENV" "$TMPIMGS"' EXIT
cat "$REPO/clinic/.env.example" > "$TMPENV"
cat "$V" >> "$TMPENV"
# A handful of required (:?) vars are identity/fleet values .env.example ships
# blank on purpose (clinic/install/tasks/*.sh derives and writes them per
# clinic); compose config still needs some value to interpolate, so stub them
# here -- none of these are what this test is verifying.
printf 'CONTAINER_DATA_PATH=/tmp\nKAFKA_CLUSTER_ID=x\nOPENMRS_MEM_LIMIT=6g\nMYSQL_AUTO_INCREMENT_OFFSET=7\nMYSQL_SERVER_ID=7\nODOO_APP_VOLUME_NAME=x\nODOO_DB_VOLUME_NAME=x\n' >> "$TMPENV"
( cd "$REPO/clinic" && docker compose --env-file "$TMPENV" --profile local --profile debezium --profile openelis config --images 2>/dev/null ) > "$TMPIMGS"
grep -q '^confluentinc/cp-kafka:8.3.2$' "$TMPIMGS" && ok "clinic compose resolves cp-kafka:8.3.2" || bad "clinic compose does not resolve cp-kafka:8.3.2: $(tr '\n' ' ' <"$TMPIMGS")"
grep -q '^quay.io/debezium/connect:3.6.2.Final$' "$TMPIMGS" && ok "clinic compose resolves debezium 3.6.2" || bad "clinic compose does not resolve debezium 3.6.2"
# Task 1 deferred these two: the odoo-10 override existed when test_versions.sh was
# written, so the clinic project could not yet resolve odoo-16 cleanly. It is gone now
# (sync-core Task 4, 2026-09-17).
grep -q '^bahmni/odoo-16:1.0.0$' "$TMPIMGS" && ok "clinic compose resolves bahmni/odoo-16:1.0.0" || bad "clinic compose does not resolve bahmni/odoo-16:1.0.0: $(tr '\n' ' ' <"$TMPIMGS")"
grep -q '^bahmni/odoo-10' "$TMPIMGS" && bad "clinic compose still resolves a bahmni/odoo-10 image: $(tr '\n' ' ' <"$TMPIMGS")" || ok "no bahmni/odoo-10 image in clinic compose"
[ -f "$REPO/hub/scripts/install-jdbc-connector.sh" ] && bad "install-jdbc-connector.sh still present (unused Confluent JDBC)" || ok "Confluent JDBC installer gone"
printf '%s failure(s)\n' "$fails"; exit $((fails>0))
