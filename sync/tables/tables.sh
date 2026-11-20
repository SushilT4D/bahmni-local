#!/usr/bin/env bash
# Reads the table lists in this directory (openmrs.conf, odoo.conf,
# openelis.conf), each with an [up] and a [down] section. Source it, or run it
# (commands at the end). SYNC_TABLES_DIR overrides the directory. bash 3.2.
SYNC_TABLES_DIR="${SYNC_TABLES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

tables_file(){
  case "$1" in
    openmrs|odoo|openelis) printf '%s/%s.conf\n' "${SYNC_TABLES_DIR}" "$1" ;;
    clinlims) printf '%s/openelis.conf\n' "${SYNC_TABLES_DIR}" ;;
    *) printf 'tables_file: unknown database %s (openmrs, odoo or openelis)\n' "$1" >&2; return 1 ;;
  esac
}

tables_section(){ # FILE SECTION
  [ -f "$1" ] || { printf 'no such table list: %s\n' "$1" >&2; return 1; }
  awk -v want="[$2]" '
    { line = $0; t = line; gsub(/^[ \t]+|[ \t]+$/, "", t) }
    t ~ /^\[[a-z]+\]$/ { inside = (t == want); if (inside) found = 1; next }
    inside { print line }
    END { exit !found }' "$1" || { printf '%s has no [%s] section\n' "${1##*/}" "$2" >&2; return 1; }
}

tables_list(){ # DB SECTION
  local f c
  f="$(tables_file "$1")" || return 1
  c="$(tables_section "$f" "$2")" || return 1
  printf '%s\n' "$c" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true
}

UP_NEVER_TABLES="users user_property global_property"   # never captured at a clinic
UP_SIGNAL_TABLE=debezium_signal                          # captured on every clinic without a line
UP_CLINICAL_TABLES="obs orders drug_order test_order"    # need a seed or floor=<table> floor
UP_CLINLIMS_OWN_ROWS="system_user result_signature"     # OpenELIS tables sent only for rows the clinic minted
up_signal_collection(){ printf '%s.%s\n' "${1:-openmrs}" "${UP_SIGNAL_TABLE}"; }

# up_tables_read FILE: the OpenMRS [up] section of FILE, one record per line:
#   <table> <pk> base <n> | seed - | floor <other table> | sync -
# Refuses (stderr, exit 1) a line it cannot place.
up_tables_read(){
  local f="$1" line n=0 t pk third kind arg recs="" re sec
  re='^([A-Za-z0-9_]+):([A-Za-z0-9_,]+)(:([^:[:space:]]+))?$'
  sec="$(tables_section "$f" up)" || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n+1))
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [ -z "${line//[[:space:]]/}" ] && continue
    if [[ ! "$line" =~ $re ]]; then
      printf '%s line %s: not table:pk[:floor] -- %s\n' "${f##*/}" "$n" "$line" >&2; return 1
    fi
    t="${BASH_REMATCH[1]}"; pk="${BASH_REMATCH[2]}"; third="${BASH_REMATCH[4]}"
    case " ${UP_NEVER_TABLES} " in
      *" ${t} "*) printf '%s line %s: %s is never captured at a clinic (users and user_property come from the hub; global_property is node-local)\n' "${f##*/}" "$n" "$t" >&2; return 1 ;;
    esac
    [ "$t" = "${UP_SIGNAL_TABLE}" ] && { printf '%s line %s: %s is the source connector'"'"'s signal table; it is captured without a line here and never sent to the hub\n' "${f##*/}" "$n" "$t" >&2; return 1; }
    case "$third" in
      '') kind=sync; arg=- ;;
      seed) kind=seed; arg=- ;;
      floor=*) kind=floor; arg="${third#floor=}" ;;
      *[!0-9]*) printf '%s line %s: %s: the third field is a base_id (digits), seed, or floor=<table>; got %s\n' "${f##*/}" "$n" "$t" "$third" >&2; return 1 ;;
      *) kind=base; arg="$third" ;;
    esac
    if printf '%s\n' "$recs" | awk -v t="$t" '$1==t {found=1} END {exit !found}'; then
      printf '%s line %s: %s is listed twice\n' "${f##*/}" "$n" "$t" >&2; return 1
    fi
    recs="${recs}${t} ${pk} ${kind} ${arg}
"
  done <<EOF_SECTION
$sec
EOF_SECTION
  # a floor source must exist, and a key shared with a floored table needs one
  local other okind opk
  while read -r t pk kind arg; do
    [ -n "$t" ] || continue
    case "$kind" in
      floor)
        read -r okind opk <<EOF
$(printf '%s\n' "$recs" | awk -v o="$arg" '$1==o {print $3, $2}')
EOF
        case "$okind" in
          base|seed) ;;
          *) printf '%s: %s takes its floor from %s, which is not a table with a floor of its own in this file\n' "${f##*/}" "$t" "$arg" >&2; return 1 ;;
        esac
        [ "$opk" = "$pk" ] || { printf '%s: %s (key %s) takes its floor from %s, whose key is %s; a floor is shared only by tables that share a key\n' "${f##*/}" "$t" "$pk" "$arg" "$opk" >&2; return 1; }
        ;;
      sync)
        other="$(printf '%s\n' "$recs" | awk -v k="$pk" -v t="$t" '$1!=t && $2==k && ($3=="base" || $3=="seed") {print $1; exit}')"
        [ -z "$other" ] || { printf '%s: %s:%s has no floor source, but %s is the key of %s, which has a floor; write %s:%s:floor=%s\n' "${f##*/}" "$t" "$pk" "$pk" "$other" "$t" "$pk" "$other" >&2; return 1; }
        ;;
    esac
    case "$kind" in
      sync|base)
        case " ${UP_CLINICAL_TABLES} " in
          *" ${t} "*) printf '%s: %s is clinical data and needs its floor from the seed (%s:%s:seed) or from another table (floor=<table>): without one it has no capture filter, and every clinic would publish its edits to the hub'"'"'s rows\n' "${f##*/}" "$t" "$t" "$pk" >&2; return 1 ;;
        esac ;;
    esac
  done <<EOF
$recs
EOF
  printf '%s' "$recs"
}

# up_floor_of FILE TABLE MANIFEST: the floor of TABLE's keys (nothing if it has none).
up_floor_of(){
  local f="$1" want="$2" m="${3:-}" recs t="" pk="" kind="" arg="" key v
  recs="$(up_tables_read "$f")" || return 1
  read -r t pk kind arg <<EOF
$(printf '%s\n' "$recs" | awk -v t="$want" '$1==t')
EOF
  if [ -z "$t" ]; then printf '%s does not list %s, so it has no floor to give\n' "${f##*/}" "$want" >&2; return 1; fi
  if [ "$kind" = floor ]; then read -r t pk kind arg <<EOF
$(printf '%s\n' "$recs" | awk -v t="$arg" '$1==t')
EOF
  fi
  case "$kind" in
    base) printf '%s\n' "$arg" ;;
    seed)
      key="FLOOR_$(printf '%s' "$t" | tr '[:lower:]' '[:upper:]')"
      if [ -z "$m" ] || [ ! -f "$m" ]; then
        printf 'the %s floor comes from the seed manifest (%s), and there is no manifest at %s\n' "$t" "$key" "${m:-an unset path}" >&2; return 1
      fi
      v="$({ grep -E "^${key}=" "$m" || true; } | tail -1 | cut -d= -f2- | tr -d "\"' ")"
      case "$v" in
        '') printf 'the %s floor comes from the seed manifest, and %s carries no %s\n' "$t" "$m" "$key" >&2; return 1 ;;
        *[!0-9]*) printf 'the %s floor comes from the seed manifest, and %s in %s is not a number: %s\n' "$t" "$key" "$m" "$v" >&2; return 1 ;;
      esac
      printf '%s\n' "$v" ;;
    *) return 0 ;;
  esac
}

# tables_unrouted DB: the [down] tables every clinic keeps (no clinic=<column>).
tables_unrouted(){ tables_list "$1" down | grep -v ':clinic=' | cut -d: -f1; }

# tables_routes DB: "<table> <column> <floor table>" for each [down] row marked
# clinic=<column>. The clinic compares <column> with its floor for <floor table>:
# the table itself when <column> is id, table t when <column> is t_id.
tables_routes(){
  tables_list "$1" down | sed -n 's/^\([a-z0-9_]*\):clinic=\([a-z0-9_]*\)$/\1 \2/p' |
    while read -r t c; do
      if [ "$c" = id ]; then echo "$t $c $t"; else echo "$t $c ${c%_id}"; fi
    done
}

# Run as a command:
#   tables.sh DB up|down          the section's entries, as written
#   tables.sh DB unrouted|routes  tables_unrouted / tables_routes
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  [ $# -eq 2 ] || { echo 'usage: tables.sh <openmrs|odoo|openelis> <up|down|unrouted|routes>' >&2; exit 2; }
  case "$2" in
    up|down) tables_list "$1" "$2" ;;
    unrouted) tables_unrouted "$1" ;;
    routes) tables_routes "$1" ;;
    *) echo "tables.sh: unknown section $2" >&2; exit 2 ;;
  esac
fi
