#!/usr/bin/env bash
# Native arm64 rebuild of the pinned OpenMRS image, replacing the 662-4-era
# build.sh for this purpose (build.sh + Dockerfile stay in the tree, unused --
# see clinic/install/tasks/040-images.sh, which calls this instead on arm64).
#
# IPLIT's image is linux/amd64 only. On Apple Silicon under podman it runs
# under QEMU: bare Tomcat+WAR start took 26,153 ms on Ghated, and
# the PREVIOUS pinned image took 51 MINUTES with modules loading. This script
# copies the four trees the source image needs to run -- /usr/local/tomcat,
# /openmrs, /etc/bahmni-emr, /home/bahmni -- onto a pinned arm64 base with the
# same OS family (Amazon Linux 2) and the same Corretto 8u432 JDK, and builds
# a native image: 2,394 ms / 2,330 ms for the same bare Tomcat+WAR on the same
# Mac (~11x faster). x86 clinics never run this -- see task 040.
#
# A multi-stage `COPY --from=<amd64 stage>` is REFUSED by this podman/buildah
# (6.1.0, rootless): "unsupported MIME type for compression" (Ghated,
# 2026-09-21), before any COPY instruction runs. The route that works instead:
# `create --platform linux/amd64` + `cp` for each of the four paths into a
# build context, then a single-stage build with plain COPY against that
# context. The source image is never executed under emulation.
#
# usage: [CT=docker|podman] [CLINIC_DIR=...] openmrs/build-native.sh [--force]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"
VERSIONS_FILE="${VERSIONS_FILE:-${CLINIC_DIR}/../sync/versions.env}"
CT="${CT:-docker}"; DRY="${DRY:-0}"; FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1
say(){ printf '  %s\n' "$*"; }; die(){ printf '  FAIL %s\n' "$*" >&2; exit 1; }
pin(){ # KEY : the environment wins, then sync/versions.env (extract-ui-config.sh's own pin)
  local v="${!1:-}"
  [ -n "$v" ] || v="$(sed -nE "s/^$1=([^#[:space:]]+).*/\1/p" "${VERSIONS_FILE}" 2>/dev/null | head -1)"
  [ -n "$v" ] || die "$1 is not set and not in ${VERSIONS_FILE}"
  printf '%s' "$v"
}
SRC="$(pin OPENMRS_IMAGE_NAME)"
BASE="$(pin OPENMRS_ARM64_BASE_IMAGE)"
SRC_TAG="${SRC##*:}"
OUT="bahmni-local/openmrs:${SRC_TAG}-arm64"

if [ "${DRY}" = 1 ]; then
  say "would build ${OUT} from ${SRC} (arm64 base ${BASE}), unless its labels already match the current source+base image ids (--force skips that check)"
  printf 'image=%s\n' "$OUT"
  exit 0
fi

image_present(){ "$CT" image inspect "$1" >/dev/null 2>&1; }
image_id(){ "$CT" image inspect --format '{{.Id}}' "$1" 2>/dev/null; }
image_label(){ "$CT" image inspect --format "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null; }
image_arch(){ "$CT" image inspect --format '{{.Architecture}}' "$1" 2>/dev/null; }

ensure_present(){ # IMAGE [PULL-FLAGS...] : present already, else pull (3 tries)
  local img="$1"; shift
  image_present "$img" && return 0
  local a
  for a in 1 2 3; do "$CT" pull "$@" "$img" >/dev/null 2>&1 && return 0; [ "$a" = 3 ] || sleep 10; done
  return 1
}
ensure_present "$SRC" --platform linux/amd64 || die "source image ${SRC} is not present and could not be pulled"
ensure_present "$BASE" || die "arm64 base image ${BASE} is not present and could not be pulled"

src_id="$(image_id "$SRC")"; [ -n "$src_id" ] || die "could not read the image id of ${SRC}"
base_id="$(image_id "$BASE")"; [ -n "$base_id" ] || die "could not read the image id of ${BASE}"

if [ "$FORCE" = 0 ] && image_present "$OUT"; then
  have_src="$(image_label "$OUT" org.t4d.source-image-id)"
  have_base="$(image_label "$OUT" org.t4d.base-image-id)"
  if [ "$have_src" = "$src_id" ] && [ "$have_base" = "$base_id" ]; then
    say "skip ${OUT} already built from ${SRC}@${src_id} + ${BASE}@${base_id}"
    printf 'image=%s\n' "$OUT"
    exit 0
  fi
fi

# Build context under CLINIC_DIR so it lands on the same filesystem as the
# checkout (a cross-device mktemp under /tmp has bitten podman builds before);
# removed on exit whether the build succeeds, refuses or fails outright. An
# `if` rather than `[ cond ] && rm` so the trap itself always returns 0 -- a
# non-zero EXIT trap re-triggers lib.sh's ERR trap on the way out (same
# pitfall documented in scripts/seed-odoo-conf.sh).
CTX="$(mktemp -d "${CLINIC_DIR}/.build-native.XXXXXX")"
cleanup(){ if [ -n "${CTX:-}" ] && [ -d "${CTX:-/nonexistent}" ]; then rm -rf "$CTX"; fi; }
trap cleanup EXIT

cid="$("$CT" create --platform linux/amd64 "$SRC")" || die "could not create a container from ${SRC}"
cp_path(){ # IN-IMAGE-PATH OUT-NAME
  if ! "$CT" cp "${cid}:$1" "${CTX}/$2" >/dev/null 2>&1; then
    "$CT" rm "$cid" >/dev/null 2>&1 || true
    die "${SRC} has no $1"
  fi
}
cp_path /usr/local/tomcat tomcat
cp_path /openmrs openmrs
cp_path /etc/bahmni-emr bahmni-emr
cp_path /home/bahmni bahmni-home
"$CT" rm "$cid" >/dev/null 2>&1 || true

# Accepted only if it looks like what Dockerfile.native's CMD actually needs --
# a source image with a different layout must never silently produce a broken tag.
[ -f "${CTX}/openmrs/bahmni_startup.sh" ] || die "${SRC} has no /openmrs/bahmni_startup.sh -- not an OpenMRS startup image"
[ -f "${CTX}/openmrs/distribution/openmrs_core/openmrs.war" ] || die "${SRC} has no /openmrs/distribution/openmrs_core/openmrs.war"

cp "${HERE}/Dockerfile.native" "${CTX}/Dockerfile.native"

"$CT" build \
  -f "${CTX}/Dockerfile.native" \
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
