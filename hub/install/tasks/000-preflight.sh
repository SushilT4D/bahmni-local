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
[ "${DRY}" = 1 ] && { info "would: check the base network + containers, base MySQL/Postgres CDC fitness (binlog format/image/retention/server_id/striding, wal_level/replication slots/senders), the ELIS Postgres too when it is a separate container, disk and memory"; exit 0; }
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
# Every read below is guarded (2>/dev/null || true), same as the retention
# read: under set -e a bare x="$(failing_cmd)" aborts right there with a
# generic trap message and never reaches the ok/fail line below it -- a
# rotated root password or a container that died between the running-check
# above and here must still produce a clean, named fail, not a trap (F-068
# class). binlog_ok already treats an empty value as unfit and reports it by
# name, so a guarded-empty read here still ends in a clean fail line.
mysql_setting(){ printf 'select @@%s' "$1" | ct exec -i "$BASE_MYSQL_CONTAINER" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N'; }
mf="$(mysql_setting binlog_format 2>/dev/null || true)"
mi="$(mysql_setting binlog_row_image 2>/dev/null || true)"
mr="$(mysql_setting binlog_expire_logs_seconds 2>/dev/null || true)"
if [ -z "$mr" ]; then
  # MySQL 5.6 (the Azure hub's base image) has no binlog_expire_logs_seconds;
  # expire_logs_days is its retention knob, in days.
  med="$(mysql_setting expire_logs_days 2>/dev/null || true)"
  mr=$(( med * 86400 ))
fi
ms="$(mysql_setting server_id 2>/dev/null || true)"
minc="$(mysql_setting auto_increment_increment 2>/dev/null || true)"
moff="$(mysql_setting auto_increment_offset 2>/dev/null || true)"
bad="$(binlog_ok "$mf" "$mi" "$mr" "$ms" "$minc" "$moff" "$CLOUD_DEBEZIUM_SERVER_ID")" \
  && ok "base mysql fit: binlog_format=${mf} binlog_row_image=${mi} retention=${mr}s server_id=${ms} auto_increment_increment/offset=${minc}/${moff}" \
  || fail "base mysql unfit:${bad}"

# 3. base Postgres: logical replication headroom (reads guarded, same reason as above)
pg_setting(){ ct exec "$BASE_PG_CONTAINER" psql -U "$BASE_PG_SUPERUSER" -Atc "show $1"; }
pv="$(pg_setting wal_level 2>/dev/null || true)"
[ "$pv" = logical ] && ok "pg wal_level=${pv}" || fail "pg wal_level=${pv} (want logical)"
pv="$(pg_setting max_replication_slots 2>/dev/null || true)"
[ "$pv" -ge 4 ] && ok "pg max_replication_slots=${pv}" || fail "pg max_replication_slots=${pv} (want >=4)"
pv="$(pg_setting max_wal_senders 2>/dev/null || true)"
[ "$pv" -ge 4 ] && ok "pg max_wal_senders=${pv}" || fail "pg max_wal_senders=${pv} (want >=4)"

# 3b. base ELIS Postgres (Ruling 11 / R5, code review fold-in Task 6/7 review):
# only when the base runs OpenELIS on its OWN Postgres container, separate
# from Odoo's (IPLIT's real hub) -- hub_compose_env always defaults
# BASE_ELIS_CONTAINER from BASE_PG_CONTAINER, so on the mini and every clinic
# this collapses to the identical container already proven fit above and the
# block below is skipped as a pure no-op.
if [ -n "${BASE_ELIS_CONTAINER:-}" ] && [ "${BASE_ELIS_CONTAINER}" != "${BASE_PG_CONTAINER}" ]; then
  elis_su="${BASE_ELIS_SUPERUSER:-$BASE_PG_SUPERUSER}"
  running="$(ct inspect --format '{{.State.Running}}' "$BASE_ELIS_CONTAINER" 2>/dev/null || true)"
  [ "$running" = true ] && ok "base elis container ${BASE_ELIS_CONTAINER} running" || fail "base elis container ${BASE_ELIS_CONTAINER} running=${running:-<not found>} (want true)"
  elis_setting(){ ct exec "$BASE_ELIS_CONTAINER" psql -U "$elis_su" -Atc "show $1"; }
  pv="$(elis_setting wal_level 2>/dev/null || true)"
  [ "$pv" = logical ] && ok "elis wal_level=${pv}" || fail "elis wal_level=${pv} (want logical)"
  pv="$(elis_setting max_replication_slots 2>/dev/null || true)"
  [ "$pv" -ge 4 ] && ok "elis max_replication_slots=${pv}" || fail "elis max_replication_slots=${pv} (want >=4)"
  pv="$(elis_setting max_wal_senders 2>/dev/null || true)"
  [ "$pv" -ge 4 ] && ok "elis max_wal_senders=${pv}" || fail "elis max_wal_senders=${pv} (want >=4)"
fi

# 4. host room (Linux-first: this installer's rehearsal and production targets
# are both Linux hubs; df -Pk is POSIX-portable, free -m is Linux-only). Read
# and validated as a plain digit string BEFORE the arithmetic (found live
# while proving task 090 the same way): on a host where DockerRootDir names a
# path only the docker daemon's own VM can see (Docker Desktop on macOS, not
# a production Linux hub), `df -Pk` fails and prints nothing, and
# `$(( EMPTY / 1048576 ))` is a bash arithmetic SYNTAX error that `fail`
# never gets a chance to name -- unlike a guarded `[ "$pv" -ge N ]` read,
# which just returns false, this aborts the whole task with a raw shell error.
root_dir="$(ct info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
[ -n "$root_dir" ] || fail "docker root dir unreadable (ct info --format '{{.DockerRootDir}}' returned nothing)"
avail_kb="$(df -Pk "$root_dir" 2>/dev/null | awk 'NR==2{print $4}' || true)"
case "$avail_kb" in
  ''|*[!0-9]*) fail "disk free at ${root_dir}: could not read available space (df -Pk returned no numeric value -- on Docker Desktop, DockerRootDir names a path inside the VM, not this host's own filesystem)" ;;
esac
avail_gb=$((avail_kb / 1048576))
[ "$avail_gb" -ge 60 ] && ok "disk free at ${root_dir}: ${avail_gb} GB" || fail "disk free at ${root_dir}: ${avail_gb} GB (want >=60 GB)"
mem_mb="$(free -m | awk '/^Mem:/{print $7}')"
[ "$mem_mb" -ge 4096 ] && ok "memory available ${mem_mb} MB" || fail "memory available ${mem_mb} MB (want >=4096 MB)"
