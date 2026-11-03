#!/usr/bin/env bash
# A multi-table sink reads one ordered topic but the JDBC sink buffers records
# per table and flushes the buffers in map order, so a parent row and its child
# in the same batch can be written child-first and fail the foreign key. One
# record per statement keeps the topic's order all the way to the database.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$HERE/../.."
fails=0
for f in "$R"/clinic/connectors/*-sink-all.json "$R"/hub/connectors/*-sink-all.json; do
  v="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); c=d.get('config',d); print(c.get('batch.size',''))" "$f")"
  if [ "$v" = 1 ]; then printf '  ok   %s: batch.size 1\n' "${f#$R/}"; else printf '  FAIL %s: batch.size is %s, want 1\n' "${f#$R/}" "${v:-unset}"; fails=$((fails+1)); fi
done
n=$(ls "$R"/clinic/connectors/*-sink-all.json "$R"/hub/connectors/*-sink-all.json | wc -l | tr -d ' ')
[ "$n" -ge 6 ] && printf '  ok   %s multi-table sink configs checked\n' "$n" || { printf '  FAIL only %s multi-table sink configs found\n' "$n"; fails=$((fails+1)); }
exit "$fails"
