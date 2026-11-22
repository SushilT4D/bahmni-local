#!/usr/bin/env bash
# Extract and validate the clinic UI and config images.
# Usage: [MRN_PREFIX=MAN] scripts/extract-ui-config.sh [--force]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"
VERSIONS_FILE="${VERSIONS_FILE:-${CLINIC_DIR}/../sync/versions.env}"
CT="${CT:-podman}"; FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1
say(){ printf '  %s\n' "$*"; }; die(){ printf '  FAIL %s\n' "$*" >&2; exit 1; }
pin(){ # KEY : the environment wins, then sync/versions.env
  local v="${!1:-}"
  [ -n "$v" ] || v="$(sed -nE "s/^$1=([^#[:space:]]+).*/\1/p" "${VERSIONS_FILE}" 2>/dev/null | head -1)"
  [ -n "$v" ] || die "$1 is not set and not in ${VERSIONS_FILE}"
  printf '%s' "$v"
}
WEB="$(pin BAHMNI_WEB_IMAGE)"; CFG="$(pin BAHMNI_CONFIG_IMAGE)"
OUT="${EXTRACT_DIR:-${CLINIC_DIR}/extracted}"
. "${HERE}/../install/initializer.sh"
env_file_get(){ # KEY : clinic/.env's value (the last line for KEY, as compose and the shell read it), a matching pair of quotes stripped
  local v
  v="$(sed -n "s/^$1=//p" "${CLINIC_DIR}/.env" 2>/dev/null | tail -1)"
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}
DOMAINS="${OPENMRS_INITIALIZER_DOMAINS:-$(env_file_get OPENMRS_INITIALIZER_DOMAINS)}"
DOMAINS="${DOMAINS:-${INITIALIZER_DOMAINS_DEFAULT}}"
# Read the Initializer domains configured in each existing OpenMRS container.
container_domains(){
  local project id opts d
  project=bahmni
  for id in $("$CT" ps -a -q --filter label=com.docker.compose.service=openmrs ${project:+--filter "label=com.docker.compose.project=${project}"} 2>/dev/null); do
    opts="$("$CT" inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$id" 2>/dev/null | sed -n 's/^OMRS_JAVA_SERVER_OPTS=//p')"
    # Java keeps the last of a repeated -D
    d="$(printf '%s' "$opts" | tr ' ' '\n' | sed -n 's/^-Dinitializer\.domains=//p' | tail -1)"
    printf '%s\n' "${d:-$(printf '%s' "${INITIALIZER_DOMAINS_KNOWN}" | tr ' ' ',')}"
  done
}
check_domains(){ # DIR WHAT : DIR's config tree loads nothing the hub owns, with this node's domain list and with the list its openmrs container runs
  local v c
  v="$(initializer_domains_verdict "$DOMAINS" "$1/bahmni_config")" || die "$2: ${v}"
  say "ok   initializer domains: ${v#ok }"
  while IFS= read -r c; do
    [ -n "$c" ] && [ "$c" != "$DOMAINS" ] || continue
    v="$(initializer_domains_verdict "$c" "$1/bahmni_config")" \
      || die "$2: the openmrs container was created with a different Initializer domain list than clinic/.env holds, and would start with it on its next restart: ${v} Run scripts/recreate-openmrs.sh first, then this again"
    say "ok   initializer domains of the running openmrs container: ${v#ok }"
  done <<EOF_DOMAINS
$(container_domains)
EOF_DOMAINS
}

image_id(){ # IMAGE : present (pulling it if need be) -> its id
  local img="$1" a
  if ! "$CT" image inspect --format '{{.Id}}' "$img" >/dev/null 2>&1; then
    for a in 1 2 3; do "$CT" pull "$img" >/dev/null 2>&1 && break; [ "$a" = 3 ] || sleep 10; done
  fi
  "$CT" image inspect --format '{{.Id}}' "$img" 2>/dev/null || die "image ${img} is not present and could not be pulled"
}
wid="$(image_id "$WEB")"; cid_="$(image_id "$CFG")"
want="$(printf 'ui=%s@%s\nconfig=%s@%s' "$WEB" "$wid" "$CFG" "$cid_")"

apply_prefix(){ # DIR : the node's registration prefix, if one was given
  local app="$1/bahmni_config/openmrs/apps/registration/app.json" t
  [ -n "${MRN_PREFIX:-}" ] || return 0
  [ -f "$app" ] || die "no registration app.json in the config image (${CFG})"
  t="$(mktemp "${app}.XXXXXX")"
  jq --arg p "${MRN_PREFIX}" '.config.defaultIdentifierPrefix = $p' "$app" > "$t" || { rm -f "$t"; die "jq could not edit ${app}"; }
  chmod 644 "$t"; mv "$t" "$app"
}

apply_landing(){ # DIR : point the landing page's Odoo tile at odoo.<LAN_NAME>
  # (Odoo lives at the root of its own name on this clinic), and disable any
  # tile for a service this clinic does not run (default: metabase, crater --
  # clinics have neither; LANDING_DISABLE overrides the list).
  local wl="$1/bahmni_config/openmrs/apps/home/whiteLabel.json" t disable="${LANDING_DISABLE:-metabase crater}"
  [ -f "$wl" ] || return 0
  t="$(mktemp "${wl}.XXXXXX")"
  jq --arg lan "${LAN_NAME:-bahmni.clinic}" --arg disable "$disable" '
    ($disable | split(" ") | map(select(length > 0))) as $dis
    | .landingPage = ((.landingPage // []) | map(
        (if $lan != "" and .name == "odoo" then (.linkHost = ("odoo." + $lan)) | del(.linkPrefix, .linkPort) else . end)
        | (if (.name as $n | $dis | index($n)) then .enabled = false else . end)
      ))
  ' "$wl" > "$t" || { rm -f "$t"; die "jq could not edit ${wl}"; }
  chmod 644 "$t"; mv "$t" "$wl"
}

no_form_builder_tile(){ # DIR : the home page offers no form builder at a clinic
  local ext="$1/bahmni_config/openmrs/apps/home/extension.json" t
  [ -f "$ext" ] || return 0
  t="$(mktemp "${ext}.XXXXXX")"
  jq 'with_entries(select((.value | type) != "object" or .value.url != "/implementer-interface"))' "$ext" > "$t" \
    || { rm -f "$t"; die "jq could not edit ${ext}"; }
  chmod 644 "$t"; mv "$t" "$ext"
}

hold_ocl(){ # DIR : keep the CIEL dictionary zips OUT of the tree OpenMRS reads
  # Hold OCL archives to prevent an unintended full dictionary import.
  local d="$1/bahmni_config/masterdata/configuration/ocl" z
  [ "${KEEP_OCL_ZIPS:-0}" = 1 ] && return 0
  [ -d "$d" ] || return 0
  for z in "$d"/*.zip; do [ -f "$z" ] || continue; mkdir -p "$1/ocl-held"; mv "$z" "$1/ocl-held/"; done
}

fix_program_edit(){ # DIR : enrolment edits send states the REST module accepts
  # Send only the state fields accepted by the OpenMRS REST endpoint.
  local d="$1/htdocs/bahmni" f n
  local mark='/*clinic: states sent by uuid*/'
  local from='states: patientProgram.states,'
  local to="states: _.map(patientProgram.states, function (s) { return s.uuid ? {uuid: s.uuid} : {state: (s.state && s.state.uuid) || s.state, startDate: s.startDate}; }), ${mark}"
  for f in "$d"/*/*.min.*.js; do
    [ -f "$f" ] || continue
    grep -qF "$mark" "$f" && continue                    # already fixed
    n="$(grep -cF "$from" "$f" || true)"
    [ "$n" = 0 ] && continue                              # bundle has no program editing
    [ "$n" = 1 ] || die "$(basename "$f") has ${n} program-state mappers, expected one -- check enrolment edits by hand"
    FROM="$from" TO="$to" perl -pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/' "$f" || die "could not rewrite the program-state mapper in ${f}"
    grep -qF "$mark" "$f" || die "the program-state mapper in ${f} was not rewritten"
  done
  grep -qF "$mark" "$d"/clinical/*.js 2>/dev/null \
    || die "${WEB}: no clinical bundle carries the program-state mapper this fix rewrites -- check that editing an enrolment saves, then remove fix_program_edit"
}

if [ "$FORCE" = 0 ] && [ -f "$OUT/.source" ] && [ "$(cat "$OUT/.source")" = "$want" ] \
   && [ -f "$OUT/htdocs/bahmni/home/index.html" ] && [ -d "$OUT/bahmni_config/openmrs" ]; then
  apply_prefix "$OUT"; apply_landing "$OUT"; no_form_builder_tile "$OUT"; hold_ocl "$OUT"; fix_program_edit "$OUT"
  check_domains "$OUT" "the config tree in extracted/ (${CFG}) would load rows the hub owns; do not restart OpenMRS on it"
  say "skip extracted/ already holds ${WEB} and ${CFG}"; exit 0
fi

pull_tree(){ # IMAGE PATH-IN-IMAGE DEST
  local c; c="$("$CT" create "$1")" || die "could not create a container from $1"
  if ! "$CT" cp "${c}:$2/." "$3" >/dev/null; then "$CT" rm "$c" >/dev/null 2>&1 || true; die "$1 has no $2"; fi
  "$CT" rm "$c" >/dev/null 2>&1 || true
}
NEW="${OUT}.new.$$"; rm -rf "$NEW"; mkdir -p "$NEW/htdocs" "$NEW/bahmni_config"
trap 'rm -rf "$NEW"' EXIT
pull_tree "$WEB" /usr/local/apache2/htdocs "$NEW/htdocs"
pull_tree "$CFG" /etc/bahmni_config "$NEW/bahmni_config"
# a tree is accepted only if it looks like what the services will ask it for
[ -f "$NEW/htdocs/bahmni/home/index.html" ] || die "${WEB} carries no bahmni/home/index.html under /usr/local/apache2/htdocs -- not a Bahmni UI image"
[ -d "$NEW/bahmni_config/openmrs/apps" ] && [ -d "$NEW/bahmni_config/masterdata/configuration" ] || die "${CFG} carries no openmrs/apps + masterdata/configuration under /etc/bahmni_config -- not a Bahmni config image"
apply_prefix "$NEW"; apply_landing "$NEW"; no_form_builder_tile "$NEW"; hold_ocl "$NEW"; fix_program_edit "$NEW"
check_domains "$NEW" "refused ${CFG}: extracted/ is left as it was"
chmod -R u+rwX,go+rX,go-w "$NEW"   # the UI image ships world-writable dirs
printf '%s\n' "$want" > "$NEW/.source"
if [ -e "$OUT" ]; then rm -rf "${OUT}.prev"; mv "$OUT" "${OUT}.prev"; fi
mv "$NEW" "$OUT"; trap - EXIT
say "ok   extracted/ <- ${WEB} ($(find "$OUT/htdocs/bahmni" -type f | wc -l | tr -d ' ') UI files), ${CFG} ($(find "$OUT/bahmni_config" -type f | wc -l | tr -d ' ') config files)${MRN_PREFIX:+, prefix ${MRN_PREFIX}}"
