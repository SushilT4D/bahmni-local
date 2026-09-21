#!/usr/bin/env bash
# L-010 business identifiers: MRN and accession numbers are NOT the sync key, so
# striding does not protect them (BL-046, BL-049). OpenELIS and Odoo are set
# here (node-local SQL). The registration prefix lives in a TRACKED config file
# shared by the fleet, so it is checked and the exact edit printed, never
# written -- a dirty tree would fail every node's drift check. The idgen source
# needs a fresh UUID and a config-image rebuild; printed as a hand-step.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# `|| true`: under set -e a missing file would end the task with no FAIL line.
appjson_prefix(){ { jq -r '.config.defaultIdentifierPrefix // empty' "$1" 2>/dev/null || true; } | head -1; }
[ "${1:-}" = "--lib-only" ] && return 0 2>/dev/null

begin_task "70 · site identity (MRN ${MRN_PREFIX}, site ${SITE_NUMBER})"
# The config tree the services read: clinic/extracted/bahmni_config since task
# 045 (node-local, gitignored), else the committed clinic/bahmni_config.
CFG_DIR=""; [ -f "${CLINIC_DIR}/.env" ] && CFG_DIR="$(env_get "${CLINIC_DIR}/.env" BAHMNI_CONFIG_DIR 2>/dev/null || true)"
[ -n "$CFG_DIR" ] || CFG_DIR="${CLINIC_DIR}/bahmni_config"
APP="${CFG_DIR}/openmrs/apps/registration/app.json"
[ -f "$APP" ] || warn "registration app.json not found at ${APP#${CLINIC_DIR}/} (fixture checkout?)"
cur="$(appjson_prefix "$APP")"
if [ "$cur" = "${MRN_PREFIX}" ]; then ok "registration defaultIdentifierPrefix is ${MRN_PREFIX}"
elif [ -f "$APP" ] && case "$CFG_DIR" in "${CLINIC_DIR}/extracted/"*) true ;; *) false ;; esac; then
  # node-local tree: the prefix is this node's to write (task 045 normally has)
  if [ "${DRY}" = 1 ]; then info "would: set defaultIdentifierPrefix ${cur:-<none>} -> ${MRN_PREFIX} in ${APP#${CLINIC_DIR}/}"; else
    t="$(mktemp "${APP}.XXXXXX")"; jq --arg p "${MRN_PREFIX}" '.config.defaultIdentifierPrefix = $p' "$APP" > "$t" && chmod 644 "$t" && mv "$t" "$APP"
    check_eq "registration defaultIdentifierPrefix" "$(appjson_prefix "$APP")" "${MRN_PREFIX}"
  fi
else
  warn "registration app.json carries defaultIdentifierPrefix='${cur}', not ${MRN_PREFIX}. It is a tracked fleet file; change it on the branch, not here:"
  info "  jq '.config.defaultIdentifierPrefix = \"${MRN_PREFIX}\"' ${APP#${CLINIC_DIR}/} > /tmp/app.json && mv /tmp/app.json ${APP#${CLINIC_DIR}/}   # then commit; or make the prefix per-node (open item)"
fi
info "hand-step (idgen): add an identifierSource row with prefix ${MRN_PREFIX} and a fresh UUID $(python3 -c 'import uuid; print(uuid.uuid4())') in masterdata/configuration/idgen/identifierSource.csv, then rebuild the config image"
[ "${DRY}" = 1 ] && { info "would: set clinlims.site_information siteNumber=${SITE_NUMBER}, acessionFormat=SITEYEARNUM; set ir_sequence prefix ${MRN_PREFIX}-SO for sale.order"; exit 0; }
setup_compose
PG="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
ct exec -i "$PG" psql -U postgres -d openelis -v ON_ERROR_STOP=1 -q <<SQL
update clinlims.site_information set value='${SITE_NUMBER}' where name='siteNumber';
update clinlims.site_information set value='SITEYEARNUM' where name='acessionFormat';
SQL
sn="$(printf "select value from clinlims.site_information where name='siteNumber'" | ct exec -i "$PG" psql -U postgres -d openelis -At)"
af="$(printf "select value from clinlims.site_information where name='acessionFormat'" | ct exec -i "$PG" psql -U postgres -d openelis -At)"
check_eq "openelis siteNumber" "$sn" "${SITE_NUMBER}"; check_eq "openelis acessionFormat" "$af" "SITEYEARNUM"
printf "update ir_sequence set prefix='%s-SO' where code='sale.order'" "${MRN_PREFIX}" | ct exec -i "$PG" psql -U postgres -d odoo -q
check_eq "odoo sale.order prefix" "$(printf "select prefix from ir_sequence where code='sale.order'" | ct exec -i "$PG" psql -U postgres -d odoo -At)" "${MRN_PREFIX}-SO"
