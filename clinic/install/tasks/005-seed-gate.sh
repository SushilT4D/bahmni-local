#!/usr/bin/env bash
# Checks the seed folder (age, checksums, versions, id floors) and the machine state before anything is installed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "${INSTALL_DIR}/state.sh"
begin_task "05 · seed gate"
refuse(){ printf '\n  >>> %s\n\n' "$1" >&2; fail "$1"; }
st="$(stamp_get STATE)"
v="$(stamp_gate_verdict "$st" "$(stamp_get SYNC_STARTED)")" || refuse "$v"
ok "machine state ${st}"
v="$(seed_manifest_verdict "${SEED_DIR}" "$(date +%s)" "${SEED_MAX_AGE_DAYS:-6}")" || refuse "$v"
taken="${v#ok }"
ok "seed taken ${taken} (limit ${SEED_MAX_AGE_DAYS:-6} days); three dumps match their checksums"

v="$(seed_floors_verdict "${SEED_DIR}/manifest.env" "${REPO_DIR}/sync/tables/openmrs.conf")" || refuse "$v"
floors="${v#ok}"
ok "id floors from the seed:${floors}"
v="$(seed_shape_verdict "${SEED_DIR}")" || refuse "$v"
ok "${v#ok }"

v="$(seed_provenance_verdict "${SEED_DIR}")" || refuse "$v"
ok "provenance record: ${v#ok }"
if [ "$st" = SEEDING ]; then ok "an earlier install stopped part-way; it is redone from the start"; fi

[ "${DRY}" = 1 ] && { info "would: mark this machine SEEDING"; exit 0; }
stamp_put STATE SEEDING; stamp_put SEEDING_AT "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; stamp_put SEED_TAKEN_AT "$taken"

for tf in $floors; do stamp_put "FLOOR_$(printf '%s' "${tf%%=*}" | tr '[:lower:]' '[:upper:]')" "${tf#*=}"; done

prov="$(env_get "${SEED_DIR}/manifest.env" PROVENANCE)"
cp "${SEED_DIR}/${prov}" "${PROVENANCE_COPY}" && chmod 644 "${PROVENANCE_COPY}" || fail "could not keep a copy of the seed's provenance record at ${PROVENANCE_COPY}"
stamp_put PROVENANCE_SHA "$(sha256_of "${PROVENANCE_COPY}")"
ok "machine state SEEDING"
