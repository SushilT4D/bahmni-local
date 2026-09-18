#!/usr/bin/env bash
# The hub installer's library: the clinic installer's helpers (logging, ERR trap,
# .env editing, runtime detection, waits) sourced with the hub as the compose dir,
# plus what only a hub needs. bash 3.2 compatible like its parent.
HUB_INSTALL_DIR="${HUB_INSTALL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
HUB_DIR="${HUB_DIR:-$(cd "${HUB_INSTALL_DIR}/.." && pwd)}"
# Derived from HUB_INSTALL_DIR, not HUB_DIR: a test overrides HUB_DIR alone (to
# point hub_compose_env's OUT at a tmp dir instead of the real hub/), and a
# REPO_DIR computed from that override would resolve to the tmp dir's parent
# instead of this checkout -- the nested source below would then fail to find
# clinic/install/lib.sh. HUB_INSTALL_DIR is always this file's own real
# location, so REPO_DIR stays correct regardless of any HUB_DIR override.
REPO_DIR="${REPO_DIR:-$(cd "${HUB_INSTALL_DIR}/../.." && pwd)}"
# The clinic lib derives CLINIC_DIR from its own path and runs compose there with
# the clinic profiles; for the hub both are overridden before sourcing. Nothing
# clinic-specific it defines is called from hub tasks.
#
# PLAIN assignments, not a `VAR=x . file` prefix (found live by the first smoke
# run that ever executed task 060 as a script): outside POSIX mode bash treats
# assignments prefixed to a command -- `.` included -- as TEMPORARY, so
# CLINIC_DIR reverted to unset the moment the source returned, and the clinic
# lib's own `CLINIC_DIR="${CLINIC_DIR:-...}"` only ever updated that temporary
# binding. Every compose() call in tasks 040, 060 and 070 then died on
# `cd "${CLINIC_DIR}"` with "CLINIC_DIR: unbound variable" under set -u. It
# stayed latent because those three tasks are exactly the ones no test had ever
# run (final review, Important 3b).
CLINIC_DIR="${HUB_DIR}"
PROFILES=""
INSTALL_DIR="${REPO_DIR}/clinic/install"
. "${REPO_DIR}/clinic/install/lib.sh"
PROFILES=""
HUB_ENV="${HUB_ENV:-${REPO_DIR}/sync/hub.env}"
HUB_KEYS="KAFKA_CLUSTER_ID REMOTE_KAFKA_HOST KAFKA_SASL_BIND KAFKA_BASE_NETWORK KAFKA_ADMIN_PASSWORD REMOTE_KAFKA_PASSWORD DEBEZIUM_DB_USER DEBEZIUM_DB_PASSWORD REMOTE_MYSQL_HOST REMOTE_MYSQL_PORT REMOTE_MYSQL_DATABASE REMOTE_MYSQL_USER REMOTE_MYSQL_PASSWORD REMOTE_MYSQL_USE_SSL ODOO_SINK_PASSWORD CLINLIMS_SINK_PASSWORD CLOUD_MYSQL_SERVER_NAME CLOUD_DEBEZIUM_SERVER_ID KAFKA_CONNECT_URL BASE_PG_SUPERUSER BASE_MYSQL_CONTAINER BASE_PG_CONTAINER BASE_ELIS_CONTAINER BASE_ELIS_SUPERUSER ODOO_DB_PASSWORD CLINLIMS_SOURCE_PASSWORD REMOTE_SERVER_NAME CLOUD_MYSQL_HOST CLOUD_MYSQL_PORT CLOUD_MYSQL_DATABASE KAFKA_UI_USER KAFKA_UI_PASSWORD"
# Dropped from HUB_KEYS (final review, Important 7): BASE_MYSQL_ROOT_PASSWORD
# and BASE_PG_PASSWORD. Both were composed into hub/.env from the base stack's
# own .env -- the first one REQUIRED to be non-empty -- and then read by
# nothing: every task that needs MySQL root goes through the container's own
# MYSQL_ROOT_PASSWORD environment (mysql_root below, so the value never
# reaches this host's argv), and every psql call goes over the Postgres socket
# inside the container, which the image trusts. Copying two more live
# credentials into a second file on disk for no reader is pure exposure.

# KAFKA_CONTAINER: the docker/podman container NAME hub tasks `exec` into for
# kafka-configs/kafka-topics calls (080-sources.sh, and
# clinic/scripts/set-schema-history-retention.sh, shared with the clinic).
# Always "kafka" in production -- hub/docker-compose.yml pins that exact
# container_name, and nothing about a real deployment ever needs it to
# differ. Deliberately NOT HUB_KEYS/hub/.env material: unlike
# KAFKA_CONNECT_URL, there is no per-deployment reason for this to vary.
# The one legitimate override is hub/install/tests/test_sources.sh, which
# must run these same tasks for real beside another real stack that already
# holds the bare name on this host's docker daemon, and so renames its own
# throwaway container and exports this before invoking the tasks.
#
# CONNECT_CONTAINER (its former sibling here) was removed (code review
# fold-in, Task 6/7 review): every hub task that talks to Kafka Connect does
# so over its REST API (CONNECT_URL), never `ct exec` into the container by
# name, so the variable was defined and exported but read by nothing.
KAFKA_CONTAINER="${KAFKA_CONTAINER:-kafka}"

# hub_compose_env BASE_ENV SECRETS OUT : write hub/.env from the fleet pointer
# (sync/hub.env), the base stack's .env (root credentials, existing sink
# passwords) and the operator's secrets file (the fleet SASL password). Values
# already in OUT are kept, so a resume never regenerates a secret -- with one
# deliberate exception: eight non-secret base-deployment coordinates go
# through put_coord/put_derived below, not put: the install command's
# environment overrides whatever is already stored on EVERY run, not just the
# first. Five take the environment or a fixed/base-.env default
# (KAFKA_BASE_NETWORK, BASE_MYSQL_CONTAINER, BASE_PG_CONTAINER,
# BASE_PG_SUPERUSER, KAFKA_SASL_BIND); three also accept the environment but
# otherwise DERIVE from another coordinate's CURRENT value, not a fixed one
# (BASE_ELIS_CONTAINER/BASE_ELIS_SUPERUSER from BASE_PG_CONTAINER/
# BASE_PG_SUPERUSER; CLOUD_MYSQL_HOST from BASE_MYSQL_CONTAINER) -- see
# put_derived's own comment below for why the derived three needed a second
# round. Residual fix round 1: `put`'s keep-existing rule made the
# "environment first" precedence documented at each call site below a dead
# letter after the first run -- a first attempt on the Azure hub that omitted
# BASE_PG_SUPERUSER baked "postgres" into hub/.env, task 000 then failed
# telling the operator to set BASE_PG_SUPERUSER in the environment, and doing
# so and rerunning changed nothing, because `put` saw an already-non-empty
# slot and left it alone. Residual fix round 2: put_coord's fix was not
# transitive -- BASE_ELIS_CONTAINER/CLOUD_MYSQL_HOST/etc. still read a
# possibly-STALE upstream value out of OUT itself when they had no override
# of their own, rather than the upstream's newly-overridden value from this
# same run (see put_derived).
hub_compose_env(){
  local base="$1" secrets="$2" out="$3" k v
  [ -f "$base" ] || fail "base .env not found: $base"
  [ -f "$secrets" ] || fail "secrets file not found: $secrets"
  [ -f "$HUB_ENV" ] || fail "hub endpoint file missing: $HUB_ENV"
  ( umask 077; [ -f "$out" ] || : > "$out" ); chmod 600 "$out"
  # shellcheck disable=SC1090
  local bs="$(set -a; . "$HUB_ENV"; set +a; printf '%s' "${REMOTE_KAFKA_BOOTSTRAP_SERVERS:?}")"
  # HUB_COMPOSE_ENV_FROM_ENV (deliberately NOT local): 020-env.sh reads it
  # back right after calling this function, to print which of the eight base
  # coordinates below had THEIR OWN environment variable set this run (names
  # only -- none of the eight are secrets, so the names, which are all this
  # prints, expose nothing). A put_derived coordinate that was only
  # re-derived from an upstream's new value -- not given its own override --
  # does NOT get added here; the upstream's own name already appears, which
  # is the fact worth telling an operator. Reset on every call so a second
  # call in the same process (tests, or a resume that re-composes hub/.env
  # before the task loop) never carries over stale names from an earlier call.
  HUB_COMPOSE_ENV_FROM_ENV=""
  put(){ [ -n "$(env_get "$out" "$1")" ] || env_put "$out" "$1" "$2"; }
  # put_coord KEY ENV_VALUE DEFAULT : for the five base coordinates whose
  # non-environment default is fixed or comes from the base .env (the other
  # three -- BASE_ELIS_CONTAINER/BASE_ELIS_SUPERUSER/CLOUD_MYSQL_HOST -- use
  # put_derived below instead, because their default is ANOTHER coordinate's
  # value, which can itself change this run).
  # ENV_VALUE is the candidate already read from the install command's
  # environment (e.g. "${BASE_PG_SUPERUSER:-}"). Non-empty: written
  # unconditionally, EVERY run, overriding whatever is already stored in
  # OUT -- unlike put() above, which only ever fills an empty slot, so this
  # is what makes the environment's precedence real on a rerun, not only the
  # first attempt. Empty: falls through to put()'s existing keep-first-write
  # behavior with DEFAULT (so the existing value in OUT still wins over
  # DEFAULT, which is itself the base .env's value or a fixed default,
  # per the expression the call site passes).
  put_coord(){
    local k="$1" env_v="$2" dflt="$3"
    if [ -n "$env_v" ]; then
      env_put "$out" "$k" "$env_v"
      HUB_COMPOSE_ENV_FROM_ENV="${HUB_COMPOSE_ENV_FROM_ENV:+${HUB_COMPOSE_ENV_FROM_ENV} }${k}"
    else
      put "$k" "$dflt"
    fi
  }
  # put_derived KEY ENV_VALUE UPSTREAM : for a coordinate whose default is
  # ITSELF another coordinate's value, not a fixed/base-.env one --
  # CLOUD_MYSQL_HOST (from BASE_MYSQL_CONTAINER) and the BASE_ELIS_* pair
  # (from BASE_PG_*). Residual fix round 2: put_coord alone was not enough
  # for these three -- its empty-ENV_VALUE branch called put() with
  # UPSTREAM's CURRENT value, which only reached a fresh (never-before-
  # written) slot; on a rerun where KEY already had a stored value from an
  # earlier compose, put() kept that stale value even when UPSTREAM had just
  # moved underneath it THIS run. Concretely: BASE_MYSQL_CONTAINER moves from
  # cloud-openmrsdb-1 to the Azure hub's real iplit-base-openmrsdb-1, but a
  # hub/.env already carrying CLOUD_MYSQL_HOST=cloud-openmrsdb-1 from a first
  # attempt kept it -- 000/020/050 all pass (none of them read
  # CLOUD_MYSQL_HOST), and 080 fails 180s later at its RUNNING wait, naming
  # nothing (the down-source dials a container that does not exist).
  #
  # Three-way precedence, checked in order: (1) ENV_VALUE non-empty -- KEY's
  # OWN environment variable is set, so it wins unconditionally, every run,
  # exactly like put_coord, and is recorded in HUB_COMPOSE_ENV_FROM_ENV since
  # it truly was taken from the environment. (2) ENV_VALUE empty but UPSTREAM
  # was itself just taken from the environment THIS run (already present in
  # HUB_COMPOSE_ENV_FROM_ENV, which every UPSTREAM this function is ever
  # called with appends to via put_coord/put_derived BEFORE the derived call
  # below it runs) -- KEY is force-rewritten to UPSTREAM's now-current value
  # in OUT, unconditionally, so a stale KEY can never survive its upstream
  # moving. This does NOT add KEY itself to HUB_COMPOSE_ENV_FROM_ENV: KEY was
  # not taken from the environment, only re-derived from something that was
  # -- UPSTREAM's own name already appears on that line, which is the
  # meaningful fact for an operator reading it. (3) Neither -- put()'s
  # ordinary keep-existing-else-UPSTREAM's-current-value rule, byte-identical
  # to this function's behavior before round 2 (no regression for the
  # nothing-changed path: a fresh OUT still gets KEY defaulted from UPSTREAM,
  # and an unrelated rerun still keeps KEY's existing value).
  put_derived(){
    local k="$1" env_v="$2" upstream="$3" upstream_val
    upstream_val="$(env_get "$out" "$upstream")"
    if [ -n "$env_v" ]; then
      env_put "$out" "$k" "$env_v"
      HUB_COMPOSE_ENV_FROM_ENV="${HUB_COMPOSE_ENV_FROM_ENV:+${HUB_COMPOSE_ENV_FROM_ENV} }${k}"
    else
      case " ${HUB_COMPOSE_ENV_FROM_ENV} " in
        *" ${upstream} "*) env_put "$out" "$k" "$upstream_val" ;;
        *) put "$k" "$upstream_val" ;;
      esac
    fi
  }
  put REMOTE_KAFKA_HOST "${bs%%:*}"
  # KAFKA_SASL_BIND (final review, Critical 2): the host interface the
  # clinic-facing SASL_PLAINTEXT listener is PUBLISHED on (hub/docker-compose.yml
  # renders `${KAFKA_SASL_BIND:-0.0.0.0}:9092:9092`). A real hub must be
  # dialable by its clinics, so the default is 0.0.0.0 -- the compose file used
  # to pin 127.0.0.1 outright, which no operator could change without editing a
  # tracked file that task 090's own git-clean check then refused. A lab hub
  # that fronts 9092 with `tailscale serve` sets 127.0.0.1 here deliberately;
  # tasks 060 and 090 read the binding back from the running container and warn
  # loudly when it is loopback. put_coord (not put): the environment wins on
  # every run, not just the first (residual fix item 1).
  put_coord KAFKA_SASL_BIND "${KAFKA_SASL_BIND:-}" "0.0.0.0"
  put_coord KAFKA_BASE_NETWORK "${KAFKA_BASE_NETWORK:-}" "cloud_default"
  put KAFKA_CLUSTER_ID "$(kafka_cluster_id)"
  put KAFKA_ADMIN_PASSWORD "$(gen_secret)"
  put REMOTE_KAFKA_PASSWORD "$(env_get "$secrets" REMOTE_KAFKA_PASSWORD)"
  put DEBEZIUM_DB_USER debezium
  put DEBEZIUM_DB_PASSWORD "$(v="$(env_get "$base" DEBEZIUM_DB_PASSWORD)"; printf '%s' "${v:-$(gen_secret)}")"
  # REMOTE_MYSQL_* on the HUB describe the hub's OWN MySQL as the up-sinks'
  # target (the fleet `sink` user), so they derive from the base coordinates
  # and never inherit the base .env's REMOTE_MYSQL_* -- on IPLIT's base those
  # are the clinic package's sample placeholders (unused.invalid / unused),
  # and inheriting them made task 050 create a MySQL account named `unused`
  # with openmrs grants (Azure rehearsal stop 4, 2026-09-18). The host follows
  # BASE_MYSQL_CONTAINER like CLOUD_MYSQL_HOST does; the user is a coordinate
  # with the fleet default; the password is generated here and kept.
  put REMOTE_MYSQL_PORT "3306"
  put REMOTE_MYSQL_DATABASE "$(v="$(env_get "$base" OPENMRS_DB_NAME)"; printf '%s' "${v:-openmrs}")"
  put_coord REMOTE_MYSQL_USER "${REMOTE_MYSQL_USER:-}" "sink"
  put REMOTE_MYSQL_PASSWORD "$(gen_secret)"
  put REMOTE_MYSQL_USE_SSL false
  put ODOO_SINK_PASSWORD "$(v="$(env_get "$base" ODOO_SINK_PASSWORD)"; printf '%s' "${v:-$(gen_secret)}")"
  put CLINLIMS_SINK_PASSWORD "$(v="$(env_get "$base" CLINLIMS_SINK_PASSWORD)"; printf '%s' "${v:-$(gen_secret)}")"
  put CLOUD_MYSQL_SERVER_NAME bahmni-cloud
  put CLOUD_DEBEZIUM_SERVER_ID 184060
  put KAFKA_CONNECT_URL http://localhost:8083
  # The base-stack coordinates (two containers, two superusers, plus the
  # network and SASL bind above) resolve in ONE order, the same for each
  # (final review, Important 6; residual fix item 1): the environment of the
  # install command wins whenever it is set and non-empty, and it wins on
  # EVERY run, not just the first -- rewriting whatever is already stored.
  # Below that: the existing value already in $out (a resume must not
  # regenerate what an earlier run already resolved), then the base stack's
  # own .env, then a fixed default. The environment has to be checked first,
  # on every run, because a stock Bahmni base .env carries no POSTGRES_USER at
  # all, so the middle source silently produced "postgres" on IPLIT's real
  # hub, where the two superusers are `odoo` and `clinlims` -- an operator who
  # reran the installer after setting BASE_PG_SUPERUSER in the environment
  # used to see no effect at all, because `put`'s own keep-existing guard had
  # already baked "postgres" into hub/.env on the first (failing) attempt.
  # hub/README.md and the P2 runbook carry the full command with all seven set.
  put_coord BASE_PG_SUPERUSER "${BASE_PG_SUPERUSER:-}" "$(v="$(env_get "$base" POSTGRES_USER)"; printf '%s' "${v:-postgres}")"
  put_coord BASE_MYSQL_CONTAINER "${BASE_MYSQL_CONTAINER:-}" "cloud-openmrsdb-1"
  put_coord BASE_PG_CONTAINER "${BASE_PG_CONTAINER:-}" "cloud-openelisdb-1"
  # BASE_ELIS_CONTAINER / BASE_ELIS_SUPERUSER: one container serves both
  # databases on the mini and every clinic, so these default straight from
  # the BASE_PG_* values just set above. put_derived (residual fix round 2,
  # displaced Important): when the operator gives BASE_PG_CONTAINER/
  # BASE_PG_SUPERUSER in the environment this run but does NOT also give the
  # ELIS pair (e.g. a resume that only touches the Odoo side, or an operator
  # who assumes -- as the one-container default implies -- that ELIS "just
  # follows"), the ELIS pair must move WITH BASE_PG_* rather than keep
  # whatever was stored from an earlier run. IPLIT's real hub base is the one
  # deployment that differs enough to matter: it runs Odoo and OpenELIS in
  # two separate Postgres containers with different bootstrap superusers
  # (iplit-base-odoodb-1/odoo, iplit-base-openelisdb-1/clinlims --
  # docs/sync-core/runbooks/hub-build-and-connect.md's container table),
  # where an operator sets all four explicitly (hub/README.md's documented
  # command does) -- put_derived's own-environment branch (case 1, same as
  # put_coord) covers that case unchanged.
  put_derived BASE_ELIS_CONTAINER "${BASE_ELIS_CONTAINER:-}" BASE_PG_CONTAINER
  put_derived BASE_ELIS_SUPERUSER "${BASE_ELIS_SUPERUSER:-}" BASE_PG_SUPERUSER
  # CLOUD_MYSQL_HOST: the down-source dials the base stack's own MySQL by
  # container name on the shared KAFKA_BASE_NETWORK (Docker resolves it), so
  # it defaults to whatever BASE_MYSQL_CONTAINER resolved to above. Also
  # put_derived, and also a coordinate now in its own right (residual fix
  # round 2): the re-review's exact worked example. hub/README.md's Azure
  # command never mentions CLOUD_MYSQL_HOST at all (nothing sets it), so a
  # first attempt with no environment left it defaulted to
  # cloud-openmrsdb-1; the documented recovery attempt then moved
  # BASE_MYSQL_CONTAINER to iplit-base-openmrsdb-1 in the environment, and
  # before this fix CLOUD_MYSQL_HOST -- never itself an environment
  # candidate, and already non-empty in $out from attempt 1 -- silently kept
  # dialing a container that does not exist on that host. 000/020/050 never
  # read CLOUD_MYSQL_HOST, so all three passed; 080 was the first thing to
  # notice, 180s into its RUNNING wait, naming nothing useful (000-preflight
  # now also asserts it directly -- see the container-running check below).
  # An operator CAN also set CLOUD_MYSQL_HOST directly (case 1) for a
  # down-source host that genuinely is not BASE_MYSQL_CONTAINER.
  put_derived CLOUD_MYSQL_HOST "${CLOUD_MYSQL_HOST:-}" BASE_MYSQL_CONTAINER
  # REMOTE_MYSQL_HOST (the up-sinks' target = the hub's own MySQL) derives from
  # the same coordinate, so it must follow it here, after the coordinate exists.
  put_derived REMOTE_MYSQL_HOST "${REMOTE_MYSQL_HOST:-}" BASE_MYSQL_CONTAINER
  put CLOUD_MYSQL_PORT 3306
  put CLOUD_MYSQL_DATABASE openmrs
  put ODOO_DB_PASSWORD "$(env_get "$base" ODOO_DB_PASSWORD)"
  put CLINLIMS_SOURCE_PASSWORD "$(env_get "$base" OPENELIS_DB_PASSWORD)"
  put REMOTE_SERVER_NAME bahmni-cloud
  # kafka-ui (Ruling 3): a login the operator actually knows, not a bare
  # generated username -- "admin" is not a secret, so it is a fixed default
  # rather than something `put`'s already-set-wins guard needs to protect
  # from being clobbered on resume (it never generates a fresh one after the
  # first run either way, same as every other `put` here).
  put KAFKA_UI_USER admin
  put KAFKA_UI_PASSWORD "$(gen_secret)"
  versions_put "$out"   # every fleet pin from sync/versions.env (L-005: one place)
  # No key is exempt from the non-empty check any more (final review,
  # Important 7): BASE_PG_PASSWORD -- the one key that could legitimately be
  # empty, since the base Postgres takes no network password -- is gone.
  for k in $HUB_KEYS; do [ -n "$(env_get "$out" "$k")" ] || fail "hub .env is missing $k"; done
}

# hub_base_container ROLE : the base stack's container name for the given
# role, read back from hub/.env (hub_compose_env's OUT) -- for hub scripts
# that docker/podman exec into the base stack's MySQL or Postgres.
hub_base_container(){
  local v
  case "$1" in
    mysql) env_get "${HUB_DIR}/.env" BASE_MYSQL_CONTAINER ;;
    pg)    env_get "${HUB_DIR}/.env" BASE_PG_CONTAINER ;;
    # elis: BASE_ELIS_CONTAINER if hub/.env carries it (always true once
    # composed by hub_compose_env, which defaults it), falling back to
    # BASE_PG_CONTAINER for an .env written before this key pair existed.
    elis)
      v="$(env_get "${HUB_DIR}/.env" BASE_ELIS_CONTAINER)"
      printf '%s' "${v:-$(env_get "${HUB_DIR}/.env" BASE_PG_CONTAINER)}"
      ;;
    *) fail "hub_base_container: unknown role $1" ;;
  esac
}

# pg_admin DB ARGS... : psql as the base Postgres superuser, for whichever
# container actually hosts DB -- "openelis" routes to BASE_ELIS_CONTAINER/
# BASE_ELIS_SUPERUSER (IPLIT's real hub base runs Odoo and OpenELIS in two
# separate Postgres containers with different bootstrap superusers), every
# other DB (odoo, and the bare "postgres" maintenance db some callers use)
# stays on BASE_PG_CONTAINER/BASE_PG_SUPERUSER. One contract, hoisted here
# (code review fold-in, Task 6/7 review): 050-base-db.sh and 080-sources.sh
# each used to define their own `pg_admin` with a DIFFERENT argument shape
# (050's took a db name and dispatched; 080's took a container+superuser
# directly), a naming collision waiting to bite the next person who greps for
# one and edits the other. Both tasks now call this one. ARGS are passed
# straight to psql -- a heredoc/pipe on stdin, or -Atc "SQL", or -f/-v as
# 050-base-db.sh already does -- with no masking here; a caller whose SQL
# carries a secret masks it the way 050-base-db.sh's own pg_admin_pw wraps
# this function for the two sink-role passwords. Reads BASE_PG_CONTAINER/
# BASE_PG_SUPERUSER/BASE_ELIS_CONTAINER/BASE_ELIS_SUPERUSER from the caller's
# already-sourced hub/.env; the BASE_ELIS_* fallback mirrors hub_compose_env's
# own default (an .env composed before that key pair existed).
pg_admin(){
  local db="$1" ct_name="${BASE_PG_CONTAINER:?pg_admin: BASE_PG_CONTAINER not set}" su="${BASE_PG_SUPERUSER:?pg_admin: BASE_PG_SUPERUSER not set}"
  if [ "$db" = openelis ]; then
    ct_name="${BASE_ELIS_CONTAINER:-$ct_name}"
    su="${BASE_ELIS_SUPERUSER:-$su}"
  fi
  shift
  ct exec -i "$ct_name" psql -U "$su" -d "$db" -v ON_ERROR_STOP=1 -q "$@"
}

# mysql_root : run the SQL on stdin as root in the base stack's MySQL
# container, tab-separated, header-less (-N). Hoisted here (final review,
# Minor 20) from 050-base-db.sh and 080-sources.sh, which carried
# byte-identical copies. One contract:
#   - the root password is expanded by the `sh` INSIDE the container, from
#     that container's OWN environment (MYSQL_ROOT_PASSWORD), so it never
#     appears in this host's argv or process list;
#   - stderr is folded into stdout and both are pushed through
#     mask_env_secrets, because a MySQL syntax error near a password clause
#     echoes the clause back, secret included;
#   - the container comes from BASE_MYSQL_CONTAINER in the caller's already-
#     sourced hub/.env; requires setup_compose to have run (uses ct).
mysql_root(){ ct exec -i "${BASE_MYSQL_CONTAINER:?mysql_root: BASE_MYSQL_CONTAINER not set}" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N' 2>&1 | mask_env_secrets REMOTE_MYSQL_PASSWORD DEBEZIUM_DB_PASSWORD; }

# container_ip CONTAINER : its address on whichever docker/podman network(s)
# it is attached to. Hoisted here (final review, Minor 20) from
# 050-base-db.sh and hub/install/tests/test_base_db.sh, which each had their
# own copy -- one through `ct`, one through a bare `docker`. Used to dial
# MySQL/Postgres from inside their OWN container by IP rather than by
# "localhost": the postgres image's pg_hba.conf special-cases 127.0.0.1/::1
# as trust regardless of POSTGRES_HOST_AUTH_METHOD, so a localhost round-trip
# would "succeed" without ever checking the password just set. The
# container's real address falls through to the catch-all host line instead,
# so only that path actually exercises the password.
container_ip(){ ct inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$1" | awk '{print $1}'; }

# sasl_bind_ok : the clinic-facing SASL listener is PUBLISHED on the interface
# hub/.env declares (KAFKA_SASL_BIND, default 0.0.0.0). On success prints the
# published binding(s) and returns 0; on failure prints the reason and returns
# 1 -- so a caller reads it as `if b="$(sasl_bind_ok)"; then ok ...; else fail
# "$b"; fi`.
#
# Why this check exists at all (final review, Critical 2): sasl_listener_ok
# above proves the listener AUTHENTICATES, but it dials 127.0.0.1, which
# answers whether the port is published on loopback only or on every
# interface. So a hub published on 127.0.0.1:9092 -- which no clinic can dial
# -- passed every check in tasks 060 and 090 while being useless to the fleet.
# This reads the binding docker/podman actually installed and compares it with
# what hub/.env declares, and warns loudly (never silently) when the declared
# value is a loopback address.
sasl_bind_ok(){
  local declared="${KAFKA_SASL_BIND:-0.0.0.0}" published line matched=0
  case "$declared" in
    127.*|localhost|::1|'[::1]') warn "KAFKA_SASL_BIND=${declared} publishes the clinic-facing SASL listener on loopback: clinics cannot dial this hub directly (only something already on this host, e.g. a tunnel or \`tailscale serve\`, can reach it). A hub clinics dial sets KAFKA_SASL_BIND=0.0.0.0." ;;
  esac
  published="$(ct port "${KAFKA_CONTAINER}" 9092 2>/dev/null)" || true
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in "${declared}:"*) matched=1 ;; esac
  done <<EOF
${published}
EOF
  [ "$matched" = 1 ] && { printf '%s' "$(printf '%s' "$published" | tr '\n' ' ')"; return 0; }
  printf 'container %s publishes port 9092 as "%s", which does not match the declared KAFKA_SASL_BIND=%s (hub/.env) -- clinics dial %s:9092\n' \
    "${KAFKA_CONTAINER}" "$(printf '%s' "$published" | tr '\n' ' ')" "$declared" "${REMOTE_KAFKA_HOST:-<REMOTE_KAFKA_HOST unset>}"
  return 1
}

# git_dirty_hub_paths : reads `git status --porcelain` output on stdin and
# prints only the paths under hub/ (renames counted by their destination).
# Pure text, so it is unit-tested directly (hub/install/tests/test_lib.sh).
# Task 090's tree check uses it to make the distinction the pre-flight ruling
# called for: a hub host legitimately carries edits to the BASE stack's own
# files beside this checkout's hub/ tree, and those must not read as "the hub
# install left the repo dirty" -- but a dirty file under hub/ must.
git_dirty_hub_paths(){
  local line path
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path="$(printf '%s' "$line" | cut -c4-)"
    case "$path" in *' -> '*) path="${path##* -> }" ;; esac
    path="${path%\"}"; path="${path#\"}"
    case "$path" in hub/*) printf '%s\n' "$path" ;; esac
  done
  return 0
}

# jaas_escape STR : backslash-escapes a value for safe embedding inside a
# double-quoted JAAS/Java-properties string. Order matters -- backslashes
# first, then quotes -- so a literal backslash already in the input is never
# re-escaped by the quote pass (Fix round 1, code review Finding 1): an
# operator-typed REMOTE_KAFKA_PASSWORD containing a '"' or '\' would otherwise
# break the quoting of whatever file it lands in.
# placeholder_value VALUE : true when VALUE is a sample/placeholder no real hub
# would carry (the clinic package's .env ships unused.invalid / unused; task
# 020 refuses them so a placeholder can never become an account or a host).
placeholder_value(){
  local v; v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$v" in
    unused|changeme|change_me|change-me|placeholder|todo|example|xxx*|*.invalid|*.example|*.example.com|*.example.org) return 0 ;;
  esac
  return 1
}
jaas_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# pg_lit_escape STR : doubles every single quote, for safe embedding inside a
# single-quoted Postgres string literal ('...'). Postgres string literals do
# not treat backslash specially (standard_conforming_strings, the default
# since 9.1), so nothing else needs escaping -- an operator-typed
# ODOO_SINK_PASSWORD/CLINLIMS_SINK_PASSWORD containing a "'" would otherwise
# break out of the ALTER ROLE ... PASSWORD '...' literal it lands in
# (Fix round 2).
pg_lit_escape(){ printf '%s' "$1" | sed "s/'/''/g"; }

# mysql_lit_escape STR : backslash-escapes a value for safe embedding inside a
# single-quoted MySQL string literal ('...'). Unlike Postgres, MySQL string
# literals DO treat backslash as an escape character, so it needs the same
# two-pass order as jaas_escape above -- backslashes first, then quotes -- so
# a literal backslash already in the input is never re-escaped by the quote
# pass. An operator-typed REMOTE_MYSQL_PASSWORD/DEBEZIUM_DB_PASSWORD
# containing a "'" or "\" would otherwise break the IDENTIFIED BY '...'
# clause mysql_user_sql builds below (Fix round 2).
mysql_lit_escape(){ printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g"; }

# mask_env_secrets NAME... : reads stdin, replaces the CURRENT value of each
# named environment variable with <hidden> -- a literal substring replace
# (Python's str.replace, not a sed regex), so a password containing any
# sed/regex-special character (., *, [, ], ^, $, \, or the delimiter itself,
# "/") can never break the mask or leak past it the way
# `sed "s/${SECRET}/<hidden>/g"` did (Fix round 2, code review: that pattern
# breaks -- or silently mis-substitutes -- the moment a secret contains a "/"
# or a regex metacharacter). Only variable NAMES are ever passed as
# arguments (never secret values); mask_env_secrets reads the actual values
# from its own inherited environment, so a secret never touches this
# process's own argv either. A name that is unset or empty is skipped, not
# replaced -- Python's str.replace(data, "", "<hidden>") would otherwise
# insert "<hidden>" between every character.
mask_env_secrets(){
  python3 -c '
import os, sys
data = sys.stdin.read()
for name in sys.argv[1:]:
    val = os.environ.get(name, "")
    if val:
        data = data.replace(val, "<hidden>")
sys.stdout.write(data)
' "$@"
}

# write_jaas OUT ADMIN_PW FLEET_PW : the broker's SASL/PLAIN users. Generated from
# hub/.env at install time -- cloud/kafka_server_jaas.conf was TRACKED with literal
# passwords since the repo's first commit (public repo), hence F-071. Both
# passwords are escaped before interpolation (Fix round 1).
write_jaas(){
  local out="$1" adm fleet
  adm="$(jaas_escape "$2")"; fleet="$(jaas_escape "$3")"
  ( umask 077; printf 'KafkaServer {\n    org.apache.kafka.common.security.plain.PlainLoginModule required\n    username="admin"\n    password="%s"\n    user_admin="%s"\n    user_mirrormaker="%s";\n};\n' "$adm" "$adm" "$fleet" > "$out" )
  chmod 600 "$out"
}

# sasl_listener_ok : proves the broker's published SASL_PLAINTEXT listener
# authenticates the mirrormaker user, dialed from the HOST network on the
# PUBLISHED port -- never by dialing REMOTE_KAFKA_HOST from inside the
# broker's own container (an Azure VM cannot reach its own public IP).
# Extracted here (code review fold-in, Task 6/7 review) so task 060 (right
# after the broker first comes up) and task 090 (the exit checks, proving it
# is STILL true at the end) share one definition instead of two copies
# drifting apart. Same ok-or-named-reason contract as binlog_ok above: prints
# nothing and returns 0 on success, prints the reason and returns 1
# otherwise. Reads KAFKA_IMAGE/REMOTE_KAFKA_HOST/REMOTE_KAFKA_PASSWORD from
# the caller's already-sourced hub/.env; requires setup_compose to have run
# (uses ct). The check's own password never touches a command line, a log, or
# a tracked file: written by the printf builtin (no subprocess ever sees it
# in argv) to a mode-600 temp file under HUB_DIR.
#
# Fix round 1 (code review, Important 3): the body runs in its OWN subshell
# with its OWN `trap ... EXIT`, not a plain `rm -f` after the `ct run` line --
# a bare `rm -f` is skipped entirely if `ct run` (or anything before it)
# crashes or is killed by a signal, leaving a mode-600 file holding the
# escaped REMOTE_KAFKA_PASSWORD sitting under hub/ indefinitely. A
# function-level `trap ... EXIT` was considered and rejected: bash's EXIT
# trap is a single, script-wide slot, so setting one inside a function
# REPLACES whatever trap the calling script (060, 090) already has installed
# for its own cleanup, firing this function's cleanup instead of the
# script's own on the script's eventual exit. A subshell's own `trap ... EXIT`
# fires when the SUBSHELL exits -- on every path, including a crash or a
# signal -- and never touches the calling script's own trap at all.
#
# SASL_LISTENER_PORT overrides which published host port is dialed (default
# 9092, production's real value): hub/install/tests/test_sources.sh's
# throwaway broker cannot publish 9092 itself (this host may already run a
# real hub bound to it), so it republishes the same internal SASL listener on
# a throwaway host port instead and sets this to match -- the one legitimate
# override, the same shape as KAFKA_CONTAINER/CONNECT_URL.
sasl_listener_ok(){
  local port="${SASL_LISTENER_PORT:-9092}"
  (
    local tmp esc_pw rc=0
    tmp="$(mktemp "${HUB_DIR}/.sasl-check.XXXXXX")"
    chmod 600 "$tmp"
    trap 'rm -f "$tmp"' EXIT
    esc_pw="$(jaas_escape "${REMOTE_KAFKA_PASSWORD:?sasl_listener_ok: REMOTE_KAFKA_PASSWORD not set}")"
    printf 'security.protocol=SASL_PLAINTEXT\nsasl.mechanism=PLAIN\nsasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="mirrormaker" password="%s";\n' "$esc_pw" > "$tmp"
    # --user (final review, Important 9): the properties file is mode 600 and
    # owned by whoever runs the installer, while the cp-kafka image's own
    # entrypoint user is a fixed in-image uid -- which on a Linux hub cannot
    # read it, so the probe would fail for a permission reason and be reported
    # as a broken SASL listener. Running the probe as the caller's own uid:gid
    # makes the mount readable on any host without loosening the file.
    ct run --rm --network host --user "$(id -u):$(id -g)" -v "${tmp}:/tmp/c.properties:ro" "${KAFKA_IMAGE:?sasl_listener_ok: KAFKA_IMAGE not set}" kafka-broker-api-versions --bootstrap-server "127.0.0.1:${port}" --command-config /tmp/c.properties >/dev/null 2>&1 || rc=$?
    [ "$rc" = 0 ] && exit 0
    printf 'SASL listener did not answer on 127.0.0.1:%s as mirrormaker (image %s)\n' "$port" "${KAFKA_IMAGE}"
    exit 1
  )
}

# kafka_ui_login_ok URL : proves the credentials in KAFKA_UI_USER/
# KAFKA_UI_PASSWORD (the caller's own already-exported environment -- e.g.
# after `set -a; . hub/.env; set +a`) actually log in to kafka-ui at URL
# (e.g. http://127.0.0.1:8080) through Spring Security's own form-login
# endpoint, and that the resulting session reads this hub's own cluster
# ("hub", KAFKA_CLUSTERS_0_NAME) back via /api/clusters. Same ok-or-named-
# reason contract as sasl_listener_ok above.
#
# Fix round 1 (code review, Critical 1): hoisted out of task 070 and the live
# smoke, which each used to pass KAFKA_UI_USER/KAFKA_UI_PASSWORD as
# positional arguments to their own `python3 -c` call -- visible in `ps -ef`
# / /proc/<pid>/cmdline for that process's whole lifetime, and duplicated
# near-verbatim between the two callers. This one function is now the only
# place either value is ever handled: it reads them from ITS OWN inherited
# environment (never its own arguments -- `kafka_ui_login_ok` takes only
# URL), and the python3 substep reads them via `os.environ`, never
# `sys.argv`, so neither value is ever visible in that process's argv at any
# point. The url-encoded form body still goes to a mode-600 temp file (never
# a command-line argument, since curl's `-d @file` needs a real file), the
# cookie jar is mode 600, and -- like sasl_listener_ok above -- the whole
# body runs in its own subshell with its own `trap ... EXIT`, so both temp
# files are removed on every exit path without touching the calling script's
# own trap.
kafka_ui_login_ok(){
  local url="$1"
  (
    local body cookie_jar login_result login_code login_redirect clusters_body
    body="$(mktemp "${HUB_DIR}/.kafka-ui-login.XXXXXX")"
    cookie_jar="$(mktemp "${HUB_DIR}/.kafka-ui-cookies.XXXXXX")"
    chmod 600 "$body" "$cookie_jar"
    trap 'rm -f "$body" "$cookie_jar"' EXIT
    : "${KAFKA_UI_USER:?kafka_ui_login_ok: KAFKA_UI_USER not set}"
    : "${KAFKA_UI_PASSWORD:?kafka_ui_login_ok: KAFKA_UI_PASSWORD not set}"
    python3 -c '
import os, sys, urllib.parse
user = os.environ["KAFKA_UI_USER"]
pw = os.environ["KAFKA_UI_PASSWORD"]
sys.stdout.write("username=%s&password=%s" % (urllib.parse.quote_plus(user), urllib.parse.quote_plus(pw)))
' > "$body"
    login_result="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 10 -c "$cookie_jar" -d @"$body" "${url}/login" 2>/dev/null || true)"
    login_code="${login_result%% *}"; login_redirect="${login_result#* }"
    case "$login_code" in
      302)
        case "$login_redirect" in
          *login*) printf 'kafka-ui login failed (redirected to %s -- check KAFKA_UI_USER/KAFKA_UI_PASSWORD in hub/.env)\n' "$login_redirect"; exit 1 ;;
        esac ;;
      *) printf 'kafka-ui login POST to %s/login answered HTTP %s, expected a 302 redirect\n' "$url" "${login_code:-<none>}"; exit 1 ;;
    esac
    clusters_body="$(curl -s --max-time 10 -b "$cookie_jar" "${url}/api/clusters" 2>/dev/null || true)"
    printf '%s' "$clusters_body" | grep -qF '"name":"hub"' && exit 0
    printf 'kafka-ui authenticated /api/clusters (%s) did not carry cluster "hub" (got: %s)\n' "$url" "$(printf '%s' "$clusters_body" | head -c 200)"
    exit 1
  )
}

# binlog_ok FORMAT IMAGE RETENTION_S SERVER_ID INCREMENT OFFSET CONNECTOR_ID : the
# base MySQL is fit for a Debezium source and the hub's striding (residue 0).
binlog_ok(){
  local f="$1" i="$2" r="$3" s="$4" inc="$5" off="$6" cid="$7" bad=''
  [ "$f" = ROW ] || bad="$bad binlog_format=$f"
  [ "$i" = FULL ] || bad="$bad binlog_row_image=$i"
  [ "${r:-0}" -ge 604800 ] || bad="$bad retention=${r}s(<7d)"
  [ "$s" != "$cid" ] || bad="$bad server_id=$s(equals the connector id, F-059)"
  [ "$inc" = 10 ] || bad="$bad auto_increment_increment=$inc"
  [ "$off" = 10 ] || bad="$bad auto_increment_offset=$off(the hub is residue 0)"
  [ -z "$bad" ] && return 0; printf '%s\n' "$bad"; return 1
}

# mysql_major_ok VERSION : true (rc 0) iff VERSION's major component is a fit
# for Debezium 3.6.2 (MySQL 8.0.x only -- 5.6/5.7 are not, though task 000's
# own binlog-fitness checks tolerate them). VERSION is whatever `select
# version()` returned, e.g. "8.0.39" or "5.7.44-log". Prints the reason and
# returns 1 when it is not a fit, same ok-or-named-reason contract as
# binlog_ok above. Extracted from 080-sources.sh (code review fold-in, Task 6
# review: this comparison used to be inlined there with no test of its own) --
# pure text logic, no docker, so it is testable directly.
mysql_major_ok(){
  local ver="$1" major="${1%%.*}"
  case "$major" in
    ''|*[!0-9]*) printf 'could not read a numeric MySQL major version (got %s)\n' "$ver"; return 1 ;;
  esac
  [ "$major" -ge 8 ] && return 0
  printf 'mysql %s is below major version 8 -- Debezium 3.6.2 supports MySQL 8.0.x only\n' "$ver"
  return 1
}

# slot_wait_state ROW SLOT : classifies a psql read-back ROW (the exact
# "<slot_name>|<active>" text a `select slot_name || '|' || active from
# pg_replication_slots where slot_name = '<slot>'` -At query produces) against
# SLOT -- "active" (the slot exists and is active), "inactive" (exists, not
# yet active) or "missing" (no such row, including an empty ROW: the slot not
# created yet). Extracted from 080-sources.sh's wait_slot (code review
# fold-in, Task 6 review) -- pure and side-effect free, so it is testable
# directly against the real shapes psql -At produces: dbz_odoo_down|true,
# dbz_odoo_down|false, empty.
slot_wait_state(){
  case "$1" in
    "${2}|true")  printf 'active\n' ;;
    "${2}|false") printf 'inactive\n' ;;
    *)            printf 'missing\n' ;;
  esac
}

# mysql_user_sql VERSION USER PASSWORD DB : SQL text (on stdout) that creates
# the MySQL account named USER if it does not already exist, and converges
# its password to PASSWORD either way -- version-branched because MySQL 8.0
# removed `GRANT ... IDENTIFIED BY`, which is 5.x's idiom (still needed for the
# Azure hub's MySQL 5.6 base image) for creating an account with a password in
# one statement. DB scopes the placeholder grant 5.x needs to create an
# account at all; USAGE is MySQL's "no real privilege" grant, so this carries
# none of the privileges the caller actually wants -- the caller issues those
# itself, in its own GRANT (identical syntax on 5.x and 8.0 once IDENTIFIED BY
# is out of it), once per privilege set, so this function never needs to know
# what they are or vary by DB. PASSWORD is escaped (mysql_lit_escape) before
# it is interpolated into either IDENTIFIED BY literal, not used raw (Fix
# round 2) -- interpolating it raw would let an operator-typed password
# containing "'" break out of the literal it lands in.
mysql_user_sql(){
  local ver="$1" user="$2" db="$4" esc_pw
  esc_pw="$(mysql_lit_escape "$3")"
  case "$ver" in
    5.*)
      printf "GRANT USAGE ON %s.* TO '%s'@'%%' IDENTIFIED BY '%s';\nSET PASSWORD FOR '%s'@'%%' = PASSWORD('%s');\n" \
        "$db" "$user" "$esc_pw" "$user" "$esc_pw"
      ;;
    *)
      printf "CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s';\nALTER USER '%s'@'%%' IDENTIFIED BY '%s';\n" \
        "$user" "$esc_pw" "$user" "$esc_pw"
      ;;
  esac
}
