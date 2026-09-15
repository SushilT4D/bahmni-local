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

# .env editing. A value containing a space, &, !, #, $, ; or | is double-quoted
# (the file is read both by compose interpolation and by scripts that `source`
# it). Python does the replace so no character in the value needs escaping.
env_put(){
  local f="$1" k="$2" v="$3"
  case "$v" in *[' &!#$;|']*) v="\"$v\"" ;; esac
  python3 - "$f" "$k" "$v" <<'PY'
import sys, re
f, k, v = sys.argv[1], sys.argv[2], sys.argv[3]
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
env_get(){ grep -E "^$2=" "$1" | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }
gen_secret(){ LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; }
# Kafka cluster id: 22 chars of url-safe base64 over 16 random bytes, what
# kafka-storage random-uuid produces, without needing the image.
kafka_cluster_id(){ python3 -c 'import uuid,base64; print(base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip("="))'; }

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
  grep -E '^[A-Z_0-9]+=(<[^>]*>)?$' "$f" | cut -d= -f1 | while read -r k; do
    case "$allow" in *" $k "*) ;; *) printf '%s\n' "$k" ;; esac
  done
}
refuse_inherited_alias(){
  case "$1" in source|ghated|rawach|cloud|remote) fail "LOCAL_CLUSTER_ALIAS '$1' is another node's identity (AL-022); a new node takes its own slug" ;; esac
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
# Three repo scripts call `podman` by name; on a Docker host they get a shim
# that forwards to docker for the duration of the run.
mk_podman_shim(){
  [ "${CT:-}" = docker ] || return 0
  mkdir -p "${INSTALL_DIR}/.bin"
  printf '#!/bin/sh\nexec docker "$@"\n' > "${INSTALL_DIR}/.bin/podman"; chmod +x "${INSTALL_DIR}/.bin/podman"
  export PATH="${INSTALL_DIR}/.bin:${PATH}"
}
check_eq(){ if [ "$2" = "$3" ]; then ok "$1 = $2"; else fail "$1: got '$2', want '$3'"; fi; }
