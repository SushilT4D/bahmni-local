#!/usr/bin/env bash
# Checks the Mac before anything is changed: macOS on Apple Silicon, disk, memory, CPUs, free ports, the checkout.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "00 · preflight"

r="$(clinic_residue "${CLINIC_SLUG}")"
[ -n "$r" ] || fail "'${CLINIC_SLUG}' has no site_number in ${CLINICS_JSON}: the operator sets it there, commits, pushes, and this checkout pulls"
[ "$r" = "${BHS_SITE_NUMBER}" ] || fail "sync/clinics.json gives ${CLINIC_SLUG} site_number ${r}, but clinic/.env says BHS_SITE_NUMBER=${BHS_SITE_NUMBER}; sync/clinics.json wins -- fix BHS_SITE_NUMBER in clinic/.env"
c="$(residue_conflicts "${CLINIC_SLUG}" "${BHS_SITE_NUMBER}")"
[ -z "$c" ] || fail "residue ${BHS_SITE_NUMBER} is already held by: $(printf '%s' "$c" | tr '\n' ' ')-- pick a free one in sync/clinics.json"
ok "residue ${BHS_SITE_NUMBER} allocated to ${CLINIC_SLUG}, unique in sync/clinics.json"

# counters:begin
. "${INSTALL_DIR}/state.sh"

preflight_mysql_read(){
  if [ -n "${PREFLIGHT_AUTO_INCREMENT:-}" ]; then
    if [ "$1" = --stride ]; then printf '%s\n' "${PREFLIGHT_STRIDE:-}"; else printf '%s\n' ${PREFLIGHT_AUTO_INCREMENT} | awk -F= -v t="$1" '$1==t {print $2}'; fi
    return 0
  fi

  local p q
  p=bahmni
  if [ "$1" = --stride ]; then q='select @@auto_increment_increment, @@auto_increment_offset'
  else q="$(printf "set session information_schema_stats_expiry=0; select auto_increment from information_schema.tables where table_schema='openmrs' and table_name='%s'" "$1")"; fi
  [ -n "${CT:-}" ] || setup_compose
  printf '%s\n' "$q" | ct exec -i "${p}-bahmni-mysql-1" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N' 2>/dev/null | tail -1 | tr '\t' ' ' || true
}

v="$(node_counters_verdict "$(stamp_get STATE)" "${REPO_DIR}/sync/tables/openmrs.conf" "${BHS_SITE_NUMBER}" preflight_mysql_read)" || fail "$v"
while IFS= read -r l; do
  case "$l" in skip\ *) ok "${l#skip }" ;; ok\ *) ok "${l#ok }" ;; esac
done <<EOF
$v
EOF

# counters:end

# fresh-only:begin
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
    ok "clinic/.env exists: task 020 keeps every value it holds"
  fi
else
  ok "no clinic/.env yet"
fi

# fresh-only:end

[ "${PREFLIGHT_SKIP_HOST:-0}" = 1 ] && { ok "host facts skipped (PREFLIGHT_SKIP_HOST)"; exit 0; }

# Each clinic has a fixed LAN address: 192.168.1.8<site number>.
ifconfig -a 2>/dev/null | grep -q "inet ${LAN_IP} " && ok "LAN address ${LAN_IP}" \
  || warn "this Mac does not have ${LAN_IP} yet, the fixed address of ${CLINIC_SLUG} (site ${BHS_SITE_NUMBER}); dnsmasq is set up for it anyway. Before clinic devices connect: sudo networksetup -setmanualwithdhcprouter <service> ${LAN_IP}"

require_cmd git; require_cmd python3; require_cmd jq "brew install jq / apt install jq"; require_cmd openssl; require_cmd curl; require_cmd gzip

avail_gb="$(( $(df -Pk "${CLINIC_DIR}" | awk 'NR==2{print $4}') / 1048576 ))"
min_gb="${CLINIC_MIN_DISK_GB:-45}"
[ "$avail_gb" -ge "$min_gb" ] && ok "disk free ${avail_gb} GB" || fail "disk free ${avail_gb} GB < ${min_gb} GB (a restored clinic database takes ~11 GB of MySQL; images, Kafka and logs need the rest; CLINIC_MIN_DISK_GB overrides)"
ram_mb="$(( $(sysctl -n hw.memsize) / 1048576 ))"
[ "$ram_mb" -ge 16384 ] && ok "RAM ${ram_mb} MB" || fail "RAM ${ram_mb} MB < 16384 MB: the podman machine alone takes ${MACHINE_MIB} MiB"

# cpu-budget:begin
cpus="${PREFLIGHT_CPUS:-$(sysctl -n hw.ncpu)}"
if [ "${cpus:-1}" -ge 2 ]; then ok "CPUs ${cpus}"; else warn "CPUs ${cpus}: OpenMRS's first boot took 36 min on one vCPU. Task 080 waits 60 min (OPENMRS_BOOT_TIMEOUT_S); two or more CPUs are recommended for a clinic"; fi

# cpu-budget:end
# macos-facts:begin
arch="${PREFLIGHT_ARCH:-$(uname -m)}"
case "$arch" in
  arm64|aarch64) info "arch ${arch}: task 040 builds OpenMRS and Odoo natively; bahmni/atomfeed-console runs emulated" ;;
  *) fail "arch ${arch}: the clinic needs an Apple Silicon Mac (arm64)" ;;
esac

if podman machine list --format '{{.Name}}' 2>/dev/null | grep -q .; then
  got="$(podman machine inspect --format '{{.Resources.CPUs}} {{.Resources.Memory}} {{.Resources.DiskSize}} {{.Rootful}}' 2>/dev/null || true)"
  want="${MACHINE_CPUS} ${MACHINE_MIB} ${MACHINE_DISK_GB} true"
  [ "$got" = "$want" ] && ok "podman machine: ${MACHINE_CPUS} CPU, ${MACHINE_MIB} MiB, ${MACHINE_DISK_GB} GiB, rootful" \
    || fail "podman machine is '${got}' (CPU MiB GiB rootful), clinics run '${want}': podman machine stop; podman machine set --rootful --cpus ${MACHINE_CPUS} --memory ${MACHINE_MIB} --disk-size ${MACHINE_DISK_GB}; podman machine start (a disk only grows)"
else
  ok "no podman machine yet (task 010 creates one)"
fi

# macos-facts:end
published="$(podman ps --format '{{.Names}} {{.Ports}}' 2>/dev/null || true)"
for p in 80 443 5432 8052 8083 9092; do
  holder="$(printf '%s\n' "$published" | awk -v p=":${p}->" 'index($0, p) {print $1; exit}')"
  if [ -n "$holder" ]; then ok "port $p held by this node's container ${holder}"
  elif port_in_use "$p"; then fail "port $p is already in use on this host (netstat -an | grep LISTEN names the holder's address)"
  else ok "port $p free"; fi
done

want_br="${EXPECTED_BRANCH:-${INSTALL_BRANCH}}"
br="$(git -C "${REPO_DIR}" branch --show-current 2>/dev/null || true)"
[ "$br" = "$want_br" ] && ok "checkout on ${want_br} ($(git -C "${REPO_DIR}" rev-parse --short HEAD))" || fail "checkout is on '${br}', expected ${want_br} (EXPECTED_BRANCH overrides, e.g. to install from a branch under test)"
[ -d "${REPO_DIR}/clinic" ] && [ -d "${REPO_DIR}/sync" ] && ok "layout clinic/ sync/ present" || fail "this checkout predates the Stage 4 layout (needs d386445 or newer)"
