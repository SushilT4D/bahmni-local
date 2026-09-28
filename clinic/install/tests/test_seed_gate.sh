#!/usr/bin/env bash
# The seed gate's refusal for a machine whose LAN name no longer points at it,
# and seed.sh's argument handling.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLINIC_DIR="$TMP"; . "${HERE}/../lib.sh"; . "${HERE}/../state.sh"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
v(){ lan_name_verdict "$@" 2>&1; }
[ "$(v 10.0.0.5 10.0.0.5 bahmni.clinic)" = ok ] && ok_ "name on this machine" || bad "same ip: $(v 10.0.0.5 10.0.0.5 bahmni.clinic)"
case "$(v 10.0.0.9 10.0.0.5 bahmni.clinic)" in "bahmni.clinic resolves to 10.0.0.9, but this machine is 10.0.0.5"*) ok_ "moved machine refused" ;; *) bad "moved: $(v 10.0.0.9 10.0.0.5 bahmni.clinic)" ;; esac
case "$(v '' 10.0.0.5 bahmni.clinic)" in "bahmni.clinic does not resolve on this machine"*) ok_ "no answer refused" ;; *) bad "empty: $(v '' 10.0.0.5 bahmni.clinic)" ;; esac
out="$(bash "${HERE}/../seed.sh" 2>&1)"; case "$out" in *"--seed <folder>"*) ok_ "seed.sh without --seed prints usage" ;; *) bad "usage: $out" ;; esac
out="$(bash "${HERE}/../seed.sh" --seed "$TMP/nope" 2>&1)"; case "$out" in *"seed folder not found"*) ok_ "missing folder refused" ;; *) bad "missing folder: $out" ;; esac
mkdir -p "$TMP/s" "$TMP/c"
out="$(CLINIC_DIR="$TMP/c" bash "${HERE}/../seed.sh" --seed "$TMP/s" 2>&1)"; case "$out" in *"this machine is not installed yet"*) ok_ "no clinic/.env refused" ;; *) bad "not installed: $out" ;; esac
grep -q '^# phase: seed$' "${HERE}/../tasks/005-seed-gate.sh" 2>/dev/null && ok_ "005 runs in the seed sitting" || bad "005 missing or not seed-phase"
exit $((fails > 0))
