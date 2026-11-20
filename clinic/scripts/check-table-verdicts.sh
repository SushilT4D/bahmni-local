#!/usr/bin/env bash
# Validate both sync table lists against cloud/table-verdicts.conf.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="${1:-$(cd "${HERE}/../.." && pwd)}"
V="${R}/cloud/table-verdicts.conf"; TF="${R}/sync/tables/openmrs.conf"
for f in "$V" "$TF"; do [ -f "$f" ] || { echo "  FAIL no such file: $f" >&2; exit 2; }; done
# shellcheck source=../../sync/tables/tables.sh
. "${R}/sync/tables/tables.sh"

# Parse verdicts and reject malformed or duplicate rows.
verdicts="$(awk '
  { sub(/#.*/, "") }
  NF == 0 { next }
  {
    t = $1; v = $2
    if (t !~ /^[a-z_][a-z0-9_]*$/) { printf "bad table name \"%s\" (line %d)\n", t, NR > "/dev/stderr"; bad = 1; next }
    if (v !~ /^(DOWN|relay|SHARED|UP|RESEED|OUT|pending)$/) { printf "%s: unknown verdict \"%s\" (line %d)\n", t, v, NR > "/dev/stderr"; bad = 1; next }
    if (v == "pending" && $3 !~ /^(DOWN|relay|SHARED|UP|RESEED|OUT)$/) { printf "%s: pending needs the proposed verdict after it (line %d)\n", t, NR > "/dev/stderr"; bad = 1; next }
    if (v != "pending" && NF > 2) { printf "%s: only a pending verdict takes a third field (line %d)\n", t, NR > "/dev/stderr"; bad = 1; next }
    if (t in seen) { printf "%s: listed twice (lines %d and %d)\n", t, seen[t], NR > "/dev/stderr"; bad = 1; next }
    seen[t] = NR; print t, v
  }
  END { exit bad }' "$V")" || { echo "  FAIL ${V} is malformed (above); nothing was checked" >&2; exit 2; }

verdict_of(){ printf '%s\n' "$verdicts" | awk -v t="$1" '$1 == t { print $2; exit }'; }

fails=0
bad(){ printf '  FAIL %s\n' "$1" >&2; fails=$((fails+1)); }

# sync/tables/openmrs.conf [down]: table:pk[,pk2...][:relay|:hub-rows|:changes|:clinic=<column>]
n=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"; line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -n "$line" ] || continue
  t="${line%%:*}"; role=""
  case "$line" in *:*:*) role="${line##*:}" ;; esac
  v="$(verdict_of "$t")"; n=$((n+1))
  if [ -z "$v" ]; then bad "sync/tables/openmrs.conf [down] lists ${t}, which has no verdict in cloud/table-verdicts.conf"
  elif [ "$role" = relay ]; then [ "$v" = relay ] || bad "sync/tables/openmrs.conf [down] marks ${t} relay, but its verdict is ${v}"
  elif [ "$role" = hub-rows ]; then
    # written at the hub and at the clinics, each its own rows; the cloud server captures only its own for clinics to pull
    [ "$v" = SHARED ] || bad "sync/tables/openmrs.conf [down] marks ${t} hub-rows, but its verdict is ${v}: only a table the hub and the clinics both write (SHARED) is captured for clinics as the cloud server's own rows"
  elif [ "$role" = changes ]; then
    # the hub's own table, sent as changes only: the same verdict as an unmarked row
    [ "$v" = DOWN ] || bad "sync/tables/openmrs.conf [down] marks ${t} changes, but its verdict is ${v}: only the cloud server's own tables (DOWN) are captured for clinics"
  elif case "$role" in clinic=*) true ;; *) false ;; esac; then
    # a clinic's table; the cloud server captures only its own rows, each kept by the clinic its column names
    [ "$v" = UP ] || bad "sync/tables/openmrs.conf [down] marks ${t} ${role}, but its verdict is ${v}: only a table the clinics write (UP) carries the hub's rows for a clinic"
    printf '%s' "${role#clinic=}" | grep -qE '^[a-z_][a-z0-9_]*$' || bad "sync/tables/openmrs.conf [down]: ${t} names a bad routing column '${role#clinic=}'"
  elif [ -n "$role" ]; then bad "sync/tables/openmrs.conf [down]: ${t} has an unknown role '${role}'"
  else [ "$v" = DOWN ] || bad "sync/tables/openmrs.conf [down] lists ${t} for a down sink, but its verdict is ${v}: only the cloud server's own tables (DOWN) are captured for clinics"
  fi
done < <(tables_section "$TF" down)

# Use the sync reader so this check accepts only valid table lists.
recs="$(up_tables_read "$TF" 2>&1)" || { printf '  FAIL the OpenMRS [up] list is refused by its reader (sync/tables/tables.sh): %s\n' "$recs" >&2; exit 2; }
m=0
while read -r t _; do
  [ -n "$t" ] || continue
  v="$(verdict_of "$t")"; m=$((m+1))
  case "$v" in
    UP|relay|SHARED) ;;
    '') bad "sync/tables/openmrs.conf [up] lists ${t}, which has no verdict in cloud/table-verdicts.conf" ;;
    *) bad "sync/tables/openmrs.conf [up] captures ${t} at the clinic, but its verdict is ${v}: a clinic sends up only what it writes (UP, relay or SHARED)" ;;
  esac
done <<EOF
$recs
EOF

# The tables that reader never lets a clinic capture (UP_NEVER_TABLES) must be
# the hub's (DOWN) or node-local (OUT) here: the two files make the same claim,
# and a verdict changed in one without the other fails until both agree.
for t in ${UP_NEVER_TABLES}; do
  v="$(verdict_of "$t")"
  case "$v" in
    DOWN|OUT) ;;
    '') bad "sync/tables/tables.sh never lets a clinic capture ${t}, which has no verdict in cloud/table-verdicts.conf (it must be DOWN or OUT)" ;;
    *) bad "sync/tables/tables.sh never lets a clinic capture ${t}, but its verdict is ${v}: a table no clinic captures is DOWN or OUT" ;;
  esac
done

[ "$fails" -eq 0 ] || exit 1
printf '  ok   %s sync/tables/openmrs.conf [down] row(s), %s sync/tables/openmrs.conf [up] row(s) and the %s never-captured table(s) agree with cloud/table-verdicts.conf\n' "$n" "$m" "$(printf '%s\n' ${UP_NEVER_TABLES} | grep -c .)"
