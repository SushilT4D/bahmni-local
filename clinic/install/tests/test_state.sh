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
stamp_put STATE INSTALLED; [ "$(stamp_get STATE)" = INSTALLED ] && ok_ "stamp round-trips" || bad "stamp round-trip"
expect "gate: no stamp refused"   1 "this machine is not installed" stamp_gate_verdict ""
expect "gate: INSTALLED ok"        0 "ok" stamp_gate_verdict INSTALLED
expect "gate: SEEDING ok (retry)"  0 "ok" stamp_gate_verdict SEEDING
expect "gate: SEEDED refused"      1 "this machine is already seeded" stamp_gate_verdict SEEDED
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
# early data
expect "nothing entered ok"         0 "ok"      early_data_verdict 0 0 0 0
expect "patients entered refused"   1 "records were entered on this machine before seeding" early_data_verdict 3 0 1 0
expect "patients entered, discard"  0 "discard" early_data_verdict 3 0 1 1
exit $((fails > 0))
