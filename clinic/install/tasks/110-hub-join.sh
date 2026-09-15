#!/usr/bin/env bash
# The clinic's authority ends here. The hub side is the operator's, from the
# workspace: skills/install-clinic.sh join <slug>. Printed, never executed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "110 · hub join (operator, from the workspace)"
cat <<EOF

  This node is installed and syncing locally. To join the hub, the OPERATOR runs,
  from the Bahmni workspace on a machine that reaches both GitHub and the hub:

    skills/install-clinic.sh join ${CLINIC_SLUG}

  which does, in order:
    1. appends to cloud/clinics.conf:   ${CLINIC_SLUG}:mysql-sink-${CLINIC_SLUG}-:${LOCAL_CLUSTER_ALIAS}:${MYSQL_SERVER_NAME}
       commits and pushes feat/bahmni-kraft, pushes the tracking ref into the hub, fast-forwards the hub
    2. on the hub:  cd cloud && scripts/generate-sink-connectors.sh ${CLINIC_SLUG} && scripts/register-all-sink-connectors.sh
    3. on the hub:  the Odoo and clinlims up-sinks for ${CLINIC_SLUG} (copies of Ghated's, topics ${LOCAL_CLUSTER_ALIAS}.${MYSQL_SERVER_NAME}.odoo.all / .clinlims.all)
    4. proof: a marker written here is read on the hub within a minute

  What this fleet cannot yet give a clinic: mTLS and per-site broker ACLs (L-007).
  This node dials ${REMOTE_KAFKA_BOOTSTRAP_SERVERS} with the fleet-wide SASL user.

EOF
ok "printed"
