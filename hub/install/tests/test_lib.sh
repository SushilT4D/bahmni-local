#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; fails=0
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
export DRY=1 HUB_DIR="$TMP/hub"; mkdir -p "$HUB_DIR"
. "$HERE/../lib.sh"
OUT="$HUB_DIR/.env"
printf 'MYSQL_ROOT_PASSWORD=r00t\nOPENMRS_DB_NAME=openmrs\nODOO_DB_PASSWORD=od\nODOO_SINK_PASSWORD=os\nOPENELIS_DB_PASSWORD=oe\n' > "$TMP/base.env"
printf 'REMOTE_KAFKA_PASSWORD=fleetpw\n' > "$TMP/secrets.env"
printf 'REMOTE_KAFKA_BOOTSTRAP_SERVERS=kafka.example:9092\nREMOTE_KAFKA_USERNAME=mirrormaker\n' > "$TMP/hub.env"
HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT"
assert_eq "REMOTE_KAFKA_HOST from sync/hub.env" "$(env_get "$OUT" REMOTE_KAFKA_HOST)" "kafka.example"
assert_eq "fleet password from secrets" "$(env_get "$OUT" REMOTE_KAFKA_PASSWORD)" "fleetpw"
assert_eq "base root password carried" "$(env_get "$OUT" BASE_MYSQL_ROOT_PASSWORD)" "r00t"
assert_eq "existing sink password reused" "$(env_get "$OUT" ODOO_SINK_PASSWORD)" "os"
assert_eq "odoo db password carried" "$(env_get "$OUT" ODOO_DB_PASSWORD)" "od"
assert_eq "clinlims source password from base OPENELIS_DB_PASSWORD" "$(env_get "$OUT" CLINLIMS_SOURCE_PASSWORD)" "oe"
assert_eq "remote server name" "$(env_get "$OUT" REMOTE_SERVER_NAME)" "bahmni-cloud"
assert_eq "clinlims sink password generated (32)" "$(env_get "$OUT" CLINLIMS_SINK_PASSWORD | wc -c | tr -d ' ')" "33"
assert_eq "cluster id generated (22)" "$(env_get "$OUT" KAFKA_CLUSTER_ID | wc -c | tr -d ' ')" "23"
assert_eq "mode 600" "$(stat -c %a "$OUT" 2>/dev/null || stat -f %Lp "$OUT")" "600"
before="$(cat "$OUT")"; HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT"
assert_eq "second compose keeps generated values" "$(cat "$OUT")" "$before"
# hub_base_container ROLE reads BASE_MYSQL_CONTAINER/BASE_PG_CONTAINER from
# ${HUB_DIR}/.env -- that is exactly $OUT above, so no separate fixture is
# needed; the defaults hub_compose_env wrote (no override in the environment)
# are asserted literally, not by re-reading $OUT through env_get, so a shared
# env_get bug couldn't mask a hub_base_container bug.
assert_eq "hub_base_container mysql" "$(hub_base_container mysql)" "cloud-openmrsdb-1"
assert_eq "hub_base_container pg" "$(hub_base_container pg)" "cloud-openelisdb-1"
( hub_base_container bogus ) >/dev/null 2>&1; rc=$?
assert_eq "hub_base_container rejects an unknown role" "$rc" "1"

# mysql_user_sql VERSION USER PASSWORD DB -- pure text generation, no docker
# needed. 5.6.51 stands in for the Azure hub's base image, 8.0.39 for every
# other target (sync/versions.env's MYSQL_IMAGE).
assert_has(){ if printf '%s' "$2" | grep -qF "$3"; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: %q does not contain %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_lacks(){ if printf '%s' "$2" | grep -qF "$3"; then printf '  FAIL %s: %q unexpectedly contains %q\n' "$1" "$2" "$3"; fails=$((fails+1)); else printf '  ok   %s\n' "$1"; fi; }
out56="$(mysql_user_sql 5.6.51 sink 's3kret' openmrs)"
out80="$(mysql_user_sql 8.0.39 sink 's3kret' openmrs)"
assert_lacks "5.6.51: no CREATE USER IF NOT EXISTS" "$out56" 'CREATE USER IF NOT EXISTS'
assert_has  "5.6.51: has IDENTIFIED BY"             "$out56" 'IDENTIFIED BY'
assert_has  "5.6.51: has SET PASSWORD"              "$out56" 'SET PASSWORD'
assert_has  "8.0.39: has CREATE USER IF NOT EXISTS" "$out80" 'CREATE USER IF NOT EXISTS'
assert_has  "8.0.39: has IDENTIFIED BY"             "$out80" 'IDENTIFIED BY'
assert_has  "8.0.39: has ALTER USER"                "$out80" 'ALTER USER'
printf '%s\n' "$fails failure(s)"; exit $((fails>0))
