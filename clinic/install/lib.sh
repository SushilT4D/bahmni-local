#!/usr/bin/env bash
# Shared helpers for the installer: output and failure, .env reading and writing, podman and compose wrappers.
set -o pipefail

INSTALL_DIR="${INSTALL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

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

INSTALL_BRANCH="${INSTALL_BRANCH:-main}"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${INSTALL_DIR}/.." && pwd)}"
REPO_DIR="${REPO_DIR:-$(cd "${CLINIC_DIR}/.." && pwd)}"
CLINICS_JSON="${CLINICS_JSON:-${REPO_DIR}/sync/clinics.json}"
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

_on_err(){
  local rc=$? ps="${PIPESTATUS[*]}" cmd="$BASH_COMMAND" i=1 n chain='' pipe=''
  trap - ERR   # bash 3.2 fires ERR on a false (( )) or [ ] inside the handler itself

  case "$ps" in *' '*) pipe=" (pipeline statuses: ${ps}; the first non-zero is the culprit)" ;; esac
  while [ "$i" -lt "${#BASH_SOURCE[@]}" ]; do
    n="${FUNCNAME[$i]}"; case "$n" in main|source) n='' ;; esac
    chain="${chain}${chain:+ <- }${BASH_SOURCE[$i]##*/}:${BASH_LINENO[$((i-1))]}${n:+ ($n)}"
    i=$((i+1))
  done

  printf '  FAILED rc=%s%s: %s\n         at %s\n' "$rc" "$pipe" "$cmd" "${chain:-${BASH_SOURCE[0]##*/}}" >&2
  trap _on_err ERR
}

case "$-" in *e*) [ "${BASH_VERSINFO[0]}" -ge 4 ] && { set -E; trap _on_err ERR; } ;; esac

# Stack name, as name: in docker-compose.yml.
COMPOSE_PROJECT_NAME=bahmni; export COMPOSE_PROJECT_NAME

# Every clinic's podman machine.
MACHINE_CPUS=5; MACHINE_MIB=11000; MACHINE_DISK_GB=100; MACHINE_SWAP_GB=4

# The address staff open Bahmni at (and odoo.<it> for Odoo), on every clinic.
LAN_NAME=bahmni.clinic; export LAN_NAME

run(){ if [ "${DRY}" = 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }

require_macos(){ [ "$(uname -s)" = Darwin ] || fail "this installer runs on macOS only (found $(uname -s))"; }

setup_compose(){
  CT="${CT:-podman}"
  COMPOSE_CMD="podman-compose"
  export CT COMPOSE_CMD
}

ct(){ "${CT:?setup_compose first}" "$@"; }

compose(){ ( cd "${CLINIC_DIR}" && ${COMPOSE_CMD:?setup_compose first} ${PROFILES} "$@" ); }

# podman-compose has no `config --format json` or `--images`: its own Python (which has PyYAML) converts.
compose_json(){ # : the merged config as JSON, volumes in long form (type, source, target, read_only)
  local py
  py="$(head -1 "$(command -v podman-compose)" | sed 's/^#! *//')"
  compose config | "$py" -c '
import json, os, sys, yaml
d = yaml.safe_load(sys.stdin) or {}
here = sys.argv[1]
for svc in (d.get("services") or {}).values():
    vols = []
    for v in svc.get("volumes") or []:
        if isinstance(v, str):
            p = v.split(":")
            src, tgt, opt = p[0], (p[1] if len(p) > 1 else p[0]), (p[2] if len(p) > 2 else "")
            bind = src.startswith(("/", ".", "~"))
            if bind: src = os.path.normpath(os.path.join(here, os.path.expanduser(src)))
            v = {"type": "bind" if bind else "volume", "source": src, "target": tgt, "read_only": "ro" in opt.split(",")}
        vols.append(v)
    if vols: svc["volumes"] = vols
json.dump(d, sys.stdout)' "${CLINIC_DIR}"
}

compose_images(){ compose_json | python3 -c 'import json,sys; print("\n".join(s["image"] for s in json.load(sys.stdin)["services"].values() if s.get("image")))'; }

compose_bind_sources(){ compose_json | python3 -c 'import json,sys
for s in json.load(sys.stdin)["services"].values():
    for v in s.get("volumes") or []:
        if v.get("type") == "bind" and v.get("source"): print(v["source"])'; }

env_put(){
  local f="$1" k="$2" v="$3" bare
  bare="$(printf '%s' "$v" | sed -E 's/\$\{[A-Za-z_][A-Za-z0-9_]*\}//g')"   # ${NAME} references stay unquoted so compose expands them
  case "$v" in
    *"'"*) fail "env_put: ${k}: a value containing a single quote cannot be stored in .env (bash and docker compose disagree on its meaning); choose another value" ;;
  esac
  case "$bare" in
    *[!A-Za-z0-9_./:@+=-]*) v="'$v'" ;;
  esac

  ENV_PUT_VALUE="$v" _env_write "$f" "$k"
}

env_del(){
  grep -qE "^$2=" "$1" 2>/dev/null || return 0
  ENV_PUT_DELETE=1 ENV_PUT_VALUE= _env_write "$1" "$2"
}

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

tables_rows(){
  type tables_section >/dev/null 2>&1 || . "${REPO_DIR}/sync/tables/tables.sh"
  local sec
  sec="$(tables_section "$1" "$2")" || fail "cannot read the [$2] section of $1"
  printf '%s\n' "$sec" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true
}

checked_name(){ # NAME ROW FILE SECTION
  printf '%s' "$1" | grep -qE '^[a-z_][a-z0-9_]*$' \
    || fail "${3##*/} [$4]: bad table name '$1' (row: $2)"
  printf '%s\n' "$1"
}

subsystem_tables(){
  local f row
  case "$1" in odoo) f="${REPO_DIR}/sync/tables/odoo.conf" ;; clinlims|openelis) f="${REPO_DIR}/sync/tables/openelis.conf" ;; *) fail "subsystem_tables: unknown subsystem $1" ;; esac
  tables_rows "$f" up | while IFS= read -r row; do checked_name "$row" "$row" "$f" up || exit 1; done
}

down_tables(){
  local f="${REPO_DIR}/sync/tables/openmrs.conf" row
  tables_rows "$f" down | while IFS= read -r row; do checked_name "${row%%:*}" "$row" "$f" down || exit 1; done
}

master_down_tables(){
  local f="${REPO_DIR}/sync/tables/openmrs.conf" row
  tables_rows "$f" down | while IFS= read -r row; do
    case "$row" in *:*:clinic=*) continue ;; esac
    checked_name "${row%%:*}" "$row" "$f" down || exit 1
  done
}

sink_grant_sql(){
  local ts t
  ts="$(down_tables)" || return 1
  for t in $ts; do printf "GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.%s TO 'sink'@'%%';\n" "$t"; done
}

SINK_GRANTS_PRIVS="concat_ws(',', if(Select_priv='Y','Select',null), if(Insert_priv='Y','Insert',null), if(Update_priv='Y','Update',null), if(Delete_priv='Y','Delete',null))"
SINK_GRANTS_READ_SQL="select Table_name, Table_priv from mysql.tables_priv where User='sink' and Host='%' and Db='openmrs' union all select '*', ${SINK_GRANTS_PRIVS} from mysql.db where User='sink' and Host='%' and Db='openmrs' union all select '*', ${SINK_GRANTS_PRIVS} from mysql.user where User='sink' and Host='%'"

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

kafka_cluster_id(){ python3 -c 'import uuid,base64
while True:
    s = base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip("=")
    if not s.startswith("-"): print(s); break'; }

derive_identity(){
  local slug="$1" residue="$2"
  printf '%s' "$slug" | grep -Eq '^[a-z][a-z0-9]{1,15}$' || fail "slug '$slug' must match ^[a-z][a-z0-9]{1,15}$"
  printf '%s' "$residue" | grep -Eq '^[1-9]$' || fail "residue '$residue' must be a single digit 1-9 (10 is the cloud)"
  BHS_LOCATION="$slug"
  COMPOSE_PROJECT_NAME=bahmni   # matches name: in docker-compose.yml
  MYSQL_SERVER_NAME="bahmni-${slug}"
  BHS_SITE_NUMBER="$residue"
  DEBEZIUM_SERVER_ID="18405${residue}"
  LAN_IP="192.168.1.8${residue}"   # each clinic's fixed LAN address
  export LAN_IP BHS_LOCATION COMPOSE_PROJECT_NAME MYSQL_SERVER_NAME BHS_SITE_NUMBER DEBEZIUM_SERVER_ID
}

clinic_get(){ # SLUG FIELD -> the field from sync/clinics.json; nothing when absent or null
  jq -r --arg s "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" --arg f "$2" '.[$s][$f] // empty' "${CLINICS_JSON}" || fail "${CLINICS_JSON} is not valid JSON"
}
clinic_known(){ jq -e --arg s "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" 'has($s)' "${CLINICS_JSON}" >/dev/null; }
clinic_residue(){ clinic_get "$1" site_number; }   # a clinic's site number is its residue
residue_conflicts(){ # SLUG SITE -> every other clinic whose site number is SITE
  jq -r --arg s "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" --argjson r "$2" 'to_entries[] | select(.key != $s and .value.site_number == $r) | .key' "${CLINICS_JSON}"
}

has_placeholders(){
  local f="$1" allow=" ${2:-} " k
  { grep -E '^[A-Z_0-9]+=(<[^>]*>)?$' "$f" || true; } | cut -d= -f1 | while read -r k; do
    case "$allow" in *" $k "*) ;; *) printf '%s\n' "$k" ;; esac
  done

  return 0
}


INPUT_KEYS="BHS_SITE_NUMBER MRN_PREFIX REMOTE_KAFKA_BOOTSTRAP_SERVERS REMOTE_KAFKA_USERNAME REMOTE_KAFKA_PASSWORD OPENMRS_ATOMFEED_PASSWORD OPENELIS_ATOMFEED_PASSWORD ODOO_ATOMFEED_USER ODOO_ATOMFEED_PASSWORD"

INPUT_DEFAULTS="ODOO_ATOMFEED_USER=emrsync"
input_defaults_apply(){ local kv k; for kv in $INPUT_DEFAULTS; do k="${kv%%=*}"; eval "[ -n \"\${$k:-}\" ] || $k=\"\${kv#*=}\"; export $k"; done; }
SECRET_KEYS="REMOTE_KAFKA_PASSWORD OPENMRS_ATOMFEED_PASSWORD OPENELIS_ATOMFEED_PASSWORD ODOO_ATOMFEED_PASSWORD"
CLOUD_KEYS="REMOTE_KAFKA_BOOTSTRAP_SERVERS REMOTE_KAFKA_USERNAME REMOTE_KAFKA_SECURITY_PROTOCOL"   # the hub endpoint, from clinic/.env

cloud_protocol(){
  local p="${REMOTE_KAFKA_SECURITY_PROTOCOL:-}"
  [ -n "$p" ] || p="$(env_get "${CLINIC_DIR}/.env" REMOTE_KAFKA_SECURITY_PROTOCOL 2>/dev/null || true)"
  printf '%s\n' "${p:-SASL_SSL}"
}

cloud_tls(){ case "$(cloud_protocol)" in *SSL) return 0 ;; *) return 1 ;; esac; }

CLOUD_CA_KEPT="${CLINIC_DIR}/certs/cloud-ca.pem"
if [ -z "${CLOUD_CA:-}" ]; then
  if [ -s "${CLOUD_CA_KEPT}" ]; then CLOUD_CA="${CLOUD_CA_KEPT}"; else CLOUD_CA="${REPO_DIR}/sync/cloud-ca.pem"; fi
fi

cloud_truststore(){
  local out="$1" img="$2" listing
  [ -s "${CLOUD_CA}" ] || fail "the hub link is $(cloud_protocol) but ${CLOUD_CA#${REPO_DIR}/} (the hub's certificate) is missing"
  TSPW="${REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD:?}" ct run --rm -i -e TSPW --entrypoint sh "$img" -c \
    'cat > /tmp/ca.pem && keytool -importcert -noprompt -alias hub -file /tmp/ca.pem -keystore /tmp/t.p12 -storetype PKCS12 -storepass:env TSPW >/dev/null 2>&1 && cat /tmp/t.p12' \
    < "${CLOUD_CA}" > "${out}.new" || { rm -f "${out}.new"; fail "keytool in ${img} could not make a truststore from ${CLOUD_CA#${REPO_DIR}/}"; }
  [ -s "${out}.new" ] || { rm -f "${out}.new"; fail "the truststore made from ${CLOUD_CA#${REPO_DIR}/} is empty"; }
  mv "${out}.new" "$out"; chmod 644 "$out"
  listing="$(TSPW="${REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD}" ct run --rm -i -e TSPW --entrypoint sh "$img" -c \
    'cat > /tmp/t.p12 && keytool -list -keystore /tmp/t.p12 -storetype PKCS12 -storepass:env TSPW' < "$out" 2>&1 || true)"
  case "$listing" in *"hub, "*) return 0 ;; *) fail "the truststore does not open with REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD or holds no hub certificate" ;; esac
}

clinic_slugs(){ jq -r 'keys_unsorted[] | select(. != "cloud")' "${CLINICS_JSON}"; }

node_mem_mb(){ # memory the database server can see, in MB; NODE_MEM_MB overrides
  if [ -n "${NODE_MEM_MB:-}" ]; then printf '%s\n' "$NODE_MEM_MB"; return; fi
  local m; m="$(podman machine inspect --format '{{.Resources.Memory}}' 2>/dev/null || true)"
  case "$m" in ''|*[!0-9]*) m="$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1048576 ))" ;; esac
  printf '%s\n' "$m"
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

clinic_table(){ jq -r 'to_entries[] | select(.key != "cloud") | "  \(.key | . + "          " | .[0:10]) site \(.value.site_number // "-" | tostring | . + "  " | .[0:2])  MRN \(.value.mrn_prefix // "-")"' "${CLINICS_JSON}"; }

OPTIONAL_INPUT_KEYS="REMOTE_KAFKA_SECURITY_PROTOCOL FORMS_REPO_URL FORMS_REPO_KEY OPENMRS_INITIALIZER_DOMAINS"

gen_password(){ python3 -c 'import secrets,string
while True:
    p = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(20))
    if any(c.islower() for c in p) and any(c.isupper() for c in p): print(p); break'; }

ask(){
  local var="$1" def="${3:-}" where="$4" v
  eval "v=\${$var:-}"; [ -z "$v" ] || return 0
  v="$def"
  [ -n "$v" ] || fail "${var} needs a value: set it in ${where}"
  eval "$var=\$v"; export "$var"
}

ask_secret(){
  local var="$1" v
  eval "v=\${$var:-}"; [ -z "$v" ] || return 0
  v="$(gen_password)"
  info "${var}: none given; generated a new one"
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

ensure_stopped(){
  local c="$1" i
  for i in 1 2 3; do
    ct stop "$c" >/dev/null 2>&1 || true
    [ "$(ct inspect --format '{{.State.Running}}' "$c" 2>/dev/null || printf false)" = false ] && return 0
    sleep 2
  done

  return 1
}

OMRS_HEAP_CAP='-Xms512m -Xmx2048m -XX:NewSize=128m -XX:MaxMetaspaceSize=512m'

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

check_eq(){ if [ "$2" = "$3" ]; then ok "$1 = $2"; else fail "$1: got '$2', want '$3'"; fi; }

topic_events(){
  local n
  n="$({ ct exec kafka kafka-get-offsets --bootstrap-server kafka:29092 --topic "$1" 2>/dev/null || true; } | sed -nE 's/^.*:0:([0-9]+)$/\1/p' | head -1)"
  printf '%s\n' "${n:-0}"
}

pull_image(){ ct pull "$1" || ct pull --platform linux/amd64 "$1"; }

VERSIONS_FILE="${VERSIONS_FILE:-${REPO_DIR:-$(cd "${INSTALL_DIR}/../.." && pwd)}/sync/versions.env}"

versions_put(){
  local f="$1" line k v
  [ -f "${VERSIONS_FILE}" ] || fail "version pins missing: ${VERSIONS_FILE}"

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    k="${line%%=*}"
    v="${line#*=}"
    v="${v%%#*}"
    v="$(printf '%s' "$v" | sed -E 's/[[:space:]]+$//')"
    env_put "$f" "$k" "$v"
  done < "${VERSIONS_FILE}"

  for k in $IMAGE_KEYS; do eval "v=\${$k:-}"; [ -z "$v" ] || env_put "$f" "$k" "$v"; done
}

IMAGE_KEYS="OPENMRS_IMAGE_NAME ODOO_LOCAL_IMAGE ODOO_CONNECT_IMAGE_TAG OPENELIS_IMAGE_TAG BAHMNI_WEB_IMAGE BAHMNI_CONFIG_IMAGE IMPLEMENTER_INTERFACE_IMAGE_TAG PATIENT_DOCUMENTS_TAG ATOMFEED_CONSOLE_IMAGE_TAG BAHMNI_LAB_IMAGE_TAG"

SCHEMA_IMAGE_KEYS="OPENMRS_IMAGE_NAME ODOO_LOCAL_IMAGE OPENELIS_IMAGE_TAG"
IMAGE_TAG_RE='^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$'
IMAGE_REF_RE='^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*(:[A-Za-z0-9_][A-Za-z0-9._-]{0,127})?(@sha256:[0-9a-f]{64})?$'
is_image_key(){ case " ${IMAGE_KEYS} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
is_schema_image_key(){ case " ${SCHEMA_IMAGE_KEYS} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

pin_get(){
  local v; v="$({ grep -E "^$1=" "${VERSIONS_FILE}" || true; } | head -1 | cut -d= -f2-)"
  v="${v%%#*}"; printf '%s\n' "$v" | sed -E 's/[[:space:]]+$//'
}

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
       base="$(pin_get "$k")"
       base="${base%@*}"
       base="${base%:*}"
       [ -n "$base" ] || fail "${k}: no default in ${VERSIONS_FILE} to put the tag '${v}' on"
       printf '%s:%s\n' "$base" "$v" ;;
  esac
}

image_set(){ local v; v="$(image_value "$1" "$2")" || exit 1; eval "$1=\$v"; export "$1"; }

image_choices_load(){
  local f="$1" line k v
  [ -f "$f" ] || fail "image versions file not found: $f"
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//')"
    case "$line" in ''|'#'*) continue ;; *=*) ;; *) fail "$f: not KEY=value: ${line}" ;; esac
    k="${line%%=*}"
    v="${line#*=}"
    v="${v%\"}"
    v="${v#\"}"
    v="${v%\'}"
    v="${v#\'}"
    image_set "$k" "$v"
  done < "$f"
}

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

run_tasks(){ # RESUME_HINT : every task in order; ONLY / FROM honoured
  local hint="$1" t n num rc t0 dt
  for t in "${TASKS_DIR}"/[0-9]*-*.sh; do
    n="$(basename "$t" .sh)"
    num="${n%%-*}"
    if [ -n "${ONLY:-}" ] && [ "$num" != "$ONLY" ]; then continue; fi
    if [ -n "${FROM:-}" ] && [ "$num" -lt "$FROM" ]; then continue; fi
    t0=$(date +%s); rc=0; bash "$t" || rc=$?; dt=$(( $(date +%s) - t0 ))
    if [ "$rc" != 0 ]; then
      log "  ${n} ${dt}s STOPPED rc=${rc}"
      printf '\n  STOPPED at task %s. Fix what its FAIL (or FAILED rc=) line names, then resume with: %s --from %s\n  log: %s\n' "$n" "$hint" "$num" "${INSTALL_LOG:-}" >&2
      exit 1
    fi

    log "  ${n} ${dt}s done"
  done
}

has_text(){ case "$1" in *"$2"*) return 0 ;; esac; return 1; }

elis_page_ok(){
  local lc
  [ "$1" = 200 ] || return 1
  lc="$(printf '%s' "$2" | tr 'A-Z' 'a-z')"
  case "$lc" in *openelis*) ;; *) return 1 ;; esac
  case "$2" in *'HTTP Status'*) return 1 ;; esac
  return 0
}

capture_filter_check(){
  local reg off floors v rc
  type up_tables_read >/dev/null 2>&1 || . "${REPO_DIR}/sync/tables/tables.sh"
  type origin_filter_verdict >/dev/null 2>&1 || . "${REPO_DIR}/sync/origin-filter.sh"
  reg="$(mktemp)"
  if ! curl -sf --max-time 10 "${CONNECT_URL:-http://localhost:8083}/connectors/mysql-source-connector/config" > "$reg" 2>/dev/null; then
    rm -f "$reg"
    printf 'could not read the registered mysql-source-connector configuration from Kafka Connect, so its capture filter was not checked: %s logs kafka-connect\n' "${COMPOSE_CMD:-docker compose}"
    return 1
  fi

  off="$(printf 'select @@global.auto_increment_offset' | ct exec -i "${COMPOSE_PROJECT_NAME}-bahmni-mysql-1" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N' 2>/dev/null | tail -1 || true)"
  floors="${STATE_FILE:-${CLINIC_DIR}/.install-state}"
  v="$(origin_filter_verdict "$reg" "${REPO_DIR}/sync/tables/openmrs.conf" "$floors" "$off")"
  rc=$?
  rm -f "$reg"
  printf '%s\n' "$v"
  return "$rc"
}

signal_table_db(){ printf '%s' "${1:-openmrs}"; }
signal_table_ddl(){ printf 'CREATE TABLE IF NOT EXISTS %s.debezium_signal (id VARCHAR(42) PRIMARY KEY, type VARCHAR(32) NOT NULL, data VARCHAR(2048) NULL)' "$(signal_table_db "${1:-}")"; }
signal_table_grant(){ printf "GRANT SELECT, INSERT, UPDATE, DELETE ON %s.debezium_signal TO 'debezium'@'%%'" "$(signal_table_db "${1:-}")"; }

signal_table_read_sql(){
  local db; db="$(signal_table_db "${1:-}")"
  printf "select 'col', column_name, column_type, is_nullable, column_key from information_schema.columns where table_schema='%s' and table_name='debezium_signal' order by ordinal_position; select 'priv', privilege_type from information_schema.table_privileges where grantee=\"'debezium'@'%%'\" and table_schema='%s' and table_name='debezium_signal' order by privilege_type;" "$db" "$db"
}

SIGNAL_TABLE_WANT='col id varchar(42) NO PRI
col type varchar(32) NO
col data varchar(2048) YES'

signal_table_verdict(){
  local rows cols privs p t
  t="$(signal_table_db "${1:-}").debezium_signal"
  rows="$(cat)"
  cols="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="col" {s=$1" "$2" "$3" "$4; if ($5 != "") s=s" "$5; print s}')"
  if [ -z "$cols" ]; then
    printf 'the signal table %s does not exist, so no catch-up of rows written before a table was captured can be asked for. Rerun the install from its databases step (install.sh ... --from 050) or call the operator.\n' "$t"; return 1
  fi

  if [ "$cols" != "$SIGNAL_TABLE_WANT" ]; then
    printf '%s is not the signal table the source connector reads (columns: %s; want: %s). Call the operator.\n' "$t" "$(printf '%s' "$cols" | sed 's/^col //' | tr '\n' ';')" "$(printf '%s' "$SIGNAL_TABLE_WANT" | sed 's/^col //' | tr '\n' ';')"; return 1
  fi

  privs="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="priv" {print $2}' | tr '\n' ' ')"
  for p in SELECT INSERT UPDATE DELETE; do
    case " $privs" in *" $p "*) ;; *) printf 'the debezium user lacks %s on %s, so an incremental snapshot cannot record its progress there. Rerun the install from its databases step (install.sh ... --from 050) or call the operator.\n' "$p" "$t"; return 1 ;; esac
  done

  printf 'ok signal table %s (id, type, data), writable by the debezium user\n' "$t"
}

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
    print("the registered source connector does not capture its signal table %s (not in table.include.list), so a signal inserted there is never read. Regenerate and register it (scripts/generate-connectors.sh, then scripts/register-connectors.sh mysql-source-connector)." % coll); sys.exit(1)
print("ok source connector captures its signal table %s" % coll)
PY
}

signal_capture_check(){
  local reg rc
  reg="$(mktemp)"
  if ! curl -sf --max-time 10 "${CONNECT_URL:-http://localhost:8083}/connectors/mysql-source-connector/config" > "$reg" 2>/dev/null; then
    rm -f "$reg"; printf 'could not read the registered mysql-source-connector configuration from Kafka Connect, so its signal table was not checked: %s logs kafka-connect\n' "${COMPOSE_CMD:-docker compose}"; return 1
  fi

  signal_capture_verdict "$reg"; rc=$?
  rm -f "$reg"; return "$rc"
}

clinlims_down_sink_verdict(){
  python3 - "$1" "$2" <<'PYV'
import json, sys
try:
    st = json.load(open(sys.argv[1])); cf = json.load(open(sys.argv[2]))
except Exception as e:
    print("the OpenELIS down sink (clinlims-clinic-sink-all) could not be read from Kafka Connect: %s" % e); sys.exit(1)
if "connector" not in st:
    print("the OpenELIS down sink (clinlims-clinic-sink-all) is not registered: lab results entered at the hub would never reach this clinic's OpenELIS"); sys.exit(1)
c = st["connector"].get("state", "?"); ts = [t.get("state", "?") for t in st.get("tasks", [])]
if c != "RUNNING" or not ts or any(t != "RUNNING" for t in ts):
    print("the OpenELIS down sink (clinlims-clinic-sink-all) is not running: connector %s, tasks %s" % (c, ",".join(ts) or "none")); sys.exit(1)
if "pg_replication_origin_session_setup(" not in cf.get("hibernate.agroal.initialSQL", ""):
    print("the OpenELIS down sink (clinlims-clinic-sink-all) claims no replication origin: this clinic's OpenELIS source would send the hub's rows back up"); sys.exit(1)
if "value.get('source').get('table')" not in cf.get("transforms.rowsForThisClinic.condition", ""):
    print("the OpenELIS down sink (clinlims-clinic-sink-all) carries no filter for this clinic: it would keep every clinic's lab rows"); sys.exit(1)
print("ok OpenELIS down sink running (connector and %d task(s)), claiming its origin, keeping only this clinic's rows" % len(ts))
PYV
}

clinlims_down_sink_check(){
  local s c rc
  s="$(mktemp)"
  c="$(mktemp)"
  curl -s --max-time 10 "${CONNECT_URL:-http://localhost:8083}/connectors/clinlims-clinic-sink-all/status" > "$s" 2>/dev/null || true
  curl -s --max-time 10 "${CONNECT_URL:-http://localhost:8083}/connectors/clinlims-clinic-sink-all/config" > "$c" 2>/dev/null || true
  clinlims_down_sink_verdict "$s" "$c"; rc=$?
  rm -f "$s" "$c"; return "$rc"
}

