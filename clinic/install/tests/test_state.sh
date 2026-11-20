#!/usr/bin/env bash
# The stamp, the seed manifest and the records-entered-before-seeding rule.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLINIC_DIR="$TMP"; . "${HERE}/../lib.sh"; . "${HERE}/../state.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
expect(){ # LABEL WANT_RC WANT_PREFIX CMD...
  local label="$1" wrc="$2" wpre="$3"; shift 3; local out rc
  out="$("$@" 2>&1)"; rc=$?
  [ "$rc" = "$wrc" ] && case "$out" in "$wpre"*) true ;; *) false ;; esac && ok_ "$label" || bad "$label: rc=$rc out='$out'"
}
# stamp
[ -z "$(stamp_get STATE)" ] && ok_ "no stamp -> empty" || bad "no stamp not empty"
stamp_put STATE SEEDING; [ "$(stamp_get STATE)" = SEEDING ] && ok_ "stamp round-trips" || bad "stamp round-trip"
expect "gate: fresh machine ok"    0 "ok" stamp_gate_verdict ""
expect "gate: INSTALLED (the old two-step install) ok" 0 "ok" stamp_gate_verdict INSTALLED
expect "gate: SEEDING ok (retry)"  0 "ok" stamp_gate_verdict SEEDING
expect "gate: SEEDED refused"      1 "this machine is already installed with the hub's data" stamp_gate_verdict SEEDED
# manifest
S="$TMP/seed"; mkdir -p "$S"
for f in openmrs odoo openelis; do printf '%s' "$f" | gzip > "$S/$f.sql.gz"; done
now=1790000000   # a fixed instant; SEED_TAKEN_AT values below are relative to it
iso(){ python3 -c 'import sys,datetime; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
mk(){ { printf 'SEED_TAKEN_AT=%s\nSEED_SOURCE=hub\n' "$1"; for f in openmrs odoo openelis; do printf 'SHA256_%s=%s\n' "$(printf '%s' "$f" | tr a-z A-Z)" "$(sha256_of "$S/$f.sql.gz")"; done; } > "$S/manifest.env"; }
expect "manifest missing refused" 1 "the seed folder has no manifest.env" seed_manifest_verdict "$S" "$now" 6
mk "$(iso $((now - 2*86400)))"; expect "2-day-old dump ok" 0 "ok " seed_manifest_verdict "$S" "$now" 6
mk "$(iso $((now - 7*86400)))"; expect "7-day-old dump refused" 1 "the dump is 7 days old" seed_manifest_verdict "$S" "$now" 6
mk "$(iso $((now + 2*86400)))"; expect "future dump refused" 1 "the dump is dated in the future" seed_manifest_verdict "$S" "$now" 6
mk "$(iso $((now - 3600)))"; printf 'x' | gzip >> "$S/odoo.sql.gz"
expect "damaged dump refused" 1 "odoo.sql.gz does not match its checksum" seed_manifest_verdict "$S" "$now" 6
# a run that reached the sync layer cannot be redone by dropping databases
expect "gate: SEEDING after sync started refused" 1 "this install stopped after the sync layer had started" stamp_gate_verdict SEEDING 1
# --from/--only only resume a run that stopped part-way, past the gate; an
# installed machine runs only --only 010 (the name service)
expect "run: fresh machine ok"            0 "ok" run_gate_verdict "" "" ""
expect "run: --from on a fresh machine refused" 1 "--from and --only only resume an install that stopped part-way" run_gate_verdict "" 050 ""
expect "run: --from 050 on SEEDING ok"    0 "ok" run_gate_verdict SEEDING 050 ""
expect "run: --from 005 on SEEDING ok (the gate runs again)" 0 "ok" run_gate_verdict SEEDING 005 ""
expect "run: SEEDED refused"              1 "this machine is already installed with the hub's data" run_gate_verdict SEEDED "" ""
expect "run: --only 050 on SEEDED refused" 1 "this machine is already installed with the hub's data; only --only 010" run_gate_verdict SEEDED "" 050
expect "run: SEEDED --only 010 ok (re-point the name service)" 0 "ok" run_gate_verdict SEEDED "" 010
# after sync started only a resume that re-runs the drop (050 or earlier) is refused
resume_redoes_drop "" ""    && ok_ "no flags: the whole run, drop included" || bad "no flags should redo the drop"
resume_redoes_drop 050 ""   && ok_ "--from 050 redoes the drop" || bad "--from 050 should redo the drop"
resume_redoes_drop 005 ""   && ok_ "--from 005 redoes the drop" || bad "--from 005 should redo the drop"
resume_redoes_drop 090 ""   && bad "--from 090 does not redo the drop" || ok_ "--from 090 resumes past the drop"
resume_redoes_drop "" 100   && bad "--only 100 does not redo the drop" || ok_ "--only 100 resumes past the drop"
resume_redoes_drop "" 050   && ok_ "--only 050 redoes the drop" || bad "--only 050 should redo the drop"
exit $((fails > 0))
