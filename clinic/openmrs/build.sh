#!/usr/bin/env bash
# Rebuilds the amd64-only OpenMRS image natively for arm64
# Copies the image's four runtime trees out

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"
VERSIONS_FILE="${VERSIONS_FILE:-${CLINIC_DIR}/../sync/versions.env}"
CT="${CT:-podman}"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1


# --- Helpers -----------------------------------------------------------------

say() { printf '  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*" >&2; exit 1; }

# Image pins: the environment wins, then sync/versions.env.
pin() {
  local v="${!1:-}"

  if [ -z "$v" ]; then
    v="$(sed -nE "s/^$1=([^#[:space:]]+).*/\1/p" "${VERSIONS_FILE}" 2>/dev/null | head -1)"
  fi

  [ -n "$v" ] || die "$1 is not set and not in ${VERSIONS_FILE}"
  printf '%s' "$v"
}

image_present() { "$CT" image inspect "$1" >/dev/null 2>&1; }
image_id()      { "$CT" image inspect --format '{{.Id}}' "$1" 2>/dev/null; }
image_label()   { "$CT" image inspect --format "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null; }
image_arch()    { "$CT" image inspect --format '{{.Architecture}}' "$1" 2>/dev/null; }

# Use the image if present, else pull it (3 tries).
ensure_present() { # IMAGE [PULL-FLAGS...]
  local img="$1"
  shift

  image_present "$img" && return 0

  local a
  for a in 1 2 3; do
    "$CT" pull "$@" "$img" >/dev/null 2>&1 && return 0
    [ "$a" = 3 ] || sleep 10
  done
  return 1
}

# --- Images ------------------------------------------------------------------

SRC="$(pin OPENMRS_IMAGE_NAME)"
BASE="$(pin OPENMRS_ARM64_BASE_IMAGE)"
OUT="bahmni-local/openmrs:${SRC##*:}-arm64"

ensure_present "$SRC" --platform linux/amd64 || die "source image ${SRC} is not present and could not be pulled"
ensure_present "$BASE"                       || die "arm64 base image ${BASE} is not present and could not be pulled"

src_id="$(image_id "$SRC")"
[ -n "$src_id" ] || die "could not read the image id of ${SRC}"

base_id="$(image_id "$BASE")"
[ -n "$base_id" ] || die "could not read the image id of ${BASE}"


# --- Skip when already built from these exact images -------------------------

if [ "$FORCE" = 0 ] && image_present "$OUT"; then
  have_src="$(image_label "$OUT" org.t4d.source-image-id)"
  have_base="$(image_label "$OUT" org.t4d.base-image-id)"

  if [ "$have_src" = "$src_id" ] && [ "$have_base" = "$base_id" ]; then
    say "skip ${OUT} already built from ${SRC}@${src_id} + ${BASE}@${base_id}"
    printf 'image=%s\n' "$OUT"
    exit 0
  fi
fi

# --- Build context -----------------------------------------------------------

# On the checkout's filesystem, removed on exit; the trap must return 0.
CTX="$(mktemp -d "${CLINIC_DIR}/.openmrs-build.XXXXXX")"

cleanup() {
  if [ -n "${CTX:-}" ] && [ -d "${CTX:-/nonexistent}" ]; then
    rm -rf "$CTX"
  fi
}
trap cleanup EXIT

# --- Copy the four runtime trees out of the source image (never run it) -----

cid="$("$CT" create --platform linux/amd64 "$SRC")" || die "could not create a container from ${SRC}"

cp_path() { # IN-IMAGE-PATH OUT-NAME
  if ! "$CT" cp "${cid}:$1" "${CTX}/$2" >/dev/null 2>&1; then
    "$CT" rm "$cid" >/dev/null 2>&1 || true
    die "${SRC} has no $1"
  fi
}

cp_path /usr/local/tomcat tomcat
cp_path /openmrs          openmrs
cp_path /etc/bahmni-emr   bahmni-emr
cp_path /home/bahmni      bahmni-home

"$CT" rm "$cid" >/dev/null 2>&1 || true

# Refuse a source image without the startup script or the WAR.
[ -f "${CTX}/openmrs/bahmni_startup.sh" ] \
  || die "${SRC} has no /openmrs/bahmni_startup.sh -- not an OpenMRS startup image"
[ -f "${CTX}/openmrs/distribution/openmrs_core/openmrs.war" ] \
  || die "${SRC} has no /openmrs/distribution/openmrs_core/openmrs.war"

cp "${HERE}/Dockerfile" "${CTX}/Dockerfile"

# --- Build, labelled with the image ids it was built from --------------------

"$CT" build \
  -f "${CTX}/Dockerfile" \
  --build-arg BASE_IMAGE="$BASE" \
  --label org.t4d.source-image="$SRC" \
  --label org.t4d.source-image-id="$src_id" \
  --label org.t4d.base-image-id="$base_id" \
  -t "$OUT" \
  "$CTX" || die "build of ${OUT} failed"

arch="$(image_arch "$OUT")"
[ "$arch" = arm64 ] || die "built image ${OUT} reports Architecture=${arch:-unknown}, not arm64 -- refusing it"

say "ok   built ${OUT} from ${SRC}@${src_id} + ${BASE}@${base_id}"
printf 'image=%s\n' "$OUT"
