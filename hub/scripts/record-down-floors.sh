#!/usr/bin/env bash
# record-down-floors.sh [--out FILE] -- PSQL-COMMAND...
#
# Run on the hub right after its Odoo ids are strided. Reads the floor of each
# down table with an `id` (sync/hub-down.conf) from its sequence and writes them
# to hub/odoo-down-floors.local, one "<table> <floor>" line each. The hub's down
# publication filters those tables with (id < <floor> OR id % 10 = 0), so the
# floors must be the values the sequences restarted at, and are recorded once.
#
# PSQL-COMMAND is how to reach the hub's Odoo database as a role that may read
# its sequences, for example:
#   hub/scripts/record-down-floors.sh -- docker exec -i <odoo-db-container> psql -U odoo -d odoo
#
# Refuses, writing nothing: when the file already exists (it keeps the floors of
# the striding that made them, and a later reading would be higher); when the
# down list cannot be read; when a sequence is not strided, or has minted an id
# since its restart (hub/odoo/read-down-floors.sql names the table).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/../odoo-down-floors.local"
[ "${1:-}" = --out ] && { OUT="${2:?--out needs a file}"; shift 2; }
[ "${1:-}" = -- ] && shift
[ "$#" -gt 0 ] || { echo "usage: record-down-floors.sh [--out FILE] -- <psql command...>" >&2; exit 2; }
die(){ printf 'record-down-floors.sh: %s\n' "$*" >&2; exit 1; }
[ -e "$OUT" ] && die "$OUT already exists: it holds the floors measured when this hub's ids were strided, and is never rewritten. Remove it only if the hub's Odoo ids were strided again from a fresh database."
tables="$(bash "$HERE/../../sync/hub-down.sh" odoo)" || die "the down list could not be read (reason above)"
tables="$(printf '%s\n' "$tables" | paste -sd, -)"
rows="$("$@" -v ON_ERROR_STOP=1 -qAt -v tables="$tables" -f /dev/stdin < "$HERE/../odoo/read-down-floors.sql" 2>&1)" \
  || die "the floors could not be read; nothing was written: $(printf '%s\n' "$rows" | grep -E 'ERROR|FATAL|error' | head -1)"
[ -n "$rows" ] || die "no down table with an id answered; nothing was written"
tmp="$OUT.tmp.$$"
( umask 022; printf '%s\n' "$rows" > "$tmp" ) || die "could not write $tmp"
bash "$HERE/down-floors.sh" "$tmp" >/dev/null || { rm -f "$tmp"; die "the floors read do not validate; nothing was written"; }
mv "$tmp" "$OUT"
printf '%s\n' "$rows" | sed 's/^/  floor /'
echo "  wrote $OUT ($(printf '%s\n' "$rows" | wc -l | tr -d ' ') tables)"
