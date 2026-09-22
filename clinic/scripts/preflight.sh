#!/usr/bin/env bash
# Node-local preflight: VM disk and memory,
# MySQL wait_timeout floor, PG replication-slot retention, Kafka reachable,
# connector task states. Exit 1 if any floor is breached.
#
# Usage: scripts/preflight.sh
#
# RUNS ENTIRELY ON THIS NODE. It takes no node name and opens no SSH connection.
#
# WHY. A script that fans out to other nodes over SSH carries, in a PUBLIC
# repo, the hub's hostname and the path to a private key. Nothing the clinic
# stack runs needs SSH -- the resolved compose config references it zero
# times -- and a clinic reaches the hub over Kafka, not a shell. That
# transport is meant to be mTLS with per-site ACLs confining each site to its
# own topics; shell access from
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

# Find the repo by asking a running container which directory its
# compose project came from. Works regardless of how this script was invoked --
# the operator wrapper pipes it over stdin, so BASH_SOURCE is not a path here.
# Resolved here (not down by the checkout-drift section that originally read
# it) so the unsynced-tables section below -- which needs sync/subsystems.conf,
# same as checkout drift needs the git repo -- has it too.
REPO=${PREFLIGHT_REPO:-}
if [ -z "$REPO" ]; then
  for c in $("$CT" ps --format '{{.Names}}' 2>/dev/null | head -5); do
    wd=$("$CT" inspect "$c" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null)
    [ -n "$wd" ] && [ -d "$wd" ] && { REPO="$wd"; break; }
  done
fi
# The compose project lives in <repo>/clinic; sync/ is a sibling of clinic/,
# so the paths below need the repository root, not the compose directory.
if [ -n "$REPO" ] && [ ! -d "$REPO/sync" ] && [ -d "$(dirname "$REPO")/sync" ]; then REPO="$(dirname "$REPO")"; fi

# --- VM disk + memory -------------------------------------------------------
# The container VM, not the host: on macOS the engine runs in a Linux VM and it
# is that VM's disk that fills. nsenter into pid 1 reads the VM's own view.
# On a Linux host there is no VM: the engine's data-root sits on a host
# filesystem and MemAvailable is the host's own. Measure it directly, at the
# engine's REAL data-root -- the first Linux clinic (manpur) keeps it on a data
# disk, and /var/lib/docker on the OS disk reported 8 GB free for a node with
# 120 GB. The nsenter/VM probes below are for macOS engines.
if [ "$(uname -s)" = Linux ]; then
  root="$("$CT" info --format '{{.DockerRootDir}}' 2>/dev/null || "$CT" info --format '{{.Store.GraphRoot}}' 2>/dev/null || echo /var/lib/docker)"
  disk="$(df -Pm "$root" 2>/dev/null | awk 'NR==2{print $4}')"
  mem="$(free -m 2>/dev/null | awk '/^Mem:/{print $7}')"
  probe="host ${root}"
else
read -r disk mem <<< "$("$CT" run --rm --privileged --pid=host alpine:3.20 nsenter -t 1 -m -u -n -i \
  sh -c 'echo $(df -m /var/lib/docker 2>/dev/null | tail -1 | awk "{print \$4}") $(free -m | awk "NR==2{print \$7}")' 2>/dev/null)"
probe="nsenter"
fi

# ROOTLESS PODMAN CANNOT nsenter INTO PID 1. It fails with
#   nsenter: can't open '/proc/1/ns/ipc': Permission denied
# so the read above returns nothing. Skipping both lines silently would leave a
# whole clinic with no disk or memory floor at all, which reads exactly like a
# node that passed.
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
# above yields nothing; a version of this script that skipped the line silently
# made a disk floor nobody was measuring read exactly like a disk floor that
# passed.
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
# village_village stopped a sink because a table nobody had listed grew rows
# that referenced, and were referenced by, a synced table. That
# is a CLASS, not a one-off: a table outside sync/subsystems.conf's synced set
# that (a) touches a synced table by a foreign key in EITHER direction and
# (b) has gained rows is a future village_village until a human gives it a
# verdict in sync/unsynced-allowlist.conf. WARN, not FAIL: this is a
# data-quality question for a person, not a broken node -- warn_ never
# touches rc.
#
# The functions between the markers below are pure (no psql, no side effects)
# so clinic/install/tests/test_unsynced_check.sh can pull them out and
# exercise the SQL-building and the allowlist/subsystems parsing without a
# database. Not sourced from clinic/install/lib.sh: this script also runs
# piped over ssh from another host (see the file header), where lib.sh and
# its REPO_DIR are not on the far side.
# unsynced-check:begin
warn_(){ echo "  WARN $*"; }

# subsystems_conf_tables PREFIX CONF : sync/subsystems.conf's <PREFIX>:<table>
# rows, one per line -- the same parse clinic/install/lib.sh's
# subsystem_tables does (trim, drop a trailing comment, skip :all, skip
# blank/comment lines). A missing CONF prints nothing rather than erroring --
# the caller decides whether that is a note or a real problem.
subsystems_conf_tables(){ # PREFIX CONF
  local prefix="$1" conf="$2" line name
  [ -f "$conf" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in "${prefix}:"*) ;; *) continue ;; esac
    name="${line#*:}"; name="${name%%#*}"
    name="$(printf '%s' "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$name" ] && continue
    [ "$name" = "all" ] && continue
    printf '%s\n' "$name"
  done < "$conf"
}

# unsynced_check_sql SCHEMA TABLE... : the query that finds a table in SCHEMA
# that is (a) not one of the given synced TABLEs, (b) linked to one by a
# foreign key in EITHER direction (an FK FROM it TO a synced table, or an FK
# FROM a synced table TO it), and (c) has rows. Both directions matter --
# village_village is pointed TO by res_partner (itself synced), but a future
# case could equally be a table a synced row points AT. Printed, never eval'd
# blind here, so a test can inspect it without a database.
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

# filter_unsynced_allowlist DB ALLOWFILE : reads "table|direction|rows" lines
# on stdin, drops any whose "DB:table" appears in ALLOWFILE (a bare substring
# match is not enough -- openelis and odoo can share a table name, e.g.
# "test"), prints the rest unchanged. A missing ALLOWFILE allowlists nothing
# (keeps every line), never passes everything through silently.
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
  echo "  note unsynced-tables check NOT RUN: no repo checkout found on this node yet (needed for sync/subsystems.conf)"
else
  CONF_F="${REPO}/sync/subsystems.conf"; ALLOW_F="${REPO}/sync/unsynced-allowlist.conf"
  if [ ! -f "$CONF_F" ]; then
    echo "  note unsynced-tables check NOT RUN: ${CONF_F} not found"
  else
    check_unsynced(){ # LABEL DB SCHEMA PREFIX
      local label="$1" db="$2" schema="$3" prefix="$4" synced sql out filtered
      synced="$(subsystems_conf_tables "$prefix" "$CONF_F")"
      if [ -z "$synced" ]; then echo "  note unsynced-tables check ($label): no ${prefix}: rows in $CONF_F"; return; fi
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
    check_unsynced odoo odoo public odoo
    check_unsynced openelis openelis clinlims clinlims
  fi
fi

# --- Kafka ------------------------------------------------------------------
if [ -n "$KF" ]; then
  kt=$("$CT" exec "$KF" kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP" --list 2>/dev/null | wc -l | tr -d ' ')
  [ "${kt:-0}" -gt 0 ] && ok "kafka reachable ($kt topics)" || bad "kafka not answering on $KAFKA_BOOTSTRAP"
else bad "kafka service '$KAFKA_SERVICE' not running"; fi

# --- Connectors -------------------------------------------------------------
# Judged on TASK state, never connector state: a connector reports RUNNING while
# its task is dead, so reading connector state passes over a broken sink.
st=$(curl -s --max-time 20 "${CONNECT_URL}/connectors?expand=status" | python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: print('connect-unreachable'); sys.exit()
bad=[k for k,v in d.items() if v['status']['connector']['state']!='RUNNING' or any(t['state']!='RUNNING' for t in v['status']['tasks'])]; print(f'{len(d)} connectors; not RUNNING: {bad}')")
case "$st" in *"not RUNNING: []") ok "$st";; *) bad "$st";; esac


# --- odoo-connect -----------------------------------------------------------
# The image lacks Apache HttpClient 5 and the compose override bind-mounts three
# jars into its WEB-INF/lib. Two ways for that to silently
# not apply: the source file missing, so the engine creates an empty DIRECTORY
# of the jar's name; or a container recreated from an older override. Both
# leave the error in the log, so the log is judged as well as the file. Only
# when the container is running: the hub runs no odoo-connect (it receives
# Odoo rows over CDC, never the atom feed) and says so rather than passing.
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

# --- checkout drift ---------------------------------------------------------
# WHY. A hub can run a sink generator weeks older than the fixed copy on the
# branch, and nobody would know, because
# nothing ever compared a node's checkout to its remote. Every other check here
# asks whether the node is HEALTHY; this one asks whether it is running the code
# we think it is.
#
# Deliberately does NOT fetch by default: this script is node-local and fast, and
# the operator wrapper is the networked half. But an "up to date" computed from a
# week-old remote-tracking ref is not evidence of anything, so the age of that
# ref is checked too -- a stale reference FAILS rather than quietly passing.
# Set PREFLIGHT_FETCH=yes to refresh it first.
REF_MAX_AGE_H=${REF_MAX_AGE_H:-24}

# REPO is resolved once, near the top of this script (the unsynced-tables
# section below needs it too) -- reused here, not recomputed.
if [ -z "${REPO:-}" ] || ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  bad "checkout drift NOT MEASURED: no git repo found (set PREFLIGHT_REPO)"
else
  [ "${PREFLIGHT_FETCH:-no}" = "yes" ] && git -C "$REPO" fetch --quiet 2>/dev/null

  dirty=$(git -C "$REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [ "${dirty:-0}" -eq 0 ] \
    && ok "working tree clean" \
    || bad "working tree has ${dirty} uncommitted change(s) -- node config diverging off-repo:$(git -C "$REPO" status --porcelain 2>/dev/null | head -5 | sed 's/^/ /' | tr '\n' ';')"

  if ! up=$(git -C "$REPO" rev-parse --abbrev-ref '@{u}' 2>/dev/null); then
    # Not pedantry: the hub had no upstream, so from that node you could not tell
    # whether your work was pushed or your checkout was stale. Drift is invisible.
    bad "no upstream for $(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null) -- drift CANNOT be detected from this node"
  else
    ahead=$(git -C "$REPO" rev-list --count "${up}..HEAD" 2>/dev/null || echo 0)
    behind=$(git -C "$REPO" rev-list --count "HEAD..${up}" 2>/dev/null || echo 0)

    age_desc=""
    # Freshness of the drift REFERENCE, not of any particular transport. The hub
    # cannot reach GitHub at all -- TCP/443 and SSH both time out from that
    # network -- so its remote-tracking ref is PUSHED IN by a node that can reach
    # both (see skills/lab-preflight.sh). FETCH_HEAD therefore never exists there,
    # and measuring it would report "never fetched" forever on a node whose
    # reference is in fact current. The ref file's own mtime is true under either
    # model: it moves when the ref moves, however it got there.
    # --absolute-git-dir, not --git-dir: the latter returns ".git" relative to the
    # REPO, and this script runs with an arbitrary CWD when the operator wrapper
    # pipes it over ssh -- which silently made every mtime lookup miss and every
    # node report "never fetched".
    gd=$(git -C "$REPO" rev-parse --absolute-git-dir 2>/dev/null)
    upref=$(git -C "$REPO" rev-parse --symbolic-full-name '@{u}' 2>/dev/null)
    ref_mtime=0
    for cand in "${gd}/${upref}" "${gd}/FETCH_HEAD" "${gd}/packed-refs"; do
      [ -f "$cand" ] || continue
      # GNU first: on Linux `stat -f %m FILE` prints FILESYSTEM status to stdout
      # before failing, and that junk landed in this variable ahead of the
      # fallback's epoch (manpur: "integer expression expected"). tail -1 keeps
      # only the last line whatever the order.
      ref_mtime=$( { stat -c %Y "$cand" 2>/dev/null || stat -f %m "$cand" 2>/dev/null || echo 0; } | tail -1)
      [ "${ref_mtime:-0}" -gt 0 ] && break
    done
    age_h=$(( ( $(date +%s) - ${ref_mtime:-0} ) / 3600 ))

    if [ "${ref_mtime:-0}" -eq 0 ]; then
      bad "drift reference NEVER FETCHED -- ahead/behind below is NOT evidence; rerun with PREFLIGHT_FETCH=yes"
      age_desc="never fetched"
    elif [ "$age_h" -gt "$REF_MAX_AGE_H" ]; then
      bad "drift reference is ${age_h}h old (max ${REF_MAX_AGE_H}h) -- ahead/behind below is NOT evidence; rerun with PREFLIGHT_FETCH=yes"
    fi
    [ "${behind:-0}" -eq 0 ] \
      && ok "checkout current with ${up} (ref ${age_desc:-${age_h}h old})" \
      || bad "checkout is ${behind} commit(s) BEHIND ${up} -- this node is running old code"
    [ "${ahead:-0}" -eq 0 ] \
      || bad "${ahead} commit(s) exist only on this node -- unpushed"
  fi
fi

exit $rc
