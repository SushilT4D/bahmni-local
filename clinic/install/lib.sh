#!/usr/bin/env bash
# Shared helpers for clinic/install. The shape (begin_task / ok / skip / fail, one
# task per file, --force-free idempotence) follows initialize/lib.sh on
# main; the content is this fleet's: derived identity, the residue ledger, the
# .env quoting contract, docker/podman behind one wrapper.
#
# bash 3.2 compatible on purpose: macOS ships 3.2. No associative arrays, no
# mapfile, no ${var,,}.
set -o pipefail

INSTALL_DIR="${INSTALL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# port_in_use PORT : something on this host listens on TCP PORT. netstat sees
# every listener whoever owns it; lsof run as a normal user on macOS sees only
# that user's sockets, so a port held by a root service would pass unseen.
port_in_use(){
  local p="$1"
  if command -v netstat >/dev/null 2>&1; then
    netstat -an 2>/dev/null | awk '/LISTEN/ {print $4}' | grep -qE "[.:]${p}\$" && return 0
  fi
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk 'NR>1 {print $4}' | grep -qE ":${p}\$" && return 0
  fi
  command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1
}
# The branch a clinic installs from; preflight refuses another unless EXPECTED_BRANCH names it.
INSTALL_BRANCH="${INSTALL_BRANCH:-feat/install-seed-split}"
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
  compose_files_exist
}
# Every file clinic/.env's COMPOSE_FILE names must exist, or every compose call fails.
compose_files_exist(){
  local cf f missing=""
  cf="$( [ -f "${CLINIC_DIR}/.env" ] && env_get "${CLINIC_DIR}/.env" COMPOSE_FILE 2>/dev/null || true)"
  [ -n "$cf" ] || return 0
  local IFS=:
  for f in $cf; do [ -f "${CLINIC_DIR}/$f" ] || missing="$missing $f"; done
  [ -z "$missing" ] || fail "clinic/.env COMPOSE_FILE names a file that does not exist:${missing}. Set it to the files that do, e.g. COMPOSE_FILE=docker-compose.yml:docker-compose.macos.yml on macOS"
}
ct(){ "${CT:?setup_compose first}" "$@"; }
# compose ARGS... : always from the clinic dir, always with the fleet's profiles.
compose(){ ( cd "${CLINIC_DIR}" && ${COMPOSE_CMD:?setup_compose first} ${PROFILES} "$@" ); }

# .env editing. This file is read by TWO different parsers that do not agree
# on quoting in general: bash `.`-sourcing (every task) and docker compose's
# own dotenv reader (for ${VAR} interpolation in a compose file). A scheme
# that double-quotes a value on trigger characters but never escapes an
# embedded `"` -- a value like
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
# as an argv element: argv is world-readable while
# the process lives (`ps -ef`, /proc/<pid>/cmdline), and every secret this fleet
# generates -- all of hub/.env's, every clinic answer file's -- is written
# through this one function, so the old `python3 - "$f" "$k" "$v"` form put each
# of them on the process list of the machine composing the file. Only the FILE
# and the KEY (neither secret) stay in argv: the python3 substep reads the value
# from os.environ and must never read a third sys.argv element.
env_put(){
  local f="$1" k="$2" v="$3"
  case "$v" in
    *"'"*) fail "env_put: ${k}: a value containing a single quote cannot be stored in .env (bash and docker compose disagree on its meaning); choose another value" ;;
    *[!A-Za-z0-9_./:@+=-]*) v="'$v'" ;;
  esac
  ENV_PUT_VALUE="$v" _env_write "$f" "$k"
}
# env_del FILE KEY : removes every KEY= line from FILE, written the way env_put
# writes. A file without the key is left untouched.
env_del(){
  grep -qE "^$2=" "$1" 2>/dev/null || return 0
  ENV_PUT_DELETE=1 ENV_PUT_VALUE= _env_write "$1" "$2"
}
# _env_write FILE KEY : env_put's and env_del's one writer. The new file is
# written beside the old one, with its mode, and renamed over it: a reader (a
# scheduled script, a compose call) sees the old file or the new one, never a
# half-written one, and a crash leaves the old one.
_env_write(){
  python3 - "$1" "$2" <<'PY'
import os, sys, re, tempfile
f, k, v = sys.argv[1], sys.argv[2], os.environ["ENV_PUT_VALUE"]
f = os.path.realpath(f)
lines = open(f).read().split("\n")
pat = re.compile(r"^" + re.escape(k) + r"=")
if os.environ.get("ENV_PUT_DELETE") == "1":
    lines = [l for l in lines if not pat.match(l)]
else:
    done = False
    for i, l in enumerate(lines):
        if pat.match(l) and not done:
            lines[i] = f"{k}={v}"; done = True
    if not done:
        if lines and lines[-1] == "": lines.insert(len(lines) - 1, f"{k}={v}")
        else: lines.append(f"{k}={v}")
mode = os.stat(f).st_mode & 0o7777
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(f), prefix=os.path.basename(f) + ".tmp.")
try:
    os.fchmod(fd, mode)
    with os.fdopen(fd, "w") as out:
        out.write("\n".join(lines)); out.flush(); os.fsync(out.fileno())
    os.replace(tmp, f)
except BaseException:
    try: os.unlink(tmp)
    except OSError: pass
    raise
PY
}
# Under `set -e -o pipefail` (every task), a grep with no match or a tr cut short
# by head turns a pipeline non-zero and aborts the caller on the SUCCESS path.
# Hence the `|| true` guard. Strips a matching pair of quotes off the ends --
# single (env_put's own output) or double (an operator-hand-
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
# `grep | cut`. An untrimmed row --
# trailing whitespace, or an inline `#` comment left on the line -- used to come
# out with embedded whitespace in the table name. `pg_get_serial_sequence` then
# returns NULL for that name, and the striding SQL only logged a NOTICE and
# skipped it: a synced table silently left unstrided, with no failing check
# anywhere -- two nodes could mint the same id for that table.
# Now: strip a trailing `#...` comment, trim surrounding whitespace, skip the
# `:all` aggregate row, and `fail` on any surviving name that is not a bare
# lowercase identifier (naming the offending row) -- a typo'd or unquoted name
# is a defect to catch here, not something to carry forward as a silent NOTICE.
subsystem_tables(){
  local subsystem="$1" conf="${REPO_DIR}/sync/subsystems.conf" line name
  [ -f "$conf" ] || fail "subsystem_tables: no such file: $conf"
  # `|| [ -n "$line" ]` : bash's `read` returns non-zero on a final line with no
  # trailing newline, which would otherwise drop that last row silently --
  # the exact gap this function exists to close,
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
# down_tables : the table of every hub/tables.conf row, one per line, in file
# order -- every table the clinic's down sinks write, relayed ones included
# (clinic/scripts/generate-local-sink-connectors.sh reads the same rows). The
# sink user's grants come from this list, so a table added there is granted
# wherever the grants are applied: seed task 050, or
# clinic/scripts/grant-down-tables.sh on a node seeded before. A name that is
# not a bare lowercase identifier fails, naming its row.
down_tables(){
  local conf="${REPO_DIR}/hub/tables.conf" line name
  [ -f "$conf" ] || fail "down_tables: no such file: $conf"
  while IFS= read -r line || [ -n "$line" ]; do
    name="${line%%#*}"
    name="$(printf '%s' "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$name" ] || continue
    name="${name%%:*}"
    printf '%s' "$name" | grep -qE '^[a-z_][a-z0-9_]*$' \
      || fail "hub/tables.conf: bad table name '${name}' (row: ${line})"
    printf '%s\n' "$name"
  done < "$conf"
}
# sink_grant_sql : one GRANT per down table for the clinic's sink database
# user: what a JDBC upsert sink with deletes enabled needs, on that table only.
sink_grant_sql(){
  local ts t
  ts="$(down_tables)" || return 1
  for t in $ts; do printf "GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.%s TO 'sink'@'%%';\n" "$t"; done
}
# SINK_GRANTS_READ_SQL is the read-back: one "table<TAB>privileges" row per
# table the sink user holds a table-level grant on, and one "*<TAB>privileges"
# row each for a grant on the whole openmrs database and a global one. A
# privilege held at any of the three levels lets the sink write the table.
SINK_GRANTS_PRIVS="concat_ws(',', if(Select_priv='Y','Select',null), if(Insert_priv='Y','Insert',null), if(Update_priv='Y','Update',null), if(Delete_priv='Y','Delete',null))"
SINK_GRANTS_READ_SQL="select Table_name, Table_priv from mysql.tables_priv where User='sink' and Host='%' and Db='openmrs' union all select '*', ${SINK_GRANTS_PRIVS} from mysql.db where User='sink' and Host='%' and Db='openmrs' union all select '*', ${SINK_GRANTS_PRIVS} from mysql.user where User='sink' and Host='%'"
# sink_grants_missing [TABLE...] : stdin is SINK_GRANTS_READ_SQL's output;
# prints every named table (every down table when none is named) the sink user
# cannot select, insert, update and delete in, counting the table's own row
# and every "*" row together.
sink_grants_missing(){
  local got ts t p
  got="$(cat)"
  if [ $# -gt 0 ]; then ts="$*"; else ts="$(down_tables)" || return 1; fi
  for t in $ts; do
    p="$(printf '%s\n' "$got" | awk -F'\t' -v t="$t" '$1==t || $1=="*" {printf "%s,", tolower($2)}')"
    case ",${p}," in *,select,*) ;; *) printf '%s\n' "$t"; continue ;; esac
    case ",${p}," in *,insert,*) ;; *) printf '%s\n' "$t"; continue ;; esac
    case ",${p}," in *,update,*) ;; *) printf '%s\n' "$t"; continue ;; esac
    case ",${p}," in *,delete,*) ;; *) printf '%s\n' "$t"; continue ;; esac
  done
  return 0
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
refuse_inherited_alias(){ # ALIAS [SLUG]
  # The cluster alias is this node's own slug and nothing else: an env copied
  # from another node carries that node's alias, and MirrorMaker would then
  # publish under the wrong name. With the slug known, equality is the rule;
  # without it, the names other nodes and the templates use are refused.
  if [ -n "${2:-}" ]; then
    [ "$1" = "$2" ] || fail "LOCAL_CLUSTER_ALIAS '$1' is not this node's slug '$2' -- an alias inherited from another node's env; a node takes its own slug"
    return 0
  fi
  case "$1" in source|ghated|rawach|cloud|remote) fail "LOCAL_CLUSTER_ALIAS '$1' is another node's identity; a new node takes its own slug" ;; esac
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
ANSWER_KEYS="CLINIC_SLUG RESIDUE MRN_PREFIX SITE_NUMBER CLINIC_PHONE CERT_HOSTNAME REMOTE_KAFKA_BOOTSTRAP_SERVERS REMOTE_KAFKA_USERNAME REMOTE_KAFKA_PASSWORD OPENMRS_ATOMFEED_PASSWORD OPENELIS_ATOMFEED_PASSWORD ODOO_ATOMFEED_PASSWORD CLINICAL_UP_SYNC"
# Answers with a default: an answers file without one takes the default, and is
# not short of an answer for lacking it. CLINICAL_UP_SYNC=off keeps the
# clinical tables at the clinic (sync/local/tables-conf.sh).
ANSWER_DEFAULTS="CLINICAL_UP_SYNC=off"
answer_defaults_apply(){ local kv k; for kv in $ANSWER_DEFAULTS; do k="${kv%%=*}"; eval "[ -n \"\${$k:-}\" ] || $k=\"\${kv#*=}\"; export $k"; done; }
SECRET_KEYS="REMOTE_KAFKA_PASSWORD OPENMRS_ATOMFEED_PASSWORD OPENELIS_ATOMFEED_PASSWORD ODOO_ATOMFEED_PASSWORD"
# --- the hub link --------------------------------------------------------------
# hub_protocol: SASL_SSL (TLS, the default) or SASL_PLAINTEXT, from the
# environment, else sync/hub.env.
hub_protocol(){
  local p="${REMOTE_KAFKA_SECURITY_PROTOCOL:-}"
  [ -n "$p" ] || p="$(env_get "${HUB_ENV}" REMOTE_KAFKA_SECURITY_PROTOCOL 2>/dev/null || true)"
  printf '%s\n' "${p:-SASL_SSL}"
}
hub_tls(){ case "$(hub_protocol)" in *SSL) return 0 ;; *) return 1 ;; esac; }
# The hub's certificate: the one given for this run (HUB_CA), else the copy the
# install kept beside the node's own certificates (task 020), else the fleet's
# sync/hub-ca.pem. The kept copy is what lets the seed sitting, run later and
# without the install's environment, trust the same hub.
HUB_CA_KEPT="${CLINIC_DIR}/certs/hub-ca.pem"
if [ -z "${HUB_CA:-}" ]; then
  if [ -s "${HUB_CA_KEPT}" ]; then HUB_CA="${HUB_CA_KEPT}"; else HUB_CA="${REPO_DIR}/sync/hub-ca.pem"; fi
fi
# hub_truststore OUT IMAGE : a PKCS12 truststore holding sync/hub-ca.pem, made with
# the image's keytool. The password comes from REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD
# through the container's environment, never its command line.
hub_truststore(){
  local out="$1" img="$2" listing
  [ -s "${HUB_CA}" ] || fail "the hub link is $(hub_protocol) but ${HUB_CA#${REPO_DIR}/} (the hub's certificate) is missing"
  TSPW="${REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD:?}" ct run --rm -i -e TSPW --entrypoint sh "$img" -c \
    'cat > /tmp/ca.pem && keytool -importcert -noprompt -alias hub -file /tmp/ca.pem -keystore /tmp/t.p12 -storetype PKCS12 -storepass:env TSPW >/dev/null 2>&1 && cat /tmp/t.p12' \
    < "${HUB_CA}" > "${out}.new" || { rm -f "${out}.new"; fail "keytool in ${img} could not make a truststore from ${HUB_CA#${REPO_DIR}/}"; }
  [ -s "${out}.new" ] || { rm -f "${out}.new"; fail "the truststore made from ${HUB_CA#${REPO_DIR}/} is empty"; }
  mv "${out}.new" "$out"; chmod 644 "$out"
  listing="$(TSPW="${REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD}" ct run --rm -i -e TSPW --entrypoint sh "$img" -c \
    'cat > /tmp/t.p12 && keytool -list -keystore /tmp/t.p12 -storetype PKCS12 -storepass:env TSPW' < "$out" 2>&1 || true)"
  case "$listing" in *"hub, "*) return 0 ;; *) fail "the truststore does not open with REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD or holds no hub certificate" ;; esac
}
fleet_slugs(){ local f; for f in "${FLEET_DIR}"/*.env; do [ -f "$f" ] || continue; basename "$f" .env; done; }
# mysql_ready CONTAINER : true only when the FINAL server answers an authenticated query
# over TCP. `mysqladmin ping` exits 0 even on "Access denied", and the official image's first
# boot runs a temporary socket-only server whose root has no password yet; a wait built on
# ping passes against it and the restore then dies with ERROR 1045. That server runs --skip-networking,
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
mysql_pool_mb(){ # MEM_MB -> buffer pool MB: a fifth, 128 MB steps, 512..4096 (the rest of the stack shares a 10 GiB VM)
  local mem="${1:-0}" mb
  case "$mem" in ''|*[!0-9]*) mem=0 ;; esac
  mb=$(( mem / 5 / 128 * 128 ))
  [ "$mb" -gt 4096 ] && mb=4096
  [ "$mb" -lt 512 ] && mb=512
  printf '%s\n' "$mb"
}
mysql_tuning_cnf(){ # POOL_MB -> the conf.d file's text
  printf '# rendered by the installer from the memory this node gives its database server\n[mysqld]\ninnodb_buffer_pool_size = %sM\ninnodb_redo_log_capacity = 512M\nsql_mode = NO_ENGINE_SUBSTITUTION\n' "$1"
}

mysql_ready(){ [ "$(ct exec "$1" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -h127.0.0.1 -uroot -N -e "select 1"' 2>/dev/null)" = 1 ]; }
# user_in_group_db GROUP : is $USER a member of GROUP in the group DATABASE? `id -nG`
# with no argument lists the running PROCESS's groups, which never contain a group that
# usermod added a moment ago -- and that is exactly the moment task 010 asks.
user_in_group_db(){ id -nG "${USER:-$(id -un)}" 2>/dev/null | tr ' ' '\n' | grep -qx "$1"; }
# docker_group_reexec CMD ARGS... : a shell opened before the login user joined
# the docker group cannot reach the daemon ("permission denied"). When the user
# IS in the group, run the same command again under it rather than stop.
# _KRAFT_SG marks the re-run so a daemon that still refuses is reported, not
# looped on.
docker_group_reexec(){
  [ "${DRY:-0}" = 1 ] && return 0
  [ "${PLATFORM:-$(detect_platform)}" = linux ] && [ "$(detect_runtime)" = docker ] || return 0
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 && return 0
  [ "${_KRAFT_SG:-}" != 1 ] && command -v sg >/dev/null 2>&1 && user_in_group_db docker || return 0
  info "docker is refusing this shell, which predates the docker group; running again under the group (no re-login needed)"
  export _KRAFT_SG=1
  exec sg docker -c "$(printf '%q ' "$@")"
}
fleet_file(){ local f="${FLEET_DIR}/$(printf '%s' "$1" | tr 'A-Z' 'a-z').env"; [ -f "$f" ] && printf '%s\n' "$f"; }
# fleet_table : one line per registered clinic -- slug, residue ("-" = none), MRN prefix.
fleet_table(){ local s r; for s in $(fleet_slugs); do r="$(ledger_residue "$s")"; printf '  %-10s residue %-2s  MRN %s\n' "$s" "${r:--}" "$(env_get "$(fleet_file "$s")" MRN_PREFIX)"; done; return 0; }
# answers_missing FILE : prints every answer key that is absent or empty.
answers_missing(){ local k; for k in $ANSWER_KEYS; do case " $ANSWER_DEFAULTS" in *" $k="*) continue ;; esac; [ -n "$(env_get "$1" "$k")" ] || printf '%s\n' "$k"; done; return 0; }
# Answers a clinic may leave out: the forms repo (task 075; empty = the node
# runs the frozen copy in clinic/bahmni_home/clinical_forms) and the
# Initializer domain list (task 020 writes it into clinic/.env; empty = the
# clinic default, initializer.sh). They come from --secrets or the answers file.
OPTIONAL_ANSWER_KEYS="FORMS_REPO_URL FORMS_REPO_KEY OPENMRS_INITIALIZER_DOMAINS"
# answers_write FILE : the twelve keys from the current environment, plus each
# optional one that is set, mode 600.
answers_write(){
  local f="$1" k v; ( umask 077; : > "$f" ); chmod 600 "$f"
  for k in $ANSWER_KEYS; do eval "v=\${$k:-}"; env_put "$f" "$k" "$v"; done
  for k in $OPTIONAL_ANSWER_KEYS; do eval "v=\${$k:-}"; [ -z "$v" ] || env_put "$f" "$k" "$v"; done
}
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
# believed it was parked, replaying every past event. A container that does not exist
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
# green "Running". -XX:-UseContainerSupport skipped that code, after which the
# JVM sized its heap from host RAM -- so the heap is pinned explicitly
# regardless (a cap proven on a 121k-patient clinic).
#
# The fleet pin is now
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
#
# The Initializer's domain list is docker-compose.yml's to set, from
# OPENMRS_INITIALIZER_DOMAINS (clinic/install/initializer.sh). A
# -Dinitializer.domains= left in OMRS_JAVA_SERVER_OPTS (set there by hand)
# would put the property on the command line twice, so it is taken out here,
# and the value it carried is reported.
ensure_openmrs_jvm_opts(){ # ENV_FILE
  local f="$1" mem srv kept='' w dropped='' changed=''
  mem="$(env_get "$f" OMRS_JAVA_MEMORY_OPTS)"
  case " $mem " in *" -Xmx"*) ;; *) env_put "$f" OMRS_JAVA_MEMORY_OPTS "${OMRS_HEAP_CAP}"; changed="${changed} heap=${OMRS_HEAP_CAP}" ;; esac
  srv="$(env_get "$f" OMRS_JAVA_SERVER_OPTS)"
  case " $srv" in
    *" -Dinitializer.domains="*)
      set -f
      for w in $srv; do
        case "$w" in -Dinitializer.domains=*) dropped="${dropped} ${w}" ;; *) kept="${kept}${kept:+ }${w}" ;; esac
      done
      set +f
      env_put "$f" OMRS_JAVA_SERVER_OPTS "$kept"
      warn "OMRS_JAVA_SERVER_OPTS carried${dropped}; removed: docker-compose.yml sets -Dinitializer.domains from OPENMRS_INITIALIZER_DOMAINS (unset = the clinic default)"
      changed="${changed} initializer-domains-moved" ;;
  esac
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
# topic_events TOPIC : the end offset of partition 0 on this node's broker. A
# topic that does not exist yet (nothing written since a fresh seed) has 0
# events; its failed lookup must not end a set -e task.
topic_events(){
  local n
  n="$({ ct exec kafka kafka-get-offsets --bootstrap-server kafka:29092 --topic "$1" 2>/dev/null || true; } | sed -nE 's/^.*:0:([0-9]+)$/\1/p' | head -1)"
  printf '%s\n' "${n:-0}"
}
# pull_image IMAGE ARCH : the native pull; on an arm64 host an image published
# only for amd64 has no arm64 entry in its index, so the native pull fails every
# time -- pull the amd64 image instead (it runs emulated, as preflight says).
pull_image(){
  ct pull "$1" && return 0
  case "$2" in arm64|aarch64) ct pull --platform linux/amd64 "$1" ;; *) return 1 ;; esac
}

# The fleet's one pin file (lockstep, cloud first -- change here,
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
  # the application images this node chose (see IMAGE_KEYS) replace the defaults
  for k in $IMAGE_KEYS; do eval "v=\${$k:-}"; [ -z "$v" ] || env_put "$f" "$k" "$v"; done
}

# --- application image versions ------------------------------------------------
# IPLIT's and Bahmni's application images. sync/versions.env holds the default
# for each; the person installing a clinic may choose another version of any of
# them: install.sh --versions <file> (KEY=value lines), or the prompt. The
# choice is kept in the answers file for resumes, written into clinic/.env, and
# read back from there by the seed sitting. The sync layer (Kafka, MirrorMaker,
# Debezium) is not here: every node runs the same.
IMAGE_KEYS="OPENMRS_IMAGE_NAME ODOO_IMAGE_NAME ODOO_CONNECT_IMAGE_TAG OPENELIS_IMAGE_TAG BAHMNI_WEB_IMAGE BAHMNI_CONFIG_IMAGE IMPLEMENTER_INTERFACE_IMAGE_TAG PATIENT_DOCUMENTS_TAG ATOMFEED_CONSOLE_IMAGE_TAG"
# These applications change their database schema when they start, and the hub
# holds the same tables: a version that differs from the hub's breaks lockstep.
# Upgrade the hub first, then every clinic.
SCHEMA_IMAGE_KEYS="OPENMRS_IMAGE_NAME ODOO_IMAGE_NAME OPENELIS_IMAGE_TAG"
IMAGE_TAG_RE='^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$'
IMAGE_REF_RE='^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*(:[A-Za-z0-9_][A-Za-z0-9._-]{0,127})?(@sha256:[0-9a-f]{64})?$'
is_image_key(){ case " ${IMAGE_KEYS} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
is_schema_image_key(){ case " ${SCHEMA_IMAGE_KEYS} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
# pin_get KEY : the default in sync/versions.env, without its inline comment
pin_get(){
  local v; v="$({ grep -E "^$1=" "${VERSIONS_FILE}" || true; } | head -1 | cut -d= -f2-)"
  v="${v%%#*}"; printf '%s\n' "$v" | sed -E 's/[[:space:]]+$//'
}
# image_value KEY INPUT : prints the value to store, or fails. A *_TAG key takes a
# tag. The others take a full image reference (it has a / or a :), or a bare tag,
# which replaces the default's tag: BAHMNI_WEB_IMAGE=bhs-0.0.34 becomes
# infoiplitin/bahmni-iplit-web:bhs-0.0.34.
image_value(){
  local k="$1" v="$2" base
  is_image_key "$k" || fail "${k} is not an application image a node can choose; those are: ${IMAGE_KEYS}"
  [ -n "$v" ] || fail "${k} is empty"
  case "$k" in
    *_TAG) printf '%s' "$v" | grep -Eq "${IMAGE_TAG_RE}" || fail "${k}='${v}' is not an image tag"
           printf '%s\n' "$v"; return 0 ;;
  esac
  case "$v" in
    */*|*:*) printf '%s' "$v" | grep -Eq "${IMAGE_REF_RE}" || fail "${k}='${v}' is not an image reference"
             printf '%s\n' "$v" ;;
    *) printf '%s' "$v" | grep -Eq "${IMAGE_TAG_RE}" || fail "${k}='${v}' is neither an image reference nor a tag"
       base="$(pin_get "$k")"; base="${base%@*}"; base="${base%:*}"
       [ -n "$base" ] || fail "${k}: no default in ${VERSIONS_FILE} to put the tag '${v}' on"
       printf '%s:%s\n' "$base" "$v" ;;
  esac
}
# image_set KEY INPUT : validates and exports KEY
image_set(){ local v; v="$(image_value "$1" "$2")" || exit 1; eval "$1=\$v"; export "$1"; }
# image_choices_load FILE : KEY=value lines (comments and blanks skipped); every
# key must be an application image, every value valid
image_choices_load(){
  local f="$1" line k v
  [ -f "$f" ] || fail "image versions file not found: $f"
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//')"
    case "$line" in ''|'#'*) continue ;; *=*) ;; *) fail "$f: not KEY=value: ${line}" ;; esac
    k="${line%%=*}"; v="${line#*=}"; v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    image_set "$k" "$v"
  done < "$f"
}
# image_keys_from FILE : exports every application image FILE (a node's .env)
# sets, so a value this node chose wins over the default loaded before it
image_keys_from(){
  local f="$1" k v
  for k in $IMAGE_KEYS; do v="$(env_get "$f" "$k")"; [ -z "$v" ] || { eval "$k=\$v"; export "$k"; }; done
}
# image_choose : on a terminal, offers to keep the defaults; otherwise asks for
# each image, Enter keeping the value shown
image_choose(){
  local a k v cur
  interactive || return 0
  printf '  application image versions (sync/versions.env): keep the defaults? [Y/n]: ' >&2
  IFS= read -r a || a=""
  case "$a" in n|N|no|NO|No) ;; *) return 0 ;; esac
  printf '  for each image, Enter keeps the value shown; a bare tag keeps the image name\n' >&2
  for k in $IMAGE_KEYS; do
    eval "cur=\${$k:-}"; [ -n "$cur" ] || cur="$(pin_get "$k")"
    printf '  %s [%s]: ' "$k" "$cur" >&2; IFS= read -r v || v=""
    image_set "$k" "${v:-$cur}"
  done
}
# image_choices_write FILE : records in FILE each application image that differs
# from its default (an answers file, so a resume makes the same choice)
image_choices_write(){
  local f="$1" k v
  for k in $IMAGE_KEYS; do eval "v=\${$k:-}"; [ -z "$v" ] || [ "$v" = "$(pin_get "$k")" ] || env_put "$f" "$k" "$v"; done
}
# image_choices_report : names each application image that differs from its
# default, and warns where that breaks lockstep with the hub
image_choices_report(){
  local k v p n=0
  for k in $IMAGE_KEYS; do
    eval "v=\${$k:-}"; p="$(pin_get "$k")"
    [ -n "$v" ] && [ "$v" != "$p" ] || continue
    n=$((n + 1)); info "image ${k}=${v} (default ${p})"
    if is_schema_image_key "$k"; then
      warn "${k}: this application changes its database schema when it starts; the hub must run the same version (upgrade the hub first, then every clinic)"
    fi
  done
  [ "$n" -gt 0 ] || info "application images: the defaults in sync/versions.env"
}

# --- phases -------------------------------------------------------------------
# A clinic is built in two sittings: install (operator, before the machine
# ships: host, images, a disposable baseline, no sync) and seed (clinic staff,
# on site: the hub's data replaces the baseline, sync starts). Each task file's
# line 2 says which sitting runs it; a task that differs by sitting reads $PHASE.
task_phase(){ # FILE -> install | seed | both
  local p; p="$(sed -n '2s/^# phase: *//p' "$1")"
  case "$p" in install|seed|both) printf '%s\n' "$p" ;; *) printf 'both\n' ;; esac
}
phase_runs(){ # PHASE TASK_PHASE
  [ "$2" = both ] || [ "$1" = "$2" ]
}
run_tasks(){ # PHASE RESUME_HINT : every matching task in order; ONLY / FROM honoured
  local phase="$1" hint="$2" t n num rc t0 dt
  export PHASE="$phase"
  for t in "${TASKS_DIR}"/[0-9]*-*.sh; do
    n="$(basename "$t" .sh)"; num="${n%%-*}"
    phase_runs "$phase" "$(task_phase "$t")" || continue
    if [ -n "${ONLY:-}" ] && [ "$num" != "$ONLY" ]; then continue; fi
    if [ -n "${FROM:-}" ] && [ "$num" -lt "$FROM" ]; then continue; fi
    t0=$(date +%s); rc=0; bash "$t" || rc=$?; dt=$(( $(date +%s) - t0 ))
    if [ "$rc" = 75 ] && [ "${_KRAFT_SG:-}" != 1 ] && command -v sg >/dev/null 2>&1; then
      log "  ${n} ${dt}s rc=75: activating the docker group and continuing (no re-login needed)..."
      export _KRAFT_SG=1
      exec sg docker -c "${hint} --from ${num}"
    fi
    if [ "$rc" != 0 ]; then
      log "  ${n} ${dt}s STOPPED rc=${rc}"
      printf '\n  STOPPED at task %s. Fix what its FAIL (or FAILED rc=) line names, then resume with: %s --from %s\n  log: %s\n' "$n" "$hint" "$num" "${INSTALL_LOG:-}" >&2
      exit 1
    fi
    log "  ${n} ${dt}s done"
  done
}
# has_text BODY NEEDLE : judge a captured value whole. Under pipefail,
# `printf "$body" | grep -q` fails when the match is FOUND: grep exits at the
# first hit and the writer's next chunk dies of SIGPIPE.
has_text(){ case "$1" in *"$2"*) return 0 ;; esac; return 1; }
# elis_page_ok CODE BODY : the page OpenELIS lands on answers 200, names
# OpenELIS, and is not Tomcat's own error page (which names the path it could
# not serve, "/openelis/", so the word alone proves nothing). The body is
# judged whole, never piped into `grep -q`: grep stops at the first match, the
# writer dies of SIGPIPE on its next chunk, and under pipefail a page that
# matched reads as one that did not.
elis_page_ok(){
  local lc
  [ "$1" = 200 ] || return 1
  lc="$(printf '%s' "$2" | tr 'A-Z' 'a-z')"
  case "$lc" in *openelis*) ;; *) return 1 ;; esac
  case "$2" in *'HTTP Status'*) return 1 ;; esac
  return 0
}

# capture_filter_check : the source connector's capture filter as Kafka
# Connect holds it (GET .../config of the registered connector, never the
# generated file), against this node: its residue must be the
# auto_increment_offset the running MySQL issues ids on, and its floors the
# ones the seed's manifest gives (the seed folder's, or else the copy the seed
# gate recorded on this machine). sync/origin-filter.sh holds the rules.
# Prints "ok ..." lines, or the refusal and returns 1. CONNECT_URL overrides
# the Connect address.
capture_filter_check(){
  local reg off floors v rc
  type up_tables_read >/dev/null 2>&1 || . "${REPO_DIR}/sync/local/tables-conf.sh"
  type origin_filter_verdict >/dev/null 2>&1 || . "${REPO_DIR}/sync/origin-filter.sh"
  reg="$(mktemp)"
  if ! curl -sf --max-time 10 "${CONNECT_URL:-http://localhost:8083}/connectors/mysql-source-connector/config" > "$reg" 2>/dev/null; then
    rm -f "$reg"
    printf 'could not read the registered mysql-source-connector configuration from Kafka Connect, so its capture filter was not checked: %s logs kafka-connect\n' "${COMPOSE_CMD:-docker compose}"
    return 1
  fi
  off="$(printf 'select @@global.auto_increment_offset' | ct exec -i "${COMPOSE_PROJECT_NAME}-bahmni-mysql-1" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N' 2>/dev/null | tail -1 || true)"
  floors="${SEED_DIR:-}/manifest.env"; [ -f "$floors" ] || floors="${STATE_FILE:-${CLINIC_DIR}/.install-state}"
  v="$(origin_filter_verdict "$reg" "${REPO_DIR}/sync/local/tables.conf" "$floors" "$off")"; rc=$?
  rm -f "$reg"
  printf '%s\n' "$v"
  return "$rc"
}

# The source connector's signal table, in the structure Debezium documents for
# its source signal channel: three columns in this order, the first the key. A
# row inserted there (type execute-snapshot) asks the connector for an
# incremental snapshot, the way a clinic sends rows it wrote before a table
# was captured. With the connector's default (not read-only) incremental
# snapshot, the connector writes its own window markers into the table, so its
# database user may insert, update and delete there. Created at seed; the
# seed's dump does not carry it, because the hub has none.
# Each takes the OpenMRS database (DATABASE_NAME, default openmrs), the one the
# source connector's include list and signal collection name.
signal_table_db(){ printf '%s' "${1:-${DATABASE_NAME:-openmrs}}"; }
signal_table_ddl(){ printf 'CREATE TABLE IF NOT EXISTS %s.debezium_signal (id VARCHAR(42) PRIMARY KEY, type VARCHAR(32) NOT NULL, data VARCHAR(2048) NULL)' "$(signal_table_db "${1:-}")"; }
signal_table_grant(){ printf "GRANT SELECT, INSERT, UPDATE, DELETE ON %s.debezium_signal TO 'debezium'@'%%'" "$(signal_table_db "${1:-}")"; }
# what information_schema says of it: column, type, nullable, key; then the
# privileges the debezium user holds on it
signal_table_read_sql(){
  local db; db="$(signal_table_db "${1:-}")"
  printf "select 'col', column_name, column_type, is_nullable, column_key from information_schema.columns where table_schema='%s' and table_name='debezium_signal' order by ordinal_position; select 'priv', privilege_type from information_schema.table_privileges where grantee=\"'debezium'@'%%'\" and table_schema='%s' and table_name='debezium_signal' order by privilege_type;" "$db" "$db"
}
SIGNAL_TABLE_WANT='col id varchar(42) NO PRI
col type varchar(32) NO
col data varchar(2048) YES'

# signal_table_verdict [DB] : stdin is signal_table_read_sql's output (tab-
# separated). Prints "ok ..." or what is wrong and returns 1.
signal_table_verdict(){
  local rows cols privs p t
  t="$(signal_table_db "${1:-}").debezium_signal"
  rows="$(cat)"
  cols="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="col" {s=$1" "$2" "$3" "$4; if ($5 != "") s=s" "$5; print s}')"
  if [ -z "$cols" ]; then
    printf 'the signal table %s does not exist, so no catch-up of rows written before a table was captured can be asked for. Rerun the seed from its databases step (seed.sh --seed <folder> --from 050) or call the operator.\n' "$t"; return 1
  fi
  if [ "$cols" != "$SIGNAL_TABLE_WANT" ]; then
    printf '%s is not the signal table the source connector reads (columns: %s; want: %s). Call the operator.\n' "$t" "$(printf '%s' "$cols" | sed 's/^col //' | tr '\n' ';')" "$(printf '%s' "$SIGNAL_TABLE_WANT" | sed 's/^col //' | tr '\n' ';')"; return 1
  fi
  privs="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="priv" {print $2}' | tr '\n' ' ')"
  for p in SELECT INSERT UPDATE DELETE; do
    case " $privs" in *" $p "*) ;; *) printf 'the debezium user lacks %s on %s, so an incremental snapshot cannot record its progress there. Rerun the seed from its databases step (seed.sh --seed <folder> --from 050) or call the operator.\n' "$p" "$t"; return 1 ;; esac
  done
  printf 'ok signal table %s (id, type, data), writable by the debezium user\n' "$t"
}

# signal_capture_verdict CONFIG_JSON : a registered source configuration must
# read signals from the source channel and capture the table it names, or a
# signal inserted there is never seen. Prints "ok ..." or the refusal.
signal_capture_verdict(){
  python3 - "$1" <<'PY'
import json, sys
try:
    c = json.load(open(sys.argv[1]))
except Exception as e:
    print("the registered source configuration cannot be read as JSON (%s)" % e); sys.exit(1)
c = c.get("config", c)
coll = c.get("signal.data.collection", "")
chans = [x.strip() for x in c.get("signal.enabled.channels", "").split(",")]
inc = [x.strip() for x in c.get("table.include.list", "").split(",")]
if not coll:
    print("the registered source connector names no signal table (signal.data.collection)"); sys.exit(1)
if "source" not in chans:
    print("the registered source connector does not read signals from its signal table (signal.enabled.channels is %r)" % c.get("signal.enabled.channels", "")); sys.exit(1)
if coll not in inc:
    print("the registered source connector does not capture its signal table %s (not in table.include.list), so a signal inserted there is never read. Regenerate and register it (scripts/generate-connectors.sh, then scripts/register-source-connector.sh)." % coll); sys.exit(1)
print("ok source connector captures its signal table %s" % coll)
PY
}

# signal_capture_check : signal_capture_verdict on the configuration Kafka
# Connect holds for mysql-source-connector.
signal_capture_check(){
  local reg rc
  reg="$(mktemp)"
  if ! curl -sf --max-time 10 "${CONNECT_URL:-http://localhost:8083}/connectors/mysql-source-connector/config" > "$reg" 2>/dev/null; then
    rm -f "$reg"; printf 'could not read the registered mysql-source-connector configuration from Kafka Connect, so its signal table was not checked: %s logs kafka-connect\n' "${COMPOSE_CMD:-docker compose}"; return 1
  fi
  signal_capture_verdict "$reg"; rc=$?
  rm -f "$reg"; return "$rc"
}

# provenance_content_lines RECORD CONTAINER : clinic/scripts/master-checksum.sh
# run on this clinic's MySQL over exactly the tables the seed's provenance
# record holds content lines for (the tool checksums the tables a hub/tables.conf
# lists, so it runs from a scratch copy whose list is the record's).
provenance_content_lines(){
  local rec="$1" my="$2" d rc=0
  d="$(mktemp -d)"; mkdir -p "$d/clinic/scripts" "$d/clinic/install" "$d/hub"
  cp "${REPO_DIR}/clinic/scripts/master-checksum.sh" "$d/clinic/scripts/"
  cp "${REPO_DIR}/clinic/install/lib.sh" "$d/clinic/install/"
  cp "${REPO_DIR}/hub/table-verdicts.conf" "${REPO_DIR}/hub/checksum-exclusions.conf" "$d/hub/"
  awk -F'\t' '$1=="content" {print $2}' "$rec" > "$d/hub/tables.conf"
  REPO_DIR="$d" CLINIC_DIR="$d/clinic" CT="${CT:-}" bash "$d/clinic/scripts/master-checksum.sh" --container "$my" || rc=$?
  rm -rf "$d"; return "$rc"
}

# clinic_fk_rows CONTAINER : CLINIC_FK_READ_SQL (state.sh) on this clinic's
# MySQL. Returns 1 when nothing comes back: a schema with no foreign key at
# all is not an OpenMRS schema, and an empty read is never compared.
clinic_fk_rows(){
  local rows
  rows="$(printf '%s\n' "${CLINIC_FK_READ_SQL}" | ct exec -i "$1" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N -B' 2>/dev/null || true)"
  [ -n "$rows" ] || return 1
  printf '%s\n' "$rows"
}

# The package manager on Ubuntu: unattended upgrades start on their own
# (often minutes after a machine first boots) and hold dpkg's lock while they
# run, and an apt-get that meets the lock fails at once. apt_get waits for the
# lock on a named budget, APT_LOCK_TIMEOUT_S (default 600 s), first by itself,
# so the wait is said, then through apt's own DPkg::Lock::Timeout for a lock
# taken between the two. A lock still held when the budget runs out fails,
# naming the process that holds it.
APT_LOCKS="/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock"
# apt_lock_holder : "<pid> <name>" of a process holding a package lock, or nothing
apt_lock_holder(){
  local f p
  if command -v fuser >/dev/null 2>&1; then
    for f in ${APT_LOCKS}; do
      p="$(sudo fuser "$f" 2>/dev/null | tr -s ' \t' '\n' | grep -E '^[0-9]+$' | head -1 || true)"
      if [ -n "$p" ]; then printf '%s %s\n' "$p" "$(ps -o comm= -p "$p" 2>/dev/null || echo unknown)"; return 0; fi
    done
    return 0
  fi
  ps -eo pid=,comm= 2>/dev/null | awk '$2 ~ /^(apt|apt-get|aptitude|dpkg|unattended-upgr|packagekitd)$/ {print $1, $2; exit}'
}
# apt_wait_lock : returns once no process holds a package lock; fails after
# APT_LOCK_TIMEOUT_S, naming the holder
apt_wait_lock(){
  local max="${APT_LOCK_TIMEOUT_S:-600}" step="${APT_LOCK_POLL_S:-5}" w=0 h
  while h="$(apt_lock_holder)"; [ -n "$h" ]; do
    if [ "$w" -ge "$max" ]; then
      fail "the package manager is still locked after ${max}s, held by process ${h} -- usually Ubuntu's automatic updates. Let it finish (sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log), then resume with --from 010; APT_LOCK_TIMEOUT_S sets the wait."
    fi
    [ "$w" = 0 ] && info "the package manager is busy (process ${h}); waiting up to ${max}s for it to finish"
    sleep "$step"; w=$((w + step)); [ "$step" -gt 0 ] || w=$((w + 1))
  done
}
# apt_get ARGS... : sudo apt-get ARGS, after the lock is free, itself waiting
# for a lock taken in between
apt_get(){
  if [ "${DRY}" = 1 ]; then printf '  would: sudo apt-get %s\n' "$*"; return 0; fi
  apt_wait_lock
  sudo apt-get -o DPkg::Lock::Timeout="${APT_LOCK_TIMEOUT_S:-600}" "$@"
}
