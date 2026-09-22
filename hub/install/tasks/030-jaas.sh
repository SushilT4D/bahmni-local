#!/usr/bin/env bash
# The broker's SASL/PLAIN JAAS file, generated from hub/.env at install time --
# never hand-written and never committed: a JAAS file carries literal passwords,
# and this repo is public. Also stakes out hub/connectors/, where task 040 lands the Kafka
# Connect plugin jars the kafka-connect service mounts read-only.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "30 · JAAS + directories"
[ "${DRY}" = 1 ] && { info "would: write ${HUB_DIR}/kafka_server_jaas.conf (mode 600) for admin+mirrormaker, mkdir -p ${HUB_DIR}/connectors"; exit 0; }

[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"
# shellcheck disable=SC1091
set -a; . "${HUB_DIR}/.env"; set +a

write_jaas "${HUB_DIR}/kafka_server_jaas.conf" "$KAFKA_ADMIN_PASSWORD" "$REMOTE_KAFKA_PASSWORD"
mkdir -p "${HUB_DIR}/connectors"

mode="$(stat -c %a "${HUB_DIR}/kafka_server_jaas.conf" 2>/dev/null || stat -f %Lp "${HUB_DIR}/kafka_server_jaas.conf")"
[ "$mode" = 600 ] || fail "kafka_server_jaas.conf mode is ${mode}, want 600"
n="$(grep -cE '^    user_(admin|mirrormaker)=' "${HUB_DIR}/kafka_server_jaas.conf" || true)"
[ "$n" = 2 ] || fail "kafka_server_jaas.conf has ${n} user_ line(s) matching user_admin=/user_mirrormaker=, want 2"
ok "JAAS written for admin and mirrormaker (mode ${mode})"
