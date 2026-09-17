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

# L-005 gate: the seed must be the shape the pinned images expect. The 1.2.0 dump carries
# IPLIT's changeset of 2025-12-23 (the only changeset unique to 1.2.0 among the synced
# tables' history, spec §10.3); an Odoo 16 dump has uom_uom, an Odoo 10 dump product_uom.
# gzip is wrapped in `{ ... || true; }` because grep -m1 closes its read end the instant
# it matches -- on a dump where the match is early and the rest of the stream is still
# large, gzip gets SIGPIPE (exit 141) while still writing. Under `set -o pipefail` (this
# task's shebang) a bare `gzip -dc f | grep -qm1 pat` would then report the WHOLE
# pipeline as failed with rc=141 even though grep found its match. `{ gzip ... || true; }`
# makes the left side of the pipe always report 0, so pipefail sees only grep's status.
{ gzip -dc "${SEED_DIR}/openmrs.sql.gz" 2>/dev/null || true; } | grep -qm1 '20251223-drop-default-value-from-column' \
  || fail "seed openmrs.sql.gz is not an iplit-1.2.0 dump (changeset 20251223-drop-default-value-from-column absent); the hub must be on ${OPENMRS_IMAGE_NAME} before it is dumped"
{ gzip -dc "${SEED_DIR}/odoo.sql.gz" 2>/dev/null || true; } | grep -qm1 -E 'CREATE TABLE (public\.)?uom_uom\b' \
  || fail "seed odoo.sql.gz is not an Odoo 16 dump (no uom_uom)"
ok "seed shape: openmrs iplit-1.2.0, odoo 16"

[ "${PREFLIGHT_SKIP_HOST:-0}" = 1 ] && { ok "host facts skipped (PREFLIGHT_SKIP_HOST)"; exit 0; }

# 4. host facts
require_cmd git; require_cmd python3; require_cmd jq "brew install jq / apt install jq"; require_cmd openssl; require_cmd curl; require_cmd gzip
# df -Pk is POSIX-portable; the BSD/macOS-only `df -g` aborts this task under
# set -e -o pipefail on Linux (the substitution fails before the fallback runs,
# with NO FAIL line) -- F-068, the first live Linux run. -P stops a long device
# name from wrapping and misaligning $4.
avail_gb="$(( $(df -Pk "${CLINIC_DIR}" | awk 'NR==2{print $4}') / 1048576 ))"
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
