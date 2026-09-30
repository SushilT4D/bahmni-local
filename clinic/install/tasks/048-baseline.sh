#!/usr/bin/env bash
# phase: install
# The disposable data this machine runs on until it is seeded. From the
# operator's --baseline folder when given, else extracted from the pinned
# baseline images into clinic/extracted/baseline/.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "48 · baseline data"
B="${CLINIC_DIR}/extracted/baseline"
if [ -n "${BASELINE_DIR:-}" ]; then
  info "baseline from the operator's folder ${BASELINE_DIR}"
  [ "${DRY}" = 1 ] && { info "would: copy ${BASELINE_DIR}/{openmrs,odoo,openelis}.sql.gz to ${B}"; exit 0; }
  mkdir -p "$B"; for f in openmrs odoo openelis; do cp "${BASELINE_DIR}/$f.sql.gz" "$B/$f.sql.gz" || fail "${BASELINE_DIR}/$f.sql.gz missing"; done
else
  [ "${DRY}" = 1 ] && { info "would: extract the three baseline dumps from ${BASELINE_OPENMRS_IMAGE:-?} ${BASELINE_ODOO_IMAGE:-?} ${BASELINE_OPENELIS_IMAGE:-?} into ${B}"; exit 0; }
  setup_compose; E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
  CT="${CT}" bash "${CLINIC_DIR}/scripts/extract-baseline.sh" "$B" || fail "baseline extraction failed (above); --baseline <dir> supplies the three dumps instead"
fi
for f in openmrs odoo openelis; do gzip -t "$B/$f.sql.gz" 2>/dev/null || fail "baseline $f.sql.gz missing or not gzip in ${B}"; done
ok "baseline: three dumps in ${B} ($(du -sh "$B" | cut -f1))"
