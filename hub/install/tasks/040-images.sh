#!/usr/bin/env bash
# Images the hub's compose project needs. All of them are public (unlike the
# clinic, the hub builds nothing locally, so there is no bahmni-local/* name
# to skip). Nothing else for this task to do: the hub's kafka-connect mounts
# no config/kafka-connect/ext (no Groovy/Debezium-scripting jars to fetch --
# that mount is clinic-only), and the JDBC sink itself needs no jar of its
# own -- it is Debezium's BUNDLED io.debezium.connector.jdbc.JdbcSinkConnector,
# already inside DEBEZIUM_CONNECT_IMAGE. Task 070 confirms all three connect
# plugin classes once kafka-connect is actually running.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "40 · images"
[ "${DRY}" = 1 ] && { info "would: pull every image in compose config --images"; exit 0; }
setup_compose
[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"

# Pull every image compose resolves. compose runs in HUB_DIR (lib.sh's
# CLINIC_DIR override), so docker/podman compose auto-loads hub/.env for the
# ${KAFKA_IMAGE}/${SCHEMA_REGISTRY_IMAGE}/${DEBEZIUM_CONNECT_IMAGE} pins --
# never a literal tag here. Per-image pull (not `compose pull`, which is
# all-or-nothing) skips what is already present and retries a transient
# failure a few times before giving up on that one image.
for img in $(compose config --images 2>/dev/null | sort -u); do
  ct image inspect "$img" >/dev/null 2>&1 && continue
  for attempt in 1 2 3; do
    if ct pull "$img"; then break; fi
    warn "pull ${img} attempt ${attempt}/3 failed; retrying in 10s"; sleep 10
  done
done
missing=""
for img in $(compose config --images 2>/dev/null | sort -u); do ct image inspect "$img" >/dev/null 2>&1 || missing="$missing $img"; done
[ -z "$missing" ] && ok "every image present ($(compose config --images 2>/dev/null | sort -u | wc -l | tr -d ' '))" || fail "images missing:${missing}"
