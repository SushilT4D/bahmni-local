#!/usr/bin/env bash
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

# 3. the seed
for f in openmrs.sql.gz odoo.sql.gz openelis.sql.gz; do
  [ -s "${SEED_DIR}/$f" ] || fail "seed file missing or empty: ${SEED_DIR}/$f"
  gzip -t "${SEED_DIR}/$f" 2>/dev/null || fail "seed file is not valid gzip: ${SEED_DIR}/$f"
done
ok "seed: three dumps present and gzip-valid ($(du -sh "${SEED_DIR}" | cut -f1))"

# Seed-shape gate: the seed must be the shape the pinned images expect. The 1.2.0 dump carries
# IPLIT's changeset 20251223-drop-default-value-from-column (the only changeset unique to
# 1.2.0 among the synced tables' history); an Odoo 16 dump has uom_uom, an Odoo 10 dump product_uom.
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

# Address-table gate: a seed dumped before the hub strode village_village and
# res_partner_attributes would hand a clinic built from it ids the hub also
# uses (a clinic-minted village_village row can stop a sink).
# Checked here, before a single byte of the seed reaches a database.
#
# pg_dump emits a serial id's owning sequence in one of two shapes: a plain
# "CREATE SEQUENCE ... INCREMENT BY n" a couple of lines after the table, or,
# for an identity column, a multi-line "ALTER TABLE ... ADD GENERATED ... AS
# IDENTITY ( SEQUENCE NAME ... INCREMENT BY n ... )". Both name the sequence
# on one line and carry INCREMENT BY within the next handful -- read the ~8
# lines following the first line that names it and take the first INCREMENT
# BY found. Streamed straight from the gz (one gzip -dc | awk pass covering
# both tables), never unpacked to disk -- the real dump is 7.6 MB.
address_seq_out="$(gzip -dc "${SEED_DIR}/odoo.sql.gz" 2>/dev/null | awk '
  function chk(tbl) { if ($0 ~ ("CREATE TABLE (public\\.)?" tbl "[[:space:](]")) print "TABLE_FOUND=" tbl }
  { chk("village_village"); chk("res_partner_attributes") }
  index($0, "village_village_id_seq") > 0 && w1 == 0 { w1 = 9 }
  w1 > 0 {
    if (match($0, /INCREMENT BY [0-9]+/)) { n = substr($0, RSTART, RLENGTH); sub(/INCREMENT BY /, "", n); print "INC=village_village_id_seq=" n; w1 = 0 }
    else w1--
  }
  index($0, "res_partner_attributes_id_seq") > 0 && w2 == 0 { w2 = 9 }
  w2 > 0 {
    if (match($0, /INCREMENT BY [0-9]+/)) { n = substr($0, RSTART, RLENGTH); sub(/INCREMENT BY /, "", n); print "INC=res_partner_attributes_id_seq=" n; w2 = 0 }
    else w2--
  }
')" || true
address_seq_check(){ # TABLE SEQ
  local table="$1" seq="$2" tfound inc
  # `|| true` on each read: grep exits 1 on zero matches, a legitimate result
  # here (a wrong-shape seed), not an error -- under this task's set -e -o
  # pipefail a bare grep -c/grep|head|cut miss would otherwise abort through
  # the generic ERR trap instead of this function's own named fail() message.
  tfound="$(printf '%s\n' "${address_seq_out}" | grep -c "^TABLE_FOUND=${table}\$" || true)"
  inc="$(printf '%s\n' "${address_seq_out}" | grep "^INC=${seq}=" | head -1 | cut -d= -f3 || true)"
  [ "${tfound:-0}" -ge 1 ] \
    || fail "seed odoo.sql.gz has no ${table} table -- wrong-shape seed (this table's ids are partitioned across the fleet); take a fresh seed with skills/install-clinic.sh seed"
  [ "$inc" = 10 ] \
    || fail "seed odoo.sql.gz: ${seq} is not INCREMENT BY 10 (found ${inc:-none}) -- this seed was dumped before the hub partitioned its address and customer-attribute ids; a clinic built from it would hand out ${table} ids the hub also uses; take a fresh seed with skills/install-clinic.sh seed"
}
address_seq_check village_village village_village_id_seq
address_seq_check res_partner_attributes res_partner_attributes_id_seq
ok "seed shape: village_village, res_partner_attributes sequences step 10"

[ "${PREFLIGHT_SKIP_HOST:-0}" = 1 ] && { ok "host facts skipped (PREFLIGHT_SKIP_HOST)"; exit 0; }

# 4. host facts
require_cmd git; require_cmd python3; require_cmd jq "brew install jq / apt install jq"; require_cmd openssl; require_cmd curl; require_cmd gzip
# df -Pk is POSIX-portable; the BSD/macOS-only `df -g` aborts this task under
# set -e -o pipefail on Linux (the substitution fails before the fallback runs,
# with NO FAIL line). -P stops a long device
# name from wrapping and misaligning $4.
avail_gb="$(( $(df -Pk "${CLINIC_DIR}" | awk 'NR==2{print $4}') / 1048576 ))"
[ "$avail_gb" -ge 60 ] && ok "disk free ${avail_gb} GB" || fail "disk free ${avail_gb} GB < 60 GB (the seed restores to ~11 GB of MySQL, Kafka and logs need the rest)"
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
for p in 8081 9443 9444 5433 8052 8083 9092; do
  if (command -v lsof >/dev/null && lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1) || (command -v ss >/dev/null && ss -ltn 2>/dev/null | grep -q ":$p "); then
    fail "port $p is already in use on this host"
  fi
done
ok "ports 8081 9443 9444 5433 8052 8083 9092 free"
br="$(git -C "${REPO_DIR}" branch --show-current 2>/dev/null || true)"
[ "$br" = "feat/bahmni-kraft" ] && ok "checkout on feat/bahmni-kraft ($(git -C "${REPO_DIR}" rev-parse --short HEAD))" || fail "checkout is on '${br}', expected feat/bahmni-kraft"
[ -d "${REPO_DIR}/clinic" ] && [ -d "${REPO_DIR}/sync" ] && [ -d "${REPO_DIR}/cloud" ] && ok "layout clinic/ cloud/ sync/ present" || fail "this checkout predates the Stage 4 layout (needs d386445 or newer)"
