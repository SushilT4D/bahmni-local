#!/usr/bin/env bash
# Sets this clinic's own identifiers: patient ID prefix, lab accession numbers, Odoo sequences.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

appjson_prefix(){ { jq -r '.config.defaultIdentifierPrefix // empty' "$1" 2>/dev/null || true; } | head -1; }

lab_site_code(){ case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1 ] && [ "$1" -le 99999 ] || return 1; printf '%05d' "$((10#$1))"; }
[ "${1:-}" = "--lib-only" ] && return 0 2>/dev/null

begin_task "70 · site identity (MRN ${MRN_PREFIX}, site ${BHS_SITE_NUMBER})"

CFG_DIR=""; [ -f "${CLINIC_DIR}/.env" ] && CFG_DIR="$(env_get "${CLINIC_DIR}/.env" BAHMNI_CONFIG_DIR 2>/dev/null || true)"
[ -n "$CFG_DIR" ] || CFG_DIR="${CLINIC_DIR}/extracted/bahmni_config"
APP="${CFG_DIR}/openmrs/apps/registration/app.json"
node_local=0; case "$CFG_DIR" in "${CLINIC_DIR}/extracted/"*) node_local=1 ;; esac
if [ ! -f "$APP" ]; then
  if [ "$node_local" = 1 ] && [ "${DRY}" != 1 ]; then
    fail "no registration app.json under ${CFG_DIR#${CLINIC_DIR}/}: the UI/config extraction has not run -- resume with --from 045"
  elif [ "$node_local" = 1 ]; then info "would: find ${APP#${CLINIC_DIR}/} written by task 045, prefix ${MRN_PREFIX}"
  else warn "registration app.json not found at ${APP#${CLINIC_DIR}/} (fixture checkout?)"; fi
fi

cur="$(appjson_prefix "$APP")"
if [ "$cur" = "${MRN_PREFIX}" ]; then ok "registration defaultIdentifierPrefix is ${MRN_PREFIX}"
elif [ ! -f "$APP" ] && [ "$node_local" = 1 ]; then :   # said above (dry run)
elif [ -f "$APP" ] && [ "$node_local" = 1 ]; then
  if [ "${DRY}" = 1 ]; then info "would: set defaultIdentifierPrefix ${cur:-<none>} -> ${MRN_PREFIX} in ${APP#${CLINIC_DIR}/}"; else
    t="$(mktemp "${APP}.XXXXXX")"; jq --arg p "${MRN_PREFIX}" '.config.defaultIdentifierPrefix = $p' "$APP" > "$t" && chmod 644 "$t" && mv "$t" "$APP"
    check_eq "registration defaultIdentifierPrefix" "$(appjson_prefix "$APP")" "${MRN_PREFIX}"
  fi
else
  warn "registration app.json carries defaultIdentifierPrefix='${cur}', not ${MRN_PREFIX}. It is a tracked fleet file; change it on the branch, not here:"
  info "  jq '.config.defaultIdentifierPrefix = \"${MRN_PREFIX}\"' ${APP#${CLINIC_DIR}/} > /tmp/app.json && mv /tmp/app.json ${APP#${CLINIC_DIR}/}   # then commit; or make the prefix per-node (open item)"
fi

info "hand-step (idgen): add an identifierSource row with prefix ${MRN_PREFIX} and a fresh UUID $(python3 -c 'import uuid; print(uuid.uuid4())') in masterdata/configuration/idgen/identifierSource.csv, then rebuild the config image"
SITE_CODE="$(lab_site_code "${BHS_SITE_NUMBER}")" || fail "BHS_SITE_NUMBER='${BHS_SITE_NUMBER}' is not a site number from 1 to 99999: OpenELIS's lab numbers start with it"
[ "${DRY}" = 1 ] && { info "would: set clinlims.site_information siteNumber=${SITE_CODE}, acessionFormat=SITEYEARNUM; set ir_sequence prefix ${MRN_PREFIX}-SO for sale.order"; exit 0; }
setup_compose
PG="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
ct exec -i "$PG" psql -U postgres -d openelis -v ON_ERROR_STOP=1 -q <<SQL
update clinlims.site_information set value='${SITE_CODE}' where name='siteNumber';
update clinlims.site_information set value='SITEYEARNUM' where name='acessionFormat';
SQL
sn="$(printf "select value from clinlims.site_information where name='siteNumber'" | ct exec -i "$PG" psql -U postgres -d openelis -At)"
af="$(printf "select value from clinlims.site_information where name='acessionFormat'" | ct exec -i "$PG" psql -U postgres -d openelis -At)"
check_eq "openelis siteNumber" "$sn" "${SITE_CODE}"; check_eq "openelis acessionFormat" "$af" "SITEYEARNUM"
printf "update ir_sequence set prefix='%s-SO' where code='sale.order'" "${MRN_PREFIX}" | ct exec -i "$PG" psql -U postgres -d odoo -q
check_eq "odoo sale.order prefix" "$(printf "select prefix from ir_sequence where code='sale.order'" | ct exec -i "$PG" psql -U postgres -d odoo -At)" "${MRN_PREFIX}-SO"
