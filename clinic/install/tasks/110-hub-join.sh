#!/usr/bin/env bash
# Prints the steps the operator runs on the hub to join this clinic (cloud/SETUP.md, "Per clinic"). Runs nothing on the hub.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "110 · hub join (operator, on the hub)"

if [ "${DRY}" = 1 ]; then
  info "would: print the steps the operator runs to join this clinic to the hub"
  exit 0
fi

cat <<EOF

  This node is installed and syncing locally. To join it to the hub, the
  OPERATOR follows "Per clinic" in cloud/SETUP.md on the hub, with SLUG=${CLINIC_SLUG}
  (${CLINIC_SLUG} is already in sync/clinics.json):
    1. creates this node's replication origins, clinic_${CLINIC_SLUG}_odoo and
       clinic_${CLINIC_SLUG}_clinlims
    2. creates its topics, ${CLINIC_SLUG}.bahmni-${CLINIC_SLUG}.<openmrs|odoo|clinlims>.all
    3. generates and registers its sinks (openmrs-${CLINIC_SLUG}-sink,
       odoo-${CLINIC_SLUG}-sink, clinlims-${CLINIC_SLUG}-sink)

  The node is joined when that section's last step lists all three sinks RUNNING.

  What this fleet cannot yet give a clinic: mTLS and per-site broker ACLs.
  This node dials ${REMOTE_KAFKA_BOOTSTRAP_SERVERS} with the fleet-wide SASL user.

EOF
ok "printed"
