#!/usr/bin/env bash
# Gets every image: builds OpenMRS, Odoo, odoo-connect, the proxy and systemdate locally, pulls the rest, fetches the Connect jars.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "40 · images + jars"
[ "${DRY}" = 1 ] && { info "would: pull every image in compose config, build bahmni-local/proxy, systemdate, odoo-16 and odoo-connect, fetch the scripting jars"; exit 0; }
setup_compose
cd "${CLINIC_DIR}"
E="${CLINIC_DIR}/.env"
omrs="$(env_get "$E" OPENMRS_IMAGE_NAME)"

info "rebuilding OpenMRS natively -- ${omrs} is amd64-only and would run emulated"
build_log="$(mktemp)"
if bash "${CLINIC_DIR}/openmrs/build.sh" >"${build_log}" 2>&1; then
  cat "${build_log}"
else
  cat "${build_log}" >&2; rm -f "${build_log}"
  fail "openmrs/build.sh failed (its FAIL line is above)"
fi

run_tag="$(sed -n 's/^image=//p' "${build_log}" | tail -1)"; rm -f "${build_log}"
[ -n "$run_tag" ] || fail "openmrs/build.sh printed no image=<tag> line"
env_put "$E" OPENMRS_RUN_IMAGE "$run_tag"
ok "openmrs image: native ${run_tag}, built from ${omrs}"

if ct image inspect "bahmni-local/proxy:$(env_get "$E" PROXY_IMAGE_TAG)" >/dev/null 2>&1; then skip "proxy image built"; else bash proxy/build.sh; fi
if ct image inspect bahmni-local/systemdate:1.0 >/dev/null 2>&1; then skip "systemdate image built"; else bash systemdate/build.sh; fi

odoo_img="$(env_get "$E" ODOO_LOCAL_IMAGE)"
bash odoo/build.sh || fail "the Odoo image ${odoo_img} could not be built (reason above)"
ok "odoo image ${odoo_img}"

bash odoo-connect/build.sh || fail "the odoo-connect image could not be built (reason above)"
ok "odoo-connect image bahmni-local/odoo-connect:$(env_get "$E" ODOO_CONNECT_IMAGE_TAG)"

for img in $(compose_images 2>/dev/null | sort -u); do
  case "$img" in bahmni-local/*) continue ;; esac
  ct image inspect "$img" >/dev/null 2>&1 && continue
  for attempt in 1 2 3; do
    if pull_image "$img"; then break; fi
    warn "pull ${img} attempt ${attempt}/3 failed; retrying in 10s"; sleep 10
  done
done

missing=""
for img in $(compose_images 2>/dev/null | sort -u); do ct image inspect "$img" >/dev/null 2>&1 || missing="$missing $img"; done
[ -z "$missing" ] && ok "every image present ($(compose_images 2>/dev/null | sort -u | wc -l | tr -d ' '))" || fail "images missing:${missing}"

J="${CLINIC_DIR}/config/kafka-connect"
GV="$(env_get "$E" GROOVY_VERSION)"
DSV="$(env_get "$E" DEBEZIUM_SCRIPTING_VERSION)"
jars="$J/ext/groovy-${GV}.jar $J/ext/groovy-jsr223-${GV}.jar $J/ext/debezium-scripting-${DSV}.jar"
jars_ok(){ local j; for j in $jars; do [ -f "$j" ] && [ -s "$j" ] || return 1; done; }
if jars_ok; then skip "scripting jars present"; else
  for j in $jars; do [ ! -d "$j" ] || rmdir "$j" || fail "${j} is a non-empty directory where the jar belongs"; done   # podman makes an empty directory for a bind source that is missing
  bash "$J/ext/fetch-scripting-jars.sh" >/dev/null || fail "the scripting jars could not be fetched from Maven Central"
  ! ct container exists kafka-connect || { ct rm -f kafka-connect >/dev/null && info "kafka-connect removed: it mounted the jars' old paths; task 090 starts it again"; }
fi
jars_ok && ok "jars: 3 scripting" || fail "scripting jars missing or empty after the fetch: ${jars}"
