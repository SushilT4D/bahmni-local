#!/usr/bin/env bash
# scripts/recreate-openmrs.sh, the one documented way to recreate OpenMRS on a
# running node: it runs the checks installer task 080 runs before OpenMRS
# starts (the JVM options, the forms mount, the Initializer domain list
# against the config tree) and only then recreates openmrs alone, the way the
# node runs compose. A runtime and compose that log every call stand in.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CL="$(cd "${HERE}/../.." && pwd)"
S="${CL}/scripts/recreate-openmrs.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
[ -f "$S" ] || { bad "no scripts/recreate-openmrs.sh"; exit 1; }
[ -x "$S" ] && ok_ "recreate-openmrs.sh is executable" || bad "recreate-openmrs.sh is not executable"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
for b in docker docker-compose podman; do
  printf '#!/usr/bin/env bash\necho "%s $* | cwd=$(pwd) | COMPOSE_FILE=${COMPOSE_FILE:-} DOCKER_HOST=${DOCKER_HOST:-}" >> "$FAKE_LOG"\nexit 0\n' "$b" > "$TMP/bin/$b"
done
chmod +x "$TMP/bin/"*
export FAKE_LOG="$TMP/calls.log"

node(){ # DIR : an installed node: config tree, frozen forms copy, clinic/.env
  local n="$1" d
  for d in globalproperties idgen concepts drugs; do mkdir -p "$n/extracted/bahmni_config/masterdata/configuration/$d"; echo x > "$n/extracted/bahmni_config/masterdata/configuration/$d/$d.csv"; done
  mkdir -p "$n/bahmni_home/clinical_forms/translations"; echo '{}' > "$n/bahmni_home/clinical_forms/f.json"
  cat > "$n/.env" <<EOF
COMPOSE_PROJECT_NAME=bahmni-t
BAHMNI_CONFIG_DIR=$n/extracted/bahmni_config
FORMS_DIR=$n/bahmni_home/clinical_forms
FORMS_READ_ONLY=false
FORMS_REPO_URL=
OMRS_JAVA_MEMORY_OPTS='-Xms512m -Xmx2048m'
OMRS_JAVA_SERVER_OPTS='-server -Dinitializer.domains=!bahmniforms -Dfile.encoding=UTF-8'
EOF
}
run(){ # DIR [ARGS...] ; RT= runtime (default docker)
  local d="$1"; shift
  env -i PATH="$TMP/bin:$PATH" HOME="$TMP" FAKE_LOG="$FAKE_LOG" CLINIC_DIR="$d" RUNTIME="${RT:-docker}" ${DH:+DOCKER_HOST="$DH"} bash "$S" "$@" 2>&1
}
envv(){ ( . "${HERE}/../lib.sh"; env_get "$1/.env" "$2" ); }
calls(){ cat "$FAKE_LOG" 2>/dev/null; }
up_line='--profile local --profile debezium --profile openelis up -d --no-deps --force-recreate openmrs'

# --- a node whose checks pass ---------------------------------------------------------------
N="$TMP/n"; node "$N"; : > "$FAKE_LOG"
out="$(run "$N")"; rc=$?
[ "$rc" -eq 0 ] && calls | grep -qF "docker compose ${up_line} | cwd=$N" && ok_ "checks pass: openmrs alone is recreated, from clinic/, with the fleet's profiles" || bad "good node: rc=$rc out=$out calls=$(calls)"
printf '%s' "$out" | grep -q 'ok   forms: 1 form files .*(mounted read-write)' && printf '%s' "$out" | grep -q 'ok   initializer domains: inclusion list; from the config tree it loads: globalproperties idgen' \
  && ok_ "it says what it checked: the forms mount and the domain list" || bad "check lines: $out"
[ "$(envv "$N" OMRS_JAVA_SERVER_OPTS)" = "-server -Dfile.encoding=UTF-8" ] && ok_ "a -Dinitializer.domains left in OMRS_JAVA_SERVER_OPTS is taken out first, so the property is passed once" || bad "jvm opts: $(envv "$N" OMRS_JAVA_SERVER_OPTS)"

# --- a config release that would load forms, under an exclusion list set as an override ----------------
EXCL='!bahmniforms,roles,privileges,concepts,conceptsets,conceptclasses,conceptsources,drugs,ocl,locations,addresshierarchy,programs,programworkflows,programworkflowstates,attributetypes,visittypes,ordertypes,personattributetypes,relationshiptypes,appointmentspecialities,appointmentservicedefinitions,liquibase'
N2="$TMP/n2"; node "$N2"; printf "OPENMRS_INITIALIZER_DOMAINS='%s'\n" "$EXCL" >> "$N2/.env"; mkdir -p "$N2/extracted/bahmni_config/masterdata/configuration/htmlforms"; echo '<htmlform/>' > "$N2/extracted/bahmni_config/masterdata/configuration/htmlforms/anc.xml"
: > "$FAKE_LOG"
out="$(run "$N2")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'FAIL the config tree carries a folder for htmlforms,' && ! calls | grep -q ' up ' \
  && ok_ "a config tree with an htmlforms folder is refused, by name, and nothing is recreated" || bad "htmlforms: rc=$rc out=$out calls=$(calls)"
out="$(run "$N2" --check)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'folder for htmlforms,' && ok_ "--check refuses it too" || bad "--check htmlforms: rc=$rc out=$out"
printf 'OPENMRS_INITIALIZER_DOMAINS=globalproperties,idgen\n' >> "$N2/.env"; : > "$FAKE_LOG"
out="$(run "$N2")"; rc=$?
[ "$rc" -eq 0 ] && calls | grep -qF -- "$up_line" && printf '%s' "$out" | grep -q 'initializer domains: inclusion list' && ok_ "with the inclusion list globalproperties,idgen the same tree is recreated on" || bad "inclusion: rc=$rc out=$out"
N2b="$TMP/n2b"; node "$N2b"; mkdir -p "$N2b/extracted/bahmni_config/masterdata/configuration/htmlforms"; echo '<htmlform/>' > "$N2b/extracted/bahmni_config/masterdata/configuration/htmlforms/anc.xml"
: > "$FAKE_LOG"
out="$(run "$N2b")"; rc=$?
[ "$rc" -eq 0 ] && calls | grep -qF -- "$up_line" && printf '%s' "$out" | grep -q 'initializer domains: inclusion list; from the config tree it loads: globalproperties idgen' && ok_ "with no list set, the default inclusion list loads no htmlforms folder, and the tree is recreated on" || bad "default with htmlforms: rc=$rc out=$out"

# --- the forms mount ---------------------------------------------------------------------------------
N3="$TMP/n3"; node "$N3"; rm -rf "$N3/bahmni_home/clinical_forms"; : > "$FAKE_LOG"
out="$(run "$N3")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'clinical_forms does not exist' && [ ! -s "$FAKE_LOG" ] && ok_ "a missing forms folder is refused before anything is recreated" || bad "missing forms: rc=$rc out=$out calls=$(calls)"
N4="$TMP/n4"; node "$N4"; printf 'FORMS_REPO_URL=git@h:o/r.git\n' >> "$N4/.env"; : > "$FAKE_LOG"
out="$(run "$N4")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'names a forms repo, but the forms mount is .*not its clone' && [ ! -s "$FAKE_LOG" ] && ok_ "a forms repo with the mount not on its clone is refused" || bad "repo vs mount: rc=$rc out=$out"
N5="$TMP/n5"; node "$N5"; printf 'FORMS_READ_ONLY=ro\n' >> "$N5/.env"; : > "$FAKE_LOG"
out="$(run "$N5")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "FORMS_READ_ONLY is 'ro'" && [ ! -s "$FAKE_LOG" ] && ok_ "a FORMS_READ_ONLY other than true or false is refused" || bad "read-only value: rc=$rc out=$out"

# --- --check changes nothing ---------------------------------------------------------------------------
N6="$TMP/n6"; node "$N6"; before="$(cat "$N6/.env")"; : > "$FAKE_LOG"
out="$(run "$N6" --check)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$N6/.env")" = "$before" ] && [ ! -s "$FAKE_LOG" ] && printf '%s' "$out" | grep -q 'openmrs was not recreated' && printf '%s' "$out" | grep -q 'carries -Dinitializer.domains' \
  && ok_ "--check runs the checks, says what a run would repair, and changes neither clinic/.env nor the stack" || bad "--check: rc=$rc out=$out calls=$(calls)"

# --- a podman node ----------------------------------------------------------------------------------------
N7="$TMP/n7"; node "$N7"; touch "$N7/docker-compose.yml" "$N7/docker-compose.macos.yml"
printf 'COMPOSE_FILE=docker-compose.yml:docker-compose.macos.yml\n' >> "$N7/.env"; : > "$FAKE_LOG"
out="$(RT=podman DH=unix:///run/podman.sock run "$N7")"; rc=$?
[ "$rc" -eq 0 ] && calls | grep -qF "docker-compose ${up_line} | cwd=$N7 | COMPOSE_FILE=docker-compose.yml:docker-compose.macos.yml DOCKER_HOST=unix:///run/podman.sock" \
  && ok_ "on podman: docker-compose over the podman socket, with clinic/.env's COMPOSE_FILE" || bad "podman: rc=$rc out=$out calls=$(calls)"

# --- the documented paths name it -----------------------------------------------------------------------------
grep -q 'scripts/recreate-openmrs.sh' "$CL/scripts/update-forms.sh" && ok_ "update-forms.sh's hint names recreate-openmrs.sh" || bad "update-forms.sh does not name recreate-openmrs.sh"
grep -vE '^[[:space:]]*#' "$CL/scripts/update-forms.sh" | grep -q -- '--force-recreate' && bad "update-forms.sh still hints a raw compose recreate" || ok_ "update-forms.sh hints no raw compose recreate"
grep -q 'scripts/recreate-openmrs.sh' "$CL/scripts/extract-ui-config.sh" && ok_ "extract-ui-config.sh's config-release steps name recreate-openmrs.sh" || bad "extract-ui-config.sh does not name recreate-openmrs.sh"
grep -q 'recreate-openmrs.sh' "$CL/install/README.md" && ! grep -q -- '--force-recreate openmrs' "$CL/install/README.md" \
  && ok_ "the installer README names recreate-openmrs.sh, not a raw compose recreate" || bad "README still documents a raw recreate"
grep -q 'recreate-openmrs.sh' "$CL/scripts/README.md" && ok_ "scripts/README.md lists recreate-openmrs.sh" || bad "scripts/README.md does not list recreate-openmrs.sh"
exit "$fails"
