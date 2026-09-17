#!/usr/bin/env bash
# Registers the hub's three Debezium sources and proves them: the down-direction
# MySQL source (cloud OpenMRS -> clinics, capturing only what generate-cloud-
# source-connector.sh's loop guard clears against sync/local/tables.conf) and the
# two up-direction Postgres relay sources (Odoo, OpenELIS/clinlims) that read
# what task 050's dbz_odoo_owned/dbz_clinlims_owned publications already carry.
#
# Registration never writes a rendered config containing a password to this
# script's own stdout: the MySQL source's rendered JSON (which DOES carry
# DEBEZIUM_DB_PASSWORD on disk, gitignored) is extracted with python3 and piped
# straight to curl; the two Postgres sources go through connectors/register-
# odoo.sh + _render_connector.py, which does the same in-memory substitution.
# Any error path is masked with mask_env_secrets before it is ever printed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "80 · sources"
[ "${DRY}" = 1 ] && { info "would: gate on base mysql major version >=8 (Debezium 3.6.2); render+register mysql-cloud-source-connector; register odoo-cloud-source/clinlims-cloud-source via connectors/register-odoo.sh NODE=cloud; set schema-history retention on schema-changes.\${CLOUD_MYSQL_SERVER_NAME}; wait for all three connectors+tasks RUNNING; assert dbz_odoo_down/dbz_clinlims_down replication slots active, the schema-changes topic present, and the heartbeat keys in both postgres sources' configs"; exit 0; }
setup_compose
[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"
# shellcheck disable=SC1091
set -a; . "${HUB_DIR}/.env"; set +a
MY="$BASE_MYSQL_CONTAINER"; PG="$BASE_PG_CONTAINER"
# ELIS/ELIS_SUPERUSER (Ruling 11): IPLIT's real hub base runs Odoo and
# OpenELIS in two separate Postgres containers with different bootstrap
# superusers; the mini and every clinic run one container for both, and
# hub_compose_env always defaults these two keys from BASE_PG_CONTAINER/
# BASE_PG_SUPERUSER, so the fallback here only matters for an .env composed
# before this key pair existed. dbz_clinlims_down's slot lives on ELIS;
# dbz_odoo_down's stays on PG.
ELIS="${BASE_ELIS_CONTAINER:-$PG}"; ELIS_SUPERUSER="${BASE_ELIS_SUPERUSER:-$BASE_PG_SUPERUSER}"
# CONNECT_URL: an already-exported value wins (hub/install/tests/test_sources.sh
# sets one to reach its own renamed, differently-published Connect instance)
# before falling back to hub/.env's own KAFKA_CONNECT_URL (an operator's real
# customization), before the bare default -- in that order, so a test override
# is never shadowed by hub/.env, and an operator's real KAFKA_CONNECT_URL is
# never shadowed by a bare default either.
CONNECT_URL="${CONNECT_URL:-${KAFKA_CONNECT_URL:-http://localhost:8083}}"

TMP_DIR="$(mktemp -d "${HUB_DIR}/.task080.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- 1. MySQL version gate: Debezium 3.6.2 supports MySQL 8.0.x only -------
# Task 000 still tolerates 5.6 (its binlog-fitness reads work on either); this
# is the one place that turns "the Azure hub is still 5.6" into a named,
# actionable failure instead of a connector that silently never comes up.
mysql_root(){ ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N' 2>&1 | mask_env_secrets REMOTE_MYSQL_PASSWORD DEBEZIUM_DB_PASSWORD; }
ver="$(printf 'select version()' | mysql_root | head -1)"
major="${ver%%.*}"
case "$major" in
  ''|*[!0-9]*) fail "could not read a numeric MySQL major version from ${MY} (got '${ver}')" ;;
esac
[ "$major" -ge 8 ] || fail "base mysql ${ver} on ${MY} is below major version 8 -- Debezium 3.6.2 supports MySQL 8.0.x only. docs/superpowers/plans/2026-09-17-fleet-on-staging-versions.md rebuilds the hub's base on 8.0.39; run that plan before this task."
ok "base mysql version ${ver} fit for Debezium 3.6.2 (major >= 8)"

# --- 2. MySQL down-source: render to a gitignored file, PUT-of-config ------
GENERATED="${HUB_DIR}/connectors/mysql-cloud-source-connector.json"
bash "${HUB_DIR}/scripts/generate-cloud-source-connector.sh" "$GENERATED" >/dev/null
ok "mysql-cloud-source-connector.json rendered from hub/tables.conf (${GENERATED}, gitignored)"
body="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(json.dumps(d.get("config", d)))
' "$GENERATED")"
put_out="${TMP_DIR}/mysql-put.out"
code="$(printf '%s' "$body" | curl -s -o "$put_out" -w '%{http_code}' -X PUT -H 'Content-Type: application/json' --data-binary @- "${CONNECT_URL}/connectors/mysql-cloud-source-connector/config")"
if [ "$code" -lt 300 ]; then
  ok "mysql-cloud-source-connector registered (HTTP ${code})"
else
  fail "mysql-cloud-source-connector registration failed (HTTP ${code}): $(mask_env_secrets DEBEZIUM_DB_PASSWORD < "$put_out")"
fi

# --- 3. Odoo + OpenELIS relay sources: reuse register-odoo.sh, NODE=cloud --
# register-odoo.sh always exits 0 once it has rendered a body (a bad HTTP
# code from Connect is only echoed, never turned into a failing exit), so
# success is read from its own "<name>: HTTP <code>" lines, not its exit
# status. Its output carries no config text on the happy path (just those
# status lines); on the unhappy path it dumps Connect's error body, which is
# masked before this task ever prints it, on the chance Connect echoed a
# submitted value back.
reg_out="$(CONNECT_URL="$CONNECT_URL" NODE=cloud bash "${HUB_DIR}/connectors/register-odoo.sh" odoo-cloud-source clinlims-cloud-source 2>&1 || true)"
printf '%s\n' "$reg_out" | mask_env_secrets ODOO_DB_PASSWORD CLINLIMS_SOURCE_PASSWORD ODOO_SINK_PASSWORD CLINLIMS_SINK_PASSWORD | sed 's/^/  /'
for name in odoo-cloud-source clinlims-cloud-source; do
  printf '%s\n' "$reg_out" | grep -qE "^  ${name}: HTTP 2[0-9][0-9]\$" \
    || fail "${name} did not register with a 2xx (see masked output above)"
done
ok "odoo-cloud-source, clinlims-cloud-source registered via connectors/register-odoo.sh NODE=cloud"

# --- 4. Wait for every connector AND every task RUNNING (per-name, bounded) -
# Before anything that depends on a connector having actually started doing
# work (the schema-history topic below, the replication slots) -- RUNNING is
# reported once Connect's REST API sees the task, which can be milliseconds
# after the config PUT, well before a fresh MySQL source has created its
# schema-history topic or a fresh Postgres source has opened its slot. The
# clinic's own task 090 asserts this fleet-wide (`connectors?expand=status`,
# any task not RUNNING fails the lot); here each of the three names is
# checked and timed out individually so a stuck connector is named, not
# lumped into an anonymous "tasks not RUNNING" list.
wait_running(){ # NAME MAX_SECONDS
  local name="$1" secs="${2:-180}" i state good
  for i in $(seq 1 $((secs/5))); do
    state="$(curl -s "${CONNECT_URL}/connectors/${name}/status" 2>/dev/null)"
    if printf '%s' "$state" | jq -e 'select((.connector.state=="RUNNING") and ((.tasks|length)>0) and ([.tasks[].state]|all(.=="RUNNING")))' >/dev/null 2>&1; then
      ok "${name}: connector RUNNING, tasks $(printf '%s' "$state" | jq -c '[.tasks[].state]')"
      return 0
    fi
    sleep 5
  done
  fail "${name} did not reach RUNNING (connector+tasks) within ${secs}s -- last status: $(printf '%s' "${state:-}" | jq -c '{connector: .connector.state, tasks: [.tasks[].state]}' 2>/dev/null || printf 'unreachable/unparseable')"
}
wait_running mysql-cloud-source-connector 180
wait_running odoo-cloud-source 180
wait_running clinlims-cloud-source 180

# --- 5. Schema-history retention (F-045) ------------------------------------
# A bounded wait for the topic itself first: RUNNING (just proven above) is
# not proof the schema-history topic already exists -- Debezium creates it
# lazily, on its first schema-history write, which can trail RUNNING by a few
# seconds on a freshly-registered source (caught live: a one-shot attempt
# here failed the very first time this task ran end to end).
schema_topic="schema-changes.${CLOUD_MYSQL_SERVER_NAME}"
topic_seen=0
for i in $(seq 1 24); do
  ct exec "$KAFKA_CONTAINER" kafka-topics --bootstrap-server kafka:29092 --list 2>/dev/null | grep -qx "$schema_topic" && { topic_seen=1; break; }
  sleep 5
done
[ "$topic_seen" = 1 ] || fail "topic ${schema_topic} never appeared within 120s of mysql-cloud-source-connector reaching RUNNING"
bash "${REPO_DIR}/clinic/scripts/set-schema-history-retention.sh" "$CT" kafka:29092 >/dev/null
# `| head -1`: --describe's own output repeats "retention.ms=-1" a second
# time inside its trailing `synonyms={...}` clause on the SAME line, so a
# bare `grep -oE` (the brief's literal text) prints the match twice --
# caught live: the config was already correct and this still failed the
# exact-string compare below on the doubled output. clinic/scripts/set-
# schema-history-retention.sh's own read-back already guards this
# (`grep -oE '...' | head -1`); mirrored here for the same reason.
ret="$(ct exec "$KAFKA_CONTAINER" kafka-configs --bootstrap-server kafka:29092 --entity-type topics --entity-name "$schema_topic" --describe | grep -oE 'retention.ms=-1' | head -1)"
[ "$ret" = "retention.ms=-1" ] && ok "schema-changes.${CLOUD_MYSQL_SERVER_NAME} retention -1" || fail "schema-changes.${CLOUD_MYSQL_SERVER_NAME} retention is not -1 (F-045)"

# --- 6. Postgres replication slots: both present and active ----------------
# Bounded wait, same reason as step 5's schema-history topic: RUNNING is
# reported once the task starts, which can precede the slot actually being
# created (Debezium creates it lazily too) or precede it showing
# active=true. Ruling 14 tags each Postgres source's JMX metrics with its own
# database (custom.metric.tags), which stops the two same-topic.prefix
# connectors from colliding on Debezium's MBean names -- the actual root
# cause traced in Fix round 1 of io.debezium.pipeline.ChangeEventSourceCoordinator
# stalling behind repeated "Unable to register metrics as an old set with the
# same name ... retrying" before it would proceed to START_REPLICATION (the
# call that flips pg_replication_slots.active to true). With that collision
# gone this should resolve in the ~2-minute range a single connector traced
# at, but the bound is Ruling 13's flat 15 minutes (900s) regardless, with a
# progress line every 30s naming the still-inactive slot -- generous enough
# to absorb host contention (this dev Mac shares ~20 other containers with
# this test) without a production install ever approaching it.
pg_admin(){ # CONTAINER SUPERUSER SQL
  ct exec -i "$1" psql -U "$2" -d postgres -v ON_ERROR_STOP=1 -q -Atc "$3"
}
wait_slot(){ # SLOT CONTAINER SUPERUSER MAX_SECONDS
  # NOTE (found live while proving this round): `slot_name || '|' || active`
  # concatenates the boolean through Postgres's ::text cast, which renders
  # "true"/"false" -- not the "t"/"f" a BARE boolean column shows under
  # psql's -At (confirmed directly: `select slot_name, active from
  # pg_replication_slots` gives `dbz_odoo_down|t`, but this query's own `||`
  # form gives `dbz_odoo_down|true` on the same row, same Postgres 16). The
  # comparison below was inherited from Fix round 1 checking for "|t", which
  # can never match this query's actual output regardless of how long it
  # waits -- a pre-existing defect this round's new progress line (Ruling
  # 13) surfaced live, not a new one introduced here.
  local slot="$1" ct_name="$2" su="$3" secs="${4:-900}" i row elapsed=0
  for i in $(seq 1 $((secs/5))); do
    row="$(pg_admin "$ct_name" "$su" "select slot_name || '|' || active from pg_replication_slots where slot_name = '${slot}'")"
    [ "$row" = "${slot}|true" ] && { ok "replication slot ${slot} active"; return 0; }
    elapsed=$((elapsed+5))
    [ $((elapsed % 30)) -eq 0 ] && info "still waiting on replication slot ${slot} to become active (${elapsed}s/${secs}s elapsed; last read: ${row:-<not found>})"
    sleep 5
  done
  case "$row" in
    "${slot}|false") fail "replication slot ${slot} exists but never became active within ${secs}s" ;;
    *) fail "replication slot ${slot} not found in pg_replication_slots within ${secs}s" ;;
  esac
}
wait_slot dbz_odoo_down "$PG" "$BASE_PG_SUPERUSER" 900
wait_slot dbz_clinlims_down "$ELIS" "$ELIS_SUPERUSER" 900

# --- 7. The MySQL source's schema-changes topic exists ----------------------
# (Already proven once, as a precondition, in step 5's bounded wait -- this is
# ruling 8's own separate, explicit `kafka-topics --list` assertion.)
topics="$(ct exec "$KAFKA_CONTAINER" kafka-topics --bootstrap-server kafka:29092 --list)"
printf '%s\n' "$topics" | grep -qx "$schema_topic" \
  && ok "topic ${schema_topic} exists" \
  || fail "topic ${schema_topic} not found in kafka-topics --list"

# --- 8. Heartbeat: assert the keys the templates already carry, never PATCH -
# 050 owns the heartbeat tables and publication membership, and both Postgres
# templates already carry heartbeat.interval.ms / heartbeat.action.query /
# <schema>.dbz_heartbeat in table.include.list from the start -- calling
# clinic/scripts/apply-slot-heartbeat.sh here would PUT the same values back,
# restart both sources and sleep 30s to prove nothing new. Read back from
# Connect's own /config instead: GET can return database.password verbatim,
# so only isolated, non-secret fields are ever pulled out of it -- the raw
# response is never assigned to a variable this task then prints.
assert_heartbeat(){ # NAME SCHEMA
  local name="$1" schema="$2" needle="${2}.dbz_heartbeat" has_hb ival query
  has_hb="$(curl -s "${CONNECT_URL}/connectors/${name}/config" | jq -r --arg t "$needle" '((.["table.include.list"] // "") | split(",") | index($t)) != null')"
  [ "$has_hb" = true ] && ok "${name}: table.include.list carries ${needle}" || fail "${name}: table.include.list missing ${needle}"
  ival="$(curl -s "${CONNECT_URL}/connectors/${name}/config" | jq -r '.["heartbeat.interval.ms"] // empty')"
  [ -n "$ival" ] && ok "${name}: heartbeat.interval.ms=${ival}" || fail "${name}: heartbeat.interval.ms missing"
  query="$(curl -s "${CONNECT_URL}/connectors/${name}/config" | jq -r '.["heartbeat.action.query"] // empty')"
  case "$query" in
    *"${needle}"*) ok "${name}: heartbeat.action.query = ${query}" ;;
    *) fail "${name}: heartbeat.action.query missing or does not target ${needle} (got: ${query:-<empty>})" ;;
  esac
}
assert_heartbeat odoo-cloud-source public
assert_heartbeat clinlims-cloud-source clinlims

ok "hub sources registered and proven: mysql-cloud-source-connector, odoo-cloud-source, clinlims-cloud-source all RUNNING; dbz_odoo_down/dbz_clinlims_down slots active; schema-changes.${CLOUD_MYSQL_SERVER_NAME} retention -1; heartbeat keys present on both postgres sources"
