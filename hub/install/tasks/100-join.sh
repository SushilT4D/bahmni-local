#!/usr/bin/env bash
# The hub's own authority ends here. Joining or removing a CLINIC is the
# OPERATOR's job, run from the Bahmni workspace on whatever machine reaches
# both GitHub and this hub: skills/install-clinic.sh join|leave <slug>.
# Printed, never executed -- mirrors clinic/install/tasks/110-hub-join.sh's
# own "the node's authority ends here" hand-off, from the hub's side of it.
#
# Values come from hub/.env at run time, never hardcoded. Three things this
# hub genuinely cannot know about itself are printed as placeholders, not
# invented: which SSH key/user reaches it, and where the checkout lives on
# whatever machine runs the operator tooling against it.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "100 · join hand-off (operator, from the workspace)"
[ "${DRY}" = 1 ] && { info "would: print the join/leave operator commands for this hub (HUB_KEY/HUB_SSH/HUB_REPO/HUB_GIT) and this hub's identity block (network, base containers, public listener, the L-007 caveat)"; exit 0; }
[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"
# shellcheck disable=SC1091
set -a; . "${HUB_DIR}/.env"; set +a
[ -n "${REMOTE_KAFKA_HOST:-}" ] || fail "hub/.env: REMOTE_KAFKA_HOST is empty -- task 020 should have refused to write it that way"

cat <<EOF

  This hub is installed and serving. To join a NEW clinic to it, the OPERATOR
  runs, from the Bahmni workspace, on a machine that reaches both GitHub and
  this hub:

    HUB_KEY=<path to this hub's operator SSH private key> HUB_SSH=<ssh-user>@${REMOTE_KAFKA_HOST} \\
    HUB_REPO=<path to the bahmni-local checkout on this hub> HUB_GIT=pull \\
    skills/install-clinic.sh join <slug>

  and, to make the hub forget a clinic so it can be reinstalled and joined
  anew:

    HUB_KEY=<path to this hub's operator SSH private key> HUB_SSH=<ssh-user>@${REMOTE_KAFKA_HOST} \\
    HUB_REPO=<path to the bahmni-local checkout on this hub> HUB_GIT=pull \\
    skills/install-clinic.sh leave <slug>

  This hub's identity, for the operator's own records:
    KAFKA_BASE_NETWORK    ${KAFKA_BASE_NETWORK}
    BASE_MYSQL_CONTAINER  ${BASE_MYSQL_CONTAINER}
    BASE_PG_CONTAINER     ${BASE_PG_CONTAINER}  (superuser: ${BASE_PG_SUPERUSER})
    BASE_ELIS_CONTAINER   ${BASE_ELIS_CONTAINER:-$BASE_PG_CONTAINER}  (superuser: ${BASE_ELIS_SUPERUSER:-$BASE_PG_SUPERUSER})
    public listener       SASL_PLAINTEXT://${REMOTE_KAFKA_HOST}:9092

  What this fleet cannot yet give a joining clinic: mTLS and per-site broker
  ACLs (L-007). Every clinic dials the listener above with the same
  fleet-wide SASL user.

EOF
ok "printed"
