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

# ============================================================================
# preflight (000): say what this host is, before anything is pulled
# ============================================================================
T00="${HERE}/../tasks/000-preflight.sh"
LIBSH="${HERE}/../lib.sh"
blk="$(sed -n '/# macos-facts:begin/,/# macos-facts:end/p' "$T00")"
[ -n "$blk" ] || bad "000 has no macos-facts block"
# A restricted PATH (no /usr/local/bin, /opt/homebrew/bin, ...) so a real
# podman on the machine running this test can never leak into the "no
# machine" case below; PREFLIGHT_MACHINE_MIB/PREFLIGHT_HOST_MIB override the
# rest, the same way PREFLIGHT_CPUS stands in for the host in test_boot_budget.sh.
runf(){ # PLATFORM RUNTIME ARCH MACHINE_MIB HOST_MIB
  env -i PATH="/usr/bin:/bin:/usr/sbin:/sbin" PLATFORM="$1" RUNTIME="$2" PREFLIGHT_ARCH="$3" PREFLIGHT_MACHINE_MIB="$4" PREFLIGHT_HOST_MIB="$5" bash -c ". '${LIBSH}'; ${blk}" 2>&1
}

out="$(runf linux docker arm64 '' '')"
printf '%s' "$out" | grep -q 'bahmni/odoo-16' && printf '%s' "$out" | grep -q 'bahmni/atomfeed-console' && ok_ "arm64 names the two emulated images" || bad "arm64 output missing emulated image names: $out"
printf '%s' "$out" | grep -qi 'rebuilt natively' && ok_ "arm64 names the native-build line" || bad "arm64 output missing the native-build line: $out"

out="$(runf linux docker x86_64 '' '')"
printf '%s' "$out" | grep -q 'bahmni/odoo-16' && bad "x86_64 output names emulated images" || ok_ "x86_64 does not name emulated images"
printf '%s' "$out" | grep -qi 'rebuilt natively' && bad "x86_64 output names the native-build line" || ok_ "x86_64 does not name the native-build line"

out="$(runf macos podman x86_64 8192 24576)"; rc=$?
[ "$rc" -ne 0 ] && ok_ "podman machine 8192 MiB < 10240: FAIL" || bad "machine 8192 MiB did not fail: $out"
printf '%s' "$out" | grep -qi '10 GiB\|10240' && ok_ "FAIL names the 10 GiB floor" || bad "FAIL message unclear: $out"

out="$(runf macos podman x86_64 12288 24576)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "machine 12288 MiB / host 24576 MiB: passes" || bad "machine 12288/host 24576 failed: $out"
printf '%s' "$out" | grep -q 'WARN' && bad "machine 12288/host 24576 warns" || ok_ "machine 12288/host 24576: no WARN"

out="$(runf macos podman x86_64 15360 18432)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "machine 15360 MiB / host 18432 MiB: passes (a warning, not a refusal)" || bad "machine 15360/host 18432 failed: $out"
printf '%s' "$out" | grep -q 'WARN' && printf '%s' "$out" | grep -q '55%' && ok_ "machine 15360/host 18432: WARN naming 55%" || bad "no WARN naming 55%: $out"

out="$(runf macos podman x86_64 '' 18432)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "no machine yet: no FAIL" || bad "no machine yet still failed: $out"
printf '%s' "$out" | grep -qi 'no podman machine yet' && ok_ "no-machine case is named explicitly" || bad "no-machine output unclear: $out"

# ============================================================================
# host-macos.sh: size a NEW machine from host RAM; never resize an existing
# one; dry run without podman prints no FAILED line
# ============================================================================
HM="${HERE}/../host-macos.sh"
mem_of(){ ( . "$HM"; podman_machine_size "$1" 8; printf '%s' "$MACHINE_MIB" ); }
cpu_of(){ ( . "$HM"; podman_machine_size 24576 "$1"; printf '%s' "$MACHINE_CPUS" ); }
[ "$(mem_of 18432)" = 9216 ] && ok_ "sizing: 18432 MiB host -> 9216 MiB machine (below the 10 GiB floor)" || bad "sizing 18432 gave $(mem_of 18432)"
[ "$(mem_of 24576)" = 12288 ] && ok_ "sizing: 24576 MiB host -> 12288 MiB machine" || bad "sizing 24576 gave $(mem_of 24576)"
[ "$(mem_of 65536)" = 12288 ] && ok_ "sizing: 65536 MiB host -> 12288 MiB machine (capped)" || bad "sizing 65536 gave $(mem_of 65536)"
[ "$(cpu_of 4)" = 2 ] && ok_ "sizing: 4 host cpus -> 2 machine cpus" || bad "sizing cpus=4 gave $(cpu_of 4)"
[ "$(cpu_of 10)" = 8 ] && ok_ "sizing: 10 host cpus -> 8 machine cpus" || bad "sizing cpus=10 gave $(cpu_of 10)"
[ "$(cpu_of 15)" = 8 ] && ok_ "sizing: 15 host cpus -> 8 machine cpus" || bad "sizing cpus=15 gave $(cpu_of 15)"

# A dry run on a Mac with no podman on PATH must never crash with the rc=127
# "podman machine inspect" FAILED line (seen 2026-09-21). PATH keeps Homebrew's
# own directory (so the install-Homebrew branch, which shells out to curl even
# under DRY to build its would-print string, is skipped outright) but excludes
# anywhere podman could live; HOME is a scratch dir so a fresh LaunchAgent
# plist check never touches the real developer machine; HOST_MIB/HOST_CPUS are
# overridden well above the 10 GiB floor so this exercises the rc=127 fix, not
# the (unrelated, legitimate) undersized-host refusal tested above.
TMPHM="$(mktemp -d)"; mkdir -p "$TMPHM/clinic"
brewbin=""; [ -x /opt/homebrew/bin/brew ] && brewbin="/opt/homebrew/bin"; [ -x /usr/local/bin/brew ] && brewbin="${brewbin:+$brewbin:}/usr/local/bin"
out="$(env -i PATH="${brewbin:+$brewbin:}/usr/bin:/bin:/usr/sbin:/sbin" HOME="$TMPHM" DRY=1 HOST_MIB=24576 HOST_CPUS=8 \
  CLINIC_DIR="$TMPHM/clinic" INSTALL_DIR="${HERE}/.." \
  bash -c ". '${HERE}/../lib.sh'; . '${HM}'; host_macos" 2>&1)"; rc=$?
rm -rf "$TMPHM"
printf '%s' "$out" | grep -q 'FAILED' && bad "dry run without podman printed a FAILED line: $out" || ok_ "dry run without podman prints no FAILED line"
[ "$rc" -eq 0 ] && ok_ "dry run without podman exits 0" || bad "dry run without podman exits $rc: $out"

exit "$fails"
