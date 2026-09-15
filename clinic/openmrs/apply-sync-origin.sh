#!/usr/bin/env bash
# SUPERSEDED 2026-09-09 on clinic nodes by retire-mysql-origin-guard.sh: the Groovy filters
# and the person/person_name stamping triggers are retired; the loop guard is
# sessionVariables=sql_log_bin=0 on the clinic sinks (sync-core F-047).
#
# apply-sync-origin.sh — install the ADR-003 write-origin guard on one OpenMRS table.
#
# WHY THIS EXISTS. The guard is live on `person` and `person_name` but was applied by
# hand; no committed script reproduces it. So the running estate cannot be rebuilt from
# the repository, and adding a third table means someone reconstructing the DDL from
# memory. This is that script.
#
# WHAT IT INSTALLS, per table:
#   1. sync_origin varchar(16) NULL           -- who authored the row
#   2. an index on it                         -- for reconciliation queries (F-036)
#   3. a backfill of existing NULLs           -- default 'cloud', see below
#   4. BEFORE INSERT and BEFORE UPDATE triggers that stamp local writes and preserve
#      the far node's stamp on sink writes
#
# WHY THE DEFAULT IS 'cloud'. Existing rows came from the shared install image and are
# byte-identical on every node; no node minted them. Stamping them 'cloud' is
# DETERMINISTIC -- every node computes the same owner, so exactly one publisher exists.
# Stamping them by residue instead would give a residue-3 row to Ghated AND to Rawach's
# copy of it, and a residue-5 row to whichever node ran first: two publishers for one
# row, the L-008 violation the guard exists to prevent. (Learned on the Odoo guard,
# 2026-09-04.)
#
# ############################################################################
# # THE RE-REPLICATION HAZARD -- READ THIS BEFORE USING --apply ON A LIVE NODE
# ############################################################################
# The backfill is an UPDATE, and an UPDATE on a captured table produces a CDC event per
# row. On the CLOUD, whose source connector carries no origin filter, stamping N rows
# 'cloud' makes the cloud publish all N to every clinic -- rows those clinics already
# hold identically from the same install image. For `person` that is ~121,700 rows per
# table, against a cloud with ~2.2 GB of host headroom. That is the shape of F-022,
# where the cloud filled its disk and Kafka died.
#
# So: install the guard on a table BEFORE adding it to any capture list. This script
# refuses to touch a table that is already captured unless --captured-ok is given, and
# always prints the blast radius first.
#
# USER(), NEVER CURRENT_USER(). CURRENT_USER() returns the trigger's definer, so it
# stamps every row identically while looking correctly installed.
#
# Usage:
#   ./apply-sync-origin.sh --table obs --node rawach              # dry run (default)
#   ./apply-sync-origin.sh --table obs --node rawach --apply
#   ./apply-sync-origin.sh --table obs --node cloud --apply --captured-ok
set -euo pipefail

TABLE=""; NODE=""; DEFAULT_ORIGIN="cloud"; APPLY=0; CAPTURED_OK=0
CTR="${MYSQL_CONTAINER:-bahmni-local-bahmni-mysql-1}"
DB="${OPENMRS_DB:-openmrs}"
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"

while [ $# -gt 0 ]; do
  case "$1" in
    --table)   TABLE="$2"; shift 2 ;;
    --node)    NODE="$2"; shift 2 ;;
    --default) DEFAULT_ORIGIN="$2"; shift 2 ;;
    --apply)   APPLY=1; shift ;;
    --captured-ok) CAPTURED_OK=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$TABLE" ] && [ -n "$NODE" ] || { echo "usage: $0 --table <t> --node <n> [--default cloud] [--apply] [--captured-ok]" >&2; exit 2; }
case "$NODE" in *[!a-z]*) echo "node must be lowercase letters (it is embedded in the trigger body)" >&2; exit 2 ;; esac

CTR_RT="${CTR_RT:-}"
if [ -z "$CTR_RT" ]; then
  if command -v docker >/dev/null 2>&1; then CTR_RT=docker
  elif command -v podman >/dev/null 2>&1; then CTR_RT=podman
  else echo "no docker or podman on PATH" >&2; exit 2; fi
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PW="$(set -a; . "$ROOT/.env" >/dev/null 2>&1; set +a; printf '%s' "${MYSQL_ROOT_PASSWORD:-${OPENMRS_DB_PASSWORD:-}}")"
[ -n "$PW" ] || { echo "no MySQL root password in $ROOT/.env" >&2; exit 2; }
q() { "$CTR_RT" exec -e MYSQL_PWD="$PW" "$CTR" mysql -uroot -N -B "$DB" -e "$1" 2>/dev/null | grep -v '^mysql:'; }

say() { printf '  %s\n' "$*"; }

# ---- preconditions -----------------------------------------------------------------
[ "$(q "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB' AND TABLE_NAME='$TABLE';")" = "1" ] \
  || { echo "  no such table: $DB.$TABLE" >&2; exit 1; }

HAS_COL=$(q "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$DB' AND TABLE_NAME='$TABLE' AND COLUMN_NAME='sync_origin';")
ROWS=$(q "SELECT COUNT(*) FROM \`$TABLE\`;")
if [ "$HAS_COL" = "1" ]; then
  NULLS=$(q "SELECT COUNT(*) FROM \`$TABLE\` WHERE sync_origin IS NULL;")
else
  NULLS="$ROWS"
fi

say "table            : $DB.$TABLE on $CTR"
say "node             : $NODE"
say "rows             : $ROWS"
say "column present   : $([ "$HAS_COL" = 1 ] && echo yes || echo no)"
say "would backfill   : $NULLS rows -> '$DEFAULT_ORIGIN'"

# ---- the blast radius --------------------------------------------------------------
# A table already being captured means the backfill UPDATE becomes N CDC events.
CAPTURED=""
if command -v curl >/dev/null 2>&1; then
  for c in $(curl -s "$CONNECT_URL/connectors" 2>/dev/null | tr ',' '\n' | tr -d '[]"'); do
    [ -z "$c" ] && continue
    if curl -s "$CONNECT_URL/connectors/$c/config" 2>/dev/null | grep -q "\"table.include.list\".*[.\"]$TABLE[,\"]"; then
      CAPTURED="$CAPTURED $c"
    fi
  done
fi
if [ -n "$CAPTURED" ]; then
  say ""
  say "!! ALREADY CAPTURED by:$CAPTURED"
  say "!! The backfill would emit ~$NULLS CDC events for rows every node already holds."
  say "!! Install the guard BEFORE adding a table to a capture list. See the header."
  [ "$CAPTURED_OK" -eq 1 ] || { echo "  refusing without --captured-ok" >&2; exit 1; }
  say "!! --captured-ok given; proceeding anyway."
fi

if [ "$APPLY" -eq 0 ]; then
  say ""
  say "DRY RUN — nothing changed. Re-run with --apply to install."
  exit 0
fi

# ---- install -----------------------------------------------------------------------
# Triggers are dropped BEFORE the backfill, not after: on a re-run the previous run's
# trigger would fire from inside the backfill's own UPDATE and overwrite every computed
# value with this node's name. Measured on the Odoo guard, 2026-09-04.
say ""
say "installing ..."
[ "$HAS_COL" = "1" ] || q "ALTER TABLE \`$TABLE\` ADD COLUMN sync_origin varchar(16) NULL;"
q "SELECT 1;" >/dev/null

HAS_IDX=$(q "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='$DB' AND TABLE_NAME='$TABLE' AND COLUMN_NAME='sync_origin';")
[ "$HAS_IDX" -gt 0 ] || q "ALTER TABLE \`$TABLE\` ADD INDEX idx_${TABLE}_sync_origin (sync_origin);"

q "DROP TRIGGER IF EXISTS ${TABLE}_origin_ins;"
q "DROP TRIGGER IF EXISTS ${TABLE}_origin_upd;"

q "UPDATE \`$TABLE\` SET sync_origin = '$DEFAULT_ORIGIN' WHERE sync_origin IS NULL;"

q "CREATE TRIGGER ${TABLE}_origin_ins BEFORE INSERT ON \`$TABLE\` FOR EACH ROW
   SET NEW.sync_origin = IF(SUBSTRING_INDEX(USER(),'@',1)='sink', NEW.sync_origin, '$NODE');"
q "CREATE TRIGGER ${TABLE}_origin_upd BEFORE UPDATE ON \`$TABLE\` FOR EACH ROW
   SET NEW.sync_origin = IF(SUBSTRING_INDEX(USER(),'@',1)='sink', NEW.sync_origin, '$NODE');"

# ---- verify ------------------------------------------------------------------------
say ""
say "verifying:"
say "  remaining NULL   : $(q "SELECT COUNT(*) FROM \`$TABLE\` WHERE sync_origin IS NULL;")"
say "  triggers         : $(q "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='$DB' AND EVENT_OBJECT_TABLE='$TABLE';")"
say "  index            : $(q "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='$DB' AND TABLE_NAME='$TABLE' AND COLUMN_NAME='sync_origin';")"
say "  origins          : $(q "SELECT GROUP_CONCAT(CONCAT(COALESCE(sync_origin,'null'),'=',n) SEPARATOR '  ') FROM (SELECT sync_origin, COUNT(*) n FROM \`$TABLE\` GROUP BY sync_origin) x;")"
say ""
say "done. The table is guarded but NOT yet synced -- add it to the capture lists"
say "and the MM2 allowlist separately, and remember a table in BOTH directions is the"
say "only kind that can loop."
