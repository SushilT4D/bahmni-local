#!/usr/bin/env bash
# 20-env renders clinic/.env from .env.example into a temp clinic dir.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
mkdir -p "$TMP/clinic"; cp "${HERE}/../../.env.example" "$TMP/clinic/.env.example"
env -i PATH="$PATH" HOME="$HOME" DRY=1 ENV_SKIP_COMPOSE=1 INSTALL_DIR="${HERE}/.." CLINIC_DIR="$TMP/clinic" REPO_DIR="$TMP" PLATFORM=linux RUNTIME=docker \
  CLINIC_SLUG=azure RESIDUE=7 MRN_PREFIX=AZR SITE_NUMBER=7 CLINIC_PHONE=+910000000000 CERT_HOSTNAME=h.test \
  REMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.test:9092 REMOTE_KAFKA_USERNAME=mirrormaker REMOTE_KAFKA_PASSWORD='p&w' \
  OPENMRS_ATOMFEED_PASSWORD=a OPENELIS_ATOMFEED_PASSWORD=b ODOO_ATOMFEED_PASSWORD=c \
  BHS_LOCATION=azure COMPOSE_PROJECT_NAME=bahmni-azure MYSQL_SERVER_NAME=bahmni-azure LOCAL_CLUSTER_ALIAS=azure MYSQL_AUTO_INCREMENT_OFFSET=7 MYSQL_SERVER_ID=7 DEBEZIUM_SERVER_ID=184057 ODOO_DB_VOLUME_NAME=bahmni-azure_odoodb-data ODOO_APP_VOLUME_NAME=bahmni-azure_odooapp-data \
  bash "${HERE}/../tasks/20-env.sh" >/dev/null 2>&1; rc=$?
assert_eq "task exits 0" "$rc" "0"
E="$TMP/clinic/.env"
. "${HERE}/../lib.sh"
assert_eq "CONTAINER_DATA_PATH at clinic/" "$(env_get "$E" CONTAINER_DATA_PATH)" "$TMP/clinic"
assert_eq "CERTIFICATE_PATH at clinic/certs" "$(env_get "$E" CERTIFICATE_PATH)" "$TMP/clinic/certs"
assert_eq "COMPOSE_PROJECT_NAME" "$(env_get "$E" COMPOSE_PROJECT_NAME)" "bahmni-azure"
assert_eq "LOCAL_CLUSTER_ALIAS" "$(env_get "$E" LOCAL_CLUSTER_ALIAS)" "azure"
assert_eq "MYSQL_SERVER_NAME" "$(env_get "$E" MYSQL_SERVER_NAME)" "bahmni-azure"
assert_eq "DEBEZIUM_SERVER_ID" "$(env_get "$E" DEBEZIUM_SERVER_ID)" "184057"
assert_eq "REMOTE_KAFKA_PASSWORD quoted" "$(grep -E '^REMOTE_KAFKA_PASSWORD=' "$E")" 'REMOTE_KAFKA_PASSWORD="p&w"'
assert_eq "OPENELIS_DB_PASSWORD == CLINLIMS_SOURCE_PASSWORD" "$(env_get "$E" OPENELIS_DB_PASSWORD)" "$(env_get "$E" CLINLIMS_SOURCE_PASSWORD)"
assert_eq "DEBEZIUM_DB_PASSWORD == LOCAL_DEBEZIUM_PASSWORD" "$(env_get "$E" DEBEZIUM_DB_PASSWORD)" "$(env_get "$E" LOCAL_DEBEZIUM_PASSWORD)"
assert_eq "KAFKA_CLUSTER_ID length" "$(env_get "$E" KAFKA_CLUSTER_ID | awk '{print length}')" "22"
assert_eq "no placeholders left" "$(has_placeholders "$E" "MAIL_USER MAIL_PASSWORD" | tr '\n' ' ')" ""
assert_eq "COMPOSE_PROJECT_NAME appears once" "$(grep -c '^COMPOSE_PROJECT_NAME=' "$E")" "1"
assert_eq "mode 600" "$(stat -f %Lp "$E" 2>/dev/null || stat -c %a "$E")" "600"
exit "$fails"
