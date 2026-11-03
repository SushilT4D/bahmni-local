#!/usr/bin/env bash
# phase: seed
# The clinic's authority ends here. The hub side is the operator's: the fleet's
# join tool, install-clinic.sh join <slug>. Printed, never executed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "110 · hub join (operator, from the workspace)"
# This clinic's master tables and foreign keys were compared with the seed's
# provenance record at the start of task 090, before its sync layer took any of
# the hub's changes. They are not compared again here: from 090 on the hub's
# master changes arrive by sync, so a difference now is expected, not a fault.
if [ "${DRY}" = 1 ]; then
  # nothing is installed or syncing in a dry run, so the join steps are not printed as if it were
  info "would: print the steps the operator runs to join this clinic to the hub"
  exit 0
fi
# The hub this node was seeded from: the seed's manifest names it. The join is
# made against that hub, and only it: a join to another one would leave this
# node's changes with nobody receiving them.
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
    1. appends to hub/clinics.<hub>.conf:   ${CLINIC_SLUG}:mysql-sink-${CLINIC_SLUG}-:${LOCAL_CLUSTER_ALIAS}:${MYSQL_SERVER_NAME}$( [ "${CLINICAL_UP_SYNC:-off}" = test ] && printf ':clinical' )
       and this node's id floors from the seed to hub/clinic-floors.<hub>.conf; commits and pushes; the hub fast-forwards
    2. on the hub: registers exactly this node's sinks (its MySQL up-sinks, odoo-${CLINIC_SLUG}-sink-all,
       clinlims-${CLINIC_SLUG}-sink-all) and proves a marker written here is read there

  The node is joined when, with the same HUB_* settings,

    install-clinic.sh status ${CLINIC_SLUG}

  ends with "<n> of <n> sinks registered and RUNNING" and exits 0. A join made to
  another hub, or never made, ends there as a FAIL naming what is missing.

  What this fleet cannot yet give a clinic: mTLS and per-site broker ACLs.
  This node dials ${REMOTE_KAFKA_BOOTSTRAP_SERVERS} with the fleet-wide SASL user.

EOF
ok "printed"
