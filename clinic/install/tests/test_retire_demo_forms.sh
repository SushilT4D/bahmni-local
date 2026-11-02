#!/usr/bin/env bash
# The config package's stock demo forms are retired, never deleted, on a clinic
# whose OpenMRS holds them (one that keeps its own database across an upgrade
# from a stack that loaded every Initializer domain):
#   - the list (clinic/install/demo-forms.conf) names exactly the package's
#     nineteen demo forms, each once, and never the hub's "Referral letter";
#   - a line that is not one uuid is refused, so only uuids reach the SQL, and
#     a list with no uuid is refused, naming the file;
#   - the SQL updates only by uuid IN (the list), only rows not retired yet,
#     deletes nothing, and reads back how many listed rows are still not
#     retired, which must be 0;
#   - forms_retire_demo prints how many it retired, retires none on a second
#     run or on a node that never loaded them, and stops when one stays unretired.
# A fake runtime stands in for the clinic's MySQL: it records the SQL it is
# given and answers with the counts the test asks for.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
L="${HERE}/../demo-forms.conf"; F="${HERE}/../forms.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/c"
REFERRAL=53a049e2-73e1-47bf-a28d-848b789bb476
U1=11111111-1111-1111-1111-111111111111

# --- the list ---------------------------------------------------------------------------
[ -f "$L" ] || { bad "no clinic/install/demo-forms.conf"; exit 1; }
lib(){ ( CLINIC_DIR="$TMP/c"; . "${HERE}/../lib.sh"; . "$F"; "$@" ); }
uuids="$(lib forms_demo_uuids)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "the list reads" || bad "the list does not read: rc=$rc $uuids"
[ "$(printf '%s\n' "$uuids" | grep -c .)" = 19 ] && ok_ "the list names 19 forms" || bad "the list names $(printf '%s\n' "$uuids" | grep -c .) forms, not 19"
[ "$(printf '%s\n' "$uuids" | sort -u | grep -c .)" = 19 ] && ok_ "no uuid is listed twice" || bad "a uuid is listed twice"
printf '%s\n' "$uuids" | grep -qx "$REFERRAL" && bad "the list names the hub's Referral letter ($REFERRAL)" || ok_ "the list never names the hub's Referral letter"
grep -q "$REFERRAL" "$L" && bad "demo-forms.conf mentions the Referral letter's uuid, even in a comment" || ok_ "demo-forms.conf does not carry the Referral letter's uuid anywhere"
n="$(awk '{ sub(/#.*/, "") } NF' "$L" | grep -c .)"; c="$(grep -E '^[0-9a-f-]{36}  # [^ ].* \([^)]+\.json\)$' "$L" | grep -c .)"
[ "$n" = 19 ] && [ "$c" = 19 ] && ok_ "every listed uuid carries a comment naming its form and its file" || bad "$c of $n listed uuids name their form and file"

printf '%s  # a form\nnot-a-uuid\n' "$U1" > "$TMP/bad.conf"
out="$(lib forms_demo_uuids "$TMP/bad.conf")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'line 2 is not one form uuid: not-a-uuid' && ! printf '%s' "$out" | grep -q "$U1" \
  && ok_ "a line that is not a uuid is refused, named, and no uuid is printed" || bad "bad line: rc=$rc out=$out"
printf "%s'); delete from form; --\n" "11111111-1111-1111-1111-11111111111" > "$TMP/inj.conf"
out="$(lib forms_demo_uuids "$TMP/inj.conf")"; rc=$?
[ "$rc" -ne 0 ] && ok_ "a line carrying SQL is refused" || bad "a line carrying SQL passed: $out"
printf '%s\n' "$(printf '%s' "$U1" | tr 1 A)" > "$TMP/upper.conf"
out="$(lib forms_demo_uuids "$TMP/upper.conf")"; rc=$?
[ "$rc" -ne 0 ] && ok_ "an uppercase uuid is refused (form uuids are lowercase)" || bad "uppercase uuid passed: $out"
out="$(lib forms_demo_uuids "$TMP/none.conf")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'no list of the stock demo forms at' && ok_ "a missing list is refused" || bad "missing list: rc=$rc out=$out"
printf '# only a comment\n\n   # and another\n' > "$TMP/empty.conf"
out="$(lib forms_demo_uuids "$TMP/empty.conf")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qF "$TMP/empty.conf lists no form uuid" && ok_ "a list holding only comments is refused, naming the file" || bad "comments-only list: rc=$rc out=$out"

# --- the SQL ------------------------------------------------------------------------------
# shellcheck disable=SC2086
sql="$(lib forms_retire_demo_sql $uuids)"
printf '%s' "$sql" | grep -qiw delete && bad "the SQL deletes: $sql" || ok_ "the SQL has no DELETE"
grep -vhE '^[[:space:]]*#' "$F" | grep -qiE '(^|[^a-z_])delete[[:space:]]+from' && bad "forms.sh carries a DELETE FROM" || ok_ "forms.sh carries no DELETE FROM"
[ "$(printf '%s' "$sql" | grep -oiw update | grep -c .)" = 1 ] && ok_ "the SQL is one UPDATE" || bad "the SQL is not one UPDATE: $sql"
upd="$(printf '%s' "$sql" | sed -n 's/^\(update form set [^;]*\);.*/\1/p')"
in="$(printf '%s\n' "$uuids" | awk '{ printf "%s'"'"'%s'"'"'", (NR > 1 ? ", " : ""), $0 }')"
[ "$(printf '%s' "$upd" | sed -n 's/.* where \(.*\)$/\1/p')" = "retired = 0 and uuid in (${in})" ] \
  && ok_ "the UPDATE changes only unretired rows whose uuid is IN the list, every listed uuid and no other" || bad "the UPDATE's where clause: $upd"
printf '%s' "$upd" | grep -q "^update form set retired = 1, retired_by = 1, date_retired = now(), retire_reason = 'stock demo form from the config package, not used by this clinic' where " \
  && ok_ "it sets retired, retired_by, date_retired and a reason in plain words" || bad "the UPDATE's set clause: $upd"
printf '%s' "$upd" | grep -qiE 'published|name *=|form_id' && bad "the UPDATE touches more than the retirement columns, or picks rows by something other than uuid" || ok_ "the UPDATE picks rows by uuid alone"
printf '%s' "$sql" | grep -qF 'select row_count(); select count(*) from form where uuid in (' && ok_ "it reports the rows it retired and the listed forms this node holds" || bad "the SQL does not report its counts: $sql"
[ "$(printf '%s' "$sql" | sed -n 's/.*; select count(\*) from form where \(retired = 0 and uuid in ([^)]*)\);$/\1/p')" = "retired = 0 and uuid in (${in})" ] \
  && ok_ "it reads back how many listed forms are still unretired after the update" || bad "the SQL does not read back the unretired listed forms: $sql"

# --- forms_retire_demo through a fake runtime ---------------------------------------------
cat > "$TMP/fakect" <<'SH'
#!/usr/bin/env bash
[ "$1" = exec ] || exit 0
cat >> "$SQL_LOG"
printf '%s\n' $ANSWER
exit "${ANSWER_RC:-0}"
SH
chmod +x "$TMP/fakect"
retire(){ # ANSWER (three counts, space-separated) [ANSWER_RC [VAR=value...]]
  local a="$1" arc="${2:-0}"; shift; [ "$#" -eq 0 ] || shift
  env -i PATH="$PATH" HOME="$TMP" CT="$TMP/fakect" SQL_LOG="$TMP/sql.log" ANSWER="$a" ANSWER_RC="$arc" COMPOSE_PROJECT_NAME=bahmni-t "$@" \
    bash -c "set -euo pipefail; CLINIC_DIR='$TMP/c'; . '${HERE}/../lib.sh'; . '$F'; forms_retire_demo" 2>&1; }
: > "$TMP/sql.log"
out="$(retire '19 19 0')"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'ok   stock demo forms: 19 retired now; this node holds 19 of the 19 in demo-forms.conf, all read back retired, none deleted' \
  && ok_ "a node holding the demo forms unretired: says how many it retired" || bad "retire 19: rc=$rc out=$out"
[ "$(cat "$TMP/sql.log")" = "$sql" ] && ok_ "the SQL the runtime receives is exactly the statement above" || bad "runtime got: $(cat "$TMP/sql.log")"
out="$(retire '0 19 0')"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'stock demo forms: 0 retired now; this node holds 19 of the 19' && ok_ "a second run retires none (idempotent)" || bad "second run: rc=$rc out=$out"
out="$(retire '0 0 0')"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'stock demo forms: 0 retired now; this node holds 0 of the 19' && ok_ "a node that never loaded them: 0 retired" || bad "fresh node: rc=$rc out=$out"
out="$(retire '17 19 2')"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qF 'FAIL retiring the stock demo forms: 2 of the 19 this node holds still read back not retired after the update (17 retired now)' \
  && ok_ "listed forms still unretired after the update stop the task, counted" || bad "left unretired: rc=$rc out=$out"
out="$(retire 'ERROR 1' 1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'FAIL could not retire the stock demo forms' && ok_ "a database error stops the task, named" || bad "db error: rc=$rc out=$out"
out="$(retire 'oops')"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "FAIL retiring the stock demo forms: openmrs answered 'oops'" && ok_ "an answer that is not three counts stops the task" || bad "odd answer: rc=$rc out=$out"
out="$(retire '19 19')"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "FAIL retiring the stock demo forms: openmrs answered '19 19', not three counts" && ok_ "an answer missing the read-back count stops the task" || bad "two counts: rc=$rc out=$out"
: > "$TMP/sql.log"; out="$(retire '0 0 0' 0 FORMS_DEMO_LIST="$TMP/empty.conf")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qF "FAIL $TMP/empty.conf lists no form uuid" && [ ! -s "$TMP/sql.log" ] \
  && ok_ "a list holding only comments stops the retirement with a FAIL line, and no SQL runs" || bad "comments-only list: rc=$rc out=$out sql=$(cat "$TMP/sql.log")"

exit "$fails"
