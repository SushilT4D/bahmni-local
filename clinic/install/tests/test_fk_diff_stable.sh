#!/usr/bin/env bash
# The foreign-key comparisons (state.sh provenance_fk_verdict, hub
# check-clinical-fks.sh) name what differs on every run. They take their set
# differences through a pipe: with process substitution a /dev/fd closed before
# its reader opened it read as empty now and then, and a refusal lost the keys
# it should name.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLINIC_DIR="$TMP" INSTALL_DIR="${HERE}/.."
. "${HERE}/../lib.sh"; . "${HERE}/../state.sh"
F="$(sed -n '/^provenance_fk_verdict()/,/^}/p' "${HERE}/../state.sh")"
case "$F" in *'<('*) bad "provenance_fk_verdict uses process substitution" ;; *) ok_ "provenance_fk_verdict uses no process substitution" ;; esac
grep -q '<(' "$RP/hub/scripts/check-clinical-fks.sh" && bad "check-clinical-fks.sh uses process substitution" || ok_ "check-clinical-fks.sh uses no process substitution"
[ "$(lines_not_in "$(printf 'a\nb\nc')" "$(printf 'b\nd\na\ne')")" = "$(printf 'd\ne')" ] && ok_ "lines_not_in: the lines of B not in A, in B's order" || bad "lines_not_in: $(lines_not_in "$(printf 'a\nb\nc')" "$(printf 'b\nd\na\ne')" | tr '\n' ' ')"
printf 'fk\tset\t2\tx\nfk\tencounter\tvisit_id\tvisit\tvisit_id\tencounter_visit\nfk\tvisit\tpatient_id\tpatient\tpatient_id\tvisit_patient\n' > "$TMP/rec"
rows="$(printf 'encounter\tvisit_id\tvisit\tvisit_id\tencounter_visit\nx\tvisit_id\tvisit\tvisit_id\tx_visit')"
want="this clinic's foreign keys on visit differ from the hub's (only at the hub: visit.patient_id -> patient.patient_id)"
n=0; for i in $(seq 1 40); do case "$(provenance_fk_verdict "$TMP/rec" "$rows")" in "$want"*) n=$((n+1)) ;; esac; done
[ "$n" = 40 ] && ok_ "40 runs: every refusal names visit.patient_id as the hub's" || bad "only ${n} of 40 runs named the key"
exit $((fails > 0))
