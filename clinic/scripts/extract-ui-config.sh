#!/usr/bin/env bash
# Fill clinic/extracted/ from IPLIT's two images, so the clinic's one nginx
# serves IPLIT's UI and every service reads IPLIT's config -- without running a
# second web server, and without a hand-taken copy committed to the repo.
#
#   extracted/htdocs/        <- BAHMNI_WEB_IMAGE:/usr/local/apache2/htdocs   (bahmni/ is the UI)
#   extracted/bahmni_config/ <- BAHMNI_CONFIG_IMAGE:/etc/bahmni_config       (openmrs, masterdata, openelis)
#   extracted/.source        <- what was extracted: image@id, one line each
#
# Both tags are pinned in sync/versions.env (L-005: the hub moves first, then the
# clinics). To take an IPLIT fix: change the tag there, run this, restart proxy,
# openmrs and openelis. An unchanged source is skipped; a changed one replaces
# extracted/ and keeps the last one at extracted.prev/. Nothing is left running:
# `create` + `cp` + `rm`, the container never starts.
#
# The tree is node-local and gitignored, so the node's own registration prefix
# (MRN_PREFIX) is written into it here -- re-applied on every extraction.
#
# usage: [CT=docker|podman] [MRN_PREFIX=MAN] scripts/extract-ui-config.sh [--force]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"
VERSIONS_FILE="${VERSIONS_FILE:-${CLINIC_DIR}/../sync/versions.env}"
CT="${CT:-docker}"; FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1
say(){ printf '  %s\n' "$*"; }; die(){ printf '  FAIL %s\n' "$*" >&2; exit 1; }
pin(){ # KEY : the environment wins, then sync/versions.env
  local v="${!1:-}"
  [ -n "$v" ] || v="$(sed -nE "s/^$1=([^#[:space:]]+).*/\1/p" "${VERSIONS_FILE}" 2>/dev/null | head -1)"
  [ -n "$v" ] || die "$1 is not set and not in ${VERSIONS_FILE}"
  printf '%s' "$v"
}
WEB="$(pin BAHMNI_WEB_IMAGE)"; CFG="$(pin BAHMNI_CONFIG_IMAGE)"
OUT="${EXTRACT_DIR:-${CLINIC_DIR}/extracted}"

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

apply_landing(){ # DIR : point the landing page's Odoo tile at THIS node's own
  # TLS port (a clinic serves Odoo at root on ${BAHMNI_ODOO_HTTPS_PORT:-9444},
  # not at IPLIT's erp-<host> DNS convention, which no clinic's DNS has -- the
  # tile opened a name that did not exist, manpur, 2026-09-21); and disable any
  # landing tile for a service this clinic does not run (default: metabase,
  # crater -- clinics have neither; LANDING_DISABLE overrides the list).
  local wl="$1/bahmni_config/openmrs/apps/home/whiteLabel.json" t disable="${LANDING_DISABLE:-metabase crater}"
  [ -f "$wl" ] || return 0
  t="$(mktemp "${wl}.XXXXXX")"
  jq --arg port "${BAHMNI_ODOO_HTTPS_PORT:-}" --arg disable "$disable" '
    ($disable | split(" ") | map(select(length > 0))) as $dis
    | .landingPage = ((.landingPage // []) | map(
        (if $port != "" and .name == "odoo" then (.linkPort = ($port | tonumber)) | del(.linkPrefix) else . end)
        | (if (.name as $n | $dis | index($n)) then .enabled = false else . end)
      ))
  ' "$wl" > "$t" || { rm -f "$t"; die "jq could not edit ${wl}"; }
  chmod 644 "$t"; mv "$t" "$wl"
}

hold_ocl(){ # DIR : keep the CIEL dictionary zips OUT of the tree OpenMRS reads
  # The config image ships OCL export zips under masterdata/configuration/ocl.
  # The Initializer imports any zip it has no checksum for -- a full CIEL load,
  # 282,699 items, and OpenMRS answers nothing until it ends. IPLIT's own stack
  # never runs it (the hub's live ocl/ dir is empty, no import row since the
  # seed's 2026-08-28 one); a clinic's checksum dir starts empty, so it did:
  # manpur, 2026-09-21, ~110 items a minute on one vCPU = about two days. The seed
  # already carries the dictionary (54,700 CIEL-mapped concepts on hub and clinic
  # alike). The zips are moved, not deleted: KEEP_OCL_ZIPS=1 leaves them in place.
  local d="$1/bahmni_config/masterdata/configuration/ocl" z
  [ "${KEEP_OCL_ZIPS:-0}" = 1 ] && return 0
  [ -d "$d" ] || return 0
  for z in "$d"/*.zip; do [ -f "$z" ] || continue; mkdir -p "$1/ocl-held"; mv "$z" "$1/ocl-held/"; done
}

if [ "$FORCE" = 0 ] && [ -f "$OUT/.source" ] && [ "$(cat "$OUT/.source")" = "$want" ] \
   && [ -f "$OUT/htdocs/bahmni/home/index.html" ] && [ -d "$OUT/bahmni_config/openmrs" ]; then
  apply_prefix "$OUT"; apply_landing "$OUT"; hold_ocl "$OUT"
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
apply_prefix "$NEW"; apply_landing "$NEW"; hold_ocl "$NEW"
chmod -R u+rwX,go+rX,go-w "$NEW"   # the UI image ships world-writable dirs
printf '%s\n' "$want" > "$NEW/.source"
if [ -e "$OUT" ]; then rm -rf "${OUT}.prev"; mv "$OUT" "${OUT}.prev"; fi
mv "$NEW" "$OUT"; trap - EXIT
say "ok   extracted/ <- ${WEB} ($(find "$OUT/htdocs/bahmni" -type f | wc -l | tr -d ' ') UI files), ${CFG} ($(find "$OUT/bahmni_config" -type f | wc -l | tr -d ' ') config files)${MRN_PREFIX:+, prefix ${MRN_PREFIX}}"
