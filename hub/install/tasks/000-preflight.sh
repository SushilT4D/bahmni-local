#!/usr/bin/env bash
# Everything that can refuse, refuses here, before the hub's own compose
# project is touched: the base network and containers exist, the base MySQL
# and Postgres are fit for a Debezium source at the hub's residue (0), and the
# host has room. mysql_setting/pg_setting read through the base containers
# (docker exec, values only) and are meant to be reused by tasks 050 and 090,
# which touch the same base stack for the same reason.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "0 · preflight"
[ "${DRY}" = 1 ] && { info "would: check the base network + containers, base MySQL/Postgres CDC fitness (binlog format/image/retention/server_id/striding, wal_level/replication slots/senders), disk and memory"; exit 0; }
setup_compose

[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"
# shellcheck disable=SC1091
set -a; . "${HUB_DIR}/.env"; set +a

# 1. the base stack's network and the two containers we're about to exec into
ct network inspect "$KAFKA_BASE_NETWORK" >/dev/null && ok "base network ${KAFKA_BASE_NETWORK} exists" || fail "base network ${KAFKA_BASE_NETWORK} not found"
running="$(ct inspect --format '{{.State.Running}}' "$BASE_MYSQL_CONTAINER" 2>/dev/null || true)"
[ "$running" = true ] && ok "base mysql container ${BASE_MYSQL_CONTAINER} running" || fail "base mysql container ${BASE_MYSQL_CONTAINER} running=${running:-<not found>} (want true)"
running="$(ct inspect --format '{{.State.Running}}' "$BASE_PG_CONTAINER" 2>/dev/null || true)"
[ "$running" = true ] && ok "base pg container ${BASE_PG_CONTAINER} running" || fail "base pg container ${BASE_PG_CONTAINER} running=${running:-<not found>} (want true)"

# 2. base MySQL: fit for a Debezium source at residue 0 (root password comes
# from the container's own environment -- MYSQL_PWD is expanded by the sh
# inside the container, never by us, so it never appears on a command line).
mysql_setting(){ printf 'select @@%s' "$1" | ct exec -i "$BASE_MYSQL_CONTAINER" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N'; }
mf="$(mysql_setting binlog_format)"
mi="$(mysql_setting binlog_row_image)"
mr="$(mysql_setting binlog_expire_logs_seconds 2>/dev/null || true)"
if [ -z "$mr" ]; then
  # MySQL 5.6 (the Azure hub's base image) has no binlog_expire_logs_seconds;
  # expire_logs_days is its retention knob, in days.
  med="$(mysql_setting expire_logs_days 2>/dev/null || true)"
  mr=$(( med * 86400 ))
fi
ms="$(mysql_setting server_id)"
minc="$(mysql_setting auto_increment_increment)"
moff="$(mysql_setting auto_increment_offset)"
bad="$(binlog_ok "$mf" "$mi" "$mr" "$ms" "$minc" "$moff" "$CLOUD_DEBEZIUM_SERVER_ID")" \
  && ok "base mysql fit: binlog_format=${mf} binlog_row_image=${mi} retention=${mr}s server_id=${ms} auto_increment_increment/offset=${minc}/${moff}" \
  || fail "base mysql unfit:${bad}"

# 3. base Postgres: logical replication headroom
pg_setting(){ ct exec "$BASE_PG_CONTAINER" psql -U "$BASE_PG_SUPERUSER" -Atc "show $1"; }
pv="$(pg_setting wal_level)"
[ "$pv" = logical ] && ok "pg wal_level=${pv}" || fail "pg wal_level=${pv} (want logical)"
pv="$(pg_setting max_replication_slots)"
[ "$pv" -ge 4 ] && ok "pg max_replication_slots=${pv}" || fail "pg max_replication_slots=${pv} (want >=4)"
pv="$(pg_setting max_wal_senders)"
[ "$pv" -ge 4 ] && ok "pg max_wal_senders=${pv}" || fail "pg max_wal_senders=${pv} (want >=4)"

# 4. host room (Linux-first: this installer's rehearsal and production targets
# are both Linux hubs; df -Pk is POSIX-portable, free -m is Linux-only)
root_dir="$(ct info --format '{{.DockerRootDir}}')"
avail_gb="$(( $(df -Pk "$root_dir" | awk 'NR==2{print $4}') / 1048576 ))"
[ "$avail_gb" -ge 60 ] && ok "disk free at ${root_dir}: ${avail_gb} GB" || fail "disk free at ${root_dir}: ${avail_gb} GB (want >=60 GB)"
mem_mb="$(free -m | awk '/^Mem:/{print $7}')"
[ "$mem_mb" -ge 4096 ] && ok "memory available ${mem_mb} MB" || fail "memory available ${mem_mb} MB (want >=4096 MB)"
