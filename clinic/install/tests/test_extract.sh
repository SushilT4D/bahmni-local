#!/usr/bin/env bash
# scripts/extract-ui-config.sh against a fake container runtime: the UI and the
# config tree come out of the two pinned IPLIT images into clinic/extracted/,
# the source is recorded, an unchanged source is skipped, a changed one keeps
# the previous copy, the node's MRN prefix is written, and a bad image never
# replaces a good extraction.
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
  *) exit 2 ;;
esac
SH
chmod +x "$TMP/bin/fakect"
export FAKE_ROOT="$TMP/images" FAKE_LOG="$TMP/calls.log"
mkimg(){ # NAME ID
  local d="$FAKE_ROOT/$(printf '%s' "$1" | tr '/:' '__')"; mkdir -p "$d"; printf 'sha256:%s\n' "$2" > "$d/.id"; printf '%s' "$d"; }
U="$(mkimg acme/web:1 aaa)"; mkdir -p "$U/usr/local/apache2/htdocs/bahmni/home"; echo "<html>v1</html>" > "$U/usr/local/apache2/htdocs/bahmni/home/index.html"; echo idx > "$U/usr/local/apache2/htdocs/index.html"
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
run(){ env -i PATH="$PATH" HOME="$HOME" CT="$TMP/bin/fakect" FAKE_ROOT="$FAKE_ROOT" FAKE_LOG="$FAKE_LOG" CLINIC_DIR="$TMP/clinic" BAHMNI_WEB_IMAGE="${WEB:-acme/web:1}" BAHMNI_CONFIG_IMAGE="${CFG:-acme/config:1}" MRN_PREFIX="${PFX-MAN}" BAHMNI_ODOO_HTTPS_PORT="${PORT-9444}" bash "$S" "$@" 2>&1; }
X="$TMP/clinic/extracted"

out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "first run succeeds" || bad "first run rc=$rc: $out"
[ -f "$X/htdocs/bahmni/home/index.html" ] && ok_ "UI extracted to extracted/htdocs/bahmni" || bad "no UI under extracted/htdocs/bahmni"
[ -d "$X/bahmni_config/masterdata/configuration" ] && [ -d "$X/bahmni_config/openelis" ] && ok_ "config extracted to extracted/bahmni_config" || bad "no config tree"
grep -q 'acme/web:1@sha256:aaa' "$X/.source" 2>/dev/null && grep -q 'acme/config:1@sha256:bbb' "$X/.source" && ok_ "source recorded with image ids" || bad ".source does not record both images: $(cat "$X/.source" 2>/dev/null)"
[ "$(jq -r .config.defaultIdentifierPrefix "$X/bahmni_config/openmrs/apps/registration/app.json")" = MAN ] && ok_ "MRN prefix written (GAN -> MAN)" || bad "prefix not written"
[ ! -e "$X/bahmni_config/masterdata/configuration/ocl/CIEL_v1.zip" ] && [ -f "$X/ocl-held/CIEL_v1.zip" ] && ok_ "OCL dictionary zip held out of the served tree, kept at extracted/ocl-held" || bad "OCL zip still in the tree OpenMRS reads (a two-day CIEL import on a small node)"
[ -f "$X/bahmni_config/masterdata/configuration/ocl/README.txt" ] && ok_ "only zips are held; other ocl files stay" || bad "non-zip ocl file was moved"
[ "$(jq -r .config.other "$X/bahmni_config/openmrs/apps/registration/app.json")" = 1 ] && ok_ "the rest of app.json is untouched" || bad "app.json lost its other keys"

WL="$X/bahmni_config/openmrs/apps/home/whiteLabel.json"
odoo(){ jq -r ".landingPage[] | select(.name==\"odoo\") | $1" "$WL"; }
[ "$(odoo .linkPort)" = 9444 ] && ok_ "odoo's landing tile gets linkPort 9444" || bad "odoo linkPort not set: $(odoo .)"
[ "$(odoo 'has("linkPrefix")')" = false ] && ok_ "odoo's landing tile loses linkPrefix" || bad "odoo still carries linkPrefix: $(odoo .)"
[ "$(jq -r '.landingPage[] | select(.name=="metabase") | .enabled' "$WL")" = false ] && ok_ "metabase tile disabled (no clinic runs one)" || bad "metabase still enabled"
[ "$(jq -r '.landingPage[] | select(.name=="clinicalService") | .enabled' "$WL")" = true ] && ok_ "clinicalService tile untouched" || bad "clinicalService tile was touched"

: > "$FAKE_LOG"; out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && ! grep -q '^create' "$FAKE_LOG" && ok_ "unchanged source: skipped, no container created" || bad "second run re-extracted: $(tr '\n' ';' < "$FAKE_LOG")"
[ "$(odoo .linkPort)" = 9444 ] && [ "$(jq -r '.landingPage[] | select(.name=="metabase") | .enabled' "$WL")" = false ] && ok_ "landing-page rules re-applied on the skip path" || bad "landing-page rules lost on the skip path"

printf 'sha256:ccc\n' > "$U/.id"; echo "<html>v2</html>" > "$U/usr/local/apache2/htdocs/bahmni/home/index.html"
out="$(run)"; rc=$?
grep -q v2 "$X/htdocs/bahmni/home/index.html" && ok_ "changed image id: re-extracted" || bad "did not pick up the new image: $out"
grep -q v1 "$X.prev/htdocs/bahmni/home/index.html" 2>/dev/null && ok_ "previous extraction kept at extracted.prev" || bad "previous extraction not kept"
[ "$(jq -r .config.defaultIdentifierPrefix "$X/bahmni_config/openmrs/apps/registration/app.json")" = MAN ] && ok_ "prefix re-applied after re-extraction" || bad "prefix lost on re-extraction"
[ "$(odoo .linkPort)" = 9444 ] && ok_ "landing-page rules re-applied after re-extraction" || bad "landing-page rules lost on re-extraction"

# a tree extracted BEFORE this rule existed (manpur) is fixed by the skip path too
mv "$X/ocl-held/CIEL_v1.zip" "$X/bahmni_config/masterdata/configuration/ocl/"; out="$(run)"
[ ! -e "$X/bahmni_config/masterdata/configuration/ocl/CIEL_v1.zip" ] && ok_ "an already-extracted tree gets its zips held on the next run" || bad "skip path left the zip in place"
out="$(env KEEP_OCL_ZIPS=1 true; PFX=MAN; env -i PATH="$PATH" HOME="$HOME" CT="$TMP/bin/fakect" FAKE_ROOT="$FAKE_ROOT" FAKE_LOG="$FAKE_LOG" CLINIC_DIR="$TMP/clinic" BAHMNI_WEB_IMAGE=acme/web:1 BAHMNI_CONFIG_IMAGE=acme/config:1 MRN_PREFIX=MAN KEEP_OCL_ZIPS=1 bash "$S" --force 2>&1)"
[ -f "$X/bahmni_config/masterdata/configuration/ocl/CIEL_v1.zip" ] && ok_ "KEEP_OCL_ZIPS=1 leaves the zips in place" || bad "KEEP_OCL_ZIPS=1 ignored"

# BAHMNI_ODOO_HTTPS_PORT unset: --force re-pulls the fixture's original
# whiteLabel.json (linkPrefix "erp", no linkPort) fresh from the image, and
# apply_landing must leave odoo's entry exactly as the image shipped it.
out="$(PORT="" run --force)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "run succeeds with BAHMNI_ODOO_HTTPS_PORT unset" || bad "run rc=$rc with unset port: $out"
[ "$(odoo .linkPrefix)" = erp ] && [ "$(odoo 'has("linkPort")')" = false ] && ok_ "unset BAHMNI_ODOO_HTTPS_PORT leaves odoo's linkPrefix alone" || bad "odoo entry changed despite unset port: $(odoo .)"

out="$(run --force)"   # back to the default for the checks below

B="$(mkimg acme/web:broken ddd)"; mkdir -p "$B/usr/local/apache2/htdocs"   # no bahmni/ inside
out="$(WEB=acme/web:broken run)"; rc=$?
[ "$rc" -ne 0 ] && ok_ "an image without the UI is refused" || bad "broken image accepted"
grep -q v2 "$X/htdocs/bahmni/home/index.html" && ok_ "the good extraction survives a refused one" || bad "good extraction was replaced"

out="$(WEB=acme/web:absent run)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'acme/web:absent' && ok_ "a missing image is named" || bad "missing image: rc=$rc out=$out"
exit "$fails"
