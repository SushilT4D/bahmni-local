#!/usr/bin/env bash
# Print this clinic's OpenELIS down-filter condition.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"
REPO_DIR="${REPO_DIR:-$(cd "${HERE}/../.." && pwd)}"
die(){ printf 'clinlims-down-filter: %s\n' "$*" >&2; exit 1; }
file_get(){ # FILE KEY -> the last value of KEY in FILE, quotes and blanks trimmed
  [ -f "$1" ] || return 0
  { grep -E "^$2=" "$1" || true; } | tail -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*$//' | tr -d "\"' "
}
value_of(){ # KEY -> environment, else clinic/.env, else SEED_MANIFEST, else .install-state
  local k="$1" v="${!1:-}"
  [ -n "$v" ] || v="$(file_get "${CLINIC_DIR}/.env" "$k")"
  [ -n "$v" ] || [ -z "${SEED_MANIFEST:-}" ] || v="$(file_get "${SEED_MANIFEST}" "$k")"
  [ -n "$v" ] || v="$(file_get "${CLINIC_DIR}/.install-state" "$k")"
  printf '%s' "$v"
}

# Resolve the clinic residue and the hub's OpenELIS routing list.
r="$(value_of BHS_SITE_NUMBER)"
case "$r" in [1-9]) ;; *) die "this clinic's residue (BHS_SITE_NUMBER, 1-9) is not set (read '${r}'): the OpenELIS down filter keeps only this clinic's rows and is not written without it" ;; esac
routes="$(bash "${REPO_DIR}/sync/tables/tables.sh" openelis routes)" || die "the hub's down list could not be read (reason above); no filter was written"

unrouted="$(bash "${REPO_DIR}/sync/tables/tables.sh" openelis unrouted)" || die "the hub's down list could not be read (reason above); no filter was written"
parts=""; missing=""
# Build filters for unrouted tables and clinic-owned rows.
for t in $unrouted; do parts="${parts}${parts:+ || }t == '${t}'"; done
while read -r t col ft; do
  [ -n "$t" ] || continue
  key="CLINLIMS_FLOOR_$(printf '%s' "$ft" | tr '[:lower:]' '[:upper:]')"
  f="$(value_of "$key")"
  if [ -z "$f" ]; then case "${missing} " in *" ${key} "*) ;; *) missing="${missing} ${key}" ;; esac; continue; fi
  case "$f" in *[!0-9]*|0*) die "${key} is '${f}', not a whole number above 0" ;; esac
  [ $(( f % 10 )) = 0 ] || die "${key} is ${f}, not a multiple of 10: floor + residue would not be on this clinic's residue"
  x="a.get('${col}')"
  parts="${parts}${parts:+ || }(t == '${t}' && ${x} instanceof Number && ${x}.longValue() >= ${f}L && ${x}.longValue() % 10 == ${r})"
done <<EOF
${routes}
EOF
[ -z "$missing" ] || die "no OpenELIS floor for this clinic:${missing} (looked in the environment, clinic/.env, SEED_MANIFEST and clinic/.install-state). Each is the id below which every row of that table came from the hub's seed. Without it the OpenELIS down filter is not written, and lab results entered at the hub do not reach this clinic's OpenELIS."
[ -n "$parts" ] || die "the hub's down list sends no OpenELIS table down; there is nothing to filter"
# Print the Debezium filter expression.
printf "%s\n" "def a = value.get('after'); def t = value.get('source').get('table'); value.get('op') != 'd' && a != null && (${parts})"
