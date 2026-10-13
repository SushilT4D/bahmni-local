#!/usr/bin/env bash
# inspect-old-node.sh -- read-only survey of a clinic machine that runs the old
# single-directory stack (docker-compose.yml, initialize/, debezium/local/ at the
# checkout root), before it is replaced by the clinic installer.
#
# Why it exists: the new stack is installed fresh and then seeded from the hub,
# which REPLACES the clinic's databases. The old stack sends only the tables its
# Debezium source captures (registration, visits, encounters) to the hub. Any row
# written at the clinic in any other table -- obs, orders, drug orders,
# diagnoses, programs -- and everything in its Odoo exists only on this disk, and
# a reseed loses it. This script finds out whether such rows exist, before
# anything is touched.
#
# How it tells clinic rows from rows that came with the starting copy: the old
# stack sets MySQL's global auto_increment_increment/offset to the clinic's
# stride, so every row the clinic inserted, in EVERY auto-increment table, has
# id = offset (mod increment) and sits above every row of the starting copy. The
# starting copy came from a server that never strided, so its rows have all
# residues. Walking each table's primary key down from the top, the first id
# off the clinic's residue is the last row of the starting copy; everything
# above it is the clinic's. Odoo has no stride, so its rows are dated against
# the clinic's first own registration (or --since).
#
# Usage (on the old clinic machine, as the user that runs the stack):
#   ./inspect-old-node.sh [--old-dir DIR] [--out DIR] [--since YYYY-MM-DD]
#
#   --old-dir  the old checkout (default: the current directory)
#   --out      where the report is written (default: ./old-node-inspection-<host>-<utc time>)
#   --since    the date the clinic started entering data itself; overrides the
#              date read from the data (needed when the stride was never set)
#
# CONNECT_PORT and MM_CONNECT_PORT (default 8083, 8084) name the host ports of
# the Debezium and MirrorMaker Connect REST APIs when the node publishes others.
#
# It writes nothing outside --out: database sessions are opened read-only and no
# container, file or setting of the stack is changed. Secrets from the old .env
# are never printed or written to the report.
#
# Exit: 0 report written with a verdict (A or B), 2 report written but the
# verdict is UNKNOWN (a part could not be read), 1 usage error or wrong directory.
#
# bash 3.2 compatible: macOS ships 3.2. No associative arrays, no mapfile.
set -u
set -o pipefail

OLD_DIR="$(pwd)"
OUT=""
SINCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --old-dir) OLD_DIR="${2:?--old-dir needs a directory}"; shift 2 ;;
    --out)     OUT="${2:?--out needs a directory}"; shift 2 ;;
    --since)   SINCE="${2:?--since needs a date}"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown argument: %s (see --help)\n' "$1" >&2; exit 1 ;;
  esac
done

log(){  printf '%s\n' "$*"; }
info(){ printf '  %s\n' "$*"; }
note(){ printf '  NOTE %s\n' "$*"; }
gap(){  printf '  GAP  %s\n' "$*"; GAPS=$((GAPS+1)); }
section(){ printf '\n== %s ==\n' "$*"; }
GAPS=0

# ---------------------------------------------------------------------------
# Tables that hold the patient record. A clinic-written row in one of these
# that the source connector does not capture is a row the hub does not have.
PATIENT_RECORD_TABLES="obs orders drug_order test_order order_group order_attribute
encounter_diagnosis conditions allergy allergy_reaction patient_program
patient_state patient_program_attribute episode episode_encounter
episode_patient_program note relationship patient_appointment
patient_appointment_audit bed_patient_assignment_map medication_dispense
cohort_member diagnosis_attribute"
# Odoo tables whose rows are the clinic's own business: bills, payments, stock.
ODOO_TABLES="account_invoice account_invoice_line account_payment account_move
sale_order sale_order_line stock_picking stock_move res_partner"
# Old-stack file trees, relative to the checkout.
FILE_TREES="data/bahmni-patient-images data/bahmni-document-images
data/bahmni-uploaded-files data/bahmni-lab-results data/bahmni-clinical-forms
files/odoo"

# ---------------------------------------------------------------------------
# Is this the old stack?
OLD_DIR="$(cd "$OLD_DIR" 2>/dev/null && pwd)" || { printf 'no such directory\n' >&2; exit 1; }
if [ -d "${OLD_DIR}/clinic/install" ] || [ -f "${OLD_DIR}/clinic/.install-state" ]; then
  printf '%s is a checkout of the new clinic installer, not the old stack.\n' "$OLD_DIR" >&2
  exit 1
fi
for f in docker-compose.yml debezium/local .env; do
  [ -e "${OLD_DIR}/${f}" ] || {
    printf '%s does not look like the old stack: %s is missing.\n' "$OLD_DIR" "$f" >&2
    printf 'Run from the old checkout, or pass --old-dir.\n' >&2
    exit 1
  }
done
ENV_FILE="${OLD_DIR}/.env"

env_value(){ # KEY : value from the old .env, quotes removed; empty if absent
  grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true
}

HOST="$(hostname -s 2>/dev/null || hostname)"
[ -n "$OUT" ] || OUT="./old-node-inspection-${HOST}-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT" || { printf 'cannot create %s\n' "$OUT" >&2; exit 1; }
OUT="$(cd "$OUT" && pwd)"
SUMMARY="${OUT}/summary.env"
: > "$SUMMARY"
kv(){ printf '%s=%s\n' "$1" "$2" >> "$SUMMARY"; }

# Everything printed also goes to report.txt.
exec > >(tee "${OUT}/report.txt") 2>&1

log "Old clinic stack inspection (read-only)"
info "machine:   ${HOST}"
info "old stack: ${OLD_DIR}"
info "report:    ${OUT}"
info "taken:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
kv taken_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
kv host "$HOST"
kv old_dir "$OLD_DIR"

# ---------------------------------------------------------------------------
section "Host"
PLATFORM="$(uname -s)"
kv platform "$PLATFORM"
kv arch "$(uname -m)"
if [ "$PLATFORM" = Darwin ]; then
  info "macOS $(sw_vers -productVersion 2>/dev/null) on $(uname -m)"
  mem_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
  cpus="$(sysctl -n hw.ncpu 2>/dev/null)"
else
  info "$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}") on $(uname -m)"
  mem_gb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0) / 1048576 ))
  cpus="$(nproc 2>/dev/null)"
fi
free_gb=$(( $(df -Pk "$OLD_DIR" | awk 'NR==2 {print $4}') / 1048576 ))
info "memory ${mem_gb} GB, ${cpus} CPUs, ${free_gb} GB free where the old stack lives"
kv memory_gb "$mem_gb"; kv cpus "$cpus"; kv disk_free_gb "$free_gb"

RT=""
if command -v podman >/dev/null 2>&1; then RT=podman
elif command -v docker >/dev/null 2>&1; then RT=docker; fi
kv runtime "${RT:-none}"
if [ -z "$RT" ]; then
  gap "neither podman nor docker is on PATH; databases and connectors cannot be read"
elif [ "$RT" = podman ] && [ "$PLATFORM" = Darwin ]; then
  mi="$(podman machine inspect 2>/dev/null || true)"
  if [ -n "$mi" ]; then
    printf '%s\n' "$mi" > "${OUT}/podman-machine.json"
    rootful="$(printf '%s' "$mi" | grep -o '"Rootful": *[a-z]*' | head -1 | awk '{print $2}')"
    pm_mem="$(printf '%s' "$mi" | grep -o '"Memory": *[0-9]*' | head -1 | awk '{print $2}')"
    pm_cpu="$(printf '%s' "$mi" | grep -o '"CPUs": *[0-9]*' | head -1 | awk '{print $2}')"
    pm_disk="$(printf '%s' "$mi" | grep -o '"DiskSize": *[0-9]*' | head -1 | awk '{print $2}')"
    pm_state="$(printf '%s' "$mi" | grep -o '"State": *"[a-z]*"' | head -1 | cut -d'"' -f4)"
    info "podman machine: state ${pm_state:-?}, rootful ${rootful:-?}, ${pm_mem:-?} MiB, ${pm_cpu:-?} CPUs, ${pm_disk:-?} GiB disk"
    kv podman_rootful "${rootful:-unknown}"; kv podman_memory_mib "${pm_mem:-}"
    kv podman_cpus "${pm_cpu:-}"; kv podman_disk_gib "${pm_disk:-}"; kv podman_state "${pm_state:-}"
    [ "${rootful:-}" = true ] && note "the podman machine is rootful; the new installer expects a rootless one"
  else
    gap "podman machine inspect returned nothing"
  fi
fi

# Things the old initialize/ scripts left on the host that the new install
# collides with: boot-time starters, host names, the dnsmasq main config.
starters=""
for p in "$HOME/Library/LaunchAgents/com.podman.machine.default.plist" \
         "/Library/LaunchDaemons/com.bahmni.podman.plist"; do
  [ -e "$p" ] && starters="${starters}${starters:+ }${p}"
done
[ -n "$starters" ] && info "old boot-time starters: ${starters}" || info "old boot-time starters: none found"
kv old_starters "$starters"
hosts_line="$(grep -E '[[:space:]]bahmni\.local([[:space:]]|$)' /etc/hosts 2>/dev/null | head -1 || true)"
[ -n "$hosts_line" ] && info "/etc/hosts: ${hosts_line}"
kv etc_hosts_bahmni_local "$([ -n "$hosts_line" ] && echo yes || echo no)"
dnsconf=""
if command -v brew >/dev/null 2>&1; then dnsconf="$(brew --prefix 2>/dev/null)/etc/dnsmasq.conf"; fi
[ -f "$dnsconf" ] || dnsconf="/etc/dnsmasq.conf"
if [ -f "$dnsconf" ]; then
  dl="$(grep -cE '^(listen-address|address)=' "$dnsconf" 2>/dev/null || true)"
  info "dnsmasq main config ${dnsconf}: ${dl:-0} listen-address/address line(s)"
  kv dnsmasq_main_lines "${dl:-0}"
fi
listening=""
for port in 80 443 2181 3306 5432 8069 8083 8084 9092; do
  if { netstat -an 2>/dev/null | awk '/LISTEN/ {print $4}' | grep -qE "[.:]${port}\$"; } ||
     { command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | awk 'NR>1 {print $4}' | grep -qE ":${port}\$"; }; then
    listening="${listening}${listening:+ }${port}"
  fi
done
info "ports in use (of the ones either stack needs): ${listening:-none}"
kv ports_listening "$listening"

# ---------------------------------------------------------------------------
section "Old checkout and its settings"
if command -v git >/dev/null 2>&1 && git -C "$OLD_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  br="$(git -C "$OLD_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  co="$(git -C "$OLD_DIR" rev-parse --short HEAD 2>/dev/null)"
  dirty="$(git -C "$OLD_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  info "branch ${br} at ${co}, ${dirty} changed or untracked path(s)"
  kv git_branch "$br"; kv git_commit "$co"; kv git_dirty_paths "$dirty"
  git -C "$OLD_DIR" status --porcelain > "${OUT}/git-status.txt" 2>/dev/null || true
fi
# Only names and versions; any key that could hold a secret is never read out.
grep -E '^[A-Z0-9_]+=' "$ENV_FILE" | cut -d= -f1 |
  grep -vE 'PASS|SECRET|KEY|TOKEN|JAAS|CRED|PWD' |
  grep -E 'IMAGE|TAG|BHS_LOCATION|SERVER_NAME|CONSUMER_GROUP|REMOTE_KAFKA_BOOTSTRAP|SECURITY_PROTOCOL|TOPIC_PATTERN|RESTART_POLICY|^TZ$|DB_NAME' |
  while read -r k; do printf '%s=%s\n' "$k" "$(env_value "$k")"; done > "${OUT}/env-settings.txt"
sed 's/^/  /' "${OUT}/env-settings.txt"
LOCATION="$(env_value BHS_LOCATION)"
SERVER_NAME="$(env_value MYSQL_SERVER_NAME)"; SERVER_NAME="${SERVER_NAME:-bahmni-local}"
kv bhs_location "$LOCATION"; kv server_name "$SERVER_NAME"
kv remote_kafka "$(env_value REMOTE_KAFKA_BOOTSTRAP_SERVERS)"

# ---------------------------------------------------------------------------
section "Containers"
find_container(){ # SERVICE : running container for a compose service, by exact name or project suffix
  [ -n "$RT" ] || return 1
  "$RT" ps --format '{{.Names}}' 2>/dev/null | grep -E "^${1}\$|[-_]${1}([-_][0-9]+)?\$" | head -1
}
if [ -n "$RT" ]; then
  if "$RT" ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' > "${OUT}/containers.tsv" 2>/dev/null; then
    sed 's/^/  /' "${OUT}/containers.tsv"
  else
    gap "${RT} ps failed (is the podman machine running?)"
  fi
fi
MYSQL_C="$(find_container bahmni-mysql || true)"
PG_C="$(find_container bahmni-postgres || true)"
KAFKA_C="$(find_container kafka || true)"
CONNECT_C="$(find_container kafka-connect || true)"
info "MySQL: ${MYSQL_C:-not running}; Postgres: ${PG_C:-not running}; Kafka: ${KAFKA_C:-not running}"

# ---------------------------------------------------------------------------
section "What the old stack sends to the hub"
fetch_connectors(){ # PORT CONTAINER
  local url="http://localhost:${1}/connectors?expand=status&expand=info" body=""
  body="$(curl -fsS --max-time 10 "$url" 2>/dev/null || true)"
  if [ -z "$body" ] && [ -n "$2" ]; then
    body="$("$RT" exec "$2" curl -fsS --max-time 10 "$url" 2>/dev/null || true)"
  fi
  printf '%s' "$body"
}
src_json="$(fetch_connectors "${CONNECT_PORT:-8083}" "$CONNECT_C")"
MM_C="$(find_container mirrormaker-connect || true)"
mm_json="$(fetch_connectors "${MM_CONNECT_PORT:-8084}" "$MM_C")"
[ -n "$src_json" ] && printf '%s\n' "$src_json" > "${OUT}/source-connectors.json"
[ -n "$mm_json" ] && printf '%s\n' "$mm_json" > "${OUT}/mirrormaker-connectors.json"
# Connector states without needing jq: every "state":"X" in the expanded status.
states(){ printf '%s' "$1" | grep -o '"state":"[A-Z]*"' | cut -d'"' -f4 | sort | uniq -c | awk '{printf "%s %s, ", $1, $2}' | sed 's/, $//'; }
[ -n "$src_json" ] && info "Debezium connectors and tasks: $(states "$src_json")" || gap "Debezium Connect (port ${CONNECT_PORT:-8083}) did not answer"
[ -n "$mm_json" ] && info "MirrorMaker connectors and tasks: $(states "$mm_json")" || gap "MirrorMaker Connect (port ${MM_CONNECT_PORT:-8084}) did not answer"

# The captured tables, from the live source connector if it answers, else from
# the old checkout's tables.conf (which may differ from what was registered).
CAPTURED=""
include="$(printf '%s' "$src_json" | grep -o '"table.include.list":"[^"]*"' | head -1 | cut -d'"' -f4)"
if [ -n "$include" ]; then
  CAPTURED="$(printf '%s' "$include" | tr ',' '\n' | sed 's/.*\.//; s/[^A-Za-z0-9_]//g' | grep -v '^$' | sort -u | tr '\n' ' ')"
  CAPTURED_FROM="the live source connector"
elif [ -f "${OLD_DIR}/debezium/local/tables.conf" ]; then
  CAPTURED="$(grep -vE '^[[:space:]]*(#|$)' "${OLD_DIR}/debezium/local/tables.conf" | cut -d: -f1 | sort -u | tr '\n' ' ')"
  CAPTURED_FROM="debezium/local/tables.conf (the connector did not answer)"
  note "captured tables taken from the checkout, not from the running connector"
fi
info "captured tables (${CAPTURED_FROM:-unknown}): ${CAPTURED:-none found}"
kv captured_tables "$CAPTURED"
[ -n "$CAPTURED" ] || gap "cannot tell which tables reach the hub"
is_captured(){ case " ${CAPTURED} " in *" $1 "*) return 0 ;; esac; return 1; }

# Local end offsets of the clinic's topics: the starting point for the drain,
# where they are compared with the hub's copies.
if [ -n "$KAFKA_C" ]; then
  for bs in localhost:9092 kafka:29092 localhost:29092; do
    if "$RT" exec "$KAFKA_C" kafka-get-offsets --bootstrap-server "$bs" \
         --topic-pattern "${SERVER_NAME}\\..*" > "${OUT}/local-topic-end-offsets.txt" 2>/dev/null &&
       [ -s "${OUT}/local-topic-end-offsets.txt" ]; then
      info "end offsets of $(wc -l < "${OUT}/local-topic-end-offsets.txt" | tr -d ' ') ${SERVER_NAME}.* partition(s) saved"
      break
    fi
  done
  [ -s "${OUT}/local-topic-end-offsets.txt" ] || note "could not read local topic end offsets"
fi

# ---------------------------------------------------------------------------
section "OpenMRS: rows written at this clinic"
DB="$(env_value OPENMRS_DB_NAME)"; DB="${DB:-openmrs}"
MYSQL_PWD="$(env_value MYSQL_ROOT_PASSWORD)"; export MYSQL_PWD
mysql_q(){ # SQL on stdin -> tab-separated rows; read-only session
  { printf 'SET SESSION TRANSACTION READ ONLY;\n'; cat; } |
    "$RT" exec -i -e MYSQL_PWD "$MYSQL_C" mysql -uroot -N -B "$DB" 2>"${OUT}/.mysql.err"
}
OPENMRS_OK=0; GOLIVE=""; INC=1; OFF=0
if [ -z "$MYSQL_C" ]; then
  gap "MySQL is not running; clinic-written rows cannot be counted"
elif [ -z "$MYSQL_PWD" ]; then
  gap "MYSQL_ROOT_PASSWORD is not in the old .env"
else
  stride="$(printf 'SELECT @@global.auto_increment_increment, @@global.auto_increment_offset, VERSION();\n' | mysql_q)"
  if [ -z "$stride" ]; then
    gap "MySQL did not answer: $(head -c 300 "${OUT}/.mysql.err")"
  else
    INC="$(printf '%s' "$stride" | cut -f1)"; OFF="$(printf '%s' "$stride" | cut -f2)"
    info "MySQL $(printf '%s' "$stride" | cut -f3), stride: every ${INC}, offset ${OFF}"
    kv mysql_version "$(printf '%s' "$stride" | cut -f3)"; kv stride_increment "$INC"; kv stride_offset "$OFF"
    OPENMRS_OK=1
  fi
fi

if [ "$OPENMRS_OK" = 1 ] && [ "$INC" -le 1 ]; then
  note "no stride is set: clinic rows cannot be told from the starting copy by id"
  [ -n "$SINCE" ] || gap "no stride and no --since: give the date the clinic started entering data"
fi

if [ "$OPENMRS_OK" = 1 ]; then
  # Every auto-increment primary key, and whether the table has date_created.
  printf "SELECT c.table_name, c.column_name,
  (SELECT COUNT(*) FROM information_schema.columns d
    WHERE d.table_schema=c.table_schema AND d.table_name=c.table_name AND d.column_name='date_created')
FROM information_schema.columns c
WHERE c.table_schema=DATABASE() AND c.extra LIKE '%%auto_increment%%'
ORDER BY c.table_name;\n" | mysql_q > "${OUT}/.ai-tables.tsv"
  info "$(wc -l < "${OUT}/.ai-tables.tsv" | tr -d ' ') tables with an auto-increment key"

  # Pass 1: for each table, the last row of the starting copy (the highest id
  # off the clinic's residue) and the rows above it. With no stride, the
  # boundary is unknowable by id; the tail is then everything dated --since on.
  {
    while IFS="$(printf '\t')" read -r t col hasdate; do
      [ -n "$t" ] || continue
      if [ "$INC" -gt 1 ]; then
        b="COALESCE((SELECT \`$col\` FROM \`$t\` WHERE MOD(\`$col\`,$INC) <> MOD($OFF,$INC) ORDER BY \`$col\` DESC LIMIT 1),0)"
        if [ "$hasdate" -gt 0 ]; then
          printf "SELECT '%s', b, (SELECT COUNT(*) FROM \`%s\` WHERE \`%s\` > b), (SELECT MIN(date_created) FROM \`%s\` WHERE \`%s\` > b), (SELECT MAX(date_created) FROM \`%s\` WHERE \`%s\` > b) FROM (SELECT %s AS b) x;\n" \
            "$t" "$t" "$col" "$t" "$col" "$t" "$col" "$b"
        else
          printf "SELECT '%s', b, (SELECT COUNT(*) FROM \`%s\` WHERE \`%s\` > b), NULL, NULL FROM (SELECT %s AS b) x;\n" \
            "$t" "$t" "$col" "$b"
        fi
      elif [ -n "$SINCE" ] && [ "$hasdate" -gt 0 ]; then
        printf "SELECT '%s', NULL, COUNT(*), MIN(date_created), MAX(date_created) FROM \`%s\` WHERE date_created >= '%s';\n" \
          "$t" "$t" "$SINCE"
      fi
    done < "${OUT}/.ai-tables.tsv"
  } | mysql_q > "${OUT}/.pass1.tsv" || gap "the per-table count failed: $(head -c 300 "${OUT}/.mysql.err")"

  # The clinic's first own registration or visit dates its start. It is read
  # from the tables the old stack floored at a base id (tables.conf
  # table:key:base): clinic rows there sit at or above the base, which the
  # starting copy never reached, so no row of the copy can date the start too
  # early. Rows of the copy that happen to sit on the clinic's residue at the
  # very top of other tables are older than the start and drop out in pass 2.
  if [ -n "$SINCE" ]; then
    GOLIVE="$SINCE"; golive_from="--since"
  elif [ "$INC" -gt 1 ] && [ -f "${OLD_DIR}/debezium/local/tables.conf" ]; then
    {
      grep -E '^(person|patient|visit|encounter):[A-Za-z_]+:[0-9]+' "${OLD_DIR}/debezium/local/tables.conf" |
        while IFS=: read -r t col base; do
          base="$(printf '%s' "$base" | tr -cd '0-9')"
          printf "SELECT MIN(date_created) FROM \`%s\` WHERE \`%s\` >= %s AND MOD(\`%s\`,%s) = MOD(%s,%s);\n" \
            "$t" "$col" "$base" "$col" "$INC" "$OFF" "$INC"
        done
    } | mysql_q > "${OUT}/.golive.tsv" || true
    GOLIVE="$(grep -v NULL "${OUT}/.golive.tsv" | sort | head -1)"
    rm -f "${OUT}/.golive.tsv"
    golive_from="the first person, visit or encounter written here, above its base id"
  else
    note "no base ids to date the start from; using the lowest-dated row above each boundary"
    GOLIVE="$(awk -F'\t' '$1=="person"||$1=="patient"||$1=="visit"||$1=="encounter" { if ($4!="NULL" && $4!="" && (m=="" || $4<m)) m=$4 } END {print m}' "${OUT}/.pass1.tsv")"
    golive_from="the first person, visit or encounter above each boundary"
  fi
  if [ -n "$GOLIVE" ]; then
    info "clinic started entering data on ${GOLIVE} (from ${golive_from})"
  else
    note "no clinic-written registration or visit found: nothing dates a start"
  fi
  kv clinic_start "$GOLIVE"

  # Pass 2: tail rows dated from the start on, by month.
  : > "${OUT}/clinic-rows-by-month.tsv"
  if [ -n "$GOLIVE" ]; then
    {
      while IFS="$(printf '\t')" read -r t b n mn mx; do
        [ "${n:-0}" != 0 ] && [ "$mn" != NULL ] || continue
        col="$(awk -F'\t' -v t="$t" '$1==t {print $2}' "${OUT}/.ai-tables.tsv")"
        if [ "$b" = NULL ]; then cond="1=1"; else cond="\`$col\` > $b"; fi
        printf "SELECT '%s', DATE_FORMAT(date_created,'%%Y-%%m'), COUNT(*) FROM \`%s\` WHERE %s AND date_created >= '%s' GROUP BY 2 ORDER BY 2;\n" \
          "$t" "$t" "$cond" "$GOLIVE"
      done < "${OUT}/.pass1.tsv"
    } | mysql_q > "${OUT}/clinic-rows-by-month.tsv" || gap "the by-month count failed: $(head -c 300 "${OUT}/.mysql.err")"
  fi

  # One line per table that has clinic rows: dated rows when the table has a
  # date, else every row above the boundary, marked undated. An undated count
  # can include a row of the starting copy that sits on the residue at the top
  # of the table, so it is shown for checking and does not decide the verdict.
  printf 'table\tcaptured\tpatient_record\tclinic_rows\tfirst\tlast\n' > "${OUT}/clinic-rows.tsv"
  while IFS="$(printf '\t')" read -r t b n mn mx; do
    [ "${n:-0}" != 0 ] || continue
    if [ "$mn" = NULL ]; then
      c="$n"; mn=undated; mx=undated
    else
      c="$(awk -F'\t' -v t="$t" '$1==t {s+=$3} END {print s+0}' "${OUT}/clinic-rows-by-month.tsv")"
    fi
    [ "$c" != 0 ] || continue
    is_captured "$t" && cap=yes || cap=no
    case " $(printf '%s' "$PATIENT_RECORD_TABLES" | tr '\n' ' ') " in *" $t "*) pr=yes ;; *) pr=no ;; esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$t" "$cap" "$pr" "$c" "$mn" "$mx" >> "${OUT}/clinic-rows.tsv"
  done < "${OUT}/.pass1.tsv"

  log ""
  info "patient-record rows written here that the hub does not receive:"
  awk -F'\t' 'NR>1 && $2=="no" && $3=="yes" {printf "    %-28s %10s   %s .. %s\n", $1, $4, substr($5,1,10), substr($6,1,10); n++} END {if (!n) print "    none"}' "${OUT}/clinic-rows.tsv"
  info "other tables written here that the hub does not receive (see clinic-rows.tsv):"
  awk -F'\t' 'NR>1 && $2=="no" && $3=="no" {printf "    %-28s %10s\n", $1, $4; n++} END {if (!n) print "    none"}' "${OUT}/clinic-rows.tsv" | head -25
  info "captured tables written here (these reach the hub):"
  awk -F'\t' 'NR>1 && $2=="yes" {printf "    %-28s %10s\n", $1, $4; n++} END {if (!n) print "    none"}' "${OUT}/clinic-rows.tsv"
fi
CLIN_UNSENT="$(awk -F'\t' 'NR>1 && $2=="no" && $3=="yes" && $5!="undated" {s+=$4} END {print s+0}' "${OUT}/clinic-rows.tsv" 2>/dev/null || echo 0)"
kv patient_record_rows_unsent "$CLIN_UNSENT"

# ---------------------------------------------------------------------------
section "Odoo: rows created since the clinic started"
ODOO_ROWS=0
ODOO_USER="$(env_value ODOO_DB_USER)"; ODOO_USER="${ODOO_USER:-odoo}"
PGPASSWORD="$(env_value ODOO_DB_PASSWORD)"; PGOPTIONS='-c default_transaction_read_only=on'
export PGPASSWORD PGOPTIONS
pg_q(){ # DB, SQL on stdin
  "$RT" exec -i -e PGPASSWORD -e PGOPTIONS "$PG_C" psql -h localhost -U "$ODOO_USER" -d "$1" -At -F "$(printf '\t')" -v ON_ERROR_STOP=1 2>"${OUT}/.pg.err"
}
if [ -z "$PG_C" ]; then
  gap "the Odoo Postgres is not running"
else
  dbs="$(printf 'SELECT datname FROM pg_database WHERE NOT datistemplate;\n' | pg_q postgres)"
  ODOO_DB=""
  for d in $dbs; do
    has="$(printf "SELECT to_regclass('public.ir_module_module') IS NOT NULL;\n" | pg_q "$d" || true)"
    [ "$has" = t ] && { ODOO_DB="$d"; break; }
  done
  if [ -z "$ODOO_DB" ]; then
    gap "no Odoo database found (databases: $(printf '%s' "$dbs" | tr '\n' ' '))"
  else
    ov="$(printf "SELECT latest_version FROM ir_module_module WHERE name='base';\n" | pg_q "$ODOO_DB")"
    info "Odoo database ${ODOO_DB}, base module ${ov}"
    kv odoo_db "$ODOO_DB"; kv odoo_version "$ov"
    if [ -z "$GOLIVE" ]; then
      gap "no clinic start date: Odoo rows cannot be dated (use --since)"
    else
      printf 'table\ttotal\tsince_start\tlast_created\n' > "${OUT}/odoo-rows.tsv"
      for t in $ODOO_TABLES; do
        r="$(printf "SELECT CASE WHEN to_regclass('public.%s') IS NULL THEN 'absent' ELSE (SELECT count(*)::text || chr(9) || count(*) FILTER (WHERE create_date >= '%s')::text || chr(9) || coalesce(max(create_date)::text,'') FROM %s) END;\n" "$t" "$GOLIVE" "$t" | pg_q "$ODOO_DB" 2>/dev/null || echo absent)"
        [ "$r" = absent ] && continue
        printf '%s\t%s\n' "$t" "$r" >> "${OUT}/odoo-rows.tsv"
      done
      awk -F'\t' 'NR>1 {printf "    %-24s %10s total %10s since start   last %s\n", $1, $2, $3, substr($4,1,10)}' "${OUT}/odoo-rows.tsv"
      ODOO_ROWS="$(awk -F'\t' 'NR>1 && $1!="res_partner" {s+=$3} END {print s+0}' "${OUT}/odoo-rows.tsv")"
    fi
  fi
fi
kv odoo_business_rows_since_start "$ODOO_ROWS"

# ---------------------------------------------------------------------------
section "Files (never synced)"
FILES_NEW=0
printf 'tree\tfiles\tkb\tsince_start\n' > "${OUT}/files.tsv"
for tr in $FILE_TREES; do
  d="${OLD_DIR}/${tr}"
  [ -d "$d" ] || continue
  n="$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')"
  kb="$(du -sk "$d" 2>/dev/null | awk '{print $1}')"
  s=""
  [ -n "$GOLIVE" ] && s="$(find "$d" -type f -newermt "$GOLIVE" 2>/dev/null | wc -l | tr -d ' ')"
  printf '%s\t%s\t%s\t%s\n' "$tr" "$n" "$kb" "$s" >> "${OUT}/files.tsv"
  printf '    %-32s %8s files %10s KB   %s since start\n' "$tr" "$n" "$kb" "${s:-?}"
  case "$tr" in data/bahmni-patient-images|data/bahmni-document-images|data/bahmni-uploaded-files|data/bahmni-lab-results)
    FILES_NEW=$((FILES_NEW + ${s:-0})) ;;
  esac
done
kv patient_files_since_start "$FILES_NEW"

# ---------------------------------------------------------------------------
section "Verdict"
REASONS=""
reason(){ REASONS="${REASONS}    - $*
"; }
[ "$CLIN_UNSENT" -gt 0 ] 2>/dev/null && reason "${CLIN_UNSENT} patient-record row(s) written here are not captured, so the hub does not have them"
[ "$ODOO_ROWS" -gt 0 ] 2>/dev/null && reason "${ODOO_ROWS} Odoo bill, payment, order or stock row(s) created here since the start; the old stack sends no Odoo data"
[ "$FILES_NEW" -gt 0 ] 2>/dev/null && reason "${FILES_NEW} patient file(s) added here since the start; files are never synced"

# Data found that only this machine holds settles it, whatever else could not
# be read. Otherwise a single unread part means nothing can be promised.
if [ -n "$REASONS" ]; then
  VERDICT=B
elif [ "$OPENMRS_OK" != 1 ] || [ "$GAPS" -gt 0 ]; then
  VERDICT=UNKNOWN
else
  VERDICT=A
fi
kv verdict "$VERDICT"
kv gaps "$GAPS"
case "$VERDICT" in
  A) log "  A -- nothing found that exists only on this machine. A reinstall and reseed from the hub loses no clinic data." ;;
  B) log "  B -- this machine holds data the hub does not have. Reinstalling now would lose it:"
     printf '%s' "$REASONS"
     log "  Decide for each item: move it to the central server first, or keep it as an archive, before anything is removed." ;;
  *) log "  UNKNOWN -- ${GAPS} part(s) could not be read (GAP lines above). Fix them and run again."
     [ -n "$REASONS" ] && { log "  Found so far:"; printf '%s' "$REASONS"; } ;;
esac
log ""
log "Report: ${OUT}  (report.txt, summary.env and the .tsv files; copy the folder off this machine)"
rm -f "${OUT}/.mysql.err" "${OUT}/.pg.err"
[ "$VERDICT" = UNKNOWN ] && exit 2
exit 0
