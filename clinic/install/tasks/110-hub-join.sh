#!/usr/bin/env bash
# Prints the command the operator runs on the hub to join this clinic. Runs nothing on the hub.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "110 · hub join (operator, from the workspace)"

if [ "${DRY}" = 1 ]; then
  info "would: print the steps the operator runs to join this clinic to the hub"
  exit 0
fi

seed_hub=""
[ -n "${SEED_DIR:-}" ] && [ -f "${SEED_DIR}/manifest.env" ] && seed_hub="$(sed -n 's/^HUB_SSH=//p' "${SEED_DIR}/manifest.env" | tail -1)"
cat <<EOF

  This node is installed and syncing locally. To join it to the hub it was
  seeded from, the OPERATOR runs the fleet's join tool on a machine that
  reaches both GitHub and the hub (the hub's ssh key and checkout path are the
  operator's; the seed folder is the one this node was seeded from):

    HUB_SSH=${seed_hub:-<operator>@<hub>} HUB_KEY=<the hub's ssh key> HUB_REPO=<the bahmni-local checkout on the hub> HUB_GIT=pull \\
      SEED_MANIFEST=<the seed folder>/manifest.env install-clinic.sh join ${CLINIC_SLUG}

  which does, in order:
    1. on the hub: pulls this repo (${CLINIC_SLUG} is already in sync/clinics.txt) and creates this node's
       replication origins, clinic_${CLINIC_SLUG}_odoo and clinic_${CLINIC_SLUG}_clinlims
    2. on the hub: generates and registers this node's sinks (openmrs-${CLINIC_SLUG}-sink,
       odoo-${CLINIC_SLUG}-sink, clinlims-${CLINIC_SLUG}-sink) and proves a marker written here is read there

  The node is joined when, with the same HUB_* settings,

    install-clinic.sh status ${CLINIC_SLUG}

  ends with "<n> of <n> sinks registered and RUNNING" and exits 0. A join made to
  another hub, or never made, ends there as a FAIL naming what is missing.

  What this fleet cannot yet give a clinic: mTLS and per-site broker ACLs.
  This node dials ${REMOTE_KAFKA_BOOTSTRAP_SERVERS} with the fleet-wide SASL user.

EOF
ok "printed"
