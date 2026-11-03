#!/usr/bin/env bash
# The clinic proxy refuses writes to the master data the hub syncs down: any
# method but GET, HEAD and OPTIONS on a path that writes those tables gets 403
# and a message saying masters are made at the hub, while reads and every
# patient-flow write pass. First the proxy's own path patterns are run (with
# nginx's first-match map semantics) over a list of master write paths, a list
# of patient-flow paths, and every DOWN table of hub/table-verdicts.conf; then,
# when a container runtime and the proxy's nginx image are already on this
# machine, the configuration is parsed by that nginx and served against a stub
# upstream, and real requests are sent. PROXY_CONF tests another copy of the
# configuration.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
C="${PROXY_CONF:-${RP}/clinic/proxy/bahmni-nginx.openelis.conf}"
V="${RP}/hub/table-verdicts.conf"
MSG='Master data is maintained at the hub; this change is refused at this clinic'
U=7c4e5b2a-0d6f-4b5e-9d1a-3f2e1c0b9a87
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; CNAME=""
trap '[ -n "$CNAME" ] && docker rm -f "$CNAME" >/dev/null 2>&1; rm -rf "$TMP"' EXIT
command -v perl >/dev/null 2>&1 || { bad "perl is needed to run the proxy's path patterns"; exit 1; }

# --- the configuration's shape -------------------------------------------------------
blk(){ awk -v s="$1" 'index($0, s){p=1} p{print} p&&/^[[:space:]]*}/{exit}' "$C"; }
m="$(blk 'map $request_method $master_write_method {')"
printf '%s\n' "$m" | grep -qE '^[[:space:]]*GET[[:space:]]+0;' && printf '%s\n' "$m" | grep -qE '^[[:space:]]*HEAD[[:space:]]+0;' \
  && printf '%s\n' "$m" | grep -qE '^[[:space:]]*OPTIONS[[:space:]]+0;' && printf '%s\n' "$m" | grep -qE '^[[:space:]]*default[[:space:]]+1;' \
  && [ "$(printf '%s\n' "$m" | grep -cE '^[[:space:]]*[A-Za-z]+[[:space:]]+[01];')" = 4 ] \
  && ok_ "GET, HEAD and OPTIONS are reads; every other method is a write" || bad "no map \$request_method \$master_write_method with GET/HEAD/OPTIONS 0, default 1"
m="$(blk 'map "$master_write_method$master_path" $master_write_refused {')"
printf '%s\n' "$m" | grep -qE '^[[:space:]]*11[[:space:]]+1;' && printf '%s\n' "$m" | grep -qE '^[[:space:]]*default[[:space:]]+0;' \
  && ok_ "a refusal is a write method on a master path, and nothing else" || bad "no map to \$master_write_refused from a write method on a master path"
grep -qE '^[[:space:]]*log_format master_write_refused .*\$request.*\$status' "$C" && ok_ "a refusal has its own access-log line format" || bad "no log_format master_write_refused"
# the check sits at server level in the main vhost, ahead of every location, so
# the exact, prefix and regex routes all refuse alike
main="$(awk '/listen 443 ssl default_server;/{p=1} p&&/server_name ~\^odoo/{exit} p{print}' "$C")"
first_if="$(printf '%s\n' "$main" | grep -nF 'if ($master_write_refused) { rewrite ^ /master-write-refused last; }' | head -1 | cut -d: -f1)"
first_loc="$(printf '%s\n' "$main" | grep -nE '^[[:space:]]*location ' | head -1 | cut -d: -f1)"
[ -n "$first_if" ] && [ -n "$first_loc" ] && [ "$first_if" -lt "$first_loc" ] \
  && ok_ "the main vhost checks every request before any location is chosen" || bad "no server-level refusal ahead of the first location in the main vhost"
r="$(blk 'location = /master-write-refused {')"
printf '%s\n' "$r" | grep -qE '^[[:space:]]*internal;' && printf '%s\n' "$r" | grep -qF "return 403 \"${MSG}" \
  && printf '%s\n' "$r" | grep -qF 'default_type text/plain;' && printf '%s\n' "$r" | grep -qE 'access_log [^ ]+ master_write_refused;' \
  && ok_ "a refusal answers 403 in plain text, says where masters are made, and is logged" || bad "the refusal location: $r"
grep -qF 'location ~ ^/openmrs/ws/rest/v1/form/[0-9a-fA-F-]+$ {' "$C" && ok_ "the form definition regex route is still there" || bad "the form definition regex route is gone"
for l in 'location = /openmrs/ws/rest/v1/bahmnicore/distro/patient/search {' 'location ^~ /openmrs/ws/rest/v1/bahmnicore/distro/bahmniencounter {' \
         'location = /openmrs/ws/rest/v1/bahmniie/form/translations {' 'location /openmrs {'; do
  grep -qF "$l" "$C" && ok_ "kept: ${l%% \{}" || bad "gone: ${l%% \{}"
done
# the odoo vhost is not OpenMRS and is not touched
awk '/server_name ~\^odoo/{p=1} p' "$C" | grep -q 'master_write' && bad "the odoo vhost refers to the master-write check" || ok_ "the odoo vhost is unchanged"

# --- the path patterns, run over master and patient-flow paths ---------------------------
perl -ne 'if (/^\s*map \$uri \$master_path \{/) { $in = 1; next } if ($in && /^\s*\}/) { $in = 0 }
          if ($in && /^\s*"~\*(.*)"\s+([01]);\s*$/) { print "$1\t$2\n" }' "$C" > "$TMP/pats"
[ -s "$TMP/pats" ] && ok_ "$(wc -l < "$TMP/pats" | tr -d ' ') case-insensitive path patterns in map \$uri \$master_path" || bad "no map \$uri \$master_path with ~* patterns"
# nginx tries a map's regexes in order and takes the first that matches
mval(){ perl -e 'open P, $ARGV[0] or die; my @p; while (<P>) { chomp; my ($r, $v) = split /\t/; push @p, [$r, $v] }
  while (<STDIN>) { chomp; my $o = 0; for my $e (@p) { if ($_ =~ /$e->[0]/i) { $o = $e->[1]; last } } print "$o\n" }' "$TMP/pats"; }

# master write paths: each must be refused
cat > "$TMP/refuse" <<EOF
/openmrs/ws/rest/v1/concept
/openmrs/ws/rest/v1/concept/$U
/openmrs/ws/rest/v1/concept/$U/name/$U
/openmrs/ws/rest/v1/concept/$U/description
/openmrs/ws/rest/v1/concept/$U/mapping
/openmrs/ws/rest/v1/concept/$U/attribute
/openmrs/ws/rest/v1/conceptclass
/openmrs/ws/rest/v1/conceptsource/$U
/openmrs/ws/rest/v1/conceptreferenceterm
/openmrs/ws/rest/v1/conceptreferencetermmap
/openmrs/ws/rest/v1/conceptattributetype
/openmrs/ws/rest/v1/conceptdatatype
/openmrs/ws/rest/v1/conceptmaptype
/openmrs/ws/rest/v1/drug
/openmrs/ws/rest/v1/drug/$U/ingredient
/openmrs/ws/rest/v1/drugreferencemap
/openmrs/ws/rest/v1/location
/openmrs/ws/rest/v1/location/$U/attribute
/openmrs/ws/rest/v1/locationtag
/openmrs/ws/rest/v1/locationattributetype
/openmrs/ws/rest/v1/program
/openmrs/ws/rest/v1/workflow/$U/state
/openmrs/ws/rest/v1/programattributetype
/openmrs/ws/rest/v1/visittype
/openmrs/ws/rest/v1/visitattributetype
/openmrs/ws/rest/v1/ordertype
/openmrs/ws/rest/v1/orderfrequency
/openmrs/ws/rest/v1/personattributetype
/openmrs/ws/rest/v1/relationshiptype
/openmrs/ws/rest/v1/providerattributetype
/openmrs/ws/rest/v1/encounterrole
/openmrs/ws/rest/v1/patientidentifiertype
/openmrs/ws/rest/v1/privilege
/openmrs/ws/rest/v1/role/$U
/openmrs/ws/rest/v1/form
/openmrs/ws/rest/v1/form/$U
/openmrs/ws/rest/v1/form/$U/resource
/openmrs/ws/rest/v1/metadatamapping/source
/openmrs/ws/rest/v1/metadatamapping/termmapping
/openmrs/ws/rest/v1/metadatamapping/metadataset/$U/members
/openmrs/ws/rest/v1/openconceptlab/import
/openmrs/ws/rest/v1/openconceptlab/subscription
/openmrs/ws/fhir2/R4/Location
/openmrs/ws/fhir2/R4/Medication/$U
/openmrs/ws/fhir2/R3/Location/$U
/openmrs/ms/fhir2Servlet/Location
/openmrs/ws/rest/v1/bahmniie/form/save
/openmrs/ws/rest/v1/bahmniie/form/publish
/openmrs/ws/rest/v1/bahmniie/form/saveTranslation
/openmrs/ws/rest/v1/bahmniie/form/name/saveTranslation
/openmrs/ws/rest/v1/bahmniie/form/saveFormPrivileges
/openmrs/ws/rest/v1/bahmniie/form/translations
/openmrs/ws/rest/v1/bahmnicore/admin/upload/concept
/openmrs/ws/rest/v1/bahmnicore/admin/upload/conceptset
/openmrs/ws/rest/v1/bahmnicore/admin/upload/drug
/openmrs/ws/rest/v1/bahmnicore/admin/upload/referenceterms
/openmrs/ws/rest/v1/bahmnicore/admin/upload/referenceterms/new
/openmrs/ws/rest/v1/reference-data/concept
/openmrs/ws/rest/v1/reference-data/conceptset
/openmrs/ws/rest/v1/reference-data/drug/$U
/openmrs/ws/rest/v1/bahmnicore/distro/locationOnBoarding
/openmrs/ws/rest/v1/bahmnicore/distro/location/$U
/openmrs/ws/rest/v1/bahmnicore/distro/addConceptAnswer/$U/answer/$U
/openmrs/dictionary/concept.form
/openmrs/admin/concepts/conceptClass.form
/openmrs/admin/concepts/conceptSource.form
/openmrs/admin/concepts/conceptDrug.form
/openmrs/admin/concepts/conceptReferenceTerm.form
/openmrs/admin/concepts/conceptAttributeType.form
/openmrs/admin/concepts/conceptMapType
/openmrs/admin/locations/location.form
/openmrs/admin/locations/locationTagEdit.form
/openmrs/admin/locations/locationAttributeType.form
/openmrs/admin/forms/formEdit.form
/openmrs/admin/forms/addFormResource
/openmrs/admin/programs/program.form
/openmrs/admin/programs/workflow.form
/openmrs/admin/visits/visitType.form
/openmrs/admin/visits/visitAttributeType.form
/openmrs/admin/person/relationshipType.form
/openmrs/admin/person/personAttributeType.form
/openmrs/admin/patients/patientIdentifierType.form
/openmrs/admin/users/role.form
/openmrs/admin/users/privilege.form
/openmrs/admin/encounters/encounterRole.form
/openmrs/admin/provider/providerAttributeType.form
/openmrs/module/metadatasharing/import/upload
/openmrs/module/metadatamapping/configure
/openmrs/ws/rest/v1/concept;jsessionid=0A1B2C
/openmrs/ws/rest/v1/concept.json
/openmrs/ws/rest/v1/Concept/$U
EOF
# patient-flow writes, identity, and names that only start like a master: each must pass
cat > "$TMP/allow" <<EOF
/openmrs/ws/rest/v1/patient
/openmrs/ws/rest/v1/patient/$U/identifier
/openmrs/ws/rest/v1/person/$U
/openmrs/ws/rest/v1/encounter
/openmrs/ws/rest/v1/obs
/openmrs/ws/rest/v1/visit
/openmrs/ws/rest/v1/order
/openmrs/ws/rest/v1/encountertype
/openmrs/ws/rest/v1/programenrollment
/openmrs/ws/rest/v1/bahmniprogramenrollment
/openmrs/ws/rest/v1/conceptsearch
/openmrs/ws/rest/v1/drugorder
/openmrs/ws/rest/v1/user/$U
/openmrs/ws/rest/v1/appointment
/openmrs/ws/rest/v1/bahmnicore/bahmniencounter
/openmrs/ws/rest/v1/bahmnicore/distro/bahmniencounter
/openmrs/ws/rest/v1/bahmnicore/distro/bahmniencounter/findWith
/openmrs/ws/rest/v1/bahmnicore/distro/patient/search
/openmrs/ws/rest/v1/bahmnicore/distro/patientRegistration
/openmrs/ws/rest/v1/bahmnicore/distro/appointment/saveAppointment
/openmrs/ws/rest/v1/bahmnicore/distro/visit/saveVisit
/openmrs/ws/rest/v1/bahmnicore/patientprofile
/openmrs/ws/rest/v1/bahmnicore/visitDocument
/openmrs/ws/rest/v1/bahmnicore/admin/upload/patient
/openmrs/ws/rest/v1/bahmnicore/admin/upload/encounter
/openmrs/ws/rest/v1/bahmnicore/admin/upload/program
/openmrs/ws/rest/v1/bahmniie/form/jsonToPdf
/openmrs/ws/fhir2/R4/Observation
/openmrs/ws/fhir2/R4/Patient
/openmrs/admin/visits/visit.form
/openmrs/admin/programs/patientProgram.form
/openmrs/admin/person/person.form
/openmrs/admin/encounters/encounterType.form
/openmrs/ws/rest/v1/session
EOF
paste -d' ' <(mval < "$TMP/refuse") "$TMP/refuse" > "$TMP/r.out"
paste -d' ' <(mval < "$TMP/allow") "$TMP/allow" > "$TMP/a.out"
n="$(grep -c '^1 ' "$TMP/r.out")"; t="$(grep -c . "$TMP/refuse")"
[ "$n" = "$t" ] && ok_ "all ${t} master write paths are master paths" || { bad "$((t-n)) of ${t} master write paths are not caught:"; grep '^0 ' "$TMP/r.out" | sed 's/^0 /         /'; }
n="$(grep -c '^0 ' "$TMP/a.out")"; t="$(grep -c . "$TMP/allow")"
[ "$n" = "$t" ] && ok_ "all ${t} patient-flow and look-alike paths pass" || { bad "$((t-n)) of ${t} patient-flow paths would be refused:"; grep '^1 ' "$TMP/a.out" | sed 's/^1 /         /'; }

# every DOWN table: a path that writes it, refused here, or the reason none is
cat > "$TMP/cover" <<EOF
role                        /openmrs/ws/rest/v1/role
role_privilege              /openmrs/ws/rest/v1/role/$U
role_role                   /openmrs/ws/rest/v1/role/$U
privilege                   /openmrs/ws/rest/v1/privilege
form                        /openmrs/ws/rest/v1/form
form_resource               /openmrs/ws/rest/v1/form/$U/resource
concept_class               /openmrs/ws/rest/v1/conceptclass
concept_reference_source    /openmrs/ws/rest/v1/conceptsource
concept                     /openmrs/ws/rest/v1/concept
concept_name                /openmrs/ws/rest/v1/concept/$U/name
concept_description         /openmrs/ws/rest/v1/concept/$U/description
concept_answer              /openmrs/ws/rest/v1/concept/$U
concept_set                 /openmrs/ws/rest/v1/concept/$U
concept_numeric             /openmrs/ws/rest/v1/concept/$U
concept_complex             /openmrs/ws/rest/v1/concept/$U
concept_reference_term      /openmrs/ws/rest/v1/conceptreferenceterm
concept_reference_term_map  /openmrs/ws/rest/v1/conceptreferencetermmap
concept_reference_map       /openmrs/ws/rest/v1/concept/$U/mapping
concept_attribute_type      /openmrs/ws/rest/v1/conceptattributetype
concept_attribute           /openmrs/ws/rest/v1/concept/$U/attribute
drug                        /openmrs/ws/rest/v1/drug
drug_ingredient             /openmrs/ws/rest/v1/drug/$U/ingredient
drug_reference_map          /openmrs/ws/rest/v1/drugreferencemap
location                    /openmrs/ws/rest/v1/location
location_tag                /openmrs/ws/rest/v1/locationtag
location_tag_map            /openmrs/ws/rest/v1/location/$U
location_attribute          /openmrs/ws/rest/v1/location/$U/attribute
location_attribute_type     /openmrs/ws/rest/v1/locationattributetype
program                     /openmrs/ws/rest/v1/program
program_workflow            /openmrs/ws/rest/v1/workflow
program_workflow_state      /openmrs/ws/rest/v1/workflow/$U/state
program_attribute_type      /openmrs/ws/rest/v1/programattributetype
visit_type                  /openmrs/ws/rest/v1/visittype
visit_attribute_type        /openmrs/ws/rest/v1/visitattributetype
order_type                  /openmrs/ws/rest/v1/ordertype
order_type_class_map        /openmrs/ws/rest/v1/ordertype/$U
person_attribute_type       /openmrs/ws/rest/v1/personattributetype
relationship_type           /openmrs/ws/rest/v1/relationshiptype
provider_attribute_type     /openmrs/ws/rest/v1/providerattributetype
order_frequency             /openmrs/ws/rest/v1/orderfrequency
encounter_role              /openmrs/ws/rest/v1/encounterrole
patient_identifier_type     /openmrs/ws/rest/v1/patientidentifiertype
location_encounter_type_map -  no REST resource in the pinned OpenMRS modules writes it
users                       -  identity: a user's own password and preferences are saved through the user resource at a clinic
user_property               -  identity: a user's preferences are saved at the clinic the user works at
user_role                   -  identity: written with the user
provider                    -  identity: a provider's attributes are saved at the clinic the provider works at
EOF
if [ -f "$V" ]; then
  awk '{ sub(/#.*/, "") } NF >= 2 && $2 == "DOWN" { print $1 }' "$V" > "$TMP/down"
  miss=""; nores=""; leak=""
  while read -r tbl; do
    line="$(awk -v t="$tbl" '$1 == t' "$TMP/cover")"
    if [ -z "$line" ]; then miss="$miss $tbl"; continue; fi
    p="$(printf '%s\n' "$line" | awk '{print $2}')"
    [ "$p" = "-" ] && { nores="$nores $tbl"; continue; }
    [ "$(printf '%s\n' "$p" | mval)" = 1 ] || leak="$leak $tbl"
  done < "$TMP/down"
  t="$(grep -c . "$TMP/down")"
  [ -z "$miss" ] && ok_ "every one of the ${t} DOWN tables has a write path listed here, or the reason it has none" || bad "DOWN tables with no write path listed here:${miss}"
  [ -z "$leak" ] && ok_ "every DOWN table's write path is refused" || bad "DOWN tables whose write path passes:${leak}"
  [ -n "$nores" ] && ok_ "not refused, with the reason listed above:${nores}"
else bad "no ${V}"; fi

# --- the real nginx, when it can be started without a download ----------------------------
IMG="$(awk '/^FROM /{print $2; exit}' "${RP}/clinic/proxy/Dockerfile")"
if [ "${TEST_NO_CONTAINERS:-0}" = 1 ] || ! command -v docker >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 \
   || ! command -v openssl >/dev/null 2>&1 || ! docker image inspect "$IMG" >/dev/null 2>&1; then
  ok_ "no container runtime, curl, openssl or local ${IMG:-proxy base image}: the live nginx checks are skipped"
  exit "$fails"
fi
W="${TMP}/w"; mkdir -p "$W/tls"
# the configuration as mounted, with the app upstreams pointed at a stub that
# echoes the method and URI it received
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
[ "$(grep -c 'server 127.0.0.1:8081;' "$W/nginx.conf")" = 3 ] || bad "the stand-in upstreams were not rendered"
cp "${RP}/clinic/proxy/05-clinic-resolver.sh" "$W/05-clinic-resolver.sh"; chmod 755 "$W/05-clinic-resolver.sh"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=clinic.test -keyout "$W/tls/key.pem" -out "$W/tls/cert.pem" >/dev/null 2>&1
chmod 644 "$W/tls/key.pem"
set -- -v "$W/nginx.conf:/etc/nginx/nginx.conf:ro" -v "$W/05-clinic-resolver.sh:/docker-entrypoint.d/05-clinic-resolver.sh:ro" \
  -v "$W/tls:/etc/tls:ro" --add-host systemdate:127.0.0.1 --add-host patient-documents:127.0.0.1 --add-host bahmni-lab:127.0.0.1
out="$(docker run --rm "$@" "$IMG" nginx -t 2>&1)"
printf '%s\n' "$out" | grep -q 'test is successful' && ok_ "nginx -t in ${IMG}: the configuration parses" || { bad "nginx -t in ${IMG}: $(printf '%s\n' "$out" | grep -E 'emerg|error' | head -3)"; exit "$fails"; }
CNAME="proxy-mw-test-$$"
docker run -d --name "$CNAME" "$@" -p 127.0.0.1::443 "$IMG" >/dev/null 2>&1 || { bad "could not start ${IMG}"; exit "$fails"; }
PORT="$(docker port "$CNAME" 443/tcp 2>/dev/null | head -1 | sed 's/.*://')"
req(){ # METHOD PATH -> prints the status; the body is left in $TMP/body
  case "$1" in
    POST|PUT) curl -sk --path-as-is -o "$TMP/body" -w '%{http_code}' -X "$1" -H 'Content-Type: application/json' --data '{}' "https://127.0.0.1:${PORT}$2" ;;
    HEAD)     curl -sk --path-as-is -o "$TMP/body" -w '%{http_code}' -I "https://127.0.0.1:${PORT}$2" ;;
    *)        curl -sk --path-as-is -o "$TMP/body" -w '%{http_code}' -X "$1" "https://127.0.0.1:${PORT}$2" ;;
  esac
}
up=0; for i in $(seq 1 30); do [ -n "$PORT" ] && [ "$(req GET /log 2>/dev/null)" = 200 ] && { up=1; break; }; sleep 1; done
[ "$up" = 1 ] || { bad "the proxy did not answer within 30 s: $(docker logs "$CNAME" 2>&1 | tail -3)"; exit "$fails"; }
bodyis(){ grep -qF "$1" "$TMP/body"; }
nr=0; ng=0; t=0; failp=""
while read -r p; do
  t=$((t+1))
  s="$(req POST "$p")"; { [ "$s" = 403 ] && bodyis "$MSG"; } && nr=$((nr+1)) || failp="${failp} POST:${p}=${s}"
  s="$(req GET "$p")"; { [ "$s" = 200 ] && bodyis "upstream GET "; } && ng=$((ng+1)) || failp="${failp} GET:${p}=${s}"
done < "$TMP/refuse"
[ "$nr" = "$t" ] && ok_ "live: POST is refused with 403 and the message on all ${t} master paths" || bad "live: POST refused on ${nr} of ${t}"
[ "$ng" = "$t" ] && ok_ "live: GET reaches OpenMRS on all ${t} master paths" || bad "live: GET passed on ${ng} of ${t}"
[ -z "$failp" ] || printf '         %s\n' $failp | head -20
k=0
for p in /openmrs/ws/rest/v1/concept/$U /openmrs/ws/rest/v1/form/$U /openmrs/ws/rest/v1/bahmniie/form/translations /openmrs/admin/concepts/conceptDrug.form; do
  for meth in PUT DELETE PATCH; do s="$(req "$meth" "$p")"; { [ "$s" = 403 ] && bodyis "$MSG"; } || { bad "live: ${meth} ${p} answered ${s}"; k=1; }; done
  for meth in OPTIONS HEAD; do s="$(req "$meth" "$p")"; [ "$s" = 200 ] || { bad "live: ${meth} ${p} answered ${s}"; k=1; }; done
done
[ "$k" = 0 ] && ok_ "live: PUT, DELETE and PATCH are refused; OPTIONS and HEAD pass (form definition regex route, translations route, a legacy page)"
na=0; t=0; failp=""
while read -r p; do
  t=$((t+1)); s="$(req POST "$p")"
  if [ "$p" = /openmrs/ws/rest/v1/bahmnicore/distro/patient/search ]; then want="upstream GET "; else want="upstream POST "; fi
  { [ "$s" = 200 ] && bodyis "$want"; } && na=$((na+1)) || failp="${failp} ${p}=${s}"
done < "$TMP/allow"
[ "$na" = "$t" ] && ok_ "live: POST reaches OpenMRS on all ${t} patient-flow and look-alike paths" || { bad "live: POST passed on ${na} of ${t}:"; printf '         %s\n' $failp | head -20; }
req POST /openmrs/ws/rest/v1/bahmnicore/distro/patient/search >/dev/null; bodyis "upstream GET /openmrs/ws/rest/v1/bahmnicore/distro/patient/search" \
  && ok_ "live: the patient search still goes on as GET" || bad "live: patient search: $(cat "$TMP/body")"
req POST /openmrs/ws/rest/v1/bahmnicore/distro/bahmniencounter >/dev/null; bodyis "upstream POST /openmrs/ws/rest/v1/bahmnicore/bahmniencounter" \
  && ok_ "live: an encounter save still goes to stock bahmnicore" || bad "live: encounter save: $(cat "$TMP/body")"
for p in "/openmrs//ws/rest/v1/concept" "/openmrs/ws/rest/v1/%63oncept" "/openmrs/ws/rest/v1/./concept/$U"; do
  s="$(req POST "$p")"; [ "$s" = 403 ] && ok_ "live: POST ${p} is refused (nginx normalises the path first)" || bad "live: POST ${p} answered ${s}"
done
s="$(req GET /master-write-refused)"; [ "$s" = 404 ] && ok_ "live: the refusal location cannot be asked for directly" || bad "live: GET /master-write-refused answered ${s}"
for i in 1 2 3 4 5 6 7 8 9 10; do
  lg="$(docker logs "$CNAME" 2>&1)"
  printf '%s\n' "$lg" | grep -q '/master-write-refused HTTP' && break; sleep 1
done
printf '%s\n' "$lg" | grep -E '"POST /openmrs/ws/rest/v1/concept HTTP/[0-9.]+" 403 master data write refused' >/dev/null \
  && ok_ "live: a refusal is logged with its request line" || bad "live: no refusal line in the access log"
printf '%s\n' "$lg" | grep -E '"GET /openmrs/ws/rest/v1/concept HTTP/[0-9.]+"' | grep -qv 'refused' \
  && ok_ "live: a read is logged as an ordinary request" || bad "live: no ordinary log line for a read"
exit "$fails"
