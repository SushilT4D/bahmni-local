#!/usr/bin/env bash
# Run node-local preflight checks.
# Usage: scripts/preflight.sh
# This script does not connect to other hosts.
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
KAFKA_BOOTSTRAP=${KAFKA_BOOTSTRAP:-kafka:29092}
CONNECT_URL=${CONNECT_URL:-localhost:8083}

rc=0
bad(){ echo "  FAIL $*"; rc=1; }
ok(){  echo "  ok   $*"; }

# Container engine: podman (CONTAINER_TOOL overrides, for tests).
CT=${CONTAINER_TOOL:-podman}
"$CT" ps >/dev/null 2>&1 || { echo "  FAIL ${CT} is not answering (is the podman machine running?)"; exit 1; }
echo "== $(hostname -s) ($CT) =="

# Resolve a compose service to its actual container name on this node.
resolve(){ "$CT" ps --format '{{.Names}}' 2>/dev/null \
  | grep -E "(^|[-_])$1([-_][0-9]+)?$" | head -1; }

MY=$(resolve "$MYSQL_SERVICE"); PG=$(resolve "$PG_SERVICE"); KF=$(resolve "$KAFKA_SERVICE")

# Resolve the checkout from Compose labels; this script may be piped over stdin.
REPO=${PREFLIGHT_REPO:-}
if [ -z "$REPO" ]; then
  for c in $("$CT" ps --format '{{.Names}}' 2>/dev/null | head -5); do
    wd=$("$CT" inspect "$c" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null)
    [ -n "$wd" ] && [ -d "$wd" ] && { REPO="$wd"; break; }
  done
fi
# The compose project lives in <repo>/clinic; sync/ is a sibling of clinic/.
if [ -n "$REPO" ] && [ ! -d "$REPO/sync" ] && [ -d "$(dirname "$REPO")/sync" ]; then REPO="$(dirname "$REPO")"; fi

# --- VM disk + memory -------------------------------------------------------
# Measure the podman machine's disk and memory.
# Podman keeps its storage under /var/lib/containers; "-" holds a missing value's place.
read -r disk mem <<< "$("$CT" run --rm --privileged --pid=host alpine:3.20 nsenter -t 1 -m -u -n -i \
  sh -c 'd=$(df -m /var/lib/containers 2>/dev/null | tail -1 | awk "{print \$4}"); m=$(free -m | awk "NR==2{print \$7}"); echo "${d:--} ${m:--}"' 2>/dev/null)"
[ "${disk:-}" != - ] || disk=""; [ "${mem:-}" != - ] || mem=""
probe="nsenter"

# Fall back to podman info when rootless mode blocks nsenter; never skip missing probes.
if [ -z "${disk:-}" ] || [ -z "${mem:-}" ]; then
  # Query podman directly when its socket omits the required resource fields.
  info_ct="$CT"; command -v podman >/dev/null 2>&1 && info_ct=podman
  if read -r d2 m2 <<< "$("$info_ct" info --format json 2>/dev/null | python3 -c '
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
    probe="${info_ct} info"
  fi
fi
# Fail explicitly when resource probes return no measurements.
if [ -n "${disk:-}" ]; then
  [ "$disk" -ge $((DISK_FLOOR_GB*1024)) ] \
    && ok "vm disk free ${disk} MB (via ${probe})" || bad "vm disk free ${disk} MB < ${DISK_FLOOR_GB} GB"
else
  bad "vm disk NOT MEASURED: neither nsenter nor ${CT} info returned a value"
fi
if [ -n "${mem:-}" ]; then
  [ "$mem" -ge "$MEM_FLOOR_MB" ] \
    && ok "vm memory available ${mem} MB (via ${probe})" || bad "vm memory available ${mem} MB < ${MEM_FLOOR_MB} MB"
else
  bad "vm memory NOT MEASURED: neither nsenter nor ${CT} info returned a value"
fi

# --- MySQL wait_timeout -----------------------------------------------------
# Password read from the container's own env, so it never appears out here.
if [ -n "$MY" ]; then
  wt=$("$CT" exec "$MY" sh -c 'mysql -N -uroot -p"$MYSQL_ROOT_PASSWORD" -e "select @@global.wait_timeout"' 2>/dev/null)
  [ -n "$wt" ] && { [ "$wt" -ge "$WAIT_FLOOR" ] \
    && ok "mysql wait_timeout $wt" || bad "mysql wait_timeout $wt < $WAIT_FLOOR (an idle sink connection would die)"; }
else bad "mysql service '$MYSQL_SERVICE' not running"; fi

# --- PG replication slots ---------------------------------------------------
if [ -n "$PG" ]; then
  slots=$("$CT" exec "$PG" psql -U "$PG_USER" -d "$PG_DB" -tAc \
    "select slot_name||' '||active||' '||(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)/1048576)::int from pg_replication_slots" 2>/dev/null)
  while read -r s a mb; do
    [ -z "$s" ] && continue
    case "$a" in t|true) :;; *) bad "slot $s inactive ($a)";; esac
    [ "${mb:-0}" -le "$SLOT_FLOOR_MB" ] \
      && ok "slot $s retains ${mb} MB" || bad "slot $s retains ${mb} MB > ${SLOT_FLOOR_MB} MB"
  done <<< "$slots"
else bad "postgres service '$PG_SERVICE' not running"; fi

# --- Unsynced tables tied to synced ones -------------------
# Warn about unsynced tables linked to synced tables; tests extract the helpers.
# unsynced-check:begin
warn_(){ echo "  WARN $*"; }

# The [up] tables of one sync/tables/*.conf file (odoo.conf, openelis.conf).
up_section_tables(){ # CONF : the [up] entries of a sync/tables/*.conf file, one per line; nothing when it is missing
  [ -f "$1" ] || return 0
  awk '{ t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t) }
       t ~ /^\[[a-z]+\]$/ { up = (t == "[up]"); next }
       up { sub(/#.*/, ""); gsub(/[ \t]/, ""); if ($0 != "") print }' "$1"
}

# Find unsynced tables with rows and foreign keys in either direction.
unsynced_check_sql(){ # SCHEMA TABLE...
  local schema="$1"; shift
  local synced_csv="" t
  for t in "$@"; do synced_csv="${synced_csv}${synced_csv:+,}'${t}'"; done
  cat <<SQL
WITH fk_to_synced AS (
  SELECT DISTINCT tc.table_name AS tbl, 'FK->synced' AS direction
  FROM information_schema.table_constraints tc
  JOIN information_schema.constraint_column_usage ccu
    ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
  WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = '${schema}'
    AND ccu.table_name IN (${synced_csv}) AND tc.table_name NOT IN (${synced_csv})
), fk_from_synced AS (
  SELECT DISTINCT ccu.table_name AS tbl, 'synced->FK' AS direction
  FROM information_schema.table_constraints tc
  JOIN information_schema.constraint_column_usage ccu
    ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
  WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = '${schema}'
    AND tc.table_name IN (${synced_csv}) AND ccu.table_name NOT IN (${synced_csv})
), candidates AS (
  SELECT tbl, direction FROM fk_to_synced UNION SELECT tbl, direction FROM fk_from_synced
)
SELECT c.tbl || '|' || c.direction || '|' || s.n_live_tup
FROM candidates c
JOIN pg_stat_user_tables s ON s.schemaname = '${schema}' AND s.relname = c.tbl
WHERE s.n_live_tup > 0
ORDER BY c.tbl;
SQL
}

# Filter allowlisted DB/table pairs without substring matches.
filter_unsynced_allowlist(){ # DB ALLOWFILE
  local db="$1" allow="$2" line tbl
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    tbl="${line%%|*}"
    if [ -f "$allow" ] && grep -qE "^${db}:${tbl}([[:space:]]|\$)" "$allow"; then
      continue
    fi
    printf '%s\n' "$line"
  done
}
# unsynced-check:end

if [ -z "${REPO:-}" ]; then
  echo "  note unsynced-tables check NOT RUN: no repo checkout found on this node yet (needed for sync/tables/)"
else
  TABLES_D="${REPO}/sync/tables"; ALLOW_F="${REPO}/sync/unsynced-allowlist.conf"
  if [ ! -d "$TABLES_D" ]; then
    echo "  note unsynced-tables check NOT RUN: ${TABLES_D} not found"
  else
    check_unsynced(){ # LABEL DB SCHEMA
      local label="$1" db="$2" schema="$3" conf="${TABLES_D}/$1.conf" synced sql out filtered
      synced="$(up_section_tables "$conf")"
      if [ -z "$synced" ]; then echo "  note unsynced-tables check ($label): no [up] tables in $conf"; return; fi
      if [ -z "$PG" ]; then echo "  note unsynced-tables check ($label): postgres service '$PG_SERVICE' not running"; return; fi
      # shellcheck disable=SC2086
      sql="$(unsynced_check_sql "$schema" $synced)"
      out="$("$CT" exec -i "$PG" psql -U odoo -d "$db" -At -c "$sql" 2>/dev/null)"
      filtered="$(printf '%s\n' "$out" | filter_unsynced_allowlist "$label" "$ALLOW_F")"
      if [ -z "$filtered" ]; then
        ok "unsynced-tables check ($label): none outside sync/unsynced-allowlist.conf"
      else
        printf '%s\n' "$filtered" | while IFS='|' read -r tbl dir rows; do
          [ -z "$tbl" ] && continue
          warn_ "${label}.${tbl} not synced, ${dir}, ${rows} row(s) -- give it a verdict in sync/unsynced-allowlist.conf"
        done
      fi
    }
    check_unsynced odoo odoo public
    check_unsynced openelis openelis clinlims
  fi
fi

# --- Kafka ------------------------------------------------------------------
if [ -n "$KF" ]; then
  kt=$("$CT" exec "$KF" kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP" --list 2>/dev/null | wc -l | tr -d ' ')
  [ "${kt:-0}" -gt 0 ] && ok "kafka reachable ($kt topics)" || bad "kafka not answering on $KAFKA_BOOTSTRAP"
else bad "kafka service '$KAFKA_SERVICE' not running"; fi

# --- Connectors -------------------------------------------------------------
# Check task state; a connector can report RUNNING while its task has failed.
st=$(curl -s --max-time 20 "${CONNECT_URL}/connectors?expand=status" | python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: print('connect-unreachable'); sys.exit()
bad=[k for k,v in d.items() if v['status']['connector']['state']!='RUNNING' or any(t['state']!='RUNNING' for t in v['status']['tasks'])]; print(f'{len(d)} connectors; not RUNNING: {bad}')")
case "$st" in *"not RUNNING: []") ok "$st";; *) bad "$st";; esac


# --- odoo-connect -----------------------------------------------------------
# Check the mounted HttpClient jar and recent logs on nodes running this service.
OC=$(resolve "odoo-connect")
if [ -n "$OC" ]; then
  if "$CT" exec "$OC" sh -c 'test -f /run/bahmni-erp-connect/bahmni-erp-connect/WEB-INF/lib/httpclient5-5.1.4.jar' 2>/dev/null; then
    ok "odoo-connect has httpclient5 mounted as a file"
  else
    bad "odoo-connect httpclient5 jar is not a file in WEB-INF/lib -- mount missing, or an empty directory took its place"
  fi
  ncdf=$("$CT" logs --tail 2000 "$OC" 2>&1 | grep -c 'NoClassDefFoundError: org/apache/hc/core5')
  [ "${ncdf:-0}" -eq 0 ] \
    && ok "odoo-connect: no HttpClient 5 NoClassDefFoundError in last 2000 lines" \
    || bad "odoo-connect logged ${ncdf} HttpClient 5 NoClassDefFoundError(s) in last 2000 lines -- recreate it from the current override"
else
  echo "  note odoo-connect not running on this node -- atom-feed consumer probes skipped (expected on the hub)"
fi

exit $rc
