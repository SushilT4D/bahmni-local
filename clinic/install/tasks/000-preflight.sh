#!/usr/bin/env bash
# Everything that can refuse, refuses here, before a machine is touched.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "00 · preflight"

# 1. identity is allocated, and only to us (TC-S-69: a node with no residue cannot join)
r="$(ledger_residue "${CLINIC_SLUG}")"
[ -n "$r" ] || fail "no row for '${CLINIC_SLUG}' in ${LEDGER}. the operator allocates first (skills/install-clinic.sh allocate ${CLINIC_SLUG} ${RESIDUE} -- the row is ${CLINIC_SLUG}:${RESIDUE}), commits, pushes, and this checkout pulls"
[ "$r" = "${RESIDUE}" ] || fail "ledger says ${CLINIC_SLUG}:${r} but the answers say RESIDUE=${RESIDUE}; the ledger wins -- fix the answers"
c="$(ledger_conflicts "${CLINIC_SLUG}" "${RESIDUE}")"
[ -z "$c" ] || fail "residue ${RESIDUE} is already held by: $(printf '%s' "$c" | tr '\n' ' ')-- pick a free one (docs/sync-core/residues.txt)"
ok "residue ${RESIDUE} allocated to ${CLINIC_SLUG}, unique in the ledger"
refuse_inherited_alias "${LOCAL_CLUSTER_ALIAS}"

# 2. fresh install only
[ ! -e "${CLINIC_DIR}/.env" ] || fail "${CLINIC_DIR}/.env already exists -- this installer does fresh installs only; remove it consciously if this node is being rebuilt"
ok "no clinic/.env yet"

# 3. the seed
for f in openmrs.sql.gz odoo.sql.gz openelis.sql.gz; do
  [ -s "${SEED_DIR}/$f" ] || fail "seed file missing or empty: ${SEED_DIR}/$f"
  gzip -t "${SEED_DIR}/$f" 2>/dev/null || fail "seed file is not valid gzip: ${SEED_DIR}/$f"
done
ok "seed: three dumps present and gzip-valid ($(du -sh "${SEED_DIR}" | cut -f1))"

[ "${PREFLIGHT_SKIP_HOST:-0}" = 1 ] && { ok "host facts skipped (PREFLIGHT_SKIP_HOST)"; exit 0; }

# 4. host facts
require_cmd git; require_cmd python3; require_cmd jq "brew install jq / apt install jq"; require_cmd openssl; require_cmd curl; require_cmd gzip
avail_gb="$(df -g "${CLINIC_DIR}" 2>/dev/null | awk 'NR==2{print $4}')"
[ -n "$avail_gb" ] || avail_gb="$(( $(df -k "${CLINIC_DIR}" | awk 'NR==2{print $4}') / 1048576 ))"
[ "$avail_gb" -ge 60 ] && ok "disk free ${avail_gb} GB" || fail "disk free ${avail_gb} GB < 60 GB (the seed restores to ~11 GB of MySQL, Kafka and logs need the rest)"
if [ "${PLATFORM}" = macos ]; then ram_mb="$(( $(sysctl -n hw.memsize) / 1048576 ))"; else ram_mb="$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)"; fi
[ "$ram_mb" -ge 8192 ] && ok "RAM ${ram_mb} MB" || fail "RAM ${ram_mb} MB < 8192 MB"
for p in 8081 9443 9444 5433 8052 8083 9092; do
  if (command -v lsof >/dev/null && lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1) || (command -v ss >/dev/null && ss -ltn 2>/dev/null | grep -q ":$p "); then
    fail "port $p is already in use on this host"
  fi
done
ok "ports 8081 9443 9444 5433 8052 8083 9092 free"
br="$(git -C "${REPO_DIR}" branch --show-current 2>/dev/null || true)"
[ "$br" = "feat/bahmni-kraft" ] && ok "checkout on feat/bahmni-kraft ($(git -C "${REPO_DIR}" rev-parse --short HEAD))" || fail "checkout is on '${br}', expected feat/bahmni-kraft"
[ -d "${REPO_DIR}/clinic" ] && [ -d "${REPO_DIR}/sync" ] && [ -d "${REPO_DIR}/cloud" ] && ok "layout clinic/ cloud/ sync/ present" || fail "this checkout predates the Stage 4 layout (needs d386445 or newer)"
