#!/usr/bin/env bash
# Prints the condition of this clinic's OpenELIS down filter: the Groovy
# expression that keeps a record of the hub's OpenELIS down stream only when it
# carries a row this clinic owns.
#
#   clinic/scripts/clinlims-down-filter.sh
#
# Every clinic receives the same stream: the result, analysis and sample rows a
# hub lab user wrote (sync/hub-down.conf). Each row names its clinic by a
# routing column (sync/hub-down.sh --routes clinlims): a result by the analysis
# it answers, an analysis or a sample by its own id. A record is kept when
#   - it is not a delete (a delete of a clinic's lab row at the hub stays at the
#     hub; the clinic's copy is the clinic's), and
#   - the routing column is a number, at or above this clinic's floor for the
#     table it names, and ends in this clinic's residue.
# Below the floor a residue says nothing about who wrote a row: those ids were
# handed out before the clinic's sequences were strided, and are the hub's.
#
# The residue is RESIDUE (environment, else clinic/.env). The floor of table t
# is CLINLIMS_FLOOR_<T> (for example CLINLIMS_FLOOR_ANALYSIS): the first id of
# t this clinic's OpenELIS hands out lies above it, a multiple of 10, taken from
# the environment, else clinic/.env, else SEED_MANIFEST, else the floors the
# seed recorded on this machine (clinic/.install-state). Without the residue or
# any floor it prints nothing, names what is missing on stderr and exits 1:
# the stream is then not taken at all, rather than taken on a guessed floor.
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

r="$(value_of RESIDUE)"
case "$r" in [1-9]) ;; *) die "this clinic's residue (RESIDUE, 1-9) is not set (read '${r}'): the OpenELIS down filter keeps only this clinic's rows and is not written without it" ;; esac
routes="$(bash "${REPO_DIR}/sync/hub-down.sh" --routes clinlims)" || die "the hub's down list could not be read (reason above); no filter was written"

parts=""; missing=""
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
[ -n "$parts" ] || die "the hub's down list routes no OpenELIS table; there is nothing to filter"
printf "%s\n" "def a = value.get('after'); def t = value.get('source').get('table'); value.get('op') != 'd' && a != null && (${parts})"
