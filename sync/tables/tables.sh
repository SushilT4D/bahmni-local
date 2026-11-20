# The one reader of the table lists in sync/tables/: every script reads them through it, so
# no table is captured by one script and skipped by another. A line it cannot place is refused.
# As a command: tables.sh <openmrs|odoo|openelis> <up|down> | subsystems | hub-down [args of hub_down]
#
# up_tables_read FILE prints one record per table line of FILE's [up] section
# (of the whole file, for a file with no sections), in file order:
#   <table> <pk> base <base_id>    table:pk:<digits>       fixed floor; striding moves AUTO_INCREMENT above it
#   <table> <pk> seed -            table:pk:seed           the floor is FLOOR_<TABLE> in the seed manifest
#   <table> <pk> floor <other>     table:pk:floor=<other>  no counter of its own; reads <other>'s floor
#   <table> <pk> sync -            table:pk                sync only, no floor
# and on a line it refuses prints the reason to stderr and returns 1.
# A floor=<other> line shares <other>'s key column and floor (drug_order and test_order on
# orders.order_id); a sync-only line on a floored table's key is refused.
#
# Refused as lines: users and user_property come down from the hub; global_property is per node.
UP_NEVER_TABLES="users user_property global_property"
# Debezium's signal table: put in every include list, refused as a line, so it never gets a topic or sink.
UP_SIGNAL_TABLE=debezium_signal
# Their rows below the floor are the hub's (from the seed): a line must be seed or floor=<table>.
UP_CLINICAL_TABLES="obs orders drug_order test_order"
# Published only for rows this clinic minted (CLINLIMS_FLOOR_<TABLE>, own residue); each has a
# filter step, in this order, in clinic/scripts/templates/clinlims-source-connector.json.
UP_CLINLIMS_OWN_ROWS="system_user result_signature"
up_signal_collection(){ printf '%s.%s\n' "${1:-openmrs}" "${UP_SIGNAL_TABLE}"; }
#
TABLES_DIR="${TABLES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
tables_has_sections(){ grep -qE '^[[:space:]]*\[[a-z]+\][[:space:]]*(#.*)?$' "$1" 2>/dev/null; }
tables_conf(){ [ -f "${TABLES_DIR}/$1.conf" ] || { printf 'no such file: %s\n' "${TABLES_DIR}/$1.conf" >&2; return 1; }; }
# Lines outside [SECTION] are blanked, not dropped, so a reader's line numbers stay the file's own.
tables_section(){
  if ! tables_has_sections "$1"; then cat "$1"; return; fi
  awk -v s="[$2]" '{ l = $0; sub(/#.*/, "", l); gsub(/^[ \t]+|[ \t]+$/, "", l) }
    l ~ /^\[[a-z]+\]$/ { u = (l == s); print ""; next } { print (u ? $0 : "") }' "$1"
}
tables_lines(){ tables_section "$1" "$2" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true; }
tables_list(){ # DB SECTION -> table names
  tables_conf "$1" || return 1
  tables_lines "${TABLES_DIR}/$1.conf" "$2" | cut -d: -f1
}
subsystems_list(){ # <schema>:<table> rows, each schema's aggregate topic first
  tables_conf openelis && tables_conf odoo || return 1
  printf 'clinlims:all\nodoo:all\n'
  tables_lines "${TABLES_DIR}/openelis.conf" up | sed 's/^/clinlims:/'
  tables_lines "${TABLES_DIR}/odoo.conf" up | sed 's/^/odoo:/'
}
hub_down_list(){
  tables_conf odoo && tables_conf openelis || return 1
  tables_lines "${TABLES_DIR}/odoo.conf" down | sed 's/^/odoo:/'
  tables_lines "${TABLES_DIR}/openelis.conf" down | sed 's/^/clinlims:/'
}
# Written at the clinics, so never sent down: a hub write to one would reach every clinic.
HUB_NEVER_DOWN_ODOO="res_partner res_partner_attributes sale_order sale_order_line account_move account_move_line stock_quant"
# The only OpenELIS tables that go down: what a hub lab user completes for one clinic's sample
# (routed by clinic=<column>), the lab accounts that work names, and the hub-only test catalogue.
HUB_DOWN_CLINLIMS_ROUTED="result analysis sample"
HUB_DOWN_CLINLIMS_ALL="system_user"
HUB_DOWN_CLINLIMS_CATALOGUE="scriptlet label method test_formats test_trailer type_of_test_result org_mls_lab_type organization organization_type organization_organization_type dictionary_category dictionary unit_of_measure test_section type_of_sample analyte test test_result test_analyte result_limits panel panel_item sampletype_test sampletype_panel"
# hub_down_rows: the [down] rows, or the first row it refuses and 1; a caller never renders from half a list.
hub_down_rows(){
  local rows synced
  rows="$(hub_down_list)" && synced="$(subsystems_list | tr '\n' ' ')" || return 1
  printf '%s\n' "$rows" | awk -F: -v synced="$synced" -v never="$HUB_NEVER_DOWN_ODOO" -v routed="$HUB_DOWN_CLINLIMS_ROUTED" \
      -v accounts="$HUB_DOWN_CLINLIMS_ALL" -v catalogue="$HUB_DOWN_CLINLIMS_CATALOGUE" '
    function set(str, a, sep,   n, i, p) { n = split(str, p, sep); for (i = 1; i <= n; i++) a[p[i]] = 1 }
    function no(msg) { print "the [down] lists: " $0 ": " msg > "/dev/stderr"; bad = 1; exit 1 }
    BEGIN { set(synced, up, " "); set(never, nv, " "); set(routed, rt, " "); set(accounts, al, " "); set(catalogue, ct, " ") }
    $0 == "" { next }
    {
      s = $1; t = $2; col = ""
      if (NF > 3 || s !~ /^[a-z0-9_]+$/ || t !~ /^[a-z0-9_]+$/) no("not <schema>:<table>[:clinic=<column>] with bare lowercase names")
      if (NF == 3) { if ($3 !~ /^clinic=[a-z_][a-z0-9_]*$/) no("the third field is clinic=<column> or nothing"); col = substr($3, 8) }
      if (t == "all") no("all is the aggregate topic, not a table")
      if (s == "odoo" && (t in nv)) no("written at the clinics, so it never goes down")
      if (s == "odoo" && col != "") no("an Odoo row goes to every clinic and takes no clinic=<column>")
      if (s == "clinlims") {
        if (!((t in rt) || (t in al) || (t in ct))) no("written at the clinics, so it never goes down; only result, analysis and sample, the lab accounts (system_user) and the lab test catalogue go down")
        if ((t in rt) && col == "") no("it goes to one clinic, so the row names the column that routes it (clinic=<column>)")
        if (!(t in rt) && col != "") no("it goes to every clinic and takes no clinic=<column>")
      }
      if (s == "clinlims" && (t in ct)) { if ((s ":" t) in up) no("the lab test catalogue is written only at the hub, so it is never in an [up] list too") }
      else if (!((s ":" t) in up)) no("not a synced table (no " s ":" t " in the [up] lists)")
      if ((s ":" t) in seen) no("listed twice")
      seen[s ":" t] = 1; row[++n] = $0; rcol[s ":" t] = col
    }
    END {
      if (bad) exit 1
      for (i = 1; i <= n; i++) {
        split(row[i], f, ":"); c = rcol[f[1] ":" f[2]]
        if (c == "" || c == "id") continue
        ft = c; sub(/_id$/, "", ft)
        if (c !~ /_id$/ || rcol[f[1] ":" ft] == "") { print "the [down] lists: " row[i] ": clinic=" c " is id or <table>_id naming another routed row of the same schema" > "/dev/stderr"; exit 1 }
      }
      for (i = 1; i <= n; i++) print row[i]
    }'
}
# hub_down SCHEMA | --unrouted SCHEMA | --routes SCHEMA (<table> <column> <floor table>) | --subsystems
hub_down(){
  local mode=tables s="${1:-}" out rows
  case "${1:-}" in --routes|--unrouted) mode="${1#--}"; s="${2:-}" ;; --subsystems) mode=subsystems ;; esac
  rows="$(hub_down_rows)" || return 1
  out="$(printf '%s\n' "$rows" | awk -F: -v m="$mode" -v s="$s" '
    m == "subsystems" { if (!seen[$1]++) print $1; next }
    $1 != s { next }
    m == "tables" { print $2 }
    m == "unrouted" && $3 == "" { print $2 }
    m == "routes" && $3 != "" { c = $3; sub(/^clinic=/, "", c); f = $2; if (c != "id") { f = c; sub(/_id$/, "", f) }; print $2, c, f }')"
  [ -n "$out" ] || [ "$mode" = unrouted ] || { printf 'the [down] lists have no %s rows for %s\n' "$mode" "${s:-any schema}" >&2; return 1; }
  [ -z "$out" ] || printf '%s\n' "$out"
}
#
# bash 3.2 compatible (macOS): no associative arrays.
up_tables_read(){
  local f="$1" line n=0 t pk third kind arg recs="" re
  re='^([A-Za-z0-9_]+):([A-Za-z0-9_,]+)(:([^:[:space:]]+))?$'
  [ -f "$f" ] || { printf 'table list not found: %s\n' "$f" >&2; return 1; }
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
  done < <(tables_section "$f" up)
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

# Run as a command (not sourced): print a list.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1:-}" = hub-down ] && [ $# -gt 1 ]; then shift; hub_down "$@"; exit; fi
  case "${1:-}:${2:-}" in
    openmrs:up|openmrs:down|odoo:up|odoo:down|openelis:up|openelis:down)
      [ -f "${TABLES_DIR}/$1.conf" ] || { printf 'tables.sh: no such file: %s\n' "${TABLES_DIR}/$1.conf" >&2; exit 1; }
      tables_section "${TABLES_DIR}/$1.conf" "$2" | grep -v '^$' || true ;;
    subsystems:) subsystems_list ;;
    hub-down:) hub_down_list ;;
    *) printf 'usage: tables.sh <openmrs|odoo|openelis> <up|down> | subsystems | hub-down\n' >&2; exit 2 ;;
  esac
fi
