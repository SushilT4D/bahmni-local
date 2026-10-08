#!/usr/bin/env bash
# phase: install
# Everything that can refuse, refuses here, before a machine is touched.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "00 · preflight"

# 1. identity is allocated, and only to us (a node with no residue cannot join)
r="$(ledger_residue "${CLINIC_SLUG}")"
[ -n "$r" ] || fail "no row for '${CLINIC_SLUG}' in ${LEDGER}. the operator allocates first (skills/install-clinic.sh allocate ${CLINIC_SLUG} ${RESIDUE} -- the row is ${CLINIC_SLUG}:${RESIDUE}), commits, pushes, and this checkout pulls"
[ "$r" = "${RESIDUE}" ] || fail "ledger says ${CLINIC_SLUG}:${r} but the answers say RESIDUE=${RESIDUE}; the ledger wins -- fix the answers"
c="$(ledger_conflicts "${CLINIC_SLUG}" "${RESIDUE}")"
[ -z "$c" ] || fail "residue ${RESIDUE} is already held by: $(printf '%s' "$c" | tr '\n' ' ')-- pick a free one in sync/clinics.txt"
ok "residue ${RESIDUE} allocated to ${CLINIC_SLUG}, unique in the ledger"
refuse_inherited_alias "${LOCAL_CLUSTER_ALIAS}" "${CLINIC_SLUG}"

# 1b. a machine already in service: MySQL strides on this residue and each
# floored id counter is still at or above its floor (a restored database or a
# reset counter would hand out ids that rows written elsewhere already carry).
# A machine not in service yet has no floors, and the line says so.
# counters:begin
. "${INSTALL_DIR}/state.sh"
# TABLE -> its AUTO_INCREMENT; --stride -> "increment offset".
# PREFLIGHT_AUTO_INCREMENT ("table=n ...") and PREFLIGHT_STRIDE stand in for MySQL.
preflight_mysql_read(){
  if [ -n "${PREFLIGHT_AUTO_INCREMENT:-}" ]; then
    if [ "$1" = --stride ]; then printf '%s\n' "${PREFLIGHT_STRIDE:-}"; else printf '%s\n' ${PREFLIGHT_AUTO_INCREMENT} | awk -F= -v t="$1" '$1==t {print $2}'; fi
    return 0
  fi
  local p q
  p="$(env_get "${CLINIC_DIR}/.env" COMPOSE_PROJECT_NAME 2>/dev/null || true)"
  if [ "$1" = --stride ]; then q='select @@auto_increment_increment, @@auto_increment_offset'
  else q="$(printf "set session information_schema_stats_expiry=0; select auto_increment from information_schema.tables where table_schema='openmrs' and table_name='%s'" "$1")"; fi
  [ -n "${CT:-}" ] || setup_compose
  printf '%s\n' "$q" | ct exec -i "${p}-bahmni-mysql-1" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N' 2>/dev/null | tail -1 | tr '\t' ' ' || true
}
v="$(node_counters_verdict "$(stamp_get STATE)" "${REPO_DIR}/sync/local/tables.conf" "${RESIDUE}" preflight_mysql_read)" || fail "$v"
while IFS= read -r l; do
  case "$l" in skip\ *) ok "${l#skip }" ;; ok\ *) ok "${l#ok }" ;; esac
done <<EOF
$v
EOF
# counters:end

# 2. fresh install only
# fresh-only:begin
# A dry run renders a real clinic/.env (later tasks read it to say what they
# would do), and a real run that follows would refuse it as "already exists".
# Task 020 stamps a dry-run render on its first
# line; a stamped file is a leftover, not a live node, so a real run moves it
# aside -- never deletes it -- and carries on. An unstamped .env is a live
# node's and is still refused.
if [ -e "${CLINIC_DIR}/.env" ]; then
  if head -n 1 "${CLINIC_DIR}/.env" | grep -q '^# DRY-RUN RENDER'; then
    if [ "${DRY}" = 1 ]; then
      info "clinic/.env is a dry-run leftover; this dry run will render over it"
    else
      aside="${CLINIC_DIR}/.env.dryrun.$(date -u +%Y%m%dT%H%M%SZ)"
      mv "${CLINIC_DIR}/.env" "$aside"
      info "clinic/.env was a dry-run leftover; moved aside to ${aside}"
    fi
  else
    fail "${CLINIC_DIR}/.env already exists -- this installer does fresh installs only; remove it consciously if this node is being rebuilt"
  fi
fi
ok "no live clinic/.env yet"
# fresh-only:end

[ "${PREFLIGHT_SKIP_HOST:-0}" = 1 ] && { ok "host facts skipped (PREFLIGHT_SKIP_HOST)"; exit 0; }

# 4. host facts
require_cmd git; require_cmd python3; require_cmd jq "brew install jq / apt install jq"; require_cmd openssl; require_cmd curl; require_cmd gzip
# df -Pk is POSIX-portable; the BSD/macOS-only `df -g` aborts this task under
# set -e -o pipefail on Linux (the substitution fails before the fallback runs,
# with NO FAIL line). -P stops a long device
# name from wrapping and misaligning $4.
avail_gb="$(( $(df -Pk "${CLINIC_DIR}" | awk 'NR==2{print $4}') / 1048576 ))"
min_gb="${CLINIC_MIN_DISK_GB:-45}"
[ "$avail_gb" -ge "$min_gb" ] && ok "disk free ${avail_gb} GB" || fail "disk free ${avail_gb} GB < ${min_gb} GB (a restored clinic database takes ~11 GB of MySQL; images, Kafka and logs need the rest; CLINIC_MIN_DISK_GB overrides)"
if [ "${PLATFORM}" = macos ]; then ram_mb="$(( $(sysctl -n hw.memsize) / 1048576 ))"; else ram_mb="$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)"; fi
[ "$ram_mb" -ge 8192 ] && ok "RAM ${ram_mb} MB" || fail "RAM ${ram_mb} MB < 8192 MB"
# cpu-budget:begin
# A warning, not a refusal: one CPU installs, but OpenMRS's first boot took
# 36 min on manpur's 1-vCPU VM against 7 min on the hub's four.
if [ -n "${PREFLIGHT_CPUS:-}" ]; then cpus="${PREFLIGHT_CPUS}"; elif [ "${PLATFORM}" = macos ]; then cpus="$(sysctl -n hw.ncpu)"; else cpus="$(nproc 2>/dev/null || printf 1)"; fi
if [ "${cpus:-1}" -ge 2 ]; then ok "CPUs ${cpus}"; else warn "CPUs ${cpus}: OpenMRS's first boot took 36 min on one vCPU. Task 080 waits 60 min (OPENMRS_BOOT_TIMEOUT_S); two or more CPUs are recommended for a clinic"; fi
# cpu-budget:end
# macos-facts:begin
# Say what this host is before anything is pulled. IPLIT's OpenMRS image is
# linux/amd64 only: 26,153 ms emulated vs 2,394/2,330 ms native for bare
# Tomcat+WAR, measured on an Apple M5 Pro under podman -- task 040
# rebuilds it natively on arm64. bahmni/odoo-16 and bahmni/atomfeed-console
# have no arm64 build and run emulated regardless (Odoo 10 did the same for
# three weeks on Ghated; usable, not fast).
arch="${PREFLIGHT_ARCH:-$(uname -m)}"
case "$arch" in
  arm64|aarch64)
    info "arch ${arch}: OpenMRS will be rebuilt natively by task 040 (IPLIT's image is amd64-only: 26 s emulated vs 2.3 s native for bare Tomcat, measured on Ghated). These images have no arm64 build and will run emulated: bahmni/odoo-16, bahmni/atomfeed-console"
    ;;
  *) ok "arch ${arch}" ;;
esac
# The podman machine's own memory, not the DRY-safe defaults task 010 uses to
# CREATE one: a machine that already exists and is undersized is a live
# problem today, not a future one -- checked here, before anything is pulled
# into it. No machine yet is fine (task 010 creates one, sized by
# host-macos.sh's own rule) and is not a FAIL.
if [ "${PLATFORM}" = macos ] && [ "$(detect_runtime)" = podman ]; then
  machine_mib="${PREFLIGHT_MACHINE_MIB:-}"
  [ -n "$machine_mib" ] || machine_mib="$(podman machine inspect --format '{{.Resources.Memory}}' 2>/dev/null || true)"
  if [ -n "${machine_mib:-}" ]; then
    host_mib="${PREFLIGHT_HOST_MIB:-}"
    [ -n "$host_mib" ] || host_mib="$(( $(sysctl -n hw.memsize) / 1048576 ))"
    [ "$machine_mib" -ge 10240 ] || fail "podman machine memory ${machine_mib} MiB < 10240 MiB -- the stack needs 10 GiB; podman machine set --memory 10240 (or more), then restart the machine"
    ok "podman machine memory ${machine_mib} MiB"
    pct=$(( machine_mib * 100 / host_mib ))
    if [ "$pct" -gt 55 ]; then
      warn "podman machine memory ${machine_mib} MiB is ${pct}% of host RAM (${host_mib} MiB), over the 55% rule: a 15 GB VM on an 18 GB Mac made macOS swap fill the disk and the VM was killed four times in a day"
    fi
  else
    ok "no podman machine yet (task 010 creates one)"
  fi
fi
# macos-facts:end
for p in 80 443 5433 8052 8083 9092; do
  if (command -v lsof >/dev/null && lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1) || (command -v ss >/dev/null && ss -ltn 2>/dev/null | grep -q ":$p "); then
    fail "port $p is already in use on this host"
  fi
done
ok "ports 80 443 5433 8052 8083 9092 free"
want_br="${EXPECTED_BRANCH:-${INSTALL_BRANCH}}"
br="$(git -C "${REPO_DIR}" branch --show-current 2>/dev/null || true)"
[ "$br" = "$want_br" ] && ok "checkout on ${want_br} ($(git -C "${REPO_DIR}" rev-parse --short HEAD))" || fail "checkout is on '${br}', expected ${want_br} (EXPECTED_BRANCH overrides, e.g. to install from a branch under test)"
[ -d "${REPO_DIR}/clinic" ] && [ -d "${REPO_DIR}/sync" ] && ok "layout clinic/ sync/ present" || fail "this checkout predates the Stage 4 layout (needs d386445 or newer)"
