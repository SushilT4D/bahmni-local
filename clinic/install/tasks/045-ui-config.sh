#!/usr/bin/env bash
# IPLIT's UI and config, copied out of the two images pinned in sync/versions.env
# into clinic/extracted/ (gitignored, node-local). The clinic's one nginx serves
# them and OpenMRS + OpenELIS read the same config tree -- no second web server,
# no hand-taken copy in the repo (review of 2026-09-21). Safe to re-run: an
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
CT="${CT}" CLINIC_DIR="${CLINIC_DIR}" VERSIONS_FILE="${VERSIONS_FILE}" MRN_PREFIX="${MRN_PREFIX}" \
  BAHMNI_WEB_IMAGE="$(env_get "$E" BAHMNI_WEB_IMAGE)" BAHMNI_CONFIG_IMAGE="$(env_get "$E" BAHMNI_CONFIG_IMAGE)" \
  bash "${CLINIC_DIR}/scripts/extract-ui-config.sh" || fail "extraction failed (its FAIL line is above)"
[ -f "$UI/home/index.html" ] && ok "UI: $(find "$UI" -type f | wc -l | tr -d ' ') files from $(env_get "$E" BAHMNI_WEB_IMAGE)" || fail "no UI at ${UI}"
[ -d "$CF/masterdata/configuration" ] && ok "config: $(find "$CF" -type f | wc -l | tr -d ' ') files from $(env_get "$E" BAHMNI_CONFIG_IMAGE)" || fail "no config at ${CF}"
( cd "${CLINIC_DIR}" && compose config -q ) && ok "compose config valid with the extracted paths" || fail "compose config rejects the rendered .env"
