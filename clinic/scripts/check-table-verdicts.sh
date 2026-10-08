#!/usr/bin/env bash
# Check both sync table lists against hub/table-verdicts.conf:
#
#   hub/tables.conf          an unmarked row must have verdict DOWN, a row
#                            marked `relay` must have verdict relay;
#   sync/local/tables.conf   every row must have verdict UP or relay, and
#                            the file must pass sync/local/tables-conf.sh's
#                            reader, which every script that reads it uses;
#   UP_NEVER_TABLES          the tables that reader never lets a clinic
#                            capture must have verdict DOWN or OUT.
#
# So a table the hub does not solely write (UP), one delivered only by the
# seed (RESEED), a node-local one (OUT) or one whose verdict is not final
# (pending) can never gain a down sink, and a hub-written table can never be
# captured at a clinic. A table with no verdict line fails in either list.
#
#   clinic/scripts/check-table-verdicts.sh [repo-dir]
#
# repo-dir defaults to the checkout this script is in. Reads files only.
# Exit 0 when both lists agree with the verdicts, 1 naming every row that
# does not, 2 when a file is missing, the verdict file is malformed or
# sync/local/tables.conf has a line its reader refuses.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="${1:-$(cd "${HERE}/../.." && pwd)}"
V="${R}/hub/table-verdicts.conf"; DOWN="${R}/hub/tables.conf"; UP="${R}/sync/local/tables.conf"
for f in "$V" "$DOWN" "$UP"; do [ -f "$f" ] || { echo "  FAIL no such file: $f" >&2; exit 2; }; done

# the verdict file, as "table verdict" lines; malformed lines are fatal
verdicts="$(awk '
  { sub(/#.*/, "") }
  NF == 0 { next }
  {
    t = $1; v = $2
    if (t !~ /^[a-z_][a-z0-9_]*$/) { printf "bad table name \"%s\" (line %d)\n", t, NR > "/dev/stderr"; bad = 1; next }
    if (v !~ /^(DOWN|relay|UP|RESEED|OUT|pending)$/) { printf "%s: unknown verdict \"%s\" (line %d)\n", t, v, NR > "/dev/stderr"; bad = 1; next }
    if (v == "pending" && $3 !~ /^(DOWN|relay|UP|RESEED|OUT)$/) { printf "%s: pending needs the proposed verdict after it (line %d)\n", t, NR > "/dev/stderr"; bad = 1; next }
    if (v != "pending" && NF > 2) { printf "%s: only a pending verdict takes a third field (line %d)\n", t, NR > "/dev/stderr"; bad = 1; next }
    if (t in seen) { printf "%s: listed twice (lines %d and %d)\n", t, seen[t], NR > "/dev/stderr"; bad = 1; next }
    seen[t] = NR; print t, v
  }
  END { exit bad }' "$V")" || { echo "  FAIL ${V} is malformed (above); nothing was checked" >&2; exit 2; }

verdict_of(){ printf '%s\n' "$verdicts" | awk -v t="$1" '$1 == t { print $2; exit }'; }

fails=0
bad(){ printf '  FAIL %s\n' "$1" >&2; fails=$((fails+1)); }

# hub/tables.conf: table:pk[,pk2...][:relay]
n=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"; line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -n "$line" ] || continue
  t="${line%%:*}"; role=""
  case "$line" in *:*:*) role="${line##*:}" ;; esac
  v="$(verdict_of "$t")"; n=$((n+1))
  if [ -z "$v" ]; then bad "hub/tables.conf lists ${t}, which has no verdict in hub/table-verdicts.conf"
  elif [ "$role" = relay ]; then [ "$v" = relay ] || bad "hub/tables.conf marks ${t} relay, but its verdict is ${v}"
  elif [ -n "$role" ]; then bad "hub/tables.conf: ${t} has an unknown role '${role}'"
  else [ "$v" = DOWN ] || bad "hub/tables.conf lists ${t} for a down sink, but its verdict is ${v}: only the hub's own tables (DOWN) are sent down"
  fi
done < "$DOWN"

# sync/local/tables.conf, through the reader every script that captures,
# mirrors, strides or sinks it uses: a line that reader refuses is refused here
# too, so this check never passes a list the sync layer cannot run
# shellcheck source=../../sync/local/tables-conf.sh
. "${HERE}/../../sync/local/tables-conf.sh"
recs="$(up_tables_read "$UP" 2>&1)" || { printf '  FAIL sync/local/tables.conf is refused by its reader (sync/local/tables-conf.sh): %s\n' "$recs" >&2; exit 2; }
m=0
while read -r t _; do
  [ -n "$t" ] || continue
  v="$(verdict_of "$t")"; m=$((m+1))
  case "$v" in
    UP|relay) ;;
    '') bad "sync/local/tables.conf lists ${t}, which has no verdict in hub/table-verdicts.conf" ;;
    *) bad "sync/local/tables.conf captures ${t} at the clinic, but its verdict is ${v}: a clinic sends up only what it writes (UP or relay)" ;;
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
    '') bad "sync/local/tables-conf.sh never lets a clinic capture ${t}, which has no verdict in hub/table-verdicts.conf (it must be DOWN or OUT)" ;;
    *) bad "sync/local/tables-conf.sh never lets a clinic capture ${t}, but its verdict is ${v}: a table no clinic captures is DOWN or OUT" ;;
  esac
done

[ "$fails" -eq 0 ] || exit 1
printf '  ok   %s hub/tables.conf row(s), %s sync/local/tables.conf row(s) and the %s never-captured table(s) agree with hub/table-verdicts.conf\n' "$n" "$m" "$(printf '%s\n' ${UP_NEVER_TABLES} | grep -c .)"
