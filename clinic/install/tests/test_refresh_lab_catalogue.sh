#!/usr/bin/env bash
# clinic/scripts/refresh-lab-catalogue.sh, against a fake container runtime and
# a fake curl: the order (feed readers stopped and proven down before OpenMRS
# restarts; OpenELIS, then odoo-connect, started only after OpenMRS's search
# finds the concept), each refusal and each wait that runs out, with a FAIL line
# naming what it saw, and the readers left stopped when OpenMRS is not ready.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
S="${RP}/clinic/scripts/refresh-lab-catalogue.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ -f "$S" ] || { bad "no $S"; exit 1; }
mkdir -p "$TMP/node" "$TMP/bin" "$TMP/state"
printf 'COMPOSE_PROJECT_NAME=bahmni-t\nOPENMRS_ATOMFEED_USER=feed\nOPENMRS_ATOMFEED_PASSWORD=pw\n' > "$TMP/node/.env"
cat > "$TMP/bin/fakect" <<'SH'
#!/usr/bin/env bash
# a container runtime: running state in files, every call logged
st="$FAKE_DIR/state"; log(){ printf '%s\n' "$*" >> "$FAKE_DIR/log"; }
case "$1" in
  exec) cat > /dev/null; log "exec $3"; cat "$FAKE_DIR/count" ;;
  stop) log "stop $2"; [ -f "$FAKE_DIR/sticky-$2" ] || echo false > "$st/$2" ;;
  start) log "start $2"; echo true > "$st/$2" ;;
  restart) log "restart $2"; echo true > "$st/$2" ;;
  inspect)
    f="$3"; c="$4"; r="$(cat "$st/$c" 2>/dev/null || echo true)"; n="$(cat "$FAKE_DIR/restarts-$c" 2>/dev/null || echo 0)"
    [ -f "$FAKE_DIR/restarts-after-start-$c" ] && grep -q "^start $c\$" "$FAKE_DIR/log" && n=$((n+1))
    case "$f" in
      '{{.State.Running}}') echo "$r" ;;
      '{{.RestartCount}}') echo "$n" ;;
      '{{.State.Running}} {{.RestartCount}}') echo "$r $n" ;;
    esac ;;
esac
SH
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
# answers by URL: the session from a script of codes, the search from a file
url=""; for a in "$@"; do case "$a" in http*) url="$a" ;; esac; done
w=0; for a in "$@"; do [ "$a" = '-w' ] && w=1; done
case "$url" in
  */openmrs/ws/rest/v1/session)
    n="$(cat "$FAKE_DIR/session-n" 2>/dev/null || echo 0)"; echo $((n+1)) > "$FAKE_DIR/session-n"
    code="$(sed -n "$((n+1))p" "$FAKE_DIR/session-codes")"; [ -n "$code" ] || code="$(tail -1 "$FAKE_DIR/session-codes")"
    printf '%s' "$code" ;;
  */openmrs/ws/rest/v1/concept\?q=*)
    printf '%s' "$url" > "$FAKE_DIR/last-search"; cat "$FAKE_DIR/search"; printf '\n200' ;;
  */openelis/LoginPage.do) printf '%s' "$(cat "$FAKE_DIR/elis-code")" ;;
  *) printf '000' ;;
esac
SH
chmod +x "$TMP/bin/fakect" "$TMP/bin/curl"
reset(){ rm -f "$TMP"/log "$TMP"/session-n "$TMP"/sticky-* "$TMP"/restarts-* "$TMP/state"/*
  echo 1 > "$TMP/count"; printf '200\n' > "$TMP/session-codes"; echo 200 > "$TMP/elis-code"
  printf '{"results":[{"uuid":"u1","display":"ZZ Haemoglobin A1c"}]}' > "$TMP/search"; }
run(){ out="$(env PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" CLINIC_DIR="$TMP/node" REPO_DIR="$RP" CT="$TMP/bin/fakect" \
  REFRESH_POLL_S=0 ODOO_CONNECT_SETTLE_S=0 OPENMRS_RESTART_TIMEOUT_S="${ORT:-10}" CONCEPT_SEARCH_TIMEOUT_S="${CST:-2}" OPENELIS_START_TIMEOUT_S="${OST:-2}" \
  bash "$S" "$@" 2>&1)"; rc=$?; }
calls(){ grep -E '^(stop|start|restart) ' "$TMP/log" 2>/dev/null | tr '\n' ',' ; }

reset; run
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'name the concept' && [ ! -s "$TMP/log" ] && ok_ "without a concept name it refuses, touching nothing" || bad "no name: rc=$rc $out"
reset; echo 0 > "$TMP/count"; run "ZZ Haemoglobin A1c"
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "no concept named 'ZZ Haemoglobin A1c' in this clinic's database" && [ -z "$(calls)" ] \
  && ok_ "a concept that has not come down yet: refused before anything is stopped or restarted" || bad "concept missing: rc=$rc $out [$(calls)]"
reset; run "ZZ Haemoglobin A1c"
[ "$rc" = 0 ] && [ "$(calls)" = "stop bahmni-t-odoo-connect-1,stop bahmni-t-openelis-1,restart bahmni-t-openmrs-1,start bahmni-t-openelis-1,start bahmni-t-odoo-connect-1," ] \
  && ok_ "in order: odoo-connect and OpenELIS stopped, OpenMRS restarted, then OpenELIS and odoo-connect started" || bad "happy path: rc=$rc [$(calls)] $out"
printf '%s' "$out" | grep -q "OpenMRS's search finds 'ZZ Haemoglobin A1c'" && grep -q 'q=ZZ%20Haemoglobin%20A1c' "$TMP/last-search" \
  && ok_ "the concept is found by a search by name (URL-encoded), not by a database read" || bad "search: $(cat "$TMP/last-search" 2>/dev/null) $out"
reset; touch "$TMP/sticky-bahmni-t-openelis-1"; run "ZZ Haemoglobin A1c"
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'OpenELIS (bahmni-t-openelis-1) will not stay stopped' && ! grep -q '^restart' "$TMP/log" \
  && ok_ "an OpenELIS that will not stay stopped: OpenMRS is not restarted" || bad "sticky OpenELIS: rc=$rc [$(calls)] $out"
reset; printf '302\n' > "$TMP/session-codes"; ORT=5 run "ZZ Haemoglobin A1c"
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'OpenMRS did not answer within 0 min (last HTTP code: 302, its startup page: still starting)' && ! grep -q '^start' "$TMP/log" \
  && printf '%s' "$out" | grep -q -- '--start-readers' && ok_ "OpenMRS still starting when its budget runs out: FAIL names the 302, the readers stay stopped, the message names --start-readers" || bad "302: rc=$rc [$(calls)] $out"
reset; printf '302\n302\n200\n' > "$TMP/session-codes"; ORT=20 run "ZZ Haemoglobin A1c"
[ "$rc" = 0 ] && ok_ "OpenMRS answering 302 and then 200 within its budget is waited for" || bad "302 then 200: rc=$rc $out"
reset; printf '{"results":[{"uuid":"u9","display":"Haemoglobin"}]}' > "$TMP/search"; run "ZZ Haemoglobin A1c"
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "has not found 'ZZ Haemoglobin A1c'" && printf '%s' "$out" | grep -q 'HTTP 200, 1 result(s), 0 naming it' && ! grep -q '^start' "$TMP/log" \
  && ok_ "a search that never names the concept: FAIL says what the search returned, the readers stay stopped" || bad "search miss: rc=$rc [$(calls)] $out"
reset; echo 503 > "$TMP/elis-code"; run "ZZ Haemoglobin A1c"
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'OpenELIS did not show its login page within 0 min (last HTTP code: 503' && ! grep -q '^start bahmni-t-odoo-connect-1' "$TMP/log" \
  && ok_ "an OpenELIS that does not come up: FAIL names its last answer, odoo-connect is not started" || bad "elis down: rc=$rc [$(calls)] $out"
reset; touch "$TMP/restarts-after-start-bahmni-t-odoo-connect-1"; run "ZZ Haemoglobin A1c"
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "odoo-connect is not running cleanly" && ok_ "an odoo-connect that restarts after its start is a FAIL" || bad "odoo-connect restart: rc=$rc $out"
reset; run --start-readers
[ "$rc" = 0 ] && [ "$(calls)" = "start bahmni-t-openelis-1,start bahmni-t-odoo-connect-1," ] && ok_ "--start-readers starts OpenELIS, then odoo-connect, and nothing else" || bad "start-readers: rc=$rc [$(calls)] $out"
reset; echo false > "$TMP/state/bahmni-t-openmrs-1"; run --start-readers
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'OpenMRS (bahmni-t-openmrs-1) is not running' && [ -z "$(calls)" ] && ok_ "--start-readers refuses while OpenMRS is not running" || bad "start-readers, OpenMRS down: rc=$rc $out"
exit "$fails"
