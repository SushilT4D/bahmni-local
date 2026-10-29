#!/bin/bash
# generate-local-sink-connectors.sh — render the DOWN-direction (cloud → clinic) sinks.
#
# One connector per cloud-owned table from hub/tables.conf. These run ON THE
# CLINIC and write into the clinic's OpenMRS DB.
#
# Deliberate choices, each one closing a defect a generator can have:
#   - the template is a FILE and substitution is explicit, so the RegexRouter
#     replacement "$1" is never exposed to the shell (an unquoted heredoc expands
#     it to empty and every connector dies with `Invalid identifier:`);
#   - every topic-prefix component is a variable, so a second clinic is not
#     blocked by a hardcoded `source.<clinic>.openmrs.`;
#   - connection.restart.on.errors is set in the template (see it for why).
#
# Usage: ./scripts/generate-local-sink-connectors.sh [output-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-${ROOT}/../sync/local/connectors/generated}"
TEMPLATE="${ROOT}/../sync/local/connectors/mysql-local-sink-connector.json.template"
TABLES_CONF="${TABLES_CONF:-${ROOT}/../hub/tables.conf}"
# The clinic's OWN capture list. Read only to refuse overlap — see the ownership guard below.
UP_TABLES_CONF="${UP_TABLES_CONF:-${ROOT}/../sync/local/tables.conf}"

[[ -f "$TEMPLATE"    ]] || { echo "missing template: $TEMPLATE" >&2; exit 1; }
[[ -f "$TABLES_CONF" ]] || { echo "missing table list: $TABLES_CONF" >&2; exit 1; }

# shellcheck disable=SC1091
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

CLOUD_SERVER_NAME="${CLOUD_MYSQL_SERVER_NAME:-bahmni-cloud}"
CLOUD_DB="${CLOUD_MYSQL_DATABASE:-openmrs}"
MM2_REMOTE_ALIAS="${MM2_REMOTE_ALIAS:-remote}"     # MM2 cluster alias for the cloud
LOCAL_MYSQL_HOST="${LOCAL_MYSQL_HOST:-bahmni-mysql}"
LOCAL_MYSQL_PORT="${LOCAL_MYSQL_PORT:-3306}"
LOCAL_MYSQL_DATABASE="${LOCAL_MYSQL_DATABASE:-openmrs}"
LOCAL_MYSQL_USE_SSL="${LOCAL_MYSQL_USE_SSL:-false}"
LOCAL_MYSQL_USER="${LOCAL_MYSQL_USER:-${SINK_DB_USER:-sink}}"
LOCAL_MYSQL_PASSWORD="${LOCAL_MYSQL_PASSWORD:-${SINK_DB_PASSWORD:-}}"

[[ -n "$LOCAL_MYSQL_PASSWORD" ]] || { echo "LOCAL_MYSQL_PASSWORD (or SINK_DB_PASSWORD) is unset — refusing to emit a passwordless connector" >&2; exit 1; }

# the mirrored name on the clinic, e.g. remote.bahmni-cloud.openmrs.users
SRC_PREFIX="${MM2_REMOTE_ALIAS}.${CLOUD_SERVER_NAME}.${CLOUD_DB}."
PREFIX_REGEX="^$(printf '%s' "$SRC_PREFIX" | sed 's/\./\\\\./g')(.*)\$"

# ---------------------------------------------------------------------------
# Read the table list ONCE, then validate the whole list before writing anything.
#
# `read` needs the `|| [[ -n "$line" ]]` fallback or a final line with no trailing
# newline is silently dropped — one table would lose its sink while the run still
# reported success. The up-direction generator already guards this; this one did not.
# ---------------------------------------------------------------------------
TABLES=(); ROUTE_COLS=(); CHANGES_ONLY=(); HW_COLS=(); HW_LINKS=()
while read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    f="$(printf '%s' "$line" | awk '{print $1}')"
    t="$(printf '%s' "$f" | cut -d: -f1)"
    keycols="$(printf '%s' "$f" | cut -s -d: -f2)"
    role="$(printf '%s' "$f" | cut -s -d: -f3)"
    [[ -n "$t" ]] || continue
    TABLES+=("$t")
    case "$role" in clinic=*) ROUTE_COLS+=("${role#clinic=}") ;; *) ROUTE_COLS+=("") ;; esac
    case "$role" in changes) CHANGES_ONLY+=(1) ;; *) CHANGES_ONLY+=(0) ;; esac
    # `hub-written` (own key) or `hub-written=<column>` (a link row, judged by
    # the row it belongs to): see the hub-written block below
    case "$role" in
        hub-written)
            [[ "$keycols" =~ ^[a-z_][a-z0-9_]*$ ]] || { echo "${TABLES_CONF}: ${f}: a hub-written table is judged on its own key, which must be one column (or name the column: hub-written=<column>)" >&2; exit 1; }
            HW_COLS+=("$keycols"); HW_LINKS+=(0) ;;
        hub-written=*)
            c="${role#hub-written=}"
            case ",${keycols}," in *",${c},"*) ;; *) echo "${TABLES_CONF}: ${f}: ${c} is not part of the key (${keycols}); a deleted row carries only its key" >&2; exit 1 ;; esac
            HW_COLS+=("$c"); HW_LINKS+=(1) ;;
        *) HW_COLS+=(""); HW_LINKS+=(0) ;;
    esac
done < "$TABLES_CONF"

# A `clinic=<column>` row carries the hub's own rows (lab results entered at
# the hub) for whichever clinic <column> names. This clinic keeps a row only
# when <column> points at a row this clinic wrote: it ends in this clinic's
# residue and is at or above that table's base. Below the base a residue says
# nothing about who wrote the row (older rows were numbered before striding),
# so those rows are not kept anywhere. The column says which table it points
# at: visit_id -> visit, order_id -> orders. The base is that table's in
# sync/local/tables.conf; a table whose base comes from the seed (orders) takes
# the floor recorded at seeding (FLOOR_ORDERS, in .env or .install-state). The
# residue comes from this clinic's .env. Without either nothing is generated.
need_residue=no
for c in "${ROUTE_COLS[@]}"; do [[ -n "$c" ]] && need_residue=yes; done
RESIDUE_OWN=""
declare -a ROUTE_BASES=()
route_table(){ case "$1" in visit_id) echo visit ;; order_id) echo orders ;; *) return 1 ;; esac; }
route_base(){ # COLUMN -> the base of the table it points at
    local t b k
    t="$(route_table "$1")" || { echo "hub/tables.conf routes by '$1'; a clinic can route only by visit_id or order_id" >&2; return 1; }
    b="$(grep -E "^[[:space:]]*${t}:[^:]+:" "$UP_TABLES_CONF" | head -1 | awk '{print $1}' | cut -d: -f3)"
    if [[ "$b" == seed ]]; then
        k="FLOOR_$(printf '%s' "$t" | tr '[:lower:]' '[:upper:]')"
        b="${!k:-}"
        [[ -n "$b" ]] || b="$(sed -n "s/^${k}=//p" "${ROOT}/.install-state" 2>/dev/null | tail -1)"
        [[ "$b" =~ ^[1-9][0-9]*$ ]] || { echo "${k} (the ${t} floor recorded at seeding) is not in ${ROOT}/.env or ${ROOT}/.install-state; the lab-result sinks need it" >&2; return 1; }
    fi
    [[ "$b" =~ ^[1-9][0-9]*$ ]] || { echo "${UP_TABLES_CONF} gives no base for ${t}; the lab-result sinks need it" >&2; return 1; }
    printf '%s' "$b"
}
if [[ "$need_residue" == yes ]]; then
    RESIDUE_OWN="${RESIDUE:-}"
    [[ -n "$RESIDUE_OWN" ]] || { [[ -n "${MYSQL_AUTO_INCREMENT_OFFSET:-}" ]] && RESIDUE_OWN=$(( MYSQL_AUTO_INCREMENT_OFFSET % 10 )); }
    [[ "$RESIDUE_OWN" =~ ^[1-9]$ ]] || { echo "this clinic's residue (RESIDUE, 1-9) is not set: the lab-result sinks keep only this clinic's rows and cannot be generated without it" >&2; exit 1; }
fi
for i in "${!ROUTE_COLS[@]}"; do
    if [[ -n "${ROUTE_COLS[$i]}" ]]; then ROUTE_BASES[$i]="$(route_base "${ROUTE_COLS[$i]}")" || exit 1
    else ROUTE_BASES[$i]=""; fi
done

(( ${#TABLES[@]} )) || { echo "no tables found in $TABLES_CONF" >&2; exit 1; }

# A `hub-written` row (a clinic's down list, never hub/tables.conf) carries the
# hub's staff to a clinic that keeps its own OpenMRS database: the logins,
# roles, providers and people the hub created. Below the hub's floor such a
# clinic's rows and the hub's are two histories that share ids, so this clinic
# keeps only rows whose <column> is at or above the floor of the table it
# points at and ends in 0, the hub's residue. The column is the table's own key,
# or `hub-written=user_id` for a link row (user_role, user_property), judged
# by the user it belongs to.
#
# Floors: a table with a base in sync/local/tables.conf (person, person_name)
# uses that base, the same value the hub's source filter uses; any other
# (users, provider) takes the hub's recorded floor from HUB_STAFF_FLOORS, a
# file of "<table> <floor>" lines (clinic/scripts/clinic-minted-staff.sh
# --print-floors writes it from the hub's rows). Without a floor nothing is
# generated.
#
# Deletes: a row with its own key (a user, a provider, a person, a name) is
# retired at the hub, never deleted, and a delete here would fail on the
# clinic's clinical rows that name it, so deletes and tombstones are dropped.
# A link row's delete is applied: it is how a revoked role is revoked here.
#
# user_property keeps only the names in USER_PROPERTY_KEEP (comma-separated;
# clinic-minted-staff.sh --print-properties): the hub's users' settings, never
# a name in sync/user-property-node-local.conf.
#
# users carries password hashes. Its receiver is generated only with
# HUB_LINK_PER_SITE_TLS=yes, which states that this clinic's link to the hub is
# TLS with plaintext refused and logs in with a login of its own, read on this
# clinic's connection. A hub that gives every clinic the same login does not
# meet it.
declare -a HW_FLOORS=()
NODE_LOCAL_PROPS="${NODE_LOCAL_PROPS:-${ROOT}/../sync/user-property-node-local.conf}"
hw_floor_table(){ case "$1" in user_id) echo users ;; *) return 1 ;; esac; }
hw_floor(){ # TABLE -> its floor
    local b fl
    b="$(grep -E "^[[:space:]]*$1:[^:]+:[0-9]+([[:space:]]|\$)" "$UP_TABLES_CONF" 2>/dev/null | head -1 | awk '{print $1}' | cut -d: -f3)"
    fl=""
    if [[ -n "${HUB_STAFF_FLOORS:-}" ]]; then
        [[ -f "$HUB_STAFF_FLOORS" ]] || { echo "HUB_STAFF_FLOORS names ${HUB_STAFF_FLOORS}, which is not a file" >&2; return 1; }
        fl="$(awk -v t="$1" '{ sub(/#.*/, "") } NF && $1 == t { print $2 }' "$HUB_STAFF_FLOORS")"
        [[ "$(printf '%s\n' "$fl" | grep -c .)" -le 1 ]] || { echo "${HUB_STAFF_FLOORS} lists $1 more than once" >&2; return 1; }
    fi
    if [[ -n "$b" ]]; then
        [[ -z "$fl" ]] || { echo "${HUB_STAFF_FLOORS} gives $1 a floor, but its floor is its base in ${UP_TABLES_CONF} (${b}), the value the hub's source filter uses; remove the line" >&2; return 1; }
        fl="$b"
    fi
    [[ -n "$fl" ]] || { echo "no floor for $1: the hub's recorded floor goes in the file HUB_STAFF_FLOORS names (clinic/scripts/clinic-minted-staff.sh --print-floors); its hub-written rows cannot be told from this clinic's own without it" >&2; return 1; }
    [[ "$fl" =~ ^[1-9][0-9]*$ ]] && (( fl % 10 == 0 )) || { echo "the floor of $1 is '${fl}', not a whole multiple of 10 (the hub mints residue 0 from its floor)" >&2; return 1; }
    printf '%s' "$fl"
}
for i in "${!HW_COLS[@]}"; do
    HW_FLOORS[$i]=""
    [[ -n "${HW_COLS[$i]}" ]] || continue
    t="${TABLES[$i]}"
    if [[ "${HW_LINKS[$i]}" == 1 ]]; then
        ft="$(hw_floor_table "${HW_COLS[$i]}")" || { echo "${TABLES_CONF}: ${t} is judged by ${HW_COLS[$i]}; a link row can be judged only by user_id (the user it belongs to)" >&2; exit 1; }
    else
        ft="$t"
    fi
    HW_FLOORS[$i]="$(hw_floor "$ft")" || exit 1
    if [[ "$t" == users && "${HUB_LINK_PER_SITE_TLS:-}" != yes ]]; then
        { echo "REFUSING users: its rows carry password hashes. Its receiver is generated only for a clinic whose"
          echo "  link to the hub is TLS with plaintext refused and logs in with a login of its own, read on this"
          echo "  clinic's connection (then HUB_LINK_PER_SITE_TLS=yes). Nothing was generated."; } >&2
        exit 1
    fi
    if [[ "$t" == user_property ]]; then
        [[ -n "${USER_PROPERTY_KEEP:-}" ]] || { echo "user_property is hub-written, and USER_PROPERTY_KEEP (the property names the hub's users carry as settings) is empty: clinic/scripts/clinic-minted-staff.sh --print-properties gives it" >&2; exit 1; }
        [[ -f "$NODE_LOCAL_PROPS" ]] || { echo "missing ${NODE_LOCAL_PROPS}: the property names that stay at each node" >&2; exit 1; }
        for p in $(printf '%s' "$USER_PROPERTY_KEEP" | tr ',' ' '); do
            [[ "$p" =~ ^[A-Za-z0-9_.:-]+$ ]] || { echo "USER_PROPERTY_KEEP: '${p}' is not a property name" >&2; exit 1; }
            if sed -e 's/#.*//' -e 's/[[:space:]]//g' "$NODE_LOCAL_PROPS" | grep -qxF "$p"; then
                echo "USER_PROPERTY_KEEP keeps ${p}, which holds each node's own state (${NODE_LOCAL_PROPS}); it never comes down" >&2; exit 1
            fi
        done
    fi
done

# Ownership guard — the mirror image of the one in
# hub/scripts/generate-sink-connectors.sh, which refuses to give a
# CLOUD-owned table an up-direction sink. Same rule, other direction: a table the
# CLINIC authors must never get a down-direction sink.
#
# Why this mattered. The clinic captures its own tables, so a sink write that lands
# in the clinic binlog ships up to the cloud, is applied there, and — because the
# table is in BOTH capture lists — comes straight back down. Unbounded, and unlike
# clinlims on Postgres there is no publication row filter on MySQL to break it.
#
# That hazard is closed when the sink writes with sessionVariables=sql_log_bin=0
# (the engine-native loop guard): the write never enters the binlog, so it
# cannot loop. The template carries that setting, and every mysql-local-sink-*
# connector uses it — including person and person_name, which an unconditional
# refusal here would never generate.
#
# An unconditional refusal here would also enforce PER-TABLE ownership, which is
# not the rule: a table MAY be written by more than one node provided no two
# nodes write the same row, which is what the residue and base_id striding
# guarantee for person/person_name.
#
# So: still refuse — loudly, before writing anything — but only when the sink would
# genuinely go out without the guard. If the template ever loses sql_log_bin=0 this
# reverts to the old absolute behaviour, which is the safe direction to fail in.
if [[ -f "$UP_TABLES_CONF" ]] && ! grep -q 'sql_log_bin=0' "$TEMPLATE"; then
    for t in "${TABLES[@]}"; do
        if grep -qE "^[[:space:]]*${t}:" "$UP_TABLES_CONF"; then
            {
              echo "REFUSING ${t}: it is clinic-owned (listed in ${UP_TABLES_CONF})."
              echo "  A down-direction sink would write cloud rows into a table the clinic authors."
              echo "  The clinic also captures that table, so the write would re-enter the binlog and"
              echo "  loop back through the cloud — with no MySQL row filter to stop it."
              echo "  Nothing was generated."
            } >&2
            exit 1
        fi
    done
fi

mkdir -p "$OUT"
count=0
for i in "${!TABLES[@]}"; do
    TABLE="${TABLES[$i]}"
    TOPIC="${SRC_PREFIX}${TABLE}"

    HW_COL="${HW_COLS[$i]}" HW_FLOOR="${HW_FLOORS[$i]}" HW_LINK="${HW_LINKS[$i]}" PROPS_KEEP="${USER_PROPERTY_KEEP:-}" \
    CHANGES="${CHANGES_ONLY[$i]}" ROUTE_COL="${ROUTE_COLS[$i]}" ROUTE_BASE="${ROUTE_BASES[$i]}" RESIDUE_OWN="$RESIDUE_OWN" \
    TEMPLATE="$TEMPLATE" TABLE="$TABLE" KAFKA_TOPICS="$TOPIC" \
    TOPIC_PREFIX_REGEX="$PREFIX_REGEX" \
    LOCAL_MYSQL_HOST="$LOCAL_MYSQL_HOST" LOCAL_MYSQL_PORT="$LOCAL_MYSQL_PORT" \
    LOCAL_MYSQL_DATABASE="$LOCAL_MYSQL_DATABASE" LOCAL_MYSQL_USE_SSL="$LOCAL_MYSQL_USE_SSL" \
    LOCAL_MYSQL_USER="$LOCAL_MYSQL_USER" LOCAL_MYSQL_PASSWORD="$LOCAL_MYSQL_PASSWORD" \
    python3 - "$OUT/mysql-local-sink-${TABLE}.json" <<'PYEOF'
import json, os, re, sys

raw = open(os.environ['TEMPLATE']).read()
for key in ('TABLE','KAFKA_TOPICS','TOPIC_PREFIX_REGEX','LOCAL_MYSQL_HOST','LOCAL_MYSQL_PORT',
            'LOCAL_MYSQL_DATABASE','LOCAL_MYSQL_USE_SSL','LOCAL_MYSQL_USER','LOCAL_MYSQL_PASSWORD'):
    raw = raw.replace('${%s}' % key, os.environ[key])

doc = json.loads(raw)
# drop the //-prefixed documentation keys: Connect would report them as unknown configs
doc['config'] = {k: v for k, v in doc['config'].items() if not k.startswith('//')}

leftover = [k for k, v in doc['config'].items() if '${' in str(v)]
if leftover:
    sys.exit(f"unsubstituted placeholder(s) in {leftover}")
if doc['config'].get('transforms.dropPrefix.replacement') != '$1':
    sys.exit("RegexRouter replacement is not literal $1 — the shell expanded it")

col = os.environ.get('ROUTE_COL', '')
if col:
    # only rows whose column points at a row this clinic wrote; tombstones carry
    # no row and are dropped, a delete still arrives as its own change event
    # with the row in `before`
    cfg = doc['config']; r = os.environ['RESIDUE_OWN']; base = os.environ['ROUTE_BASE']
    cfg['transforms'] = cfg['transforms'] + ',rowsForThisClinic'
    cfg['transforms.rowsForThisClinic.type'] = 'io.debezium.transforms.Filter'
    cfg['transforms.rowsForThisClinic.language'] = 'jsr223.groovy'
    cfg['transforms.rowsForThisClinic.null.handling.mode'] = 'drop'
    cfg['transforms.rowsForThisClinic.condition'] = (
        "def r = value.get('after') != null ? value.get('after') : value.get('before'); "
        f"r != null && r.get('{col}') instanceof Number && r.get('{col}').longValue() >= {base}L "
        f"&& r.get('{col}').longValue() % 10 == {r}")

hw = os.environ.get('HW_COL', '')
if hw:
    # a `hub-written` table: only rows the hub wrote, judged on the record's key
    # so that a change, a delete and its tombstone are judged alike
    cfg = doc['config']; f = os.environ['HW_FLOOR']
    if not re.fullmatch(r'[1-9][0-9]*', f) or int(f) % 10:
        sys.exit(f"{os.environ['TABLE']}: floor '{f}' is not a whole multiple of 10")
    cond = (f"key != null && key.get('{hw}') instanceof Number && "
            f"key.get('{hw}').longValue() >= {f}L && key.get('{hw}').longValue() % 10 == 0")
    if os.environ['TABLE'] == 'user_property':
        keep = sorted({p for p in os.environ.get('PROPS_KEEP', '').split(',') if p})
        if not keep or any(not re.fullmatch(r'[A-Za-z0-9_.:-]+', p) for p in keep):
            sys.exit("user_property: no property names to keep, or one that is not a name")
        cond += " && [" + ", ".join(f"'{p}'" for p in keep) + "].contains(key.get('property'))"
    cfg['transforms'] = cfg['transforms'] + ',hubWrittenOnly'
    cfg['transforms.hubWrittenOnly.type'] = 'io.debezium.transforms.Filter'
    cfg['transforms.hubWrittenOnly.language'] = 'jsr223.groovy'
    cfg['transforms.hubWrittenOnly.null.handling.mode'] = 'evaluate'
    cfg['transforms.hubWrittenOnly.condition'] = cond
    if os.environ.get('HW_LINK') != '1':
        # a row with its own key is retired, never deleted: same as `changes` below
        os.environ['CHANGES'] = '1'

if os.environ.get('CHANGES') == '1':
    # a `changes` table (hub/tables.conf): inserts and updates are applied,
    # never a delete. The hub retires such a row rather than deleting it, and a
    # delete here would fail on, or orphan, the clinic's own rows that point to
    # it. Tombstones carry no row and are dropped with the deletes.
    cfg = doc['config']
    cfg['delete.enabled'] = 'false'
    cfg['transforms'] = cfg['transforms'] + ',noDeletes'
    cfg['transforms.noDeletes.type'] = 'io.debezium.transforms.Filter'
    cfg['transforms.noDeletes.language'] = 'jsr223.groovy'
    cfg['transforms.noDeletes.null.handling.mode'] = 'drop'
    cfg['transforms.noDeletes.condition'] = "value.get('op') != 'd'"

json.dump(doc, open(sys.argv[1], 'w'), indent=2)
PYEOF
    echo "  ✓ $(basename "$OUT")/mysql-local-sink-${TABLE}.json   ← ${TOPIC}"
    count=$((count+1))
done

echo
echo "generated ${count} DOWN-direction sink connector(s) in ${OUT}"
echo "  mirrored-topic prefix : ${SRC_PREFIX}"
echo "  target                : ${LOCAL_MYSQL_HOST}:${LOCAL_MYSQL_PORT}/${LOCAL_MYSQL_DATABASE}"
