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
# everything else the profiles reference. Visible output + retry: a fresh VM IP
# hits Docker Hub's anonymous pull-rate limit, and the old `--quiet 2>/dev/null
# || true` HID that cause on the first live run -- the check below then reported
# only "images missing". `docker login` raises the anonymous limit.
pull_ok=0
for attempt in 1 2 3; do
  if compose pull --ignore-buildable; then pull_ok=1; break; fi
  warn "image pull attempt ${attempt}/3 failed (Docker Hub rate-limits fresh IPs -- 'docker login' raises the limit); retrying in 15s"
  sleep 15
done
[ "$pull_ok" = 1 ] || warn "image pull did not fully succeed after 3 tries; the check below names what is still missing"
missing=""
for img in $(compose config --images 2>/dev/null | sort -u); do ct image inspect "$img" >/dev/null 2>&1 || missing="$missing $img"; done
[ -z "$missing" ] && ok "every image present ($(compose config --images 2>/dev/null | sort -u | wc -l | tr -d ' '))" || fail "images missing:${missing}"
# Connect plugin jars: scripting (fetched, gitignored) and the customizer (tracked)
J="${CLINIC_DIR}/config/kafka-connect"
if ls "$J"/ext/groovy-4.0.22.jar "$J"/ext/groovy-jsr223-4.0.22.jar "$J"/ext/debezium-scripting-3.2.4.Final.jar >/dev/null 2>&1; then skip "scripting jars present"; else bash "$J/ext/fetch-scripting-jars.sh" >/dev/null; fi
[ -f "$J/sync-origin-customizer.jar" ] || fail "customizer jar missing from the checkout: $J/sync-origin-customizer.jar (rebuild: $J/sync-origin/build.sh ${CT})"
unzip -l "$J/sync-origin-customizer.jar" | grep -q 't4d/sync/SyncOriginCustomizer.class' && ok "jars: 3 scripting + customizer" || fail "customizer jar does not contain t4d.sync.SyncOriginCustomizer"
