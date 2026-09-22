#!/usr/bin/env bash
# Shared helpers for clinic/install. The shape (begin_task / ok / skip / fail, one
# task per file, --force-free idempotence) follows Sushil's initialize/lib.sh on
# main; the content is this fleet's: derived identity, the residue ledger, the
# .env quoting contract, docker/podman behind one wrapper.
#
# bash 3.2 compatible on purpose: macOS ships 3.2. No associative arrays, no
# mapfile, no ${var,,}.
set -o pipefail

INSTALL_DIR="${INSTALL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${INSTALL_DIR}/.." && pwd)}"
REPO_DIR="${REPO_DIR:-$(cd "${CLINIC_DIR}/.." && pwd)}"
LEDGER="${LEDGER:-${REPO_DIR}/sync/clinics.txt}"
DRY="${DRY:-0}"
PROFILES="--profile local --profile debezium --profile openelis"

log(){   printf '%s\n' "$*"; }
info(){  printf '  %s\n' "$*"; }
ok(){    printf '  ok   %s\n' "$*"; }
skip(){  printf '  skip %s\n' "$*"; }
warn(){  printf '  WARN %s\n' "$*" >&2; }
fail(){  printf '  FAIL %s\n' "$*" >&2; exit 1; }
begin_task(){ printf '\n== %s ==\n' "$*"; }
require_cmd(){ command -v "$1" >/dev/null 2>&1 || fail "missing command: $1${2:+ -- $2}"; }

# Every task runs under set -e, so a bare command that fails ends the task with
# no FAIL line: the runner prints STOPPED and nothing names the culprit (first
# live clinic, manpur: three silent stops in one evening -- df -g, a $(...)
# assignment, a psql heredoc). Print the failing command AS WRITTEN (never
# expanded, so no secret value can reach the log), its exit status and the call
# chain. -E so the trap also fires inside functions and $(...); guarded
# failures (if / && / || / while) never trip an ERR trap, so ok/fail lines and
# probes stay quiet.
_on_err(){
  local rc=$? ps="${PIPESTATUS[*]}" cmd="$BASH_COMMAND" i=1 n chain='' pipe=''
  trap - ERR   # bash 3.2 fires ERR on a false (( )) or [ ] inside the handler itself
  # BASH_COMMAND names the LAST command of a failed pipeline, not the one that
  # failed (manpur: "sed" was blamed for a grep with no match) -- show them all.
  case "$ps" in *' '*) pipe=" (pipeline statuses: ${ps}; the first non-zero is the culprit)" ;; esac
  while [ "$i" -lt "${#BASH_SOURCE[@]}" ]; do
    n="${FUNCNAME[$i]}"; case "$n" in main|source) n='' ;; esac
    chain="${chain}${chain:+ <- }${BASH_SOURCE[$i]##*/}:${BASH_LINENO[$((i-1))]}${n:+ ($n)}"
    i=$((i+1))
  done
  printf '  FAILED rc=%s%s: %s\n         at %s\n' "$rc" "$pipe" "$cmd" "${chain:-${BASH_SOURCE[0]##*/}}" >&2
  trap _on_err ERR
}
# Armed only where set -e is already on (every task and install.sh set it before
# sourcing): the trap exists to name what -e kills, and the test suites run
# failing commands unguarded on purpose. bash 3.2 also fires ERR for a guarded
# probe inside $(...), which would print a misleading FAILED line on a Mac dry
# run; arm it on bash 4+ only (every Linux clinic), 3.2 keeps the plain STOPPED.
case "$-" in *e*) [ "${BASH_VERSINFO[0]}" -ge 4 ] && { set -E; trap _on_err ERR; } ;; esac

# run CMD... : in dry mode prints the command instead of executing it. Wrap
# anything with side effects in it; keep reads outside it so a dry run still
# reports real facts.
run(){ if [ "${DRY}" = 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }

detect_platform(){ case "$(uname -s)" in Darwin) echo macos ;; Linux) echo linux ;; *) echo unknown ;; esac; }
# RUNTIME overrides; default podman on macOS, docker on Linux.
detect_runtime(){
  if [ -n "${RUNTIME:-}" ]; then echo "${RUNTIME}"; return; fi
  if [ "$(detect_platform)" = macos ]; then echo podman; else echo docker; fi
}
podman_socket(){
  if [ "$(detect_platform)" = macos ]; then
    printf 'unix://%s\n' "$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null)"
  else
    printf 'unix:///run/user/%s/podman/podman.sock\n' "$(id -u)"
  fi
}
# setup_compose: CT is the runtime binary; COMPOSE_CMD is how compose is invoked.
# podman is driven through the docker-compose binary over DOCKER_HOST, exactly as
# Ghated runs (memory: ghated-clinic-2-node); podman-compose is not used.
setup_compose(){
  CT="$(detect_runtime)"
  if [ "${CT}" = docker ]; then
    COMPOSE_CMD="docker compose"
  else
    COMPOSE_CMD="docker-compose"
    [ -n "${DOCKER_HOST:-}" ] || export DOCKER_HOST="$(podman_socket)"
  fi
  export CT COMPOSE_CMD
}
ct(){ "${CT:?setup_compose first}" "$@"; }
# compose ARGS... : always from the clinic dir, always with the fleet's profiles.
compose(){ ( cd "${CLINIC_DIR}" && ${COMPOSE_CMD:?setup_compose first} ${PROFILES} "$@" ); }

# .env editing. This file is read by TWO different parsers that do not agree
# on quoting in general: bash `.`-sourcing (every task) and docker compose's
# own dotenv reader (for ${VAR} interpolation in a compose file). Fix round 1
# (code review, live PoC): the previous scheme double-quoted a value on
# trigger characters but never escaped an embedded `"` -- a value like
# `pass"; touch /tmp/x; echo "` was written to the file as literal shell
# code, which RUNS the moment any task `.`-sources it. The one representation
# both parsers read identically is a SINGLE-quoted value with no `'` inside
# it: bash and docker compose's dotenv both treat everything between a pair
# of `'` as fully literal, with no escape processing at all, so nothing in
# the value -- `"`, `$`, `` ` ``, `\`, `#`, `;`, a space -- can ever be
# reinterpreted by either reader. So:
#   - a value using only [A-Za-z0-9_./:@+=-] is written bare, unquoted (the
#     common case -- container names, urls, base64 ids -- unchanged from
#     before).
#   - any other character forces a single-quoted literal, KEY='value'.
#   - a value containing a `'` cannot be represented identically for both
#     readers (escaping it, e.g. bash's own '\'' trick, is not something
#     docker compose's own dotenv parser is guaranteed to read the same way)
#     -- refused outright, naming the key, rather than silently picking one
#     reader's interpretation over the other's.
# Python does the file rewrite so no character in the (already-quoted) value
# needs further escaping there.
#
# The VALUE is handed to python3 through the ENVIRONMENT (ENV_PUT_VALUE), never
# as an argv element (final review, Critical 1): argv is world-readable while
# the process lives (`ps -ef`, /proc/<pid>/cmdline), and every secret this fleet
# generates -- all of hub/.env's, every clinic answer file's -- is written
# through this one function, so the old `python3 - "$f" "$k" "$v"` form put each
# of them on the process list of the machine composing the file. Only the FILE
# and the KEY (neither secret) stay in argv. hub/install/tests/test_lib.sh keeps
# a static guard over this function's source: its python3 substep must read the
# value from os.environ and must never read a third sys.argv element.
env_put(){
  local f="$1" k="$2" v="$3"
  case "$v" in
    *"'"*) fail "env_put: ${k}: a value containing a single quote cannot be stored in .env (bash and docker compose disagree on its meaning); choose another value" ;;
    *[!A-Za-z0-9_./:@+=-]*) v="'$v'" ;;
  esac
  ENV_PUT_VALUE="$v" python3 - "$f" "$k" <<'PY'
import os, sys, re
f, k, v = sys.argv[1], sys.argv[2], os.environ["ENV_PUT_VALUE"]
lines = open(f).read().split("\n")
pat = re.compile(r"^" + re.escape(k) + r"=")
done = False
for i, l in enumerate(lines):
    if pat.match(l) and not done:
        lines[i] = f"{k}={v}"; done = True
if not done:
    if lines and lines[-1] == "": lines.insert(len(lines) - 1, f"{k}={v}")
    else: lines.append(f"{k}={v}")
open(f, "w").write("\n".join(lines))
PY
}
# Under `set -e -o pipefail` (every task), a grep with no match or a tr cut short
# by head turns a pipeline non-zero and aborts the caller on the SUCCESS path.
# Hence the `|| true` guard. Strips a matching pair of quotes off the ends --
# single (env_put's own output, Fix round 1) or double (an operator-hand-
# written .env, or a file predating this change) -- never an unpaired quote,
# and never spawns a subprocess just to do it (env_get is called very often,
# e.g. once per HUB_KEYS entry in 020-env.sh's round-trip check).
env_get(){
  local v
  v="$({ grep -E "^$2=" "$1" || true; } | head -1 | cut -d= -f2-)"
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}
gen_secret(){ python3 -c 'import secrets,string; print("".join(secrets.choice(string.ascii_letters+string.digits) for _ in range(32)))'; }
# subsystem_tables SUBSYSTEM : prints sync/subsystems.conf's `<SUBSYSTEM>:<table>`
# rows' table names, one per line -- the ONE parsing path task 050 (publications)
# and task 060 (striding) both call, instead of each carrying its own
# `grep | cut`. Fixes a real gap (code review, 2026-09-17): an untrimmed row --
# trailing whitespace, or an inline `#` comment left on the line -- used to come
# out with embedded whitespace in the table name. `pg_get_serial_sequence` then
# returns NULL for that name, and the striding SQL only logged a NOTICE and
# skipped it: a synced table silently left unstrided, with no failing check
# anywhere -- an L-008 gap (two nodes could mint the same id for that table).
# Now: strip a trailing `#...` comment, trim surrounding whitespace, skip the
# `:all` aggregate row, and `fail` on any surviving name that is not a bare
# lowercase identifier (naming the offending row) -- a typo'd or unquoted name
# is a defect to catch here, not something to carry forward as a silent NOTICE.
subsystem_tables(){
  local subsystem="$1" conf="${REPO_DIR}/sync/subsystems.conf" line name
  [ -f "$conf" ] || fail "subsystem_tables: no such file: $conf"
  # `|| [ -n "$line" ]` : bash's `read` returns non-zero on a final line with no
  # trailing newline, which would otherwise drop that last row silently (code
  # review, round 2, 2026-09-17) -- the exact L-008 gap this file exists to close,
  # just moved one line down. sync/subsystems.conf ends in a newline today, so this
  # was dormant, but a hand-edit that saves without one must not silently lose the
  # last odoo:/clinlims: row.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "${subsystem}:"*) ;; *) continue ;; esac
    name="${line#*:}"                                                    # drop "<subsystem>:"
    name="${name%%#*}"                                                   # drop a trailing comment
    name="$(printf '%s' "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"  # trim
    [ "$name" = "all" ] && continue
    printf '%s' "$name" | grep -qE '^[a-z_][a-z0-9_]*$' \
      || fail "sync/subsystems.conf: bad ${subsystem} table name '${name}' (row: ${line})"
    printf '%s\n' "$name"
  done < "$conf"
}
# Kafka cluster id: 22 chars of url-safe base64 over 16 random bytes, what
# kafka-storage random-uuid produces, without needing the image.
# Kafka's own Uuid.randomUuid() rejects ids whose base64 form starts with "-":
# `kafka-storage format -t <id>` (the runbook form) parses it as a flag. The
# Confluent image uses --cluster-id=<id>, which is why manpur booted with one.
kafka_cluster_id(){ python3 -c 'import uuid,base64
while True:
    s = base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip("=")
    if not s.startswith("-"): print(s); break'; }

# derive_identity SLUG RESIDUE : sets the nine identity variables (global
# constraints in the plan). Slug: lowercase letters and digits, 2-16 chars,
# starting with a letter. Residue: 1-9 (10 is the cloud's).
derive_identity(){
  local slug="$1" residue="$2"
  printf '%s' "$slug" | grep -Eq '^[a-z][a-z0-9]{1,15}$' || fail "slug '$slug' must match ^[a-z][a-z0-9]{1,15}$"
  printf '%s' "$residue" | grep -Eq '^[1-9]$' || fail "residue '$residue' must be a single digit 1-9 (10 is the cloud)"
  BHS_LOCATION="$slug"
  COMPOSE_PROJECT_NAME="bahmni-${slug}"
  MYSQL_SERVER_NAME="bahmni-${slug}"
  LOCAL_CLUSTER_ALIAS="$slug"
  MYSQL_AUTO_INCREMENT_OFFSET="$residue"
  MYSQL_SERVER_ID="$residue"
  DEBEZIUM_SERVER_ID="18405${residue}"
  ODOO_DB_VOLUME_NAME="bahmni-${slug}_odoodb-data"
  ODOO_APP_VOLUME_NAME="bahmni-${slug}_odooapp-data"
  export BHS_LOCATION COMPOSE_PROJECT_NAME MYSQL_SERVER_NAME LOCAL_CLUSTER_ALIAS MYSQL_AUTO_INCREMENT_OFFSET MYSQL_SERVER_ID DEBEZIUM_SERVER_ID ODOO_DB_VOLUME_NAME ODOO_APP_VOLUME_NAME
}

# The residue ledger: sync/clinics.txt, `slug:offset` per line, whole-line
# comments only, slug matched case-insensitively (configure-pk-offsets.sh's
# parser does the same).
ledger_residue(){ awk -F: -v s="$(printf '%s' "$1" | tr 'A-Z' 'a-z')" '$0 !~ /^[[:space:]]*#/ && NF==2 && tolower($1)==s {print $2; exit}' "${LEDGER}"; }
ledger_conflicts(){ awk -F: -v s="$(printf '%s' "$1" | tr 'A-Z' 'a-z')" -v r="$2" '$0 !~ /^[[:space:]]*#/ && NF==2 && $2==r && tolower($1)!=s {print tolower($1)}' "${LEDGER}"; }

# has_placeholders FILE ALLOWLIST : prints every key whose value is empty or
# <placeholder>, except keys in the space-separated allowlist.
has_placeholders(){
  local f="$1" allow=" ${2:-} " k
  { grep -E '^[A-Z_0-9]+=(<[^>]*>)?$' "$f" || true; } | cut -d= -f1 | while read -r k; do
    case "$allow" in *" $k "*) ;; *) printf '%s\n' "$k" ;; esac
  done
  return 0
}
refuse_inherited_alias(){
  case "$1" in source|ghated|rawach|cloud|remote) fail "LOCAL_CLUSTER_ALIAS '$1' is another node's identity (AL-022); a new node takes its own slug" ;; esac
}
# --- fleet registry -----------------------------------------------------------
# sync/fleet/<slug>.env holds a clinic's non-secret identity (MRN prefix, site
# number, phone, cert hostname); sync/hub.env the hub endpoint. The residue stays
# in the ledger alone (one source). Secrets are never in the repo: they come from
# <seed>/secrets.env or a hidden prompt. install.sh --clinic <slug> composes the
# twelve answers from these; --answers <file> remains the hand-written path.
FLEET_DIR="${FLEET_DIR:-${REPO_DIR}/sync/fleet}"
HUB_ENV="${HUB_ENV:-${REPO_DIR}/sync/hub.env}"
ANSWERS_DIR="${ANSWERS_DIR:-${HOME}}"
ANSWER_KEYS="CLINIC_SLUG RESIDUE MRN_PREFIX SITE_NUMBER CLINIC_PHONE CERT_HOSTNAME REMOTE_KAFKA_BOOTSTRAP_SERVERS REMOTE_KAFKA_USERNAME REMOTE_KAFKA_PASSWORD OPENMRS_ATOMFEED_PASSWORD OPENELIS_ATOMFEED_PASSWORD ODOO_ATOMFEED_PASSWORD"
SECRET_KEYS="REMOTE_KAFKA_PASSWORD OPENMRS_ATOMFEED_PASSWORD OPENELIS_ATOMFEED_PASSWORD ODOO_ATOMFEED_PASSWORD"
fleet_slugs(){ local f; for f in "${FLEET_DIR}"/*.env; do [ -f "$f" ] || continue; basename "$f" .env; done; }
# mysql_ready CONTAINER : true only when the FINAL server answers an authenticated query
# over TCP. `mysqladmin ping` exits 0 even on "Access denied", and the official image's first
# boot runs a temporary socket-only server whose root has no password yet; a wait built on
# ping passes against it and the restore then dies with ERROR 1045 (manpur's fresh VM,
# 2026-09-18; the hub rebuild met the same temp server). That server runs --skip-networking,
# so 127.0.0.1 is the discriminator. MYSQL_PWD keeps the password off the command line.
# --- MySQL sizing -------------------------------------------------------------
# The image's defaults (128 MB buffer pool, 100 MB redo log) starve a node with
# gigabytes of memory: every read misses the cache and a restore checkpoints
# constantly. One conf.d file, sized from the memory the database server can
# see, mounted read-only -- never SET PERSIST (lost with the data volume) and
# never more `command:` flags (compose replaces the whole list).
node_mem_mb(){ # memory the database server can see, in MB; NODE_MEM_MB overrides
  if [ -n "${NODE_MEM_MB:-}" ]; then printf '%s\n' "$NODE_MEM_MB"; return; fi
  if [ "${PLATFORM:-$(detect_platform)}" = macos ]; then
    # the containers run inside the podman machine, so its memory is the ceiling
    local m; m="$(podman machine inspect --format '{{.Resources.Memory}}' 2>/dev/null || true)"
    case "$m" in ''|*[!0-9]*) m="$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1048576 ))" ;; esac
    printf '%s\n' "$m"
  else
    awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0
  fi
}
mysql_pool_mb(){ # MEM_MB -> buffer pool MB: a quarter, 128 MB steps, 512..4096
  local mem="${1:-0}" mb
  case "$mem" in ''|*[!0-9]*) mem=0 ;; esac
  mb=$(( mem / 4 / 128 * 128 ))
  [ "$mb" -gt 4096 ] && mb=4096
  [ "$mb" -lt 512 ] && mb=512
  printf '%s\n' "$mb"
}
mysql_tuning_cnf(){ # POOL_MB -> the conf.d file's text
  printf '# rendered by the installer from the memory this node gives its database server\n[mysqld]\ninnodb_buffer_pool_size = %sM\ninnodb_redo_log_capacity = 512M\n' "$1"
}

mysql_ready(){ [ "$(ct exec "$1" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -h127.0.0.1 -uroot -N -e "select 1"' 2>/dev/null)" = 1 ]; }
# user_in_group_db GROUP : is $USER a member of GROUP in the group DATABASE? `id -nG`
# with no argument lists the running PROCESS's groups, which never contain a group that
# usermod added a moment ago -- and that is exactly the moment task 010 asks.
user_in_group_db(){ id -nG "${USER:-$(id -un)}" 2>/dev/null | tr ' ' '\n' | grep -qx "$1"; }
fleet_file(){ local f="${FLEET_DIR}/$(printf '%s' "$1" | tr 'A-Z' 'a-z').env"; [ -f "$f" ] && printf '%s\n' "$f"; }
# fleet_table : one line per registered clinic -- slug, residue ("-" = none), MRN prefix.
fleet_table(){ local s r; for s in $(fleet_slugs); do r="$(ledger_residue "$s")"; printf '  %-10s residue %-2s  MRN %s\n' "$s" "${r:--}" "$(env_get "$(fleet_file "$s")" MRN_PREFIX)"; done; return 0; }
# answers_missing FILE : prints every answer key that is absent or empty.
answers_missing(){ local k; for k in $ANSWER_KEYS; do [ -n "$(env_get "$1" "$k")" ] || printf '%s\n' "$k"; done; return 0; }
# answers_write FILE : the twelve keys from the current environment, mode 600.
answers_write(){ local f="$1" k v; ( umask 077; : > "$f" ); chmod 600 "$f"; for k in $ANSWER_KEYS; do eval "v=\${$k:-}"; env_put "$f" "$k" "$v"; done; }
# interactive : stdin is a terminal, or INSTALL_INTERACTIVE=1 (tests pipe answers in).
interactive(){ [ -t 0 ] || [ "${INSTALL_INTERACTIVE:-0}" = 1 ]; }
# ask VAR PROMPT DEFAULT WHERE : keeps a value already set; otherwise asks (empty
# answer = DEFAULT) or, with no terminal, fails naming WHERE to put it.
ask(){
  local var="$1" prompt="$2" def="${3:-}" where="$4" v
  eval "v=\${$var:-}"; [ -z "$v" ] || return 0
  interactive || fail "${var} is not set and there is no terminal to ask on: set it in ${where}"
  printf '  %s [%s]: ' "$prompt" "$def" >&2; IFS= read -r v || v=""
  [ -n "$v" ] || v="$def"
  [ -n "$v" ] || fail "${var} needs a value (${where})"
  eval "$var=\$v"; export "$var"
}
# ask_secret VAR WHERE : like ask, typed hidden, no default, never echoed.
ask_secret(){
  local var="$1" where="$2" v
  eval "v=\${$var:-}"; [ -z "$v" ] || return 0
  interactive || fail "${var} is not set and there is no terminal to ask on: put it in ${where}"
  printf '  %s (hidden): ' "$var" >&2; IFS= read -r -s v || v=""; printf '\n' >&2
  [ -n "$v" ] || fail "${var} needs a value (${where})"
  eval "$var=\$v"; export "$var"
}

wait_for_http(){ # URL SECONDS : 200 or 401 counts as answering
  local url="$1" secs="${2:-300}" i code
  for i in $(seq 1 $((secs/5))); do
    code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null)"
    case "$code" in 200|401) return 0 ;; esac
    sleep 5
  done
  return 1
}

# wait_for_http_or_restart URL SECONDS CONTAINER : like wait_for_http, but a
# container Docker has restarted meanwhile is a crash loop, not a slow boot:
# return 2 at once with its last log lines instead of burning the timeout
# (first live clinic, manpur: OpenMRS looped for 25 min behind "Running").
wait_for_http_or_restart(){
  local url="$1" secs="${2:-300}" c="$3" i code r0 r
  r0="$(ct inspect --format '{{.RestartCount}}' "$c" 2>/dev/null || printf 0)"
  for i in $(seq 1 $((secs/5))); do
    code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null)"
    case "$code" in 200|401) return 0 ;; esac
    r="$(ct inspect --format '{{.RestartCount}}' "$c" 2>/dev/null || printf 0)"
    if [ "${r:-0}" -gt "${r0:-0}" ]; then
      warn "$c restarted $((r - r0)) time(s) while we waited: a crash loop, not a slow boot. Its last log lines:"
      ct logs --tail 15 "$c" 2>&1 | sed 's/^/    /' >&2
      return 2
    fi
    sleep 5
  done
  return 1
}

# ensure_stopped CONTAINER : stop it and PROVE it stayed down. A stop that
# raced the restart policy left odoo-connect looping on manpur while task 080
# believed it was parked (F-066 replay risk). A container that does not exist
# counts as stopped.
ensure_stopped(){
  local c="$1" i
  for i in 1 2 3; do
    ct stop "$c" >/dev/null 2>&1 || true
    [ "$(ct inspect --format '{{.State.Running}}' "$c" 2>/dev/null || printf false)" = false ] && return 0
    sleep 2
  done
  return 1
}

# --- OpenMRS JVM options ----------------------------------------------------
# infoiplitin/openmrs:iplit-1.0.0-662-4 shipped Java 8u372, whose cgroup v2
# metrics code threw a NullPointerException on an Azure Ubuntu 24.04 host the
# moment Tomcat registered its MBeans; the container restart-looped behind a
# green "Running" (first live clinic, manpur, 2026-09-17; reproduced on the hub
# with jrunscript). -XX:-UseContainerSupport skipped that code, after which the
# JVM sized its heap from host RAM -- so the heap is pinned explicitly
# regardless (Rawach's proven cap, F-050).
#
# RETIRED 2026-09-17 (sync-core Task 4): the fleet pin moved to
# infoiplitin/openmrs:iplit-1.2.0-1200-03, Java 8u432, which does not have the
# bug. This function used to ADD the flag to any .env missing it (a template-
# era node, repaired on resume, not by hand) -- it must NOT do that any more,
# or task 080 would silently reintroduce on every run the exact flag this
# task's .env.example edit just removed. An operator's own flag (added by
# hand, or left over on a node still running the old image) is left alone
# either way: this function only ever adds what is missing, and the flag is no
# longer something it considers missing. The heap cap is unrelated to the bug
# and stays pinned regardless.
OMRS_HEAP_CAP='-Xms512m -Xmx2048m -XX:NewSize=128m -XX:MaxMetaspaceSize=512m'
ensure_openmrs_jvm_opts(){ # ENV_FILE
  local f="$1" mem changed=''
  mem="$(env_get "$f" OMRS_JAVA_MEMORY_OPTS)"
  case " $mem " in *" -Xmx"*) ;; *) env_put "$f" OMRS_JAVA_MEMORY_OPTS "${OMRS_HEAP_CAP}"; changed="${changed} heap=${OMRS_HEAP_CAP}" ;; esac
  if [ -n "$changed" ]; then ok "openmrs JVM opts pinned in .env:${changed}"; else skip "openmrs JVM opts already pinned"; fi
}
# Three repo scripts call `podman` by name; on a Docker host they get a shim
# that forwards to docker for the duration of the run.
mk_podman_shim(){
  [ "${CT:-}" = docker ] || return 0
  mkdir -p "${INSTALL_DIR}/.bin"
  printf '#!/bin/sh\nexec docker "$@"\n' > "${INSTALL_DIR}/.bin/podman"; chmod +x "${INSTALL_DIR}/.bin/podman"
  export PATH="${INSTALL_DIR}/.bin:${PATH}"
}
check_eq(){ if [ "$2" = "$3" ]; then ok "$1 = $2"; else fail "$1: got '$2', want '$3'"; fi; }

# The fleet's one pin file (L-005: lockstep, cloud first -- change here,
# nowhere else). REPO_DIR may itself be overridden by a test harness pointing
# at a tmp checkout, so this is resolved relative to REPO_DIR, not a fixed path.
VERSIONS_FILE="${VERSIONS_FILE:-${REPO_DIR:-$(cd "${INSTALL_DIR}/../.." && pwd)}/sync/versions.env}"
# versions_put FILE : copy every KEY=value of sync/versions.env into FILE (env_put semantics)
versions_put(){
  local f="$1" line k v
  [ -f "${VERSIONS_FILE}" ] || fail "version pins missing: ${VERSIONS_FILE}"
  # `|| [ -n "$line" ]` : a versions.env saved without a trailing newline on its
  # last line would otherwise drop that last KEY=value silently (the same class
  # of bug subsystem_tables's own comment above documents for sync/subsystems.conf).
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    k="${line%%=*}"; v="${line#*=}"; v="${v%%#*}"; v="$(printf '%s' "$v" | sed -E 's/[[:space:]]+$//')"
    env_put "$f" "$k" "$v"
  done < "${VERSIONS_FILE}"
}
