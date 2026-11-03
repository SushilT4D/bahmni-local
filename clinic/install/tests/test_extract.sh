#!/usr/bin/env bash
# scripts/extract-ui-config.sh against a fake container runtime: the UI and the
# config tree come out of the two pinned IPLIT images into clinic/extracted/,
# the source is recorded, an unchanged source is skipped, a changed one keeps
# the previous copy, the node's MRN prefix is written, the UI's program-state
# mapper is rewritten once (and a UI without it is refused), and a bad image
# never replaces a good extraction.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${HERE}/../../scripts/extract-ui-config.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
[ -f "$S" ] || { bad "no scripts/extract-ui-config.sh"; exit 1; }

# --- fake runtime: $FAKE_ROOT/<image with / and : as _>/ is that image's filesystem
mkdir -p "$TMP/bin" "$TMP/clinic"
cat > "$TMP/bin/fakect" <<'SH'
#!/usr/bin/env bash
san(){ printf '%s' "$1" | tr '/:' '__'; }
echo "$*" >> "$FAKE_LOG"
case "$1" in
  image) img="${@: -1}"; [ -d "$FAKE_ROOT/$(san "$img")" ] || exit 1; cat "$FAKE_ROOT/$(san "$img")/.id" ;;
  pull)  exit 1 ;;
  create) img="${@: -1}"; echo "cid-$(san "$img")" ;;
  cp) src="$2"; dst="$3"; cid="${src%%:*}"; p="${src#*:}"; p="${p%/.}"; [ -d "$FAKE_ROOT/${cid#cid-}$p" ] || exit 1; mkdir -p "$dst"; cp -R "$FAKE_ROOT/${cid#cid-}$p/." "$dst/" ;;
  rm) : ;;
  # an openmrs container of this node exists when FAKE_OPENMRS=1, created with FAKE_OPENMRS_OPTS
  ps) [ "${FAKE_OPENMRS:-}" = 1 ] && echo cid-openmrs; exit 0 ;;
  inspect) [ "${FAKE_OPENMRS:-}" = 1 ] || exit 1; printf 'PATH=/usr/bin\nOMRS_JAVA_SERVER_OPTS=%s\n' "${FAKE_OPENMRS_OPTS:-}" ;;
  *) exit 2 ;;
esac
SH
chmod +x "$TMP/bin/fakect"
export FAKE_ROOT="$TMP/images" FAKE_LOG="$TMP/calls.log"
mkimg(){ # NAME ID
  local d="$FAKE_ROOT/$(printf '%s' "$1" | tr '/:' '__')"; mkdir -p "$d"; printf 'sha256:%s\n' "$2" > "$d/.id"; printf '%s' "$d"; }
U="$(mkimg acme/web:1 aaa)"; mkdir -p "$U/usr/local/apache2/htdocs/bahmni/home"; echo "<html>v1</html>" > "$U/usr/local/apache2/htdocs/bahmni/home/index.html"; echo idx > "$U/usr/local/apache2/htdocs/index.html"
MAPPER='        return {
            dateEnrolled: x,
            states: patientProgram.states,
            uuid: patientProgram.uuid
        };'
mkdir -p "$U/usr/local/apache2/htdocs/bahmni/clinical" "$U/usr/local/apache2/htdocs/bahmni/ot"
printf '%s\n' "$MAPPER" > "$U/usr/local/apache2/htdocs/bahmni/clinical/clinical.min.abc.js"
echo 'var web = 1;' > "$U/usr/local/apache2/htdocs/bahmni/clinical/clinical.min.web.def.js"
printf '%s\n' "$MAPPER" > "$U/usr/local/apache2/htdocs/bahmni/ot/ot.min.123.js"
C="$(mkimg acme/config:1 bbb)"; mkdir -p "$C/etc/bahmni_config/openmrs/apps/registration" "$C/etc/bahmni_config/openmrs/apps/home" "$C/etc/bahmni_config/masterdata/configuration" "$C/etc/bahmni_config/openelis"
printf '{"id":"bahmni.registration","config":{"defaultIdentifierPrefix":"GAN","other":1}}\n' > "$C/etc/bahmni_config/openmrs/apps/registration/app.json"
mkdir -p "$C/etc/bahmni_config/masterdata/configuration/ocl"; echo zipbytes > "$C/etc/bahmni_config/masterdata/configuration/ocl/CIEL_v1.zip"; echo keepme > "$C/etc/bahmni_config/masterdata/configuration/ocl/README.txt"
# whiteLabel.json: odoo carries IPLIT's linkPrefix convention (erp-<host>, which
# does not resolve for a clinic -- Odoo is on this node's own TLS port
# instead), metabase is enabled though no clinic runs one, clinicalService is
# an ordinary tile that must survive untouched.
cat > "$C/etc/bahmni_config/openmrs/apps/home/whiteLabel.json" <<'JSON'
{"landingPage":[
  {"name":"odoo","enabled":true,"link":"/","linkPrefix":"erp","title":"Stock Inventory & Billing","logo":"odoo.png"},
  {"name":"metabase","enabled":true,"link":"/metabase","title":"Analytics","logo":"metabase.png"},
  {"name":"clinicalService","enabled":true,"link":"/clinical","title":"Clinical","logo":"clinical.png"}
]}
JSON
cat > "$C/etc/bahmni_config/openmrs/apps/home/extension.json" <<'JSON'
{"implementerInterface":{"id":"bahmni.implementer.interface","type":"link","url":"/implementer-interface","order":4},
 "registration":{"id":"bahmni.registration","type":"link","url":"/bahmni/registration/index.html","order":1}}
JSON
run(){ env -i PATH="$PATH" HOME="$HOME" CT="$TMP/bin/fakect" FAKE_ROOT="$FAKE_ROOT" FAKE_LOG="$FAKE_LOG" FAKE_OPENMRS="${FAKE_OPENMRS-}" FAKE_OPENMRS_OPTS="${FAKE_OPENMRS_OPTS-}" CLINIC_DIR="$TMP/clinic" BAHMNI_WEB_IMAGE="${WEB:-acme/web:1}" BAHMNI_CONFIG_IMAGE="${CFG:-acme/config:1}" MRN_PREFIX="${PFX-MAN}" LAN_NAME="${LAN-bahmni.clinic}" bash "$S" "$@" 2>&1; }
X="$TMP/clinic/extracted"

out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "first run succeeds" || bad "first run rc=$rc: $out"
[ -f "$X/htdocs/bahmni/home/index.html" ] && ok_ "UI extracted to extracted/htdocs/bahmni" || bad "no UI under extracted/htdocs/bahmni"
[ -d "$X/bahmni_config/masterdata/configuration" ] && [ -d "$X/bahmni_config/openelis" ] && ok_ "config extracted to extracted/bahmni_config" || bad "no config tree"
[ ! -e "$X/bahmni_config/masterdata/configuration/bahmniforms" ] && ok_ "a config image without forms gets no forms folder: nothing is mounted into the config tree" || bad "the extraction made masterdata/configuration/bahmniforms in the config tree"
grep -q 'acme/web:1@sha256:aaa' "$X/.source" 2>/dev/null && grep -q 'acme/config:1@sha256:bbb' "$X/.source" && ok_ "source recorded with image ids" || bad ".source does not record both images: $(cat "$X/.source" 2>/dev/null)"
[ "$(jq -r .config.defaultIdentifierPrefix "$X/bahmni_config/openmrs/apps/registration/app.json")" = MAN ] && ok_ "MRN prefix written (GAN -> MAN)" || bad "prefix not written"
[ ! -e "$X/bahmni_config/masterdata/configuration/ocl/CIEL_v1.zip" ] && [ -f "$X/ocl-held/CIEL_v1.zip" ] && ok_ "OCL dictionary zip held out of the served tree, kept at extracted/ocl-held" || bad "OCL zip still in the tree OpenMRS reads (a two-day CIEL import on a small node)"
[ -f "$X/bahmni_config/masterdata/configuration/ocl/README.txt" ] && ok_ "only zips are held; other ocl files stay" || bad "non-zip ocl file was moved"
[ "$(jq -r .config.other "$X/bahmni_config/openmrs/apps/registration/app.json")" = 1 ] && ok_ "the rest of app.json is untouched" || bad "app.json lost its other keys"

CB="$X/htdocs/bahmni/clinical/clinical.min.abc.js"; MARK='/*clinic: states sent by uuid*/'
marks(){ grep -cF "$MARK" "$1"; }
[ "$(marks "$CB")" = 1 ] && ! grep -qF 'states: patientProgram.states,' "$CB" && ok_ "program edits: the clinical bundle sends states by uuid" || bad "clinical bundle not rewritten: $(cat "$CB")"
grep -qF 'states: _.map(patientProgram.states,' "$CB" && grep -qF 'uuid: patientProgram.uuid' "$CB" && ok_ "program edits: only the states line changed" || bad "clinical bundle damaged: $(cat "$CB")"
[ "$(marks "$X/htdocs/bahmni/ot/ot.min.123.js")" = 1 ] && ok_ "program edits: the OT bundle, which shares the mapper, is rewritten too" || bad "OT bundle not rewritten"
[ "$(cat "$X/htdocs/bahmni/clinical/clinical.min.web.def.js")" = 'var web = 1;' ] && ok_ "program edits: a bundle without the mapper is untouched" || bad "unrelated bundle changed"
if command -v node >/dev/null 2>&1; then
  node -e 'var _={map:function(a,f){return a.map(f);}};var patientProgram={uuid:"p",states:[{uuid:"s1",state:{uuid:"w1",concept:{name:{name:"Admitted"}}},patientProgram:{uuid:"p"}},{state:{uuid:"w2"},startDate:null}]};var x;var r=(function(){'"$(cat "$CB")"'})();if(JSON.stringify(r.states)!==JSON.stringify([{uuid:"s1"},{state:"w2",startDate:null}]))process.exit(1);' \
    && ok_ "program edits: the rewritten mapper sends {uuid} for a held state and {state, startDate} for a new one" || bad "rewritten mapper produces the wrong states"
fi

WL="$X/bahmni_config/openmrs/apps/home/whiteLabel.json"
odoo(){ jq -r ".landingPage[] | select(.name==\"odoo\") | $1" "$WL"; }
[ "$(odoo .linkHost)" = odoo.bahmni.clinic ] && [ "$(odoo 'has("linkPort")')" = false ] && ok_ "odoo's landing tile opens odoo.bahmni.clinic" || bad "odoo linkHost not set: $(odoo .)"
[ "$(odoo 'has("linkPrefix")')" = false ] && ok_ "odoo's landing tile loses linkPrefix" || bad "odoo still carries linkPrefix: $(odoo .)"
[ "$(jq -r '.landingPage[] | select(.name=="metabase") | .enabled' "$WL")" = false ] && ok_ "metabase tile disabled (no clinic runs one)" || bad "metabase still enabled"
[ "$(jq -r '.landingPage[] | select(.name=="clinicalService") | .enabled' "$WL")" = true ] && ok_ "clinicalService tile untouched" || bad "clinicalService tile was touched"

: > "$FAKE_LOG"; out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && ! grep -q '^create' "$FAKE_LOG" && ok_ "unchanged source: skipped, no container created" || bad "second run re-extracted: $(tr '\n' ';' < "$FAKE_LOG")"
[ "$(odoo .linkHost)" = odoo.bahmni.clinic ] && [ "$(jq -r '.landingPage[] | select(.name=="metabase") | .enabled' "$WL")" = false ] && ok_ "landing-page rules re-applied on the skip path" || bad "landing-page rules lost on the skip path"
[ "$(marks "$CB")" = 1 ] && ok_ "program edits: the skip path leaves one rewrite, not two" || bad "skip path rewrote the mapper again: $(marks "$CB") marks"

printf 'sha256:ccc\n' > "$U/.id"; echo "<html>v2</html>" > "$U/usr/local/apache2/htdocs/bahmni/home/index.html"
out="$(run)"; rc=$?
grep -q v2 "$X/htdocs/bahmni/home/index.html" && ok_ "changed image id: re-extracted" || bad "did not pick up the new image: $out"
grep -q v1 "$X.prev/htdocs/bahmni/home/index.html" 2>/dev/null && ok_ "previous extraction kept at extracted.prev" || bad "previous extraction not kept"
[ "$(jq -r .config.defaultIdentifierPrefix "$X/bahmni_config/openmrs/apps/registration/app.json")" = MAN ] && ok_ "prefix re-applied after re-extraction" || bad "prefix lost on re-extraction"
[ "$(odoo .linkHost)" = odoo.bahmni.clinic ] && ok_ "landing-page rules re-applied after re-extraction" || bad "landing-page rules lost on re-extraction"
[ "$(marks "$CB")" = 1 ] && ok_ "program edits: rewritten again after re-extraction" || bad "re-extracted bundle not rewritten"

# a tree extracted BEFORE this rule existed (manpur) is fixed by the skip path too
mv "$X/ocl-held/CIEL_v1.zip" "$X/bahmni_config/masterdata/configuration/ocl/"; out="$(run)"
[ ! -e "$X/bahmni_config/masterdata/configuration/ocl/CIEL_v1.zip" ] && ok_ "an already-extracted tree gets its zips held on the next run" || bad "skip path left the zip in place"
out="$(env KEEP_OCL_ZIPS=1 true; PFX=MAN; env -i PATH="$PATH" HOME="$HOME" CT="$TMP/bin/fakect" FAKE_ROOT="$FAKE_ROOT" FAKE_LOG="$FAKE_LOG" CLINIC_DIR="$TMP/clinic" BAHMNI_WEB_IMAGE=acme/web:1 BAHMNI_CONFIG_IMAGE=acme/config:1 MRN_PREFIX=MAN KEEP_OCL_ZIPS=1 bash "$S" --force 2>&1)"
[ -f "$X/bahmni_config/masterdata/configuration/ocl/CIEL_v1.zip" ] && ok_ "KEEP_OCL_ZIPS=1 leaves the zips in place" || bad "KEEP_OCL_ZIPS=1 ignored"

# LAN_NAME unset: --force re-pulls the fixture's original
# whiteLabel.json (linkPrefix "erp", no linkHost) fresh from the image, and
# apply_landing must leave odoo's entry exactly as the image shipped it.
out="$(LAN="" run --force)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "run succeeds with LAN_NAME unset" || bad "run rc=$rc with unset LAN_NAME: $out"
[ "$(odoo .linkPrefix)" = erp ] && [ "$(odoo 'has("linkHost")')" = false ] && ok_ "unset LAN_NAME leaves odoo's linkPrefix alone" || bad "odoo entry changed despite unset LAN_NAME: $(odoo .)"

out="$(run --force)"   # back to the default for the checks below

B="$(mkimg acme/web:broken ddd)"; mkdir -p "$B/usr/local/apache2/htdocs"   # no bahmni/ inside
out="$(WEB=acme/web:broken run)"; rc=$?
[ "$rc" -ne 0 ] && ok_ "an image without the UI is refused" || bad "broken image accepted"
grep -q v2 "$X/htdocs/bahmni/home/index.html" && ok_ "the good extraction survives a refused one" || bad "good extraction was replaced"

N="$(mkimg acme/web:nomapper eee)"; mkdir -p "$N/usr/local/apache2/htdocs/bahmni/home" "$N/usr/local/apache2/htdocs/bahmni/clinical"
echo "<html>nomapper</html>" > "$N/usr/local/apache2/htdocs/bahmni/home/index.html"; echo 'var other = 1;' > "$N/usr/local/apache2/htdocs/bahmni/clinical/clinical.min.zzz.js"
out="$(WEB=acme/web:nomapper run)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'program-state mapper' && ok_ "a UI whose clinical bundle no longer has the mapper is refused, by name" || bad "UI without the mapper accepted: rc=$rc out=$out"
grep -q v2 "$X/htdocs/bahmni/home/index.html" && ok_ "the good extraction survives a UI without the mapper" || bad "good extraction was replaced by one without the fix"

out="$(WEB=acme/web:absent run)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'acme/web:absent' && ok_ "a missing image is named" || bad "missing image: rc=$rc out=$out"

# the form builder is not offered at a clinic: its home page tile is removed
EXT="$X/bahmni_config/openmrs/apps/home/extension.json"
[ "$(jq -r 'has("implementerInterface")' "$EXT")" = false ] && [ "$(jq -r '.registration.url' "$EXT")" = /bahmni/registration/index.html ] \
  && ok_ "the form builder's home page tile is removed, the other tiles kept" || bad "extension.json: $(cat "$EXT")"

# the Initializer domain check guards the config-release path: a config image
# whose tree would load rows the hub owns never replaces the current tree. The
# default inclusion list loads no htmlforms folder; an exclusion list set as an
# override leaves it loading, so under one the image is refused.
H="$(mkimg acme/config:htmlforms fff)"; cp -R "$C/etc" "$H/"
mkdir -p "$H/etc/bahmni_config/masterdata/configuration/htmlforms"; echo '<htmlform/>' > "$H/etc/bahmni_config/masterdata/configuration/htmlforms/anc.xml"
EXCL='!bahmniforms,roles,privileges,concepts,conceptsets,conceptclasses,conceptsources,drugs,ocl,locations,addresshierarchy,programs,programworkflows,programworkflowstates,attributetypes,visittypes,ordertypes,personattributetypes,relationshiptypes,appointmentspecialities,appointmentservicedefinitions,liquibase'
printf "OPENMRS_INITIALIZER_DOMAINS='%s'\n" "$EXCL" > "$TMP/clinic/.env"
src0="$(cat "$X/.source")"; prev0="$(cat "$X.prev/.source" 2>/dev/null)"
out="$(CFG=acme/config:htmlforms run)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'refused acme/config:htmlforms: extracted/ is left as it was' && printf '%s' "$out" | grep -q 'folder for htmlforms,' \
  && ok_ "a config image adding an htmlforms folder is refused, naming the folder" || bad "htmlforms image: rc=$rc out=$out"
[ "$(cat "$X/.source")" = "$src0" ] && [ ! -e "$X/bahmni_config/masterdata/configuration/htmlforms" ] && [ "$(cat "$X.prev/.source" 2>/dev/null)" = "$prev0" ] \
  && ok_ "the refused tree replaces nothing: extracted/ and extracted.prev/ are as they were" || bad "the refused tree replaced the current one: $(cat "$X/.source")"
ls -d "$X".new.* >/dev/null 2>&1 && bad "the refused tree was left behind" || ok_ "nothing of the refused tree is left behind"
rm -f "$TMP/clinic/.env"
out="$(env -i PATH="$PATH" HOME="$HOME" CT="$TMP/bin/fakect" FAKE_ROOT="$FAKE_ROOT" FAKE_LOG="$FAKE_LOG" CLINIC_DIR="$TMP/clinic" BAHMNI_WEB_IMAGE=acme/web:1 BAHMNI_CONFIG_IMAGE=acme/config:htmlforms MRN_PREFIX=MAN LAN_NAME=bahmni.clinic OPENMRS_INITIALIZER_DOMAINS=globalproperties,idgen bash "$S" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -d "$X/bahmni_config/masterdata/configuration/htmlforms" ] && printf '%s' "$out" | grep -q 'initializer domains: inclusion list' \
  && ok_ "with the inclusion list globalproperties,idgen the same image is taken" || bad "htmlforms with the inclusion list: rc=$rc out=$out"
# the domain list comes from clinic/.env when the environment does not set it
printf "OPENMRS_INITIALIZER_DOMAINS='!bahmniforms'\n" > "$TMP/clinic/.env"
out="$(run --force)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'with -Dinitializer.domains=!bahmniforms the Initializer would load' && ok_ "the domain list is read from clinic/.env" || bad "domain list from clinic/.env: rc=$rc out=$out"
rm -f "$TMP/clinic/.env"
# the skip path checks the tree in place: an unchanged image is still refused
printf "OPENMRS_INITIALIZER_DOMAINS='%s'\n" "$EXCL" > "$TMP/clinic/.env"
out="$(CFG=acme/config:htmlforms run)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'the config tree in extracted/ (acme/config:htmlforms) would load rows the hub owns' && ok_ "the skip path refuses a tree in place that would load rows the hub owns" || bad "skip path with htmlforms in place: rc=$rc out=$out"
rm -f "$TMP/clinic/.env"
out="$(CFG=acme/config:htmlforms run)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'initializer domains: inclusion list; from the config tree it loads: nothing' && ok_ "with no list set, the default inclusion list takes the same tree in place" || bad "skip path under the default: rc=$rc out=$out"
out="$(run --force)"; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$X/bahmni_config/masterdata/configuration/htmlforms" ] && ok_ "a good image replaces it again" || bad "back to the good image: rc=$rc out=$out"

# the openmrs container's own list: clinic/.env already holds the inclusion
# list, but the container was created with an exclusion list, which a plain
# restart would start it with on the new tree
printf 'OPENMRS_INITIALIZER_DOMAINS=globalproperties,idgen\n' > "$TMP/clinic/.env"
src0="$(cat "$X/.source")"
out="$(FAKE_OPENMRS=1 FAKE_OPENMRS_OPTS='-Xmx2g -Dinitializer.domains=!bahmniforms' CFG=acme/config:htmlforms run)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'the openmrs container was created with a different Initializer domain list' && printf '%s' "$out" | grep -q 'Run scripts/recreate-openmrs.sh first' \
  && [ "$(cat "$X/.source")" = "$src0" ] && ok_ "a tree the running openmrs container's own list would load from is refused, naming recreate-openmrs.sh; extracted/ unchanged" || bad "container list: rc=$rc out=$out"
out="$(FAKE_OPENMRS=1 FAKE_OPENMRS_OPTS='-Dinitializer.domains=!bahmniforms -Dinitializer.domains=globalproperties,idgen' CFG=acme/config:htmlforms run)"; rc=$?
[ "$rc" -eq 0 ] && [ -d "$X/bahmni_config/masterdata/configuration/htmlforms" ] && ! printf '%s' "$out" | grep -q 'running openmrs container' \
  && ok_ "a container created with the same list (the last -D, as Java reads it) adds no second check" || bad "same list: rc=$rc out=$out"
out="$(FAKE_OPENMRS=1 FAKE_OPENMRS_OPTS='-Xmx2g' run --force)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'the openmrs container was created with a different Initializer domain list' \
  && ok_ "a container created with no domain list loads every domain, and is judged so" || bad "no -D in the container: rc=$rc out=$out"
out="$(FAKE_OPENMRS=1 FAKE_OPENMRS_OPTS='-Dinitializer.domains=globalproperties,idgen' run --force)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "with the container on the same list as clinic/.env, the good image is taken" || bad "container agrees: rc=$rc out=$out"
# a duplicated key in clinic/.env: the last line wins, as compose and the shell read it
printf "OPENMRS_INITIALIZER_DOMAINS='!bahmniforms'\nOPENMRS_INITIALIZER_DOMAINS=globalproperties,idgen\n" > "$TMP/clinic/.env"
out="$(CFG=acme/config:htmlforms run --force)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'initializer domains: inclusion list' && ok_ "a duplicated OPENMRS_INITIALIZER_DOMAINS in clinic/.env is read as its last line" || bad "duplicate key: rc=$rc out=$out"
rm -f "$TMP/clinic/.env"
exit "$fails"
