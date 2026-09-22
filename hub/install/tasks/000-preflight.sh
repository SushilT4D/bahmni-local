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
[ "${DRY}" = 1 ] && { info "would: check the base network + containers, base MySQL/Postgres CDC fitness (binlog format/image/retention/server_id/striding, postgres major >= 10, wal_level/replication slots/senders), the ELIS Postgres too when it is a separate container, disk and memory"; exit 0; }
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

# 1b. CLOUD_MYSQL_HOST (residual fix round 2): the down-direction Debezium
# source dials this name over Docker's own resolution on KAFKA_BASE_NETWORK
# (hub_compose_env derives it from BASE_MYSQL_CONTAINER, and the two are
# meant to track each other), so it must itself name a running container --
# checked here, by name, exactly like BASE_MYSQL_CONTAINER just above,
# because nothing else in this task, 020, or 050 ever reads it. Before this
# check existed, a stale hub/.env (CLOUD_MYSQL_HOST left over from an
# earlier attempt, pointing at a container that no longer applies -- e.g.
# the documented Azure recovery, which moves BASE_MYSQL_CONTAINER but never
# mentions CLOUD_MYSQL_HOST) sailed straight through 000/020/050, and 080
# was the first thing to notice, 180s into its RUNNING wait, naming nothing
# useful. The failure below names the actual (wrong) value.
running="$(ct inspect --format '{{.State.Running}}' "$CLOUD_MYSQL_HOST" 2>/dev/null || true)"
[ "$running" = true ] && ok "down-source host ${CLOUD_MYSQL_HOST} (CLOUD_MYSQL_HOST) running" || fail "down-source host ${CLOUD_MYSQL_HOST} (CLOUD_MYSQL_HOST) running=${running:-<not found>} (want true)"

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
#
# pg_connect_ok CONTAINER SUPERUSER LABEL: before any setting is read, prove we
# can log in AT ALL, and name the role when we cannot (final review, Important
# 6). A stock Bahmni base .env carries no POSTGRES_USER, so BASE_PG_SUPERUSER
# used to default to "postgres" -- which does not exist on IPLIT's base, where
# the two bootstrap superusers are `odoo` and `clinlims`. Every read below then
# came back empty and this task failed as `pg wal_level= (want logical)`: true,
# useless, and pointing at the wrong thing entirely. psql's own error text is
# echoed (it carries no password: the connection is over the container's local
# socket) so "role \"postgres\" does not exist" reaches the operator verbatim.
pg_connect_ok(){ # CONTAINER SUPERUSER LABEL
  local c="$1" su="$2" label="$3" out
  # -d postgres: without -d, libpq defaults the database to the ROLE name, which
  # exists for postgres/odoo but not for IPLIT's clinlims (databases openelis +
  # postgres) -- the Azure rehearsal's second stop, 2026-09-18. The maintenance
  # database exists on every instance; every read here is cluster-wide.
  out="$(ct exec "$c" psql -U "$su" -d postgres -Atc 'select 1' 2>&1)" || true
  if [ "$out" = 1 ]; then
    # Connecting is not enough: task 050 creates roles and publications as this
    # role, which only a superuser may do (Azure rehearsal stop 4, 2026-09-18:
    # a stock postgres:16 OpenELIS instance has superuser postgres, and
    # clinlims is merely the database owner -- clinlims is the bootstrap
    # superuser only on IPLIT's own openelis-db image).
    local su_ok
    su_ok="$(ct exec "$c" psql -U "$su" -d postgres -Atc 'select rolsuper from pg_roles where rolname = current_user' 2>&1)" || true
    [ "$su_ok" = t ] && return 0
    fail "${label}: Postgres role \"${su}\" on ${c} connects but is not a superuser (rolsuper=${su_ok:-?}) -- set BASE_PG_SUPERUSER/BASE_ELIS_SUPERUSER to the instance's bootstrap superuser (postgres on a stock postgres image; clinlims only on IPLIT's own openelis-db image); the environment overrides the stored value on every run"
  fi
  fail "${label}: cannot connect to container ${c} as Postgres role \"${su}\" -- psql said: ${out}. Set BASE_PG_SUPERUSER/BASE_ELIS_SUPERUSER to the role that base actually bootstrapped (IPLIT's base: odoo and clinlims) in the install command's environment -- the environment overrides the stored value on every run, so this takes effect immediately on the next attempt."
}
pg_setting(){ ct exec "$BASE_PG_CONTAINER" psql -U "$BASE_PG_SUPERUSER" -d postgres -Atc "show $1"; }
pg_connect_ok "$BASE_PG_CONTAINER" "$BASE_PG_SUPERUSER" "base pg"
ok "base pg ${BASE_PG_CONTAINER} accepts role ${BASE_PG_SUPERUSER}"
# Postgres major >= 10 (final review, Minor 14): pgoutput (every source here
# uses it) arrived in 10, and so did the pg_sequences view task 050's striding
# assertion reads. IPLIT's own OpenELIS image shipped 9.6 as recently as the
# staging audit, so this is a live possibility, not a theoretical one.
pvnum="$(pg_setting server_version_num 2>/dev/null || true)"
case "$pvnum" in
  ''|*[!0-9]*) fail "pg server_version_num unreadable on ${BASE_PG_CONTAINER} (got '${pvnum}')" ;;
esac
[ "$pvnum" -ge 100000 ] && ok "pg major $((pvnum / 10000)) (>=10: pgoutput and pg_sequences)" || fail "pg major $((pvnum / 10000)) on ${BASE_PG_CONTAINER} (want >=10 -- pgoutput logical decoding and the pg_sequences view are both 10+)"
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
  elis_setting(){ ct exec "$BASE_ELIS_CONTAINER" psql -U "$elis_su" -d postgres -Atc "show $1"; }
  pg_connect_ok "$BASE_ELIS_CONTAINER" "$elis_su" "base elis"
  ok "base elis ${BASE_ELIS_CONTAINER} accepts role ${elis_su}"
  pvnum="$(elis_setting server_version_num 2>/dev/null || true)"
  case "$pvnum" in
    ''|*[!0-9]*) fail "elis server_version_num unreadable on ${BASE_ELIS_CONTAINER} (got '${pvnum}')" ;;
  esac
  [ "$pvnum" -ge 100000 ] && ok "elis pg major $((pvnum / 10000)) (>=10)" || fail "elis pg major $((pvnum / 10000)) on ${BASE_ELIS_CONTAINER} (want >=10 -- pgoutput and pg_sequences; IPLIT's stock openelis-db image is 9.6)"
  pv="$(elis_setting wal_level 2>/dev/null || true)"
  [ "$pv" = logical ] && ok "elis wal_level=${pv}" || fail "elis wal_level=${pv} (want logical)"
  pv="$(elis_setting max_replication_slots 2>/dev/null || true)"
  [ "$pv" -ge 4 ] && ok "elis max_replication_slots=${pv}" || fail "elis max_replication_slots=${pv} (want >=4)"
  pv="$(elis_setting max_wal_senders 2>/dev/null || true)"
  [ "$pv" -ge 4 ] && ok "elis max_wal_senders=${pv}" || fail "elis max_wal_senders=${pv} (want >=4)"
fi

# 4. host room -- two floors, two filesystems (Azure rehearsal stop 3,
# 2026-09-18). A base container's ROOT filesystem is the image/overlay store,
# which on a hub with a small OS disk and a big data disk is the small one;
# the disk that actually fills is the one Docker's VOLUMES live on.
# So: the volume pool is measured inside the base MySQL container at its own
# data volume's mount point (a named or anonymous volume; the image's
# VOLUME /var/lib/mysql gives one on every stock base), falling back to the
# host's DockerRootDir when the container has no volume, and to the rootfs
# figure -- with a warn -- when neither can be read (Docker Desktop's
# DockerRootDir lives inside the daemon's VM). The image store gets its own,
# smaller floor: the four hub images are ~4 GB together and a pull needs
# headroom. HUB_MIN_DISK_GB (60) and HUB_MIN_IMAGE_DISK_GB (8) are the
# documented, test-only overrides; never lower them on a real hub. Every read
# is validated as a plain digit string BEFORE the arithmetic: `$(( EMPTY /
# 1048576 ))` is a bash SYNTAX error that `fail` never gets to name.
read_avail_kb(){ # prints the available KB of a df -Pk output on stdin, or nothing
  awk 'NR==2{print $4}' | grep -E '^[0-9]+$' || true
}
root_kb="$(ct exec "$BASE_MYSQL_CONTAINER" df -Pk / 2>/dev/null | read_avail_kb)"
case "$root_kb" in
  '') fail "image store: could not read available space (ct exec ${BASE_MYSQL_CONTAINER} df -Pk / returned no numeric value)" ;;
esac
vol_mount="$(ct inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Destination}}{{"\n"}}{{end}}{{end}}' "$BASE_MYSQL_CONTAINER" 2>/dev/null | head -n 1 || true)"
pool_kb=""; pool_src=""
if [ -n "$vol_mount" ]; then
  pool_kb="$(ct exec "$BASE_MYSQL_CONTAINER" df -Pk "$vol_mount" 2>/dev/null | read_avail_kb)"
  pool_src="volume ${vol_mount} in ${BASE_MYSQL_CONTAINER}"
fi
if [ -z "$pool_kb" ]; then
  droot="$(ct info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
  [ -n "$droot" ] && pool_kb="$(df -Pk "$droot" 2>/dev/null | read_avail_kb)"
  pool_src="host ${droot:-<unknown DockerRootDir>}"
fi
if [ -z "$pool_kb" ]; then
  warn "volume pool: neither a data volume in ${BASE_MYSQL_CONTAINER} nor the host's DockerRootDir could be measured (Docker Desktop?) -- using the container rootfs figure"
  pool_kb="$root_kb"; pool_src="container rootfs of ${BASE_MYSQL_CONTAINER} (fallback)"
fi
pool_gb=$((pool_kb / 1048576)); root_gb=$((root_kb / 1048576))
min_disk_gb="${HUB_MIN_DISK_GB:-60}"; min_image_gb="${HUB_MIN_IMAGE_DISK_GB:-8}"
[ "$pool_gb" -ge "$min_disk_gb" ] && ok "disk free on the volume pool (${pool_src}): ${pool_gb} GB (want >= ${min_disk_gb})" \
  || fail "disk free on the volume pool (${pool_src}): ${pool_gb} GB (want >= ${min_disk_gb} GB) -- this is where the hub's Kafka data and the base's databases grow"
[ "$root_gb" -ge "$min_image_gb" ] && ok "disk free on the image store (container rootfs of ${BASE_MYSQL_CONTAINER}): ${root_gb} GB (want >= ${min_image_gb})" \
  || fail "disk free on the image store (container rootfs of ${BASE_MYSQL_CONTAINER}): ${root_gb} GB (want >= ${min_image_gb} GB) -- the four hub images are ~4 GB and a pull needs headroom"
# Guarded and validated as a plain digit string before the comparison, the
# same way avail_kb above is (final review, Minor 12): an unguarded
# `mem_mb="$(free -m | ...)"` followed by `[ "" -ge 4096 ]` aborts the task
# with a raw shell diagnostic instead of a named line. free(1) is Linux-only
# and every real hub is Linux, so its ABSENCE is not a failure of the host
# under test -- it means this check does not apply here (the live smoke runs
# this task for real on a Mac). A present-but-unreadable `free` still fails.
if command -v free >/dev/null 2>&1; then
  mem_mb="$(free -m 2>/dev/null | awk '/^Mem:/{print $7}')" || true
  case "$mem_mb" in
    ''|*[!0-9]*) fail "memory available: free -m returned no numeric value" ;;
  esac
  [ "$mem_mb" -ge 4096 ] && ok "memory available ${mem_mb} MB" || fail "memory available ${mem_mb} MB (want >=4096 MB)"
else
  warn "free(1) not available -- memory headroom unchecked (this check is Linux-only; every production hub is Linux)"
fi
