#!/usr/bin/env bash
# IPLIT's UI and config, copied out of the two images pinned in sync/versions.env
# into clinic/extracted/ (gitignored, node-local). The clinic's one nginx serves
# them and OpenMRS + OpenELIS read the same config tree -- no second web server,
# no hand-taken copy in the repo. Safe to re-run: an
# unchanged source is skipped.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "45 · UI + config from the pinned IPLIT images"
E="${CLINIC_DIR}/.env"
UI="${CLINIC_DIR}/extracted/htdocs/bahmni"; CF="${CLINIC_DIR}/extracted/bahmni_config"
[ "${DRY}" = 1 ] && { info "would: extract BAHMNI_WEB_IMAGE + BAHMNI_CONFIG_IMAGE into ${CLINIC_DIR#${REPO_DIR}/}/extracted, write prefix ${MRN_PREFIX}, point BAHMNI_UI_DIR / BAHMNI_CONFIG_DIR at it"; exit 0; }
setup_compose
# A node whose .env was rendered before this task existed (manpur, mid-install)
# gets the pins and the two paths here; on a fresh install 020 already wrote them.
versions_put "$E"
env_put "$E" BAHMNI_UI_DIR "$UI"; env_put "$E" BAHMNI_CONFIG_DIR "$CF"
ODOO_PORT="$(env_get "$E" BAHMNI_ODOO_HTTPS_PORT)"; ODOO_PORT="${ODOO_PORT:-9444}"
CT="${CT}" CLINIC_DIR="${CLINIC_DIR}" VERSIONS_FILE="${VERSIONS_FILE}" MRN_PREFIX="${MRN_PREFIX}" BAHMNI_ODOO_HTTPS_PORT="${ODOO_PORT}" \
  BAHMNI_WEB_IMAGE="$(env_get "$E" BAHMNI_WEB_IMAGE)" BAHMNI_CONFIG_IMAGE="$(env_get "$E" BAHMNI_CONFIG_IMAGE)" \
  bash "${CLINIC_DIR}/scripts/extract-ui-config.sh" || fail "extraction failed (its FAIL line is above)"
[ -f "$UI/home/index.html" ] && ok "UI: $(find "$UI" -type f | wc -l | tr -d ' ') files from $(env_get "$E" BAHMNI_WEB_IMAGE)" || fail "no UI at ${UI}"
[ -d "$CF/masterdata/configuration" ] && ok "config: $(find "$CF" -type f | wc -l | tr -d ' ') files from $(env_get "$E" BAHMNI_CONFIG_IMAGE)" || fail "no config at ${CF}"
# ocl-proof:begin
# Belt and braces on top of extract-ui-config.sh's own hold_ocl: a first boot
# imported the CIEL dictionary for hours because two OCL zips sat in the
# config tree OpenMRS reads. Prove they are really out of
# the served tree rather than trusting the extraction script's own move.
ocl_zips="$(find "$CF/masterdata/configuration/ocl" -name '*.zip' 2>/dev/null)"
if [ "${KEEP_OCL_ZIPS:-0}" = 1 ]; then
  skip "OCL dictionary zip check skipped (KEEP_OCL_ZIPS=1)"
elif [ -z "$ocl_zips" ]; then
  ocl_held="$(find "$(dirname "$CF")/ocl-held" -name '*.zip' 2>/dev/null | wc -l | tr -d ' ')"
  ok "no OCL dictionary zip in the tree OpenMRS reads (${ocl_held:-0} held aside)"
else
  fail "OCL dictionary zip(s) still in the tree OpenMRS reads -- a days-long CIEL import on a small node: $(printf '%s' "$ocl_zips" | tr '\n' ' ')"
fi
# ocl-proof:end
WL="$CF/openmrs/apps/home/whiteLabel.json"
[ -f "$WL" ] && [ "$(jq -r '.landingPage[]? | select(.name=="odoo") | .linkPort' "$WL")" = "${ODOO_PORT}" ] \
  && ok "landing page: odoo tile linkPort ${ODOO_PORT}" || fail "landing page odoo tile does not carry linkPort ${ODOO_PORT}: ${WL}"
( cd "${CLINIC_DIR}" && compose config -q ) && ok "compose config valid with the extracted paths" || fail "compose config rejects the rendered .env"
