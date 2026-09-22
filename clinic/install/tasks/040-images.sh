#!/usr/bin/env bash
# Images the stack needs before anything starts: pulled ones, the two built
# locally, the OpenMRS fallback for podman, and the Connect plugin jars.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "40 · images + jars"
[ "${DRY}" = 1 ] && { info "would: pull every image in compose config, build bahmni-local/proxy and systemdate, fetch the scripting jars"; exit 0; }
setup_compose; mk_podman_shim
cd "${CLINIC_DIR}"
E="${CLINIC_DIR}/.env"
omrs="$(env_get "$E" OPENMRS_IMAGE_NAME)"
# OpenMRS: IPLIT's image is linux/amd64 only. On an arm64 host it is rebuilt
# natively (openmrs/build-native.sh -- 2.3s bare Tomcat+WAR on Ghated vs 26s
# emulated, ~11x; the PREVIOUS pinned image took 51 minutes under QEMU with
# modules loading) and the result is written to OPENMRS_RUN_IMAGE, which
# docker-compose.yml prefers over OPENMRS_IMAGE_NAME. x86 clinics are
# untouched: OPENMRS_IMAGE_NAME runs as-is, pulled like every other image.
# HOST_ARCH overrides `uname -m` for tests.
arch="${HOST_ARCH:-$(uname -m)}"
case "$arch" in
  arm64|aarch64)
    info "arm64 host (${arch}): rebuilding OpenMRS natively -- ${omrs} is amd64-only and would run emulated"
    build_log="$(mktemp)"
    if bash "${CLINIC_DIR}/openmrs/build-native.sh" >"${build_log}" 2>&1; then
      cat "${build_log}"
    else
      cat "${build_log}" >&2; rm -f "${build_log}"
      fail "openmrs/build-native.sh failed (its FAIL line is above)"
    fi
    run_tag="$(sed -n 's/^image=//p' "${build_log}" | tail -1)"; rm -f "${build_log}"
    [ -n "$run_tag" ] || fail "openmrs/build-native.sh printed no image=<tag> line"
    env_put "$E" OPENMRS_RUN_IMAGE "$run_tag"
    ok "openmrs image: native ${run_tag}, built from ${omrs}"
    ;;
  *)
    # A stale OPENMRS_RUN_IMAGE (a node that was ever installed on arm64, or a
    # hand-edited .env) would silently run the wrong-architecture image on this
    # host -- refused rather than ignored, since docker-compose.yml prefers it.
    stale="$(env_get "$E" OPENMRS_RUN_IMAGE)"
    [ -z "$stale" ] || fail "clinic/.env carries OPENMRS_RUN_IMAGE=${stale} on a non-arm64 host (${arch}) -- remove the key (it is only ever set by task 040 on arm64)"
    if ct image inspect "$omrs" >/dev/null 2>&1; then skip "openmrs image present"; else
      ct pull "$omrs" >/dev/null 2>&1 || fail "openmrs image ${omrs} could not be pulled"
    fi
    ct image inspect "$omrs" >/dev/null 2>&1 && ok "openmrs image ${omrs}" || fail "openmrs image ${omrs} unavailable"
    ;;
esac
# the two local builds (their scripts source .env from CWD and call podman by name)
if ct image inspect "bahmni-local/proxy:$(env_get "$E" PROXY_IMAGE_TAG)" >/dev/null 2>&1; then skip "proxy image built"; else bash proxy/build.sh; fi
if ct image inspect bahmni-local/systemdate:1.0 >/dev/null 2>&1; then skip "systemdate image built"; else bash systemdate/build.sh; fi
# Pull each registry image individually. `docker compose pull` is all-or-nothing
# and also tries to pull the two locally-built images (bahmni-local/proxy,
# bahmni-local/systemdate) -- they are built by proxy/build.sh and systemdate/
# build.sh, not a compose `build:` section, so --ignore-buildable does NOT skip
# them; their inevitable "pull access denied" then aborts and "Interrupts" every
# real pull (first live run, manpur). Per-image pull skips what is already present
# (the local builds, openmrs) and the bahmni-local/* local-only names, retries
# transient failures (a fresh VM IP can hit Docker Hub's anonymous rate limit --
# `docker login` raises it), and one failure never stops the others.
for img in $(compose config --images 2>/dev/null | sort -u); do
  case "$img" in bahmni-local/*) continue ;; esac
  ct image inspect "$img" >/dev/null 2>&1 && continue
  for attempt in 1 2 3; do
    if ct pull "$img"; then break; fi
    warn "pull ${img} attempt ${attempt}/3 failed; retrying in 10s"; sleep 10
  done
done
missing=""
for img in $(compose config --images 2>/dev/null | sort -u); do ct image inspect "$img" >/dev/null 2>&1 || missing="$missing $img"; done
[ -z "$missing" ] && ok "every image present ($(compose config --images 2>/dev/null | sort -u | wc -l | tr -d ' '))" || fail "images missing:${missing}"
# Connect plugin jars: scripting (fetched, gitignored). The replication-origin claim
# is config-only -- see the
# hibernate.agroal.initialSQL key in each clinic-side sink connector's own JSON.
J="${CLINIC_DIR}/config/kafka-connect"
GV="$(env_get "$E" GROOVY_VERSION)"; DSV="$(env_get "$E" DEBEZIUM_SCRIPTING_VERSION)"
if ls "$J/ext/groovy-${GV}.jar" "$J/ext/groovy-jsr223-${GV}.jar" "$J/ext/debezium-scripting-${DSV}.jar" >/dev/null 2>&1; then skip "scripting jars present"; else bash "$J/ext/fetch-scripting-jars.sh" >/dev/null; fi
ok "jars: 3 scripting"
