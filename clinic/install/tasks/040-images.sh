#!/usr/bin/env bash
# Images the stack needs before anything starts: pulled ones, the two built
# locally, the OpenMRS fallback for podman, and the Connect plugin jars.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "40 · images + jars"
[ "${DRY}" = 1 ] && { info "would: pull every image in compose config, build bahmni-local/proxy and systemdate, fetch the scripting jars, verify the customizer jar"; exit 0; }
setup_compose; mk_podman_shim
cd "${CLINIC_DIR}"
E="${CLINIC_DIR}/.env"
omrs="$(env_get "$E" OPENMRS_IMAGE_NAME)"
# OpenMRS first: on podman some registries' manifests trip a MIME error; the
# repo carries openmrs/build.sh, which transplants the WAR into openmrs-base.
if ct image inspect "$omrs" >/dev/null 2>&1; then skip "openmrs image present"; else
  if ! ct pull "$omrs" >/dev/null 2>&1; then
    warn "pull of ${omrs} failed on ${CT}; building via openmrs/build.sh (WAR transplant)"
    bash openmrs/build.sh "$omrs" openmrs-base:latest "$omrs"
  fi
fi
ct image inspect "$omrs" >/dev/null 2>&1 && ok "openmrs image ${omrs}" || fail "openmrs image ${omrs} unavailable"
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
# Connect plugin jars: scripting (fetched, gitignored) and the customizer (tracked)
J="${CLINIC_DIR}/config/kafka-connect"
if ls "$J"/ext/groovy-4.0.22.jar "$J"/ext/groovy-jsr223-4.0.22.jar "$J"/ext/debezium-scripting-3.2.4.Final.jar >/dev/null 2>&1; then skip "scripting jars present"; else bash "$J/ext/fetch-scripting-jars.sh" >/dev/null; fi
[ -f "$J/sync-origin-customizer.jar" ] || fail "customizer jar missing from the checkout: $J/sync-origin-customizer.jar (rebuild: $J/sync-origin/build.sh ${CT})"
# a jar is a zip; check with python3 (already required) rather than unzip, which
# is not installed on a fresh Ubuntu VM (first live run, manpur).
if python3 -c 'import zipfile,sys; sys.exit(0 if "t4d/sync/SyncOriginCustomizer.class" in zipfile.ZipFile(sys.argv[1]).namelist() else 1)' "$J/sync-origin-customizer.jar" 2>/dev/null; then
  ok "jars: 3 scripting + customizer"
else
  fail "customizer jar does not contain t4d.sync.SyncOriginCustomizer"
fi
