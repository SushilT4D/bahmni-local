#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; fails=0
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
export DRY=1 HUB_DIR="$TMP/hub"; mkdir -p "$HUB_DIR"
. "$HERE/../lib.sh"
printf 'MYSQL_ROOT_PASSWORD=r00t\nOPENMRS_DB_NAME=openmrs\nODOO_DB_PASSWORD=od\nODOO_SINK_PASSWORD=os\nOPENELIS_DB_PASSWORD=oe\n' > "$TMP/base.env"
printf 'REMOTE_KAFKA_PASSWORD=fleetpw\n' > "$TMP/secrets.env"
printf 'REMOTE_KAFKA_BOOTSTRAP_SERVERS=kafka.example:9092\nREMOTE_KAFKA_USERNAME=mirrormaker\n' > "$TMP/hub.env"
HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$TMP/out.env"
assert_eq "REMOTE_KAFKA_HOST from sync/hub.env" "$(env_get "$TMP/out.env" REMOTE_KAFKA_HOST)" "kafka.example"
assert_eq "fleet password from secrets" "$(env_get "$TMP/out.env" REMOTE_KAFKA_PASSWORD)" "fleetpw"
assert_eq "base root password carried" "$(env_get "$TMP/out.env" BASE_MYSQL_ROOT_PASSWORD)" "r00t"
assert_eq "existing sink password reused" "$(env_get "$TMP/out.env" ODOO_SINK_PASSWORD)" "os"
assert_eq "odoo db password carried" "$(env_get "$TMP/out.env" ODOO_DB_PASSWORD)" "od"
assert_eq "clinlims source password from base OPENELIS_DB_PASSWORD" "$(env_get "$TMP/out.env" CLINLIMS_SOURCE_PASSWORD)" "oe"
assert_eq "remote server name" "$(env_get "$TMP/out.env" REMOTE_SERVER_NAME)" "bahmni-cloud"
assert_eq "clinlims sink password generated (32)" "$(env_get "$TMP/out.env" CLINLIMS_SINK_PASSWORD | wc -c | tr -d ' ')" "33"
assert_eq "cluster id generated (22)" "$(env_get "$TMP/out.env" KAFKA_CLUSTER_ID | wc -c | tr -d ' ')" "23"
assert_eq "mode 600" "$(stat -c %a "$TMP/out.env" 2>/dev/null || stat -f %Lp "$TMP/out.env")" "600"
before="$(cat "$TMP/out.env")"; HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$TMP/out.env"
assert_eq "second compose keeps generated values" "$(cat "$TMP/out.env")" "$before"
printf '%s\n' "$fails failure(s)"; exit $((fails>0))
