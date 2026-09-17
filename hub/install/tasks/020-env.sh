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
# back. Re-source the file just written, once per key, each time in a FRESH
# bash process with an empty environment (`env -i`) -- never this task's own
# environment or subshell, which both run under this task's own `set -euo
# pipefail`: Fix round 1 (code review) found that a badly-quoted value
# containing an unintended `$name` reference could make the `.`-source
# itself abort under `set -u` before ever reaching the comparison below,
# turning a quoting bug into a raw shell abort instead of the named `fail`
# line this check exists to produce. `env -i bash -c '...'` starts with
# bash's own default `set +u` (explicit here too, for clarity); indirect
# expansion (`${!2}`) reads the dynamically-named key back without `eval`.
mismatch=""
for k in $HUB_KEYS; do
  sourced="$(env -i bash -c 'set +u; set -a; . "$1" >/dev/null 2>&1; set +a; printf "%s" "${!2}"' _ "${HUB_DIR}/.env" "$k" 2>/dev/null || true)"
  parsed="$(env_get "${HUB_DIR}/.env" "$k")"
  [ "$sourced" = "$parsed" ] || mismatch="${mismatch} ${k}"
done
[ -z "$mismatch" ] && ok "every HUB_KEYS value round-trips through sourcing hub/.env directly (fresh env, set +u)" \
  || fail "hub/.env: sourcing disagrees with env_get for:${mismatch} (a quoting bug -- would corrupt any shell that sources this file)"

mode="$(stat -c %a "${HUB_DIR}/.env" 2>/dev/null || stat -f %Lp "${HUB_DIR}/.env")"
[ "$mode" = 600 ] || fail "hub/.env mode is ${mode}, want 600"
ok "hub/.env complete (${n} keys, mode ${mode})"
