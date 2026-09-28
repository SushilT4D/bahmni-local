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
# --from cannot skip the gate on a machine that never passed it
mkdir -p "$TMP/c3"; printf 'CLINIC_SLUG=azure\nRESIDUE=7\nLAN_NAME=bahmni.clinic\n' > "$TMP/c3/.env"; printf 'STATE=INSTALLED\n' > "$TMP/c3/.install-state"
out="$(CLINIC_DIR="$TMP/c3" REPO_DIR="${HERE}/../../.." TASKS_DIR="$TMP/none" INSTALL_LOG="$TMP/l.log" bash "${HERE}/../seed.sh" --seed "$TMP/s" --from 050 2>&1)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"--from and --only only resume a seed that stopped part-way"*) true ;; *) false ;; esac && ok_ "seed --from on an INSTALLED machine refused" || bad "seed --from not refused: rc=$rc $out"
printf 'STATE=SEEDED\n' > "$TMP/c3/.install-state"
out="$(CLINIC_DIR="$TMP/c3" REPO_DIR="${HERE}/../../.." TASKS_DIR="$TMP/none" INSTALL_LOG="$TMP/l.log" bash "${HERE}/../seed.sh" --seed "$TMP/s" --only 050 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok_ "seed --only on a SEEDED machine refused" || bad "seed --only on SEEDED not refused: rc=$rc"
# 005 carries the sync-started flag into the gate, and fails closed on counts
G="${HERE}/../tasks/005-seed-gate.sh"
grep -q 'stamp_gate_verdict "$st" "$(stamp_get SYNC_STARTED)"' "$G" && ok_ "005 refuses a retry after sync started" || bad "005 ignores SYNC_STARTED"
grep -q '|| printf 0' "$G" && bad "005 turns a failed count into 0" || ok_ "005 does not turn a failed count into 0"
grep -q 'stamp_put SYNC_STARTED 1' "${HERE}/../tasks/090-local-sync.sh" && ok_ "090 marks that sync started" || bad "090 does not mark SYNC_STARTED"
exit $((fails > 0))
