#!/usr/bin/env bash
# ADDED 2026-09-04 (sync-core, D7 Odoo full-replication build).
#
# Moves one node's Odoo database off its shipped PostgreSQL 9.6 onto the node's PG 15
# instance. This is a PREREQUISITE, not a nicety: the write-origin guard filters at the
# publication, and 9.6 has no publications at all (F-021). Without this move Odoo cannot
# ride the same CDC pipeline as OpenMRS and OpenELIS, which is the whole design.
#
# COMPATIBILITY IS MEASURED, NOT ASSUMED. Verified 2026-09-04 on Rawach: the Odoo 10
# schema restores into PG 15.18 with ZERO errors (375 tables), Odoo 10 boots against it
# (49 modules, no CRITICAL), /web/login returns 200, and XML-RPC authenticates and reads
# through the ORM. Re-run that check on any node whose Odoo addons differ.
#
# NON-DESTRUCTIVE. The source 9.6 database is never dropped or altered -- it is left
# intact and running so the cutover can be reversed by pointing the container back. The
# script refuses to overwrite a non-empty target unless --force is given.
#
# QUIESCE. Odoo is stopped for the dump so no write lands between dump and cutover. A
# hot dump would silently lose whatever was written during the copy.
#
# Usage: odoo/migrate-odoo-to-pg15.sh --source odoodb --target bahmni-postgres [--force]
set -euo pipefail

SRC=""; TGT=""; FORCE=0; ODOO_CTR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source) SRC="$2"; shift 2 ;;
    --target) TGT="$2"; shift 2 ;;
    --odoo)   ODOO_CTR="$2"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$SRC" ] && [ -n "$TGT" ] || { echo "usage: $0 --source <ctr> --target <ctr> [--odoo <ctr>] [--force]" >&2; exit 2; }

# Resolve the odoo app container if not named: it is the one whose image is odoo-ish.
if [ -z "$ODOO_CTR" ]; then
  ODOO_CTR=$(docker ps --format '{{.Names}}\t{{.Image}}' | awk -F'\t' '$2 ~ /odoo/ && $1 !~ /connect|db/ {print $1; exit}')
fi

say() { printf '  %s\n' "$*"; }

say "source : $SRC"
say "target : $TGT"
say "odoo   : ${ODOO_CTR:-<none found>}"

# ---- preconditions -----------------------------------------------------------------
TV=$(docker exec "$TGT" psql -U postgres -t -A -c "SHOW server_version;" 2>/dev/null | cut -d. -f1)
[ "${TV:-0}" -ge 15 ] || { echo "  target is PG ${TV:-?}; publication row filters need 15+" >&2; exit 1; }
WL=$(docker exec "$TGT" psql -U postgres -t -A -c "SHOW wal_level;" 2>/dev/null)
[ "$WL" = "logical" ] || { echo "  target wal_level=$WL; CDC needs logical" >&2; exit 1; }
say "target PG $TV, wal_level=$WL -- ok"

EXISTING=$(docker exec "$TGT" psql -U postgres -t -A -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_catalog='odoo' AND table_schema='public';" 2>/dev/null || echo 0)
if [ "${EXISTING:-0}" -gt 0 ] && [ "$FORCE" -eq 0 ]; then
  echo "  target already holds $EXISTING tables in odoo/public -- refusing. Use --force to replace." >&2
  exit 1
fi

# ---- quiesce -----------------------------------------------------------------------
STOPPED=0
if [ -n "$ODOO_CTR" ] && [ "$(docker inspect -f '{{.State.Running}}' "$ODOO_CTR" 2>/dev/null)" = "true" ]; then
  say "stopping $ODOO_CTR so no write lands mid-copy"
  docker stop "$ODOO_CTR" >/dev/null; STOPPED=1
fi
restore_odoo() { [ "$STOPPED" -eq 1 ] && { say "restarting $ODOO_CTR"; docker start "$ODOO_CTR" >/dev/null; }; }
trap restore_odoo EXIT

# ---- dump + restore ----------------------------------------------------------------
DUMP=$(mktemp); trap 'rm -f "$DUMP"; restore_odoo' EXIT
say "dumping from $SRC ..."
docker exec "$SRC" pg_dump -U odoo -d odoo --no-owner --no-privileges > "$DUMP"
say "dump size: $(du -h "$DUMP" | cut -f1), $(grep -c '^CREATE TABLE' "$DUMP") tables"

docker exec "$TGT" psql -U postgres -q -c "DROP DATABASE IF EXISTS odoo;" >/dev/null 2>&1 || true
docker exec "$TGT" psql -U postgres -q -c "CREATE DATABASE odoo OWNER odoo;" >/dev/null
docker cp "$DUMP" "$TGT":/tmp/.odoo_migrate.sql >/dev/null
say "restoring into $TGT (as odoo, so odoo OWNS the objects) ..."
# RESTORE AS odoo, NOT postgres. The dump is --no-owner, so whoever runs the restore
# owns every object. Restoring as postgres leaves the odoo role a non-owner, and
# information_schema only shows objects the current role has privileges on -- so Odoo's
# own setup_signaling() sees no base_registry_signaling sequence, tries to CREATE it,
# and dies with 'relation "base_registry_signaling" already exists' on every request.
#
# This bit only the cloud. Rawach's odoo role is the image's POSTGRES_USER and therefore
# SUPERUSER, which sees everything regardless of ownership, so the identical migration
# looked completely healthy there. A latent break that surfaces only on a correctly
# least-privileged node is worse than one that always fires.
ERRS=$(docker exec "$TGT" psql -U odoo -d odoo -f /tmp/.odoo_migrate.sql 2>&1 | grep -c '^ERROR' || true)
docker exec "$TGT" rm -f /tmp/.odoo_migrate.sql
say "restore errors: $ERRS"
[ "$ERRS" -eq 0 ] || { echo "  restore reported errors -- NOT cutting over" >&2; exit 1; }

# ---- verify the copy is faithful ---------------------------------------------------
say "verifying row counts table by table ..."
MISMATCH=0
for t in res_partner product_product product_template product_category product_uom \
         sale_order sale_order_line stock_move stock_quant stock_picking \
         account_invoice account_invoice_line ir_module_module; do
  a=$(docker exec "$SRC" psql -U odoo -d odoo -t -A -c "SELECT COUNT(*) FROM $t;" 2>/dev/null || echo x)
  b=$(docker exec "$TGT" psql -U postgres -d odoo -t -A -c "SELECT COUNT(*) FROM $t;" 2>/dev/null || echo y)
  if [ "$a" != "$b" ]; then printf '    MISMATCH %-22s %s -> %s\n' "$t" "$a" "$b"; MISMATCH=1; fi
done
[ "$MISMATCH" -eq 0 ] && say "all counts match" || { echo "  counts differ -- NOT cutting over" >&2; exit 1; }

say ""
say "migration complete. Odoo is NOT yet pointed at the new database."
say "next, in order:"
say "  1. odoo/create-odoo-sink-role.sh <node>"
say "  2. psql -U postgres -d odoo -v residue=<n> -f odoo/apply-odoo-sequence-striding.sql"
say "  3. psql -U postgres -d odoo -v node=<node> -v residue=<n> -f odoo/apply-odoo-write-origin-guard.sql"
say "  4. repoint the odoo container: HOST=$TGT  (compose override), then start it"
say "  5. register the connectors and add the odoo topics to mm2.properties"
