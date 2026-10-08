# Reader for sync/local/tables.conf, sourced by every script that reads it, so
# the source connector, MirrorMaker, the striding script and the hub's sinks
# all accept the same lines and agree on what each one means. A line one
# reader skips and another accepts is a table captured with no sink, or sunk
# with no striding; a line this reader cannot place is refused, never skipped.
#
# up_tables_read FILE prints one record per table line, in file order:
#   <table> <pk> base <base_id>    table:pk:<digits>       fixed floor; striding moves AUTO_INCREMENT above it
#   <table> <pk> seed -            table:pk:seed           the floor is FLOOR_<TABLE> in the seed manifest
#   <table> <pk> floor <other>     table:pk:floor=<other>  no counter of its own; reads <other>'s floor
#   <table> <pk> sync -            table:pk                sync only, no floor
# and on a line it refuses prints the reason to stderr and returns 1.
#
# A floor=<other> line names a table with a floor of its own (base or seed)
# and the same key column: drug_order's key is orders.order_id, so its rows
# are on a clinic's residue exactly when the orders row is, and the capture
# filter and catch-up read the orders floor. A sync-only line whose key column
# is a floored table's key is refused for the same reason: without a floor
# source nothing can tell its legacy rows from the clinic's own.
#
# Some tables are never captured at a clinic, whatever the line says: users and
# user_property are written at the hub and reach a clinic through its down
# sinks, and global_property is each node's own configuration (it holds, among
# others, the next order number this node issues). A line for one is refused.
UP_NEVER_TABLES="users user_property global_property"
#
# The source connector's signal table (Debezium's source signal channel: a row
# inserted there asks the connector for an incremental snapshot) is captured
# on every clinic, outside this file: it is not clinical data, is never sent to
# the hub and has no sink. Every reader puts it in the connector's include list
# (up_signal_collection) and refuses a line that names it, so it can never
# acquire a topic in MirrorMaker's list or a sink on the hub.
UP_SIGNAL_TABLE=debezium_signal
#
# The clinical tables. Their rows below the floor are the hub's, copied to
# every clinic by the seed, so a line for one must say where its floor comes
# from (seed, or floor=<table>): read as sync-only or with a fixed base_id, it
# would carry no capture filter and every clinic would publish its edits to
# the hub's rows. Such a line is refused.
UP_CLINICAL_TABLES="obs orders drug_order"
up_signal_collection(){ printf '%s.%s\n' "${1:-openmrs}" "${UP_SIGNAL_TABLE}"; }
#
# bash 3.2 compatible (macOS): no associative arrays.
up_tables_read(){
  local f="$1" line n=0 t pk third kind arg recs="" re
  re='^([A-Za-z0-9_]+):([A-Za-z0-9_,]+)(:([^:[:space:]]+))?$'
  [ -f "$f" ] || { printf 'tables.conf not found: %s\n' "$f" >&2; return 1; }
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
  done < "$f"
  # second pass: a floor source must exist, and a key shared with a floored
  # table needs one
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

# up_floor_of FILE TABLE MANIFEST prints the floor that applies to TABLE's keys:
# its base_id, its seed manifest floor, or the floor of the table it reads; and
# nothing for a sync-only table. Returns 1, with the reason on stderr, when
# TABLE is not in FILE, or its floor should come from the manifest and the
# manifest is missing or does not carry it as a number. It never stops the
# calling shell itself, under set -e -o pipefail or not: a caller that does not
# test the status still sees why.
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
