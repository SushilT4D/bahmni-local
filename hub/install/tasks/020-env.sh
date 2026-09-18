#!/usr/bin/env bash
# Compose hub/.env (sync/hub.env + the base stack's own .env + the operator's
# secrets file) and read back every HUB_KEYS entry from the file that was
# actually written. hub_compose_env's own put() only fills a key still empty,
# so calling it again here is idempotent -- a resume never regenerates a
# secret, and the runner having already composed hub/.env before the task
# loop (install.sh) is not a problem, just a no-op refresh. Eight base
# coordinates (put_coord/put_derived, hub/install/lib.sh) are the deliberate
# exception: the install command's environment overrides the stored value for
# those on EVERY run, not just the first -- see the "taken from the
# environment" line below. Three of the eight (BASE_ELIS_CONTAINER,
# BASE_ELIS_SUPERUSER, CLOUD_MYSQL_HOST) can ALSO be silently rewritten with
# no environment variable of their own set at all, when the coordinate they
# derive from moved this run (residual fix round 2) -- that rewrite does not
# add the derived key's own name to the line below (see put_derived's
# comment): only a key whose OWN environment variable was read appears there.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "20 · hub/.env"
[ "${DRY}" = 1 ] && { info "would: compose ${HUB_DIR}/.env from the base .env and secrets file, then read back every HUB_KEYS entry and prove it round-trips through sourcing"; exit 0; }

hub_compose_env "$BASE_ENV" "$SECRETS" "${HUB_DIR}/.env"

# Names only, never values: none of the eight coordinates are secrets, so
# the names -- which are all this prints -- expose nothing. This line names
# only the coordinates whose OWN environment variable was read this run, not
# a derived one silently rewritten because its upstream moved (put_derived,
# hub/install/lib.sh) -- the upstream's own name already appears when that
# happens, which is what the operator actually set. HUB_COMPOSE_ENV_FROM_ENV
# is set by hub_compose_env/put_coord/put_derived, space-separated, empty
# when none of the eight were set in the environment this run.
if [ -n "${HUB_COMPOSE_ENV_FROM_ENV:-}" ]; then
  info "base coordinates taken from the install command's environment this run:${HUB_COMPOSE_ENV_FROM_ENV}"
else
  info "base coordinates taken from the install command's environment this run: none (kept their stored/base/default value)"
fi

n=0
for k in $HUB_KEYS; do
  n=$((n+1))
  v="$(env_get "${HUB_DIR}/.env" "$k")" || true   # guard outside the substitution (hub/install/tests/test_lint.sh)
  [ -n "$v" ] || fail "hub/.env: $k is empty or missing"
  if placeholder_value "$v"; then
    case "$k" in
      *PASSWORD*|*SECRET*) fail "hub/.env: $k holds a placeholder value -- set a real one (the clinic package's sample .env ships placeholders; the hub must not inherit them)" ;;
      *) fail "hub/.env: $k holds the placeholder value '${v}' -- set a real one (the clinic package's sample .env ships placeholders; the hub must not inherit them)" ;;
    esac
  fi
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
  sourced="$(env -i bash -c 'set +u; set -a; . "$1" >/dev/null 2>&1; set +a; printf "%s" "${!2}"' _ "${HUB_DIR}/.env" "$k" 2>/dev/null)" || true
  parsed="$(env_get "${HUB_DIR}/.env" "$k")" || true
  [ "$sourced" = "$parsed" ] || mismatch="${mismatch} ${k}"
done
[ -z "$mismatch" ] && ok "every HUB_KEYS value round-trips through sourcing hub/.env directly (fresh env, set +u)" \
  || fail "hub/.env: sourcing disagrees with env_get for:${mismatch} (a quoting bug -- would corrupt any shell that sources this file)"

mode="$(stat -c %a "${HUB_DIR}/.env" 2>/dev/null || stat -f %Lp "${HUB_DIR}/.env")"
[ "$mode" = 600 ] || fail "hub/.env mode is ${mode}, want 600"
ok "hub/.env complete (${n} keys, mode ${mode})"
