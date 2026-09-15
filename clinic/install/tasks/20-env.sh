#!/usr/bin/env bash
# Render clinic/.env: derived identity, the ten absolute path keys at clinic/,
# generated secrets, the pasted five, fleet constants. Written to a temp file and
# moved into place only after the compose config gate passes.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "20 · clinic/.env"
E="${CLINIC_DIR}/.env"; X="${CLINIC_DIR}/.env.example"
[ -f "$X" ] || fail "no ${X}"
[ ! -e "$E" ] || fail "${E} exists -- fresh install only"
T="$(mktemp "${CLINIC_DIR}/.env.render.XXXXXX")"; cp "$X" "$T"
put(){ env_put "$T" "$1" "$2"; }

# paths -- every one absolute, every one under clinic/ (F-067: a stale one
# makes the runtime mount an empty directory silently)
put CONTAINER_DATA_PATH "${CLINIC_DIR}"
put CERTIFICATE_PATH "${CLINIC_DIR}/certs"
for k in BAHMNI_APPS_PATH:bahmni-apps BAHMNI_CONFIG_PATH:bahmni_config BAHMNI_OPENMRS_MODULES_PATH:openmrs-modules BAHMNI_ODOO_MODULES_PATH:odoo-modules EXTRA_ODOO_ADDONS_PATH:odoo-addons IMPLEMENTER_INTERFACE_CODE_PATH:implementer-interface CONFIG_BACKUP:config-backup RESTORE_ARTIFACTS_PATH:restore-artifacts SNOWSTORM_RF2_FILE_PATH:snomed-rf2.zip; do
  put "${k%%:*}" "${CLINIC_DIR}/${k#*:}"
done
put LOKI_URL "http://localhost:3100/loki/api/v1/push"

# identity (derived by install.sh; never the example's values)
for k in BHS_LOCATION COMPOSE_PROJECT_NAME MYSQL_SERVER_NAME LOCAL_CLUSTER_ALIAS MYSQL_AUTO_INCREMENT_OFFSET MYSQL_SERVER_ID DEBEZIUM_SERVER_ID ODOO_DB_VOLUME_NAME ODOO_APP_VOLUME_NAME; do
  eval "put $k \"\${$k}\""
done
put PHONE_NUMBER "${CLINIC_PHONE}"
put DEBEZIUM_SNAPSHOT_MODE no_data
put KAFKA_CLUSTER_ID "$(kafka_cluster_id)"
if [ "${PLATFORM}" = macos ]; then put RESTART_POLICY always; else put RESTART_POLICY unless-stopped; fi

# fleet constants the example does not carry (Rawach's live .env does)
put OPENMRS_MEM_LIMIT 6g
put REMOTE_SERVER_NAME bahmni-cloud
put MM2_REMOTE_ALIAS remote
put ODOO_HOST odoo; put ODOO_PORT 8069
put ODOO_IMAGE_TAG latest; put ODOO_DB_IMAGE_TAG demo-latest; put ODOO_CONNECT_IMAGE_TAG latest
put ODOO_ATOMFEED_USER admin
put HEIGHT_CONCEPT_UUID 5090AAAAAAAAAAAAAAAAAAAAAAAAAAAA
put WEIGHT_CONCEPT_UUID 5089AAAAAAAAAAAAAAAAAAAAAAAAAAAA
put MAIL_USER ""; put MAIL_PASSWORD ""; put MAIL_FROM none@localhost

# the hub
put REMOTE_KAFKA_BOOTSTRAP_SERVERS "${REMOTE_KAFKA_BOOTSTRAP_SERVERS}"
put REMOTE_KAFKA_USERNAME "${REMOTE_KAFKA_USERNAME}"
put REMOTE_KAFKA_PASSWORD "${REMOTE_KAFKA_PASSWORD}"
put REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD "$(gen_secret)"   # file is mounted, unused under SASL_PLAINTEXT

# secrets bound to the seed (pasted) and secrets born here (generated)
put OPENMRS_ATOMFEED_PASSWORD "${OPENMRS_ATOMFEED_PASSWORD}"
put OPENELIS_ATOMFEED_PASSWORD "${OPENELIS_ATOMFEED_PASSWORD}"
put ODOO_ATOMFEED_PASSWORD "${ODOO_ATOMFEED_PASSWORD}"
put MYSQL_ROOT_PASSWORD "$(gen_secret)"
put OPENMRS_DB_PASSWORD "$(gen_secret)"
put ODOO_DB_PASSWORD "$(gen_secret)"
oe="$(gen_secret)"; put OPENELIS_DB_PASSWORD "$oe"; put CLINLIMS_SOURCE_PASSWORD "$oe"   # the clinlims source logs in as role clinlims
put OPENELIS_DB_USERNAME clinlims; put OPENELIS_DB_USER clinlims
dz="$(gen_secret)"; put LOCAL_DEBEZIUM_PASSWORD "$dz"; put DEBEZIUM_DB_PASSWORD "$dz"
put LOCAL_MYSQL_PASSWORD "$(gen_secret)"
put SNOWSTORM_LITE_ADMIN_PASSWORD "$(gen_secret)"

left="$(has_placeholders "$T" "MAIL_USER MAIL_PASSWORD" | tr '\n' ' ')"
[ -z "$left" ] || { rm -f "$T"; fail "placeholders left unfilled: ${left}"; }
chmod 600 "$T"
if [ "${DRY}" = 1 ] || [ "${ENV_SKIP_COMPOSE:-0}" = 1 ]; then
  mv "$T" "$E"; ok "rendered ${E} (compose config gate skipped: dry run)"; exit 0
fi
setup_compose
mv "$T" "$E"
if ! compose config >/dev/null 2>"${CLINIC_DIR}/.env.render.err"; then
  mv "$E" "${CLINIC_DIR}/.env.rejected"
  fail "compose config rejected the rendered env (kept as .env.rejected): $(head -c 300 "${CLINIC_DIR}/.env.render.err")"
fi
rm -f "${CLINIC_DIR}/.env.render.err"
ok "rendered ${E}; compose config passes; COMPOSE_PROJECT_NAME=$(env_get "$E" COMPOSE_PROJECT_NAME)"
