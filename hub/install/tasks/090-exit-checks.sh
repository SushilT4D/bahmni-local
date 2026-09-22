#!/usr/bin/env bash
# The hub's own exit checks: everything the install must still be true of,
# read fresh from the live system -- never trusted from an earlier task's own
# ok line, which ran once, earlier, and could have drifted since. Unlike
# every other task here, this one deliberately does NOT use lib.sh's fail()
# (which exits at the first failure): a checklist's whole point is to report
# the complete picture in one pass, so every check below always runs, each
# prints ok/FAIL with the value it read, and only the summary line at the end
# decides whether this task -- and so install.sh's task loop -- passes or
# stops. hub/install/tests/test_sources.sh (Ruling 9) runs this task for real
# against a throwaway stack; two of its six checks are annotated below for
# what that means in a throwaway environment (the disk-free threshold is
# overridable with HUB_MIN_DISK_GB, the same way KAFKA_CONTAINER is; the git-status
# check can be skipped there with HUB_EXIT_CHECKS_SKIP_GIT=1, since the smoke runs beside
# another session's own in-flight edits to this same checkout).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "90 · exit checks"
[ "${DRY}" = 1 ] && { info "would: disk free under the broker's data volume >=20 GB (ct exec into \$KAFKA_CONTAINER); every connector+task RUNNING (from Connect's REST API); both base Postgres replication slots (dbz_odoo_down, dbz_clinlims_down) retain <2 GB; port 9092 still published on the declared KAFKA_SASL_BIND and the SASL listener still answers; the base openmrs event_records count (informational); hub/.env and kafka_server_jaas.conf mode 600; git status --porcelain carrying nothing under hub/"; exit 0; }
setup_compose
[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"
# shellcheck disable=SC1091
set -a; . "${HUB_DIR}/.env"; set +a
# Same override precedence as 080-sources.sh: an already-exported
# HUB_CONNECT_URL_OVERRIDE (the live smoke, addressing its own throwaway
# Connect) wins over hub/.env's KAFKA_CONNECT_URL, which wins over the bare
# default. Renamed from a bare CONNECT_URL (final review, Minor 13).
CONNECT_URL="${HUB_CONNECT_URL_OVERRIDE:-${KAFKA_CONNECT_URL:-http://localhost:8083}}"

FAILS=0
bad(){ printf '  FAIL %s\n' "$*" >&2; FAILS=$((FAILS+1)); }

# --- 1. Disk free under the broker's own data volume >= HUB_MIN_DISK_GB ----
# (default 20). Ruling R1b: NOT a host-level `df` on `ct info`'s
# DockerRootDir -- Docker Desktop for macOS runs the whole docker daemon
# (storage included) inside a VM, so DockerRootDir names a path the HOST's
# own df can never resolve (found live: the bare host-df approach reported
# "could not read available space" on every run on this dev host, never a
# real number, no matter how low HUB_MIN_DISK_GB was set). Measured instead
# from INSIDE the kafka container itself, on the filesystem its own data
# volume (KAFKA_LOG_DIRS, hub/docker-compose.yml) is mounted on -- the disk
# that actually fills in a real incident -- which works identically
# on Docker Desktop and a production Linux hub, and is the number an
# operator actually needs. HUB_MIN_DISK_GB is a test-only override
# (documented and overridable the same way KAFKA_CONTAINER is,
# hub/install/lib.sh): hub/install/tests/test_sources.sh sets it to 1 so the
# assertion is about the CHECK running and reporting a real number, not
# about how much space this dev host's own disk happens to have free right
# now. Never lower the production default of 20. avail_kb is read and
# validated as a plain non-empty digit string, with `|| true` inside the
# substitution -- under `pipefail` (this task's own `set -euo pipefail`) a
# failed `ct exec` would otherwise abort the whole task via set -e before it
# could reach a clean, named FAIL line, the exact class of bug this file's
# own header warns every OTHER guarded read about (`2>/dev/null || true`).
avail_kb="$(ct exec "$KAFKA_CONTAINER" df -Pk /var/lib/kafka/data 2>/dev/null | awk 'NR==2{print $4}' || true)"
case "$avail_kb" in
  ''|*[!0-9]*) bad "disk free under the broker's data volume: could not read available space (ct exec ${KAFKA_CONTAINER} df -Pk /var/lib/kafka/data returned no numeric value)" ;;
  *) avail_gb=$((avail_kb / 1048576)); min_gb="${HUB_MIN_DISK_GB:-20}"; [ "$avail_gb" -ge "$min_gb" ] && ok "disk free under the broker's data volume: ${avail_gb} GB (want >= ${min_gb})" || bad "disk free under the broker's data volume: ${avail_gb} GB (want >= ${min_gb})" ;;
esac

# --- 2. Every connector AND every task RUNNING, read fresh from Connect ----
# Same per-name RUNNING predicate 080-sources.sh's wait_running uses, but
# read once here (no waiting/retrying -- by the time install reaches its
# last task, everything should already be settled) and applied to whatever
# connectors actually exist, not a hardcoded list of three, so a hub with
# more sources registered later is still checked completely.
raw="$(curl -s --max-time 10 "${CONNECT_URL}/connectors" 2>/dev/null || true)"
names="$(printf '%s' "$raw" | jq -r '.[]' 2>/dev/null || true)"
if [ -z "$names" ]; then
  bad "no connectors registered at ${CONNECT_URL}/connectors (raw response: ${raw:-<empty>})"
else
  for name in $names; do
    state="$(curl -s --max-time 10 "${CONNECT_URL}/connectors/${name}/status" 2>/dev/null)" || true
    if printf '%s' "$state" | jq -e 'select((.connector.state=="RUNNING") and ((.tasks|length)>0) and ([.tasks[].state]|all(.=="RUNNING")))' >/dev/null 2>&1; then
      ok "${name}: connector RUNNING, tasks $(printf '%s' "$state" | jq -c '[.tasks[].state]')"
    else
      bad "${name}: not RUNNING (connector=$(printf '%s' "$state" | jq -r '.connector.state // "?"' 2>/dev/null || echo '?'), tasks=$(printf '%s' "$state" | jq -c '[.tasks[].state]' 2>/dev/null || echo '[]'))"
    fi
  done
fi

# --- 3. Both base Postgres replication slots retain < 2 GB ------------------
# dbz_odoo_down through BASE_PG_CONTAINER/BASE_PG_SUPERUSER, dbz_clinlims_down
# through BASE_ELIS_CONTAINER/BASE_ELIS_SUPERUSER -- pg_admin (lib.sh)
# dispatches this from the db name alone ("odoo" / "openelis"), the same way
# 050-base-db.sh and 080-sources.sh's wait_slot already do.
check_slot_retention(){ # SLOT DB CONTAINER_FOR_DISPLAY
  local slot="$1" db="$2" disp="$3" bytes
  bytes="$(pg_admin "$db" -Atc "select coalesce(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn), 0)::bigint from pg_replication_slots where slot_name = '${slot}'" 2>/dev/null || true)"
  case "$bytes" in
    ''|*[!0-9]*) bad "slot ${slot} (${disp}): could not read retained bytes via pg_wal_lsn_diff" ; return ;;
  esac
  if [ "$bytes" -lt 2147483648 ]; then
    ok "slot ${slot} (${disp}) retains $(( bytes / 1048576 )) MB (< 2 GB)"
  else
    bad "slot ${slot} (${disp}) retains $(( bytes / 1073741824 )) GB (want < 2 GB -- a consumer or MirrorMaker is stalled)"
  fi
}
check_slot_retention dbz_odoo_down odoo "${BASE_PG_CONTAINER}"
check_slot_retention dbz_clinlims_down openelis "${BASE_ELIS_CONTAINER:-$BASE_PG_CONTAINER}"

# --- 4. The SASL listener is published where hub/.env says, and answers -----
# sasl_bind_ok + sasl_listener_ok (lib.sh): 060's own two checks, reused
# rather than duplicated, so "did it come up" and "is it still up at the end"
# can never drift apart (code review fold-in, Task 6/7 review). The bind
# read-back is the half sasl_listener_ok structurally cannot do: it dials
# 127.0.0.1, which answers whether 9092 is published to the world or to
# loopback only (final review, Critical 2).
if bind_published="$(sasl_bind_ok)"; then
  ok "clinic-facing 9092 published on ${bind_published} (declared KAFKA_SASL_BIND=${KAFKA_SASL_BIND:-0.0.0.0})"
else
  bad "$bind_published"
fi
reason="$(sasl_listener_ok)" && ok "SASL listener answers on the published ${SASL_LISTENER_PORT:-9092} as mirrormaker" || bad "$reason"

# --- 4b. Informational: the base OpenMRS event_records backlog --------------
# Not a pass/fail check -- a number the operator wants in the install log.
# event_records is OpenMRS's own atomfeed publication table: it grows while a
# feed consumer is behind and is the first place a stalled Bahmni-side
# integration shows up, independent of anything Kafka does. Read through
# mysql_root (lib.sh), so the root password stays inside the container and
# everything printed back is masked.
ev="$(printf 'select count(*) from openmrs.event_records' | mysql_root | head -1)" || true
case "$ev" in
  ''|*[!0-9]*) info "base openmrs event_records: not readable (${ev:-<no answer>}) -- informational only" ;;
  *)           info "base openmrs event_records: ${ev} row(s) (informational)" ;;
esac

# --- 5. hub/.env and kafka_server_jaas.conf mode 600 ------------------------
for f in "${HUB_DIR}/.env" "${HUB_DIR}/kafka_server_jaas.conf"; do
  mode="$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f" 2>/dev/null)" || true
  [ "$mode" = 600 ] && ok "$(basename "$f") mode 600" || bad "$(basename "$f") mode is ${mode:-<missing>}, want 600"
done

# --- 6. git status --porcelain empty in the repo ----------------------------
# HUB_EXIT_CHECKS_SKIP_GIT=1 is set ONLY by the live smoke (Ruling 9), which
# runs this task for real beside another session's own in-flight edits to
# this same checkout -- a dirty tree there proves nothing about THIS task,
# just about who else is working. Unset (the default, every real install),
# this check runs exactly as written.
if [ "${HUB_EXIT_CHECKS_SKIP_GIT:-0}" = 1 ]; then
  skip "git status --porcelain (HUB_EXIT_CHECKS_SKIP_GIT=1 -- set only by the live smoke)"
else
  status="$(git -C "${REPO_DIR}" status --porcelain 2>&1)" || true
  if [ -z "$status" ]; then
    ok "git status --porcelain empty"
  else
    # The pre-flight ruling: a hub host legitimately carries edits to the BASE
    # stack's own tracked files beside this checkout (the Azure hub keeps
    # cloud/docker-compose.override.yml modified on purpose), and those say
    # nothing about whether THIS install left its own tree dirty. So: name
    # every dirty path either way, and fail only on the ones under hub/.
    dirty_hub="$(printf '%s\n' "$status" | git_dirty_hub_paths)" || true
    if [ -n "$dirty_hub" ]; then
      bad "git status --porcelain: $(printf '%s' "$dirty_hub" | tr '\n' ' ')dirty under hub/ (whole tree:$(printf '\n%s' "$status" | sed 's/^/      /'))"
    else
      ok "git status --porcelain: nothing dirty under hub/ (outside it:$(printf '%s' "$status" | sed 's/^/ /' | tr '\n' ';'))"
    fi
  fi
fi

[ "$FAILS" = 0 ] && ok "exit checks: all green" || fail "exit checks: ${FAILS} check(s) failed (see FAIL lines above)"
