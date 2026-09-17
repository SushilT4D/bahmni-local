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
[ "${DRY}" = 1 ] && { info "would: compose ${HUB_DIR}/.env from the base .env and secrets file, then read back every HUB_KEYS entry and prove it round-trips through sourcing"; exit 0; }

hub_compose_env "$BASE_ENV" "$SECRETS" "${HUB_DIR}/.env"

n=0
for k in $HUB_KEYS; do
  n=$((n+1))
  [ "$k" = BASE_PG_PASSWORD ] && continue   # may legitimately be empty (no network password)
  v="$(env_get "${HUB_DIR}/.env" "$k")"
  [ -n "$v" ] || fail "hub/.env: $k is empty or missing"
done

# Round-trip proof (code review fold-in): env_put's quoting only matters if a
# shell that `.`-sources hub/.env agrees with env_get's own grep/cut/sed
# parse of it -- every later task does exactly that (`set -a; . hub/.env; set
# +a`), so THAT is the real test, not just env_get reading its own write
# back. Re-source the file just written, once per key, each time in its own
# subshell (never this task's own environment -- these values have no
# business leaking into install.sh's remaining tasks except by reading
# hub/.env again normally), and compare what bash's own quoting rules
# produced against what env_get already read above.
mismatch=""
for k in $HUB_KEYS; do
  sourced="$(set -a; . "${HUB_DIR}/.env" >/dev/null 2>&1; eval "printf '%s' \"\${${k}:-}\"")"
  parsed="$(env_get "${HUB_DIR}/.env" "$k")"
  [ "$sourced" = "$parsed" ] || mismatch="${mismatch} ${k}"
done
[ -z "$mismatch" ] && ok "every HUB_KEYS value round-trips through sourcing hub/.env directly (subshell)" \
  || fail "hub/.env: sourcing disagrees with env_get for:${mismatch} (a quoting bug -- would corrupt any shell that sources this file)"

mode="$(stat -c %a "${HUB_DIR}/.env" 2>/dev/null || stat -f %Lp "${HUB_DIR}/.env")"
[ "$mode" = 600 ] || fail "hub/.env mode is ${mode}, want 600"
ok "hub/.env complete (${n} keys, mode ${mode})"
