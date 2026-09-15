#!/usr/bin/env bash
# Node-local preflight (F-007, F-017, F-022, F-043, F-050): VM disk and memory,
# MySQL wait_timeout floor, PG replication-slot retention, Kafka reachable,
# connector task states. Exit 1 if any floor is breached.
#
# Usage: scripts/preflight.sh
#
# RUNS ENTIRELY ON THIS NODE. It takes no node name and opens no SSH connection.
#
# WHY. Until 2026-09-14 this script fanned out to all three lab nodes over SSH
# and carried, in a PUBLIC repo, the hub's hostname and the path to one
# developer's private key. Nothing the clinic stack runs needs SSH -- the
# resolved compose config references it zero times -- and a clinic reaches the
# hub over Kafka, not a shell. Under L-007 that transport is meant to be mTLS
# with per-site ACLs confining each site to its own topics; shell access from
# every clinic to the hub is far wider than the architecture grants, and
# shipping it to six clinics makes the hub shell-reachable from all of them.
#
# The three-node fan-out now lives with the operator, in the Bahmni workspace
# repo (skills/lab-preflight.sh), which SSHes to each node and runs THIS script
# there. Checks live here, once; only the operator wrapper knows node names.
set -u

DISK_FLOOR_GB=${DISK_FLOOR_GB:-5}
MEM_FLOOR_MB=${MEM_FLOOR_MB:-1024}
WAIT_FLOOR=${WAIT_FLOOR:-28800}
SLOT_FLOOR_MB=${SLOT_FLOOR_MB:-2048}

# Service names, not container names: the container carries the compose project
# prefix, which differs per node (bahmni-local-*, bahmni-ghated-*).
MYSQL_SERVICE=${MYSQL_SERVICE:-bahmni-mysql}
PG_SERVICE=${PG_SERVICE:-bahmni-postgres}
PG_USER=${PG_USER:-odoo}
PG_DB=${PG_DB:-openelis}
KAFKA_SERVICE=${KAFKA_SERVICE:-kafka}
KAFKA_BOOTSTRAP=${KAFKA_BOOTSTRAP:-localhost:9092}
CONNECT_URL=${CONNECT_URL:-localhost:8083}

rc=0
bad(){ echo "  FAIL $*"; rc=1; }
ok(){  echo "  ok   $*"; }

# Container engine: Rawach runs docker, Ghated podman. Detect, never assume.
CT=${CONTAINER_TOOL:-}
if [ -z "$CT" ]; then
  for c in docker podman; do command -v "$c" >/dev/null 2>&1 && { "$c" ps >/dev/null 2>&1 && CT=$c && break; }; done
fi
[ -n "$CT" ] || { echo "  FAIL no working container engine (tried docker, podman)"; exit 1; }
echo "== $(hostname -s) ($CT) =="

# Resolve a compose service to its actual container name on this node.
resolve(){ "$CT" ps --format '{{.Names}}' 2>/dev/null \
  | grep -E "(^|[-_])$1([-_][0-9]+)?$" | head -1; }

MY=$(resolve "$MYSQL_SERVICE"); PG=$(resolve "$PG_SERVICE"); KF=$(resolve "$KAFKA_SERVICE")

# --- VM disk + memory -------------------------------------------------------
# The container VM, not the host: on macOS the engine runs in a Linux VM and it
# is that VM's disk that fills. nsenter into pid 1 reads the VM's own view.
read -r disk mem <<< "$("$CT" run --rm --privileged --pid=host alpine:3.20 nsenter -t 1 -m -u -n -i \
  sh -c 'echo $(df -m /var/lib/docker 2>/dev/null | tail -1 | awk "{print \$4}") $(free -m | awk "NR==2{print \$7}")' 2>/dev/null)"
probe="nsenter"

# ROOTLESS PODMAN CANNOT nsenter INTO PID 1. It fails with
#   nsenter: can't open '/proc/1/ns/ipc': Permission denied
# so the read above returns nothing. Until 2026-09-15 the script then skipped
# both lines silently and Ghated -- a whole clinic -- had no disk or memory floor
# at all, which read exactly like a node that passed.
#
# `podman info` reports the same numbers without entering any namespace.
# MUST be memAvailable, NOT memFree: on this node memFree read 182 MB against a
# memAvailable of 1157 MB, so memFree would have raised a false FAIL against the
# 1024 MB floor every time.
if [ -z "${disk:-}" ] || [ -z "${mem:-}" ]; then
  if read -r d2 m2 <<< "$("$CT" info --format json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
st=d.get("store",{}); h=d.get("host",{})
alloc,used = st.get("graphRootAllocated"), st.get("graphRootUsed")
avail = h.get("memAvailable")
if alloc is None or used is None or avail is None: sys.exit(1)
print((alloc-used)//1048576, avail//1048576)
' 2>/dev/null)"; then
    [ -n "${d2:-}" ] && disk="$d2"
    [ -n "${m2:-}" ] && mem="$m2"
    probe="${CT} info"
  fi
fi
# A probe that returns nothing must SAY so. Under rootless podman the nsenter
# above yields nothing (Ghated, measured 2026-09-14), and the previous version
# of this script skipped the line silently -- so a disk floor nobody was
# measuring read exactly like a disk floor that passed.
if [ -n "${disk:-}" ]; then
  [ "$disk" -ge $((DISK_FLOOR_GB*1024)) ] \
    && ok "vm disk free ${disk} MB (via ${probe})" || bad "vm disk free ${disk} MB < ${DISK_FLOOR_GB} GB (F-022)"
else
  bad "vm disk NOT MEASURED: neither nsenter nor ${CT} info returned a value"
fi
if [ -n "${mem:-}" ]; then
  [ "$mem" -ge "$MEM_FLOOR_MB" ] \
    && ok "vm memory available ${mem} MB (via ${probe})" || bad "vm memory available ${mem} MB < ${MEM_FLOOR_MB} MB (F-050)"
else
  bad "vm memory NOT MEASURED: neither nsenter nor ${CT} info returned a value"
fi

# --- MySQL wait_timeout -----------------------------------------------------
# Password read from the container's own env, so it never appears out here.
if [ -n "$MY" ]; then
  wt=$("$CT" exec "$MY" sh -c 'mysql -N -uroot -p"$MYSQL_ROOT_PASSWORD" -e "select @@global.wait_timeout"' 2>/dev/null)
  [ -n "$wt" ] && { [ "$wt" -ge "$WAIT_FLOOR" ] \
    && ok "mysql wait_timeout $wt" || bad "mysql wait_timeout $wt < $WAIT_FLOOR (F-007/BL-039)"; }
else bad "mysql service '$MYSQL_SERVICE' not running"; fi

# --- PG replication slots ---------------------------------------------------
if [ -n "$PG" ]; then
  slots=$("$CT" exec "$PG" psql -U "$PG_USER" -d "$PG_DB" -tAc \
    "select slot_name||' '||active||' '||(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)/1048576)::int from pg_replication_slots" 2>/dev/null)
  while read -r s a mb; do
    [ -z "$s" ] && continue
    case "$a" in t|true) :;; *) bad "slot $s inactive ($a)";; esac
    [ "${mb:-0}" -le "$SLOT_FLOOR_MB" ] \
      && ok "slot $s retains ${mb} MB" || bad "slot $s retains ${mb} MB > ${SLOT_FLOOR_MB} MB (F-043)"
  done <<< "$slots"
else bad "postgres service '$PG_SERVICE' not running"; fi

# --- Kafka ------------------------------------------------------------------
if [ -n "$KF" ]; then
  kt=$("$CT" exec "$KF" kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP" --list 2>/dev/null | wc -l | tr -d ' ')
  [ "${kt:-0}" -gt 0 ] && ok "kafka reachable ($kt topics)" || bad "kafka not answering on $KAFKA_BOOTSTRAP"
else bad "kafka service '$KAFKA_SERVICE' not running"; fi

# --- Connectors -------------------------------------------------------------
# Judged on TASK state, never connector state: a connector reports RUNNING while
# its task is dead, so reading connector state passes over a broken sink (F-027).
st=$(curl -s --max-time 20 "${CONNECT_URL}/connectors?expand=status" | python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: print('connect-unreachable'); sys.exit()
bad=[k for k,v in d.items() if v['status']['connector']['state']!='RUNNING' or any(t['state']!='RUNNING' for t in v['status']['tasks'])]; print(f'{len(d)} connectors; not RUNNING: {bad}')")
case "$st" in *"not RUNNING: []") ok "$st";; *) bad "$st";; esac

exit $rc
