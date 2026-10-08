#!/usr/bin/env bash
# Check both sync table lists against hub/table-verdicts.conf:
#
#   hub/tables.conf          an unmarked row must have verdict DOWN, a row
#                            marked `relay` must have verdict relay;
#   sync/local/tables.conf   every row must have verdict UP or relay.
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
# does not, 2 when a file is missing or the verdict file is malformed.
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

# sync/local/tables.conf: table:pk[:base_id]
m=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"; line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -n "$line" ] || continue
  t="${line%%:*}"; v="$(verdict_of "$t")"; m=$((m+1))
  case "$v" in
    UP|relay) ;;
    '') bad "sync/local/tables.conf lists ${t}, which has no verdict in hub/table-verdicts.conf" ;;
    *) bad "sync/local/tables.conf captures ${t} at the clinic, but its verdict is ${v}: a clinic sends up only what it writes (UP or relay)" ;;
  esac
done < "$UP"

[ "$fails" -eq 0 ] || exit 1
printf '  ok   %s hub/tables.conf row(s) and %s sync/local/tables.conf row(s) agree with hub/table-verdicts.conf\n' "$n" "$m"
