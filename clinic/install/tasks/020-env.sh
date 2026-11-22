#!/usr/bin/env bash
# Writes clinic/.env: the clinic's identity, paths, generated passwords, image versions and hub settings; every value an existing clinic/.env holds is kept.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "20 · clinic/.env"
E="${CLINIC_DIR}/.env"
X="${CLINIC_DIR}/.env.example"
[ -f "$X" ] || fail "no ${X}"
T="$(mktemp "${CLINIC_DIR}/.env.render.XXXXXX")"; cp "$X" "$T"
trap 'rm -f "$T"' EXIT   # a failed run leaves no render (it can hold the cloud password)
put(){ env_put "$T" "$1" "$2"; }

put CONTAINER_DATA_PATH "${CLINIC_DIR}"
put CERTIFICATE_PATH "${CLINIC_DIR}/certs"
for k in BAHMNI_APPS_PATH:bahmni-apps BAHMNI_CONFIG_PATH:bahmni_config BAHMNI_OPENMRS_MODULES_PATH:openmrs-modules BAHMNI_ODOO_MODULES_PATH:odoo-modules EXTRA_ODOO_ADDONS_PATH:odoo-addons IMPLEMENTER_INTERFACE_CODE_PATH:implementer-interface CONFIG_BACKUP:config-backup; do
  put "${k%%:*}" "${CLINIC_DIR}/${k#*:}"
done

put BAHMNI_UI_DIR "${CLINIC_DIR}/extracted/htdocs/bahmni"          # filled by task 045 from BAHMNI_WEB_IMAGE
put BAHMNI_CONFIG_DIR "${CLINIC_DIR}/extracted/bahmni_config"       # filled by task 045 from BAHMNI_CONFIG_IMAGE

mem_mb="$(node_mem_mb)"
pool_mb="$(mysql_pool_mb "$mem_mb")"
mkdir -p "${CLINIC_DIR}/config/mysql"
mysql_tuning_cnf "$pool_mb" > "${CLINIC_DIR}/config/mysql/sync-tuning.cnf"
ok "mysql tuning: buffer pool ${pool_mb} MB (node memory ${mem_mb} MB), redo log 512 MB -> config/mysql/sync-tuning.cnf"

IDENTITY_KEYS="BHS_LOCATION MYSQL_SERVER_NAME BHS_SITE_NUMBER DEBEZIUM_SERVER_ID"
for k in $IDENTITY_KEYS; do
  eval "put $k \"\${$k}\""
done


put MRN_PREFIX "${MRN_PREFIX}"
put LAN_NAME "${LAN_NAME}"

[ -z "${OPENMRS_INITIALIZER_DOMAINS:-}" ] || put OPENMRS_INITIALIZER_DOMAINS "${OPENMRS_INITIALIZER_DOMAINS}"
put DEBEZIUM_SNAPSHOT_MODE no_data
put KAFKA_CLUSTER_ID "$(kafka_cluster_id)"
put RESTART_POLICY always

put OPENMRS_MEM_LIMIT 6g
put REMOTE_SERVER_NAME bahmni-cloud
put ODOO_HOST odoo; put ODOO_PORT 8069
versions_put "$T"   # every fleet pin from sync/versions.env, the one place they live
put ODOO_ATOMFEED_USER "${ODOO_ATOMFEED_USER:-emrsync}"   # the hub's own Odoo feed login (lib.sh INPUT_DEFAULTS)
put HEIGHT_CONCEPT_UUID 5090AAAAAAAAAAAAAAAAAAAAAAAAAAAA
put WEIGHT_CONCEPT_UUID 5089AAAAAAAAAAAAAAAAAAAAAAAAAAAA
put MAIL_USER ""; put MAIL_PASSWORD ""; put MAIL_FROM none@localhost

put REMOTE_KAFKA_BOOTSTRAP_SERVERS "${REMOTE_KAFKA_BOOTSTRAP_SERVERS}"
put REMOTE_KAFKA_USERNAME "${REMOTE_KAFKA_USERNAME}"
put REMOTE_KAFKA_PASSWORD "${REMOTE_KAFKA_PASSWORD}"
put REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD "$(gen_secret)"   # opens the truststore task 090 makes from sync/cloud-ca.pem
proto="$(cloud_protocol)"
case "$proto" in SASL_SSL|SASL_PLAINTEXT) ;; *) fail "REMOTE_KAFKA_SECURITY_PROTOCOL is '${proto}': SASL_SSL or SASL_PLAINTEXT" ;; esac
[ "$proto" = SASL_PLAINTEXT ] || [ -s "${CLOUD_CA}" ] || fail "the hub link is SASL_SSL but ${CLOUD_CA#${REPO_DIR}/} (the hub's certificate) is missing"

if [ "$proto" = SASL_SSL ] && [ "${DRY}" != 1 ] && [ "${CLOUD_CA}" != "${CLOUD_CA_KEPT}" ]; then
  mkdir -p "$(dirname "${CLOUD_CA_KEPT}")"
  cp "${CLOUD_CA}" "${CLOUD_CA_KEPT}.new" && mv "${CLOUD_CA_KEPT}.new" "${CLOUD_CA_KEPT}" || fail "could not keep the hub's certificate at ${CLOUD_CA_KEPT}"
  ok "hub certificate kept at ${CLOUD_CA_KEPT#${REPO_DIR}/} for later tasks"
fi

put REMOTE_KAFKA_SECURITY_PROTOCOL "$proto"

put OPENMRS_ATOMFEED_PASSWORD "${OPENMRS_ATOMFEED_PASSWORD}"
put OPENELIS_ATOMFEED_PASSWORD "${OPENELIS_ATOMFEED_PASSWORD}"
put ODOO_ATOMFEED_PASSWORD "${ODOO_ATOMFEED_PASSWORD}"
put MYSQL_ROOT_PASSWORD "$(gen_secret)"
put OPENMRS_DB_PASSWORD "$(gen_secret)"
put ODOO_DB_PASSWORD "$(gen_secret)"
put POSTGRES_SUPERUSER_PASSWORD "$(gen_secret)"
put OPENELIS_DB_PASSWORD "$(gen_secret)"; put ODOO_SOURCE_PASSWORD "$(gen_secret)"; put CLINLIMS_SOURCE_PASSWORD "$(gen_secret)"   # the clinlims source logs in as role clinlims
put OPENELIS_DB_USERNAME clinlims; put OPENELIS_DB_USER clinlims
put DEBEZIUM_PASSWORD "$(gen_secret)"
put OPENMRS_SINK_PASSWORD "$(gen_secret)"

put ODOO_SINK_PASSWORD "$(gen_secret)"; put CLINLIMS_SINK_PASSWORD "$(gen_secret)"

DERIVED_KEYS="${IDENTITY_KEYS} CLINIC_SLUG MRN_PREFIX LAN_NAME $(sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' "${VERSIONS_FILE}" | tr '\n' ' ')"
RETIRED_KEYS="KAFKA_TOPICS KAFKA_TOPIC_PATTERNS LOCAL_CLUSTER_ALIAS MM2_REMOTE_ALIAS PHONE_NUMBER COMPOSE_PROJECT_NAME LOCAL_DEBEZIUM_PASSWORD DEBEZIUM_DB_PASSWORD LOCAL_DEBEZIUM_USER DEBEZIUM_DB_USER DATABASE_NAME DATABASE_INCLUDE_LIST TABLE_INCLUDE_LIST LOCAL_MYSQL_PASSWORD RESIDUE SITE_NUMBER BHS_LOCATION_OFFSET MYSQL_SERVER_ID ODOO_DB_VOLUME_NAME ODOO_APP_VOLUME_NAME LOCAL_MYSQL_HOST LOCAL_MYSQL_PORT LOCAL_MYSQL_DATABASE LOCAL_MYSQL_USE_SSL LOCAL_MYSQL_USER BAHMNI_MYSQL_HOST"   # dropped from an older .env: setup-mirrormaker.sh derives them
if [ -f "$E" ] && ! head -n 1 "$E" | grep -q '^# DRY-RUN RENDER'; then
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in [A-Za-z_]*=*) ;; *) continue ;; esac
    k="${line%%=*}"; v="${line#*=}"
    case "$v" in
      \"*\") v="${v#\"}"; v="${v%\"}" ;;   # env_put re-quotes
      \'*\') v="${v#\'}"; v="${v%\'}" ;;
      *) v="$(printf '%s' "$v" | sed -E 's/[[:space:]]+#.*$//')" ;;   # an unquoted value's inline comment is not part of it (compose reads it the same way)
    esac
    [ -n "$v" ] || continue
    case " ${DERIVED_KEYS} ${RETIRED_KEYS} " in *" $k "*) continue ;; esac   # derived from CLINIC_SLUG and BHS_SITE_NUMBER, or pinned in sync/versions.env
    put "$k" "$v"; n=$((n + 1))
  done < "$E"
  # An older .env's debezium password, under either retired name, is the one MySQL holds.
  if [ -z "$(env_get "$E" DEBEZIUM_PASSWORD)" ]; then
    dz="$(env_get "$E" LOCAL_DEBEZIUM_PASSWORD)"; [ -n "$dz" ] || dz="$(env_get "$E" DEBEZIUM_DB_PASSWORD)"
    [ -z "$dz" ] || put DEBEZIUM_PASSWORD "$dz"
  fi
  # Likewise the sink user's password under its old name.
  [ -n "$(env_get "$E" OPENMRS_SINK_PASSWORD)" ] || { dz="$(env_get "$E" LOCAL_MYSQL_PASSWORD)"; [ -z "$dz" ] || put OPENMRS_SINK_PASSWORD "$dz"; }
  ok "kept ${n} values from the existing ${E}"
  if [ "${DRY}" = 1 ]; then rm -f "$T"; ok "would re-render ${E}, its values kept (dry run: left as it is)"; exit 0; fi
  cp -p "$E" "${E}.prev"
fi

left="$(has_placeholders "$T" "MAIL_USER MAIL_PASSWORD" | tr '\n' ' ')"
[ -z "$left" ] || { rm -f "$T"; fail "placeholders left unfilled: ${left}"; }
chmod 600 "$T"
if [ "${DRY}" = 1 ] || [ "${ENV_SKIP_COMPOSE:-0}" = 1 ]; then
  if [ "${DRY}" = 1 ]; then
    S="$(mktemp "${CLINIC_DIR}/.env.render.XXXXXX")"
    { printf '# DRY-RUN RENDER -- written by a dry run, not a live env; the next real run moves it aside\n'; cat "$T"; } > "$S"
    chmod 600 "$S"; rm -f "$T"; T="$S"
  fi

  mv "$T" "$E"; ok "rendered ${E} (compose config gate skipped: dry run)"; exit 0
fi

setup_compose
mv "$T" "$E"
if ! compose config >/dev/null 2>"${CLINIC_DIR}/.env.render.err"; then
  mv "$E" "${CLINIC_DIR}/.env.rejected"
  [ ! -f "${E}.prev" ] || mv "${E}.prev" "$E"
  fail "compose config rejected the rendered env (kept as .env.rejected; the previous .env is back in place): $(head -c 300 "${CLINIC_DIR}/.env.render.err")"
fi

rm -f "${CLINIC_DIR}/.env.render.err" "${E}.prev"
ok "rendered ${E}; compose config passes"
