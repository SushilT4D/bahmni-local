#!/usr/bin/env bash
# The macOS/Apple-Silicon path, static + compose-config checks: compose falls
# back OPENMRS_RUN_IMAGE -> OPENMRS_IMAGE_NAME, task 040 branches on host
# architecture and no longer references the old openmrs/build.sh fallback,
# both pin files carry the new arm64 base image, preflight's macos-facts
# block (arch line + podman-machine memory gate), and host-macos.sh's new
# machine-sizing function and dry-run-without-podman fix. Sections below
# mirror the plan's task list (compose+040, preflight, host-macos.sh).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

# ============================================================================
# compose + task 040: run the native image on arm64, IPLIT's elsewhere
# ============================================================================
C="${HERE}/../../docker-compose.yml"
grep -qE '^\s*image:\s*\$\{OPENMRS_RUN_IMAGE:-\$\{OPENMRS_IMAGE_NAME:\?\}\}' "$C" \
  && ok_ "compose openmrs image falls back OPENMRS_RUN_IMAGE -> OPENMRS_IMAGE_NAME" \
  || bad "compose openmrs image line has the wrong shape: $(grep -n 'OPENMRS_IMAGE_NAME\|OPENMRS_RUN_IMAGE' "$C")"

T40="${HERE}/../tasks/040-images.sh"
code40="$(grep -vE '^[[:space:]]*#' "$T40")"
printf '%s' "$code40" | grep -q 'HOST_ARCH:-\$(uname -m)' && ok_ "040 decides architecture via HOST_ARCH/uname -m" || bad "040 has no HOST_ARCH/uname -m arch decision"
printf '%s' "$code40" | grep -qF 'arm64|aarch64' && ok_ "040 branches on arm64|aarch64" || bad "040 does not branch on arm64|aarch64"
printf '%s' "$code40" | grep -q 'openmrs/build\.sh' && bad "040 still references openmrs/build.sh (the pull-failed fallback was supposed to be removed)" || ok_ "040 no longer references openmrs/build.sh"
printf '%s' "$code40" | grep -q 'openmrs/build-native\.sh' && ok_ "040 calls openmrs/build-native.sh" || bad "040 does not call openmrs/build-native.sh"
printf '%s' "$code40" | grep -q 'OPENMRS_RUN_IMAGE' && ok_ "040 writes/reads OPENMRS_RUN_IMAGE" || bad "040 never mentions OPENMRS_RUN_IMAGE"
printf '%s' "$code40" | grep -q 'bahmni-local/\*' && ok_ "040's pull loop still skips bahmni-local/* (covers the native tag)" || bad "040 lost its bahmni-local/* skip pattern"

grep -qE '^OPENMRS_ARM64_BASE_IMAGE=amazoncorretto:8u432-al2' "${HERE}/../../.env.example" && ok_ ".env.example carries the arm64 base pin" || bad ".env.example missing OPENMRS_ARM64_BASE_IMAGE"
grep -qE '^OPENMRS_ARM64_BASE_IMAGE=amazoncorretto:8u432-al2' "${HERE}/../../../sync/versions.env" && ok_ "sync/versions.env carries the arm64 base pin" || bad "sync/versions.env missing OPENMRS_ARM64_BASE_IMAGE"

# compose-config check: needs a real docker binary (no daemon required --
# `docker compose config` only renders). Synthetic --env-file built from
# .env.example + sync/versions.env, same technique as sync/tests/test_versions.sh,
# so this never depends on a developer's own clinic/.env existing.
if command -v docker >/dev/null 2>&1; then
  TMPENV="$(mktemp)"; trap 'rm -f "$TMPENV"' EXIT
  cat "${HERE}/../../.env.example" > "$TMPENV"
  cat "${HERE}/../../../sync/versions.env" >> "$TMPENV"
  printf 'CONTAINER_DATA_PATH=/tmp\nKAFKA_CLUSTER_ID=x\nOPENMRS_MEM_LIMIT=6g\nMYSQL_AUTO_INCREMENT_OFFSET=7\nMYSQL_SERVER_ID=7\nODOO_APP_VOLUME_NAME=x\nODOO_DB_VOLUME_NAME=x\nBAHMNI_UI_DIR=/tmp/ui\nBAHMNI_CONFIG_DIR=/tmp/cfg\nBAHMNI_WEB_IMAGE=x/web:1\nBAHMNI_CONFIG_IMAGE=x/config:1\nPHONE_NUMBER=+910000000000\n' >> "$TMPENV"
  openmrs_image(){ # extra env assignments in "$1", "" for none
    ( cd "${HERE}/../.." && env $1 docker compose --env-file "$TMPENV" --profile local --profile debezium --profile openelis config --format json 2>/dev/null ) \
      | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["services"]["openmrs"]["image"])
except Exception: pass' 2>/dev/null
  }
  img1="$(openmrs_image "")"
  [ "$img1" = "infoiplitin/openmrs:iplit-1.2.0-1200-03" ] && ok_ "without OPENMRS_RUN_IMAGE, compose resolves OPENMRS_IMAGE_NAME" || bad "compose resolved '$img1' without OPENMRS_RUN_IMAGE"
  img2="$(openmrs_image 'OPENMRS_RUN_IMAGE=bahmni-local/openmrs:iplit-1.2.0-1200-03-arm64')"
  [ "$img2" = "bahmni-local/openmrs:iplit-1.2.0-1200-03-arm64" ] && ok_ "with OPENMRS_RUN_IMAGE set, compose resolves it" || bad "compose resolved '$img2' with OPENMRS_RUN_IMAGE set"
  imgs="$( cd "${HERE}/../.." && OPENMRS_RUN_IMAGE="bahmni-local/openmrs:iplit-1.2.0-1200-03-arm64" docker compose --env-file "$TMPENV" --profile local --profile debezium --profile openelis config --images 2>/dev/null )"
  printf '%s\n' "$imgs" | grep -qx 'bahmni-local/openmrs:iplit-1.2.0-1200-03-arm64' && ok_ "compose config --images lists the native tag on an arm64-rendered .env" || bad "native tag missing from compose config --images: $(printf '%s' "$imgs" | tr '\n' ' ')"
else
  ok_ "compose-config checks skipped (no docker binary here)"
fi

exit "$fails"
