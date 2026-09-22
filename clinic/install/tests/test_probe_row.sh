#!/usr/bin/env bash
# The install probe is a row the node owns (an insert on the strided sequence,
# so its id carries the node's residue), and its marker names the node, so the
# hub can look for this clinic's marker. Updating the oldest row would write a
# legacy id every clinic shares on the hub.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
T100="${HERE}/../tasks/100-exit-checks.sh"
code="$(grep -vE '^[[:space:]]*#' "$T100")"
printf '%s' "$code" | grep -q 'select min(id) from res_partner' && bad "100 still updates the oldest res_partner row" || ok_ "100 no longer updates the oldest row"
printf '%s' "$code" | grep -q 'insert into res_partner' && ok_ "100 inserts a node-owned probe row" || bad "100 does not insert a probe row"
printf '%s' "$code" | grep -q 'INSTALL-PROBE-${CLINIC_SLUG}-' && ok_ "the marker names the node" || bad "the marker does not carry the slug"
printf '%s' "$code" | grep -q 'probe_id % 10' && ok_ "100 checks the probe id against the residue" || bad "100 does not check the residue"
# the block against a fake psql: the returned id must match the residue
blk="$(sed -n '/# probe-row:begin/,/# probe-row:end/p' "$T100")"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
run(){ # FAKE_ID RESIDUE
  env -i PATH="$W:$PATH" HOME="$W" bash -c "set -euo pipefail; . '${HERE}/../lib.sh'; CT=fakect; ct(){ fakect \"\$@\"; }; PG=x; CLINIC_SLUG=ghated; RESIDUE=$2; ${blk}" 2>&1
}
mkfake(){ printf '#!/bin/sh\ncat >/dev/null; echo %s\n' "$1" > "$W/fakect"; chmod +x "$W/fakect"; }
mkfake 808523; out="$(run 808523 3)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'residue 3' && ok_ "id 808523 passes for residue 3" || bad "id 808523 / residue 3: rc=$rc $out"
mkfake 808521; out="$(run 808521 3)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'not on residue 3' && ok_ "id 808521 fails for residue 3 (sequence not strided)" || bad "wrong residue accepted: rc=$rc $out"
mkfake ""; out="$(run "" 3)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'could not insert' && ok_ "a failed insert is a named FAIL" || bad "failed insert: rc=$rc $out"
exit "$fails"
