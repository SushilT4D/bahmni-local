#!/usr/bin/env bash
# The clinic proxy refuses OpenELIS's administration actions that write the lab
# test catalogue (which comes down from the hub), whatever the method, and
# passes the pages that show the catalogue and every lab-flow action. First the
# proxy's own pattern is run (perl, case-insensitive, as nginx's ~*) over the
# action names the pinned OpenELIS image declares; then, when a container
# runtime and the proxy's nginx base image are already on this machine, real
# requests go through the configuration to a stub upstream. PROXY_CONF tests
# another copy of the configuration.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
C="${PROXY_CONF:-${RP}/clinic/proxy/bahmni-nginx.openelis.conf}"
MSG='The lab test catalogue is maintained at the hub; this change is refused at this clinic'
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; CNAME=""
trap '[ -n "$CNAME" ] && docker rm -f "$CNAME" >/dev/null 2>&1; rm -rf "$TMP"' EXIT
command -v perl >/dev/null 2>&1 || { bad "perl is needed to run the proxy's path pattern"; exit 1; }

# --- the configuration's shape -------------------------------------------------------
blk(){ awk -v s="$1" 'index($0, s){p=1} p{print} p&&/^[[:space:]]*}/{exit}' "$C"; }
pat="$(blk 'map $uri $catalogue_write_refused {' | perl -ne 'print "$1\n" if /^\s*"~\*(.*)"\s+1;\s*$/')"
[ "$(printf '%s\n' "$pat" | grep -c .)" = 1 ] && blk 'map $uri $catalogue_write_refused {' | grep -qE '^[[:space:]]*default[[:space:]]+0;' \
  && ok_ "one case-insensitive pattern in map \$uri \$catalogue_write_refused, default 0 (no method in the key: every method is refused)" || bad "no map \$uri \$catalogue_write_refused with one ~* pattern"
main="$(awk '/listen 443 ssl default_server;/{p=1} p&&/server_name ~\^odoo/{exit} p{print}' "$C")"
first_if="$(printf '%s\n' "$main" | grep -nF 'if ($catalogue_write_refused) { rewrite ^ /catalogue-write-refused last; }' | head -1 | cut -d: -f1)"
first_loc="$(printf '%s\n' "$main" | grep -nE '^[[:space:]]*location ' | head -1 | cut -d: -f1)"
[ -n "$first_if" ] && [ -n "$first_loc" ] && [ "$first_if" -lt "$first_loc" ] && ok_ "the main vhost checks it before any location is chosen" || bad "no server-level catalogue refusal ahead of the first location"
r="$(blk 'location = /catalogue-write-refused {')"
printf '%s\n' "$r" | grep -qE '^[[:space:]]*internal;' && printf '%s\n' "$r" | grep -qF "return 403 \"${MSG}" && printf '%s\n' "$r" | grep -qE 'access_log [^ ]+ catalogue_write_refused;' \
  && ok_ "a refusal answers 403 in plain text, says where the catalogue is made, and is logged" || bad "the refusal location: $r"
grep -qE '^[[:space:]]*log_format catalogue_write_refused .*\$request.*\$status' "$C" && ok_ "a refusal has its own access-log line format" || bad "no log_format catalogue_write_refused"

# --- the pattern, over the image's action names --------------------------------------------
# catalogue writers: every Update/UpdateNextPrevious/Delete action of a catalogue
# entity in the pinned OpenELIS image's struts configuration
for e in Test TestSection Panel PanelItem TypeOfSample TestResult TestAnalyte TestReflex TestTrailer Analyte Dictionary DictionaryCategory Label Method Scriptlet UnitOfMeasure TypeOfTestResult ResultLimits Organization; do
  printf '/openelis/Update%s.do\n/openelis/UpdateNextPrevious%s.do\n/openelis/Delete%s.do\n' "$e" "$e" "$e"
done > "$TMP/refuse"
cat >> "$TMP/refuse" <<'EOF'
/openelis/UpdateTypeOfSampleTest.do
/openelis/DeleteTypeOfSampleTest.do
/openelis/UpdateTypeOfSamplePanel.do
/openelis/DeleteTypeOfSamplePanel.do
/openelis/UpdateTestAnalyteTestResult.do
/openelis/DeleteTestAnalyteTestResult.do
/openelis/updatetest.do
/openelis/UpdateTest.do;jsessionid=0A1B2C
EOF
# the pages that show the catalogue, and lab-flow actions, some named much alike
cat > "$TMP/allow" <<'EOF'
/openelis/Test.do
/openelis/TestMenu.do
/openelis/Panel.do
/openelis/PanelMenu.do
/openelis/TypeOfSampleTestMenu.do
/openelis/ResultLimitsMenu.do
/openelis/UpdateTestManagement.do
/openelis/UpdateTestManagementNewborn.do
/openelis/UpdateSampleDemographicsAndTestManagement.do
/openelis/UpdateStatusOfSample.do
/openelis/UpdateTypeOfTestStatus.do
/openelis/UpdateSiteInformation.do
/openelis/UpdateMessageOrganization.do
/openelis/ResultsLogbookUpdate.do
/openelis/ResultValidationSave.do
/openelis/SamplePatientEntrySave.do
/openelis/LoginPage.do
/openelis/ws/rest/accession/1234
/openelis/feed/recent
/openelis/UpdateTest.dox
/openmrs/ws/rest/v1/patient
EOF
mval(){ perl -e 'my $p = shift; while (<STDIN>) { chomp; print(($_ =~ /$p/i) ? "1 $_\n" : "0 $_\n") }' "$pat"; }
mval < "$TMP/refuse" > "$TMP/r.out"; mval < "$TMP/allow" > "$TMP/a.out"
n="$(grep -c '^1 ' "$TMP/r.out")"; t="$(grep -c . "$TMP/refuse")"
[ "$n" = "$t" ] && ok_ "all ${t} catalogue-writing actions match" || { bad "$((t-n)) of ${t} catalogue writers do not match:"; grep '^0 ' "$TMP/r.out" | sed 's/^0 /         /'; }
n="$(grep -c '^0 ' "$TMP/a.out")"; t="$(grep -c . "$TMP/allow")"
[ "$n" = "$t" ] && ok_ "all ${t} catalogue pages, lab-flow actions and look-alikes pass" || { bad "$((t-n)) of ${t} paths that must pass would be refused:"; grep '^1 ' "$TMP/a.out" | sed 's/^1 /         /'; }

# --- the real nginx, when it can be started without a download --------------------------------
IMG="$(awk '/^FROM /{print $2; exit}' "${RP}/clinic/proxy/Dockerfile")"
if [ "${TEST_NO_CONTAINERS:-0}" = 1 ] || ! command -v docker >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 \
   || ! command -v openssl >/dev/null 2>&1 || ! docker image inspect "$IMG" >/dev/null 2>&1; then
  ok_ "no container runtime, curl, openssl or local ${IMG:-proxy base image}: the live nginx checks are skipped"
  exit "$fails"
fi
W="${TMP}/w"; mkdir -p "$W/tls"
[ "$(tail -n 1 "$C")" = "}" ] || { bad "the configuration does not end with the http block's closing brace"; exit "$fails"; }
sed -e 's/server openmrs:8080 resolve;/server 127.0.0.1:8081;/' -e 's/server openelis:8052 resolve;/server 127.0.0.1:8081;/' \
    -e 's/server odoo:8069 resolve;/server 127.0.0.1:8081;/' "$C" | sed '$d' > "$W/nginx.conf"
cat >> "$W/nginx.conf" <<'EOF'
    server {
        listen 127.0.0.1:8081;
        location / { default_type text/plain; return 200 "upstream $request_method $request_uri\n"; }
    }
}
EOF
cp "${RP}/clinic/proxy/05-clinic-resolver.sh" "$W/05-clinic-resolver.sh"; chmod 755 "$W/05-clinic-resolver.sh"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=clinic.test -keyout "$W/tls/key.pem" -out "$W/tls/cert.pem" >/dev/null 2>&1
chmod 644 "$W/tls/key.pem"
set -- -v "$W/nginx.conf:/etc/nginx/nginx.conf:ro" -v "$W/05-clinic-resolver.sh:/docker-entrypoint.d/05-clinic-resolver.sh:ro" \
  -v "$W/tls:/etc/tls:ro" --add-host systemdate:127.0.0.1 --add-host patient-documents:127.0.0.1 --add-host bahmni-lab:127.0.0.1
out="$(docker run --rm "$@" "$IMG" nginx -t 2>&1)"
printf '%s\n' "$out" | grep -q 'test is successful' && ok_ "nginx -t in ${IMG}: the configuration parses" || { bad "nginx -t in ${IMG}: $(printf '%s\n' "$out" | grep -E 'emerg|error' | head -3)"; exit "$fails"; }
CNAME="proxy-cw-test-$$"
docker run -d --name "$CNAME" "$@" -p 127.0.0.1::443 "$IMG" >/dev/null 2>&1 || { bad "could not start ${IMG}"; exit "$fails"; }
PORT="$(docker port "$CNAME" 443/tcp 2>/dev/null | head -1 | sed 's/.*://')"
req(){ curl -sk --path-as-is -o "$TMP/body" -w '%{http_code}' -X "$1" ${3:+--data "$3"} "https://127.0.0.1:${PORT}$2"; }
up=0; for i in $(seq 1 30); do [ -n "$PORT" ] && [ "$(req GET /log 2>/dev/null)" = 200 ] && { up=1; break; }; sleep 1; done
[ "$up" = 1 ] || { bad "the proxy did not answer within 30 s: $(docker logs "$CNAME" 2>&1 | tail -3)"; exit "$fails"; }
nr=0; t=0; failp=""
while read -r p; do
  t=$((t+1))
  for m in GET POST; do s="$(req "$m" "$p" "$( [ "$m" = POST ] && echo x=1)")"; { [ "$s" = 403 ] && grep -qF "$MSG" "$TMP/body"; } || failp="${failp} ${m}:${p}=${s}"; done
  [ -z "$failp" ] && nr=$((nr+1))
done < "$TMP/refuse"
[ "$nr" = "$t" ] && ok_ "live: GET and POST are both refused with 403 and the message on all ${t} catalogue writers" || { bad "live: refused on ${nr} of ${t}"; printf '         %s\n' $failp | head -10; }
np=0; t=0; failp=""
while read -r p; do
  t=$((t+1)); s="$(req POST "$p" x=1)"
  if [ "$s" = 200 ] && grep -qF 'upstream POST ' "$TMP/body"; then np=$((np+1)); else failp="${failp} ${p}=${s}"; fi
done < "$TMP/allow"
[ "$np" = "$t" ] && ok_ "live: a POST to each of the ${t} paths that must pass reaches its application" || { bad "live: passed ${np} of ${t}"; printf '         %s\n' $failp | head -10; }
exit "$fails"
