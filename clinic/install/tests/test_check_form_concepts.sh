#!/usr/bin/env bash
# install/check-form-concepts.py on a small forms tree: a form whose concepts
# the node has is OK, a new form missing one is BLOCKED (exit 1), one the node
# already publishes only WARNs, a manifest file that climbs out of the tree is
# skipped, never read, and a broken manifest or an empty concept list cannot
# run (exit 2). The tree is read as data: nothing in it is executed.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="${HERE}/../check-form-concepts.py"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
[ -x "$C" ] || { bad "no executable install/check-form-concepts.py"; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
T="$TMP/tree"; mkdir -p "$T/clinical_forms" "$T/tools"
U1=11111111-1111-1111-1111-111111111111; U2=22222222-2222-2222-2222-222222222222; U3=33333333-3333-3333-3333-333333333333
K1=aaaaaaaa-0000-0000-0000-000000000001; K2=aaaaaaaa-0000-0000-0000-000000000002; K3=aaaaaaaa-0000-0000-0000-000000000003
# Vitals: one field with a coded answer, both concepts known
printf '{"controls":[{"label":{"value":"Pulse"},"concept":{"uuid":"%s","answers":[{"uuid":"%s","name":"High"}]}}]}' "$K1" "$K2" > "$T/clinical_forms/$U1.json"
# ANC: a section holding a field whose concept the node lacks
printf '{"controls":[{"type":"section","controls":[{"label":{"value":"Temperature"},"concept":{"uuid":"%s"}}]}]}' "$K3" > "$T/clinical_forms/$U2.json"
cp "$T/clinical_forms/$U2.json" "$T/clinical_forms/$U3.json"
echo '{"controls":[{"concept":{"uuid":"aaaaaaaa-0000-0000-0000-00000000dead"}}]}' > "$TMP/outside.json"
printf '#!/usr/bin/env bash\ntouch "%s/ran"\n' "$TMP" > "$T/tools/check-concepts.sh"; chmod +x "$T/tools/check-concepts.sh"
manifest(){ # extra rows on stdin are appended
  { printf 'form_name\tversion\tuuid\tpublished\tretired\tfile\tsource\texported_at\n'
    printf 'Vitals\t1\t%s\t1\t0\tclinical_forms/%s.json\thub\t2000-01-01T00:00:00Z\n' "$U1" "$U1"
    cat; } > "$T/MANIFEST.tsv"
}
printf '%s\n%s\n' "$K1" "$K2" > "$TMP/known"; : > "$TMP/forms"; printf '%s\n' "$U3" > "$TMP/forms-u3"
run(){ "$C" --repo "$T" --known "$TMP/known" --known-forms "${1:-$TMP/forms}" 2>&1; }

manifest < /dev/null
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "^OK       Vitals v1 (clinical_forms/$U1.json): 2 concepts" && ok_ "a form whose concepts the node has is OK, exit 0" || bad "ok: rc=$rc out=$out"

printf 'ANC\t2\t%s\t1\t0\tclinical_forms/%s.json\thub\t2000-01-01T00:00:00Z\nANC\t1\t%s\t1\t1\tclinical_forms/%s.json\thub\t2000-01-01T00:00:00Z\n' "$U2" "$U2" "$U3" "$U3" | manifest
out="$(run)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "^BLOCKED  ANC v2 .*new to the node" && printf '%s' "$out" | grep -q "missing  $K3  Temperature" \
  && ok_ "a new form missing a concept is BLOCKED (exit 1), naming the concept and field" || bad "blocked: rc=$rc out=$out"
printf '%s' "$out" | grep -q 'ANC v1' && bad "a retired version was checked: $out" || ok_ "retired versions are not checked"

printf 'ANC\t3\t%s\t1\t0\tclinical_forms/%s.json\thub\t2000-01-01T00:00:00Z\n' "$U3" "$U3" | manifest
out="$(run "$TMP/forms-u3")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "^WARN     ANC v3 .*already published on the node" && ok_ "a form the node already publishes only warns, exit 0" || bad "warn: rc=$rc out=$out"

printf 'Evil\t1\t%s\t1\t0\tclinical_forms/../../outside.json\thub\t2000-01-01T00:00:00Z\nAbs\t1\t%s\t1\t0\t%s\thub\t2000-01-01T00:00:00Z\n' "$U2" "$U3" "$TMP/outside.json" | manifest
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(printf '%s' "$out" | grep -c 'is not a plain path inside the forms tree; skipped')" -eq 2 ] && ! printf '%s' "$out" | grep -q dead \
  && ok_ "a manifest file outside the tree (climbing or absolute) is skipped and never read" || bad "outside: rc=$rc out=$out"

printf 'bad header\n' > "$T/MANIFEST.tsv"
out="$(run)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'header is not' && ok_ "a manifest it does not know cannot be checked: exit 2" || bad "bad manifest: rc=$rc out=$out"
manifest < /dev/null; : > "$TMP/empty"
out="$("$C" --repo "$T" --known "$TMP/empty" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'lists no concepts' && ok_ "an empty concept list cannot be checked against: exit 2" || bad "empty known: rc=$rc out=$out"
out="$("$C" --known "$TMP/known" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok_ "a wrong call exits 2" || bad "usage: rc=$rc"
printf 'Vitals\t2\t%s\t1\t0\tclinical_forms/%s.json\thub\t2000-01-01T00:00:00Z\n' "$U2" "$U2" | manifest
cp "$T/clinical_forms/$U2.json" "$TMP/u2.keep"; echo '{"controls":5}' > "$T/clinical_forms/$U2.json"
out="$(run)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'could not check the forms' && ok_ "a form file of an unexpected shape cannot be checked: exit 2, never 1" || bad "odd shape: rc=$rc out=$out"
printf '{"controls":[{"concept":{"uuid":"x y\\u001b[2J"}}]}' > "$T/clinical_forms/$U2.json"
out="$(run)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'refusing odd uuid' && ! printf '%s' "$out" | grep -q "$(printf '\033')" && ok_ "an odd concept uuid is refused (exit 2), escaped" || bad "odd uuid: rc=$rc out=$out"
cp "$TMP/u2.keep" "$T/clinical_forms/$U2.json"
: > "$T/MANIFEST.tsv"
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '0 published forms' && ok_ "an empty manifest has nothing to check: exit 0" || bad "empty manifest: rc=$rc out=$out"
[ ! -e "$TMP/ran" ] && ok_ "nothing in the forms tree is executed" || bad "the tree's tool ran"
exit "$fails"
