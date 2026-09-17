#!/usr/bin/env bash
# Compose hub/.env (sync/hub.env + the base stack's own .env + the operator's
# secrets file) and read back every HUB_KEYS entry from the file that was
# actually written. hub_compose_env's own put() only fills a key still empty,
# so calling it again here is idempotent -- a resume never regenerates a
# secret, and the runner having already composed hub/.env before the task
# loop (install.sh) is not a problem, just a no-op refresh.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "20 · hub/.env"
[ "${DRY}" = 1 ] && { info "would: compose ${HUB_DIR}/.env from the base .env and secrets file, then read back every HUB_KEYS entry"; exit 0; }

hub_compose_env "$BASE_ENV" "$SECRETS" "${HUB_DIR}/.env"

n=0
for k in $HUB_KEYS; do
  n=$((n+1))
  [ "$k" = BASE_PG_PASSWORD ] && continue   # may legitimately be empty (no network password)
  v="$(env_get "${HUB_DIR}/.env" "$k")"
  [ -n "$v" ] || fail "hub/.env: $k is empty or missing"
done
mode="$(stat -c %a "${HUB_DIR}/.env" 2>/dev/null || stat -f %Lp "${HUB_DIR}/.env")"
[ "$mode" = 600 ] || fail "hub/.env mode is ${mode}, want 600"
ok "hub/.env complete (${n} keys, mode ${mode})"
