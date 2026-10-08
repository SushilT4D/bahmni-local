#!/usr/bin/env bash
# phase: seed
# The clinic's authority ends here. The hub side is the operator's, from the
# workspace: skills/install-clinic.sh join <slug>. Printed, never executed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "110 · hub join (operator, from the workspace)"
# provenance:begin
# Before the hub is asked to take this clinic: its master tables are still the
# ones of the seed it was built from (same rows, same content, read with the
# same tool the hub's record was computed with). A clinic seeded from another
# dump, or one whose masters changed after the seed, is refused here, naming
# the first table that differs.
. "${INSTALL_DIR}/state.sh"
if [ "${DRY}" = 1 ]; then
  info "would: compare this clinic's master tables with the seed's provenance record (${PROVENANCE_COPY})"
else
  [ -s "${PROVENANCE_COPY}" ] || fail "no seed provenance record on this machine (${PROVENANCE_COPY}); the seed gate keeps one. Rerun the seed from its gate (seed.sh --seed <folder> --from 005) or call the operator."
  [ "$(sha256_of "${PROVENANCE_COPY}")" = "$(stamp_get PROVENANCE_SHA)" ] || fail "the seed provenance record on this machine (${PROVENANCE_COPY}) is not the one the seed gate kept; call the operator."
  setup_compose; E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
  lines="$(provenance_content_lines "${PROVENANCE_COPY}" "${COMPOSE_PROJECT_NAME}-bahmni-mysql-1")" || fail "could not checksum this clinic's master tables (clinic/scripts/master-checksum.sh failed above)"
  v="$(provenance_content_verdict "${PROVENANCE_COPY}" "$lines" "$(sha256_of "${REPO_DIR}/clinic/scripts/master-checksum.sh")" "${REPO_DIR}/hub/checksum-exclusions.conf")" || fail "$v"
  ok "${v#ok }"
fi
# provenance:end
cat <<EOF

  This node is installed and syncing locally. To join the hub, the OPERATOR runs,
  from the Bahmni workspace on a machine that reaches both GitHub and the hub:

    skills/install-clinic.sh join ${CLINIC_SLUG}

  which does, in order:
    1. appends to hub/clinics.conf:   ${CLINIC_SLUG}:mysql-sink-${CLINIC_SLUG}-:${LOCAL_CLUSTER_ALIAS}:${MYSQL_SERVER_NAME}
       commits and pushes the install branch, pushes the tracking ref into the hub, fast-forwards the hub
    2. on the hub:  cd hub && scripts/generate-sink-connectors.sh ${CLINIC_SLUG} && scripts/register-all-sink-connectors.sh
    3. on the hub:  the Odoo and clinlims up-sinks for ${CLINIC_SLUG} (copies of Ghated's, topics ${LOCAL_CLUSTER_ALIAS}.${MYSQL_SERVER_NAME}.odoo.all / .clinlims.all)
    4. proof: a marker written here is read on the hub within a minute

  What this fleet cannot yet give a clinic: mTLS and per-site broker ACLs.
  This node dials ${REMOTE_KAFKA_BOOTSTRAP_SERVERS} with the fleet-wide SASL user.

EOF
ok "printed"
