#!/usr/bin/env bash
# The Initializer at a clinic loads only what a clinic may write: OpenMRS gets
# -Dinitializer.domains once, from OPENMRS_INITIALIZER_DOMAINS or the clinic
# default, and task 080 refuses, before the stack starts, a value naming a
# domain the module does not have or one that would load a config folder
# other than globalproperties and idgen.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; CL="$(cd "${HERE}/../.." && pwd)"
I="${HERE}/../initializer.sh"; T080="${HERE}/../tasks/080-stack.sh"; Y="$CL/docker-compose.yml"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
svc(){ awk -v s="  $2:" '$0==s{p=1;next} p&&/^  [A-Za-z]/{exit} p' "$1" | grep -vE '^[[:space:]]*#'; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ -f "$I" ] || { bad "no clinic/install/initializer.sh"; exit 1; }
v(){ ( . "${HERE}/../lib.sh"; . "$I"; initializer_domains_verdict "$@" ); }
k(){ ( . "$I"; eval "printf '%s' \"\${$1}\"" ); }

# --- the domain list ---------------------------------------------------------------
[ "$(k INITIALIZER_DOMAINS_KNOWN | wc -w | tr -d ' ')" = 52 ] && ok_ "the module's 52 domains are known" || bad "known domains: $(k INITIALIZER_DOMAINS_KNOWN | wc -w)"
DEF="$(k INITIALIZER_DOMAINS_DEFAULT)"
[ "$DEF" = globalproperties,idgen ] && ok_ "the default is the inclusion list globalproperties,idgen" || bad "default: $DEF"
[ "$(k INITIALIZER_DOMAINS_KEPT | tr ' ' ',')" = "$DEF" ] && ok_ "the default loads exactly the domains a clinic keeps" || bad "kept $(k INITIALIZER_DOMAINS_KEPT) vs default $DEF"
# An exclusion list stays accepted as an override: the one the README gives,
# every domain the clinic config tree carries a folder for but the kept two.
EXCL='!bahmniforms,roles,privileges,concepts,conceptsets,conceptclasses,conceptsources,drugs,ocl,locations,addresshierarchy,programs,programworkflows,programworkflowstates,attributetypes,visittypes,ordertypes,personattributetypes,relationshiptypes,appointmentspecialities,appointmentservicedefinitions,liquibase'
grep -qF -- "    ${EXCL}" "${HERE}/../README.md" && ok_ "the README gives the exclusion list these checks use" || bad "the README does not give the exclusion list"

# --- compose ---------------------------------------------------------------------------
env_block="$(svc "$Y" openmrs)"
[ "$(printf '%s\n' "$env_block" | grep -c 'OMRS_JAVA_SERVER_OPTS:')" = 1 ] && ok_ "openmrs sets OMRS_JAVA_SERVER_OPTS once" || bad "OMRS_JAVA_SERVER_OPTS lines: $(printf '%s\n' "$env_block" | grep -c 'OMRS_JAVA_SERVER_OPTS:')"
line="$(printf '%s\n' "$env_block" | grep 'OMRS_JAVA_SERVER_OPTS:')"
printf '%s' "$line" | grep -qF -- "-Dinitializer.domains=\${OPENMRS_INITIALIZER_DOMAINS:-${DEF}}\"" && ok_ "compose passes -Dinitializer.domains from OPENMRS_INITIALIZER_DOMAINS, defaulting to initializer.sh's list" || bad "compose line: $line"
grep -E '^[A-Z_0-9]+=' "$CL/.env.example" | grep -q -- '-Dinitializer.domains' && bad ".env.example sets the domains in OMRS_JAVA_SERVER_OPTS" || ok_ ".env.example leaves -Dinitializer.domains to compose"
if command -v docker >/dev/null 2>&1; then
  { grep -E '^[A-Z_0-9]+=' "$CL/.env.example" | cut -d= -f1
    grep -ohE '\$\{[A-Z_0-9]+:\?' "$CL/docker-compose.yml" "$CL/docker-compose.macos.yml" | sed -E 's/.*\{([A-Z_0-9]+):\?/\1/'
  } | sort -u | grep -v '^OMRS_JAVA_SERVER_OPTS$' | awk '/PATH$|DIR$|BACKUP$/{print $0"=/p"; next} {print $0"=1"}' > "$TMP/render.vars"
  printf 'OMRS_JAVA_SERVER_OPTS="-server -Dfile.encoding=UTF-8"\n' >> "$TMP/render.vars"
  opts(){ ( cd "$CL" && env -u OPENMRS_INITIALIZER_DOMAINS "$@" docker compose --env-file "$TMP/render.vars" --profile local config --format json 2>/dev/null ) \
          | python3 -c 'import json,sys; print(json.load(sys.stdin)["services"]["openmrs"]["environment"]["OMRS_JAVA_SERVER_OPTS"])' 2>/dev/null; }
  got="$(opts)"
  [ "$got" = "-server -Dfile.encoding=UTF-8 -Dinitializer.domains=${DEF}" ] && ok_ "rendered: the node's own options, then the clinic default, once" || bad "rendered default: '$got'"
  got="$(opts OPENMRS_INITIALIZER_DOMAINS=globalproperties,idgen)"
  [ "$got" = "-server -Dfile.encoding=UTF-8 -Dinitializer.domains=globalproperties,idgen" ] && ok_ "rendered: OPENMRS_INITIALIZER_DOMAINS replaces the default" || bad "rendered override: '$got'"
else
  ok_ "compose not available here; render checks skipped"
fi

# --- the verdict -----------------------------------------------------------------------------
C="$TMP/cfg"; M="$C/masterdata/configuration"
# the folders the clinic config tree carries today; ocl is empty there
for d in addresshierarchy appointmentservicedefinitions appointmentspecialities attributetypes bahmniforms conceptclasses concepts conceptsets conceptsources drugs globalproperties idgen liquibase locations ordertypes personattributetypes privileges programs programworkflows programworkflowstates relationshiptypes roles visittypes; do
  mkdir -p "$M/$d"; echo x > "$M/$d/$d.csv"
done
mkdir -p "$M/ocl"
out="$(v "$DEF" "$C")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^ok inclusion list; from the config tree it loads: globalproperties idgen$' && ok_ "the default passes the config tree a clinic carries, loading only globalproperties and idgen" || bad "default: rc=$rc out=$out"
out="$(v "$EXCL" "$C")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^ok exclusion list; from the config tree it loads: globalproperties idgen$' && ok_ "the exclusion list override passes the same tree, loading the same two" || bad "exclusion: rc=$rc out=$out"
out="$(v '!bahmniforms,bogus,Concepts,!idgen' "$C")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'does not have: bogus Concepts !idgen\.' && ok_ "unknown names are refused, each named (case and a second ! included)" || bad "unknown: rc=$rc out=$out"
out="$(v 'globalproperties,idgen,bogus' "$C")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'does not have: bogus\.' && ok_ "an unknown name in an inclusion list is refused too" || bad "unknown inclusion: rc=$rc out=$out"
mkdir -p "$M/encountertypes"; echo x > "$M/encountertypes/encountertypes.csv"
out="$(v "$EXCL" "$C")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'carries a folder for encountertypes,' && ok_ "an exclusion list refuses a config folder for a domain it does not exclude (a config release adding one)" || bad "new folder under the exclusion list: rc=$rc out=$out"
out="$(v "$DEF" "$C")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'it loads: globalproperties idgen$' && ok_ "the default is not affected by that folder: it loads only the kept two" || bad "default with a new folder: rc=$rc out=$out"
rm -rf "$M/encountertypes"
mkdir -p "$M/htmlforms"; echo x > "$M/htmlforms/f.xml"
out="$(v "$EXCL" "$C")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'carries a folder for htmlforms,' && ok_ "an exclusion list refuses a new htmlforms folder (it writes forms)" || bad "htmlforms under the exclusion list: rc=$rc out=$out"
out="$(v "$DEF" "$C")"; rc=$?
[ "$rc" -eq 0 ] && ok_ "the default does not load a new htmlforms folder, so it passes" || bad "htmlforms under the default: rc=$rc out=$out"
rm -rf "$M/htmlforms"
# a folder for a domain this list does not know (a newer module's) is refused
# by name under either kind of list, not left to load
mkdir -p "$M/newdomain"; echo x > "$M/newdomain/x.csv"
out="$(v "$DEF" "$C")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'carries a folder for newdomain, which is not one of the Initializer domains known here' && ok_ "an unknown folder is refused under the default, by name" || bad "unknown folder, default: rc=$rc out=$out"
out="$(v "$EXCL" "$C")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'folder for newdomain,' && ok_ "an unknown folder is refused under an exclusion list too" || bad "unknown folder, exclusion: rc=$rc out=$out"
rm -rf "$M/newdomain"; mkdir -p "$M/newdomain"
for l in "$DEF" "$EXCL"; do
  out="$(v "$l" "$C")"; rc=$?
  [ "$rc" -eq 0 ] || bad "empty unknown folder refused under $l: rc=$rc out=$out"
done
ok_ "an empty unknown folder loads nothing and is not refused, under either list"
rmdir "$M/newdomain"
out="$(v '!bahmniforms' "$C")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'folder for addresshierarchy appointmentservicedefinitions .*liquibase .*roles visittypes,' && ok_ "excluding only bahmniforms is refused, naming every hub-owned folder it would load" || bad "bahmniforms only: rc=$rc out=$out"
out="$(v globalproperties,idgen,concepts "$C")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'folder for concepts,' && ok_ "an inclusion list that names a hub-owned domain with a folder is refused" || bad "inclusion of concepts: rc=$rc out=$out"
out="$(v globalproperties,idgen,ocl "$C")"; rc=$?
[ "$rc" -eq 0 ] && ok_ "an empty folder loads nothing and is not refused" || bad "empty folder: rc=$rc out=$out"
for bad_v in 'globalproperties,,idgen' ',idgen' 'globalproperties, idgen' 'idgen,*' ''; do
  out="$(v "$bad_v" "$C")"; rc=$?
  [ "$rc" -ne 0 ] || bad "malformed value accepted: '$bad_v'"
done
ok_ "malformed values are refused (empty name, space, glob character, empty)"
out="$(v "$DEF" "$TMP/none")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'no config tree at' && ok_ "a missing config tree is refused" || bad "missing tree: rc=$rc out=$out"

# --- task 080 checks before compose up ----------------------------------------------------------
blk="$(sed -n '/# initializer-guard:begin/,/# initializer-guard:end/p' "$T080")"
[ -n "$blk" ] || bad "080 has no initializer-guard block"
gl="$(grep -n 'initializer-guard:end' "$T080" | head -1 | cut -d: -f1)"; ul="$(grep -n ' up -d >/dev/null' "$T080" | head -1 | cut -d: -f1)"
[ -n "$gl" ] && [ -n "$ul" ] && [ "$gl" -lt "$ul" ] && ok_ "080 checks the domain list before it starts the stack" || bad "080's initializer check is not before compose up (${gl:-none} vs ${ul:-none})"
g080(){ env -i PATH="$PATH" BAHMNI_CONFIG_DIR="$C" "$@" bash -c "INSTALL_DIR='${HERE}/..'; . '${HERE}/../lib.sh'; fail(){ printf 'FAIL %s\n' \"\$*\"; exit 1; }; ok(){ printf 'OK %s\n' \"\$*\"; }
${blk}" 2>&1; }
out="$(g080)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^OK initializer domains: inclusion list; from the config tree it loads: globalproperties idgen$' && ok_ "080 uses the default when OPENMRS_INITIALIZER_DOMAINS is unset" || bad "080 default: rc=$rc out=$out"
out="$(g080 OPENMRS_INITIALIZER_DOMAINS="$EXCL")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^OK initializer domains: exclusion list' && ok_ "080 accepts an exclusion list set as an override" || bad "080 exclusion override: rc=$rc out=$out"
out="$(g080 OPENMRS_INITIALIZER_DOMAINS='!bahmniforms,nosuchdomain')"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '^FAIL .*does not have: nosuchdomain' && ok_ "080 stops on an unknown domain" || bad "080 unknown: rc=$rc out=$out"

# --- a value left in OMRS_JAVA_SERVER_OPTS is moved out, not doubled ----------------------------------
j="$TMP/j.env"
printf 'OMRS_JAVA_MEMORY_OPTS="-Xmx2g"\nOMRS_JAVA_SERVER_OPTS="-server -Dinitializer.domains=!bahmniforms -Dfile.encoding=UTF-8"\n' > "$j"
out="$( . "${HERE}/../lib.sh"; ensure_openmrs_jvm_opts "$j" 2>&1 )"
got="$( . "${HERE}/../lib.sh"; env_get "$j" OMRS_JAVA_SERVER_OPTS )"
[ "$got" = "-server -Dfile.encoding=UTF-8" ] && printf '%s' "$out" | grep -q 'carried -Dinitializer.domains=!bahmniforms; removed' && ok_ "a -Dinitializer.domains in OMRS_JAVA_SERVER_OPTS is removed and reported" || bad "strip: got '$got' out=$out"
( set -a; . "$j"; [ "$OMRS_JAVA_SERVER_OPTS" = "-server -Dfile.encoding=UTF-8" ] ) && ok_ "the rewritten .env still sources" || bad "rewritten .env does not source"
printf 'OMRS_JAVA_MEMORY_OPTS="-Xmx2g"\nOMRS_JAVA_SERVER_OPTS="-server -Dx=1"\n' > "$j"
out="$( . "${HERE}/../lib.sh"; ensure_openmrs_jvm_opts "$j" 2>&1 )"
[ "$( . "${HERE}/../lib.sh"; env_get "$j" OMRS_JAVA_SERVER_OPTS )" = "-server -Dx=1" ] && ! printf '%s' "$out" | grep -q removed && ok_ "options without it are left alone" || bad "untouched opts: $out"

# --- the answer -------------------------------------------------------------------------------------
grep -q 'put OPENMRS_INITIALIZER_DOMAINS' "${HERE}/../tasks/020-env.sh" && ok_ "020 writes OPENMRS_INITIALIZER_DOMAINS into clinic/.env when the answers set it" || bad "020 does not carry OPENMRS_INITIALIZER_DOMAINS"
a="$TMP/answers.env"
( . "${HERE}/../lib.sh"; OPENMRS_INITIALIZER_DOMAINS=globalproperties,idgen answers_write "$a" )
[ "$( . "${HERE}/../lib.sh"; env_get "$a" OPENMRS_INITIALIZER_DOMAINS )" = globalproperties,idgen ] && ok_ "composed answers keep OPENMRS_INITIALIZER_DOMAINS when set" || bad "answers_write dropped OPENMRS_INITIALIZER_DOMAINS"
grep -qE '^OPENMRS_INITIALIZER_DOMAINS=' "${HERE}/../clinic.env.example" && ok_ "clinic.env.example documents OPENMRS_INITIALIZER_DOMAINS" || bad "clinic.env.example lacks OPENMRS_INITIALIZER_DOMAINS"
grep -q '^### Initializer domains' "${HERE}/../README.md" && ok_ "the installer README explains the Initializer domains" || bad "README has no Initializer domains section"
exit "$fails"
