#!/usr/bin/env bash
# Seed clinic/config/odoo/odoo.conf from the ODOO IMAGE'S OWN /etc/odoo/odoo.conf.
#
# Incident (fix-round-1 review, compared against staging): the clinic compose
# mounts CONTAINER_DATA_PATH/config/odoo read-write at /etc/odoo; task 030
# creates that directory EMPTY (nothing under clinic/config/odoo is tracked in
# git), which HIDES the image's own conf underneath the empty bind mount.
# bahmni/odoo-16:1.0.0's entrypoint reads $ODOO_RC (default
# /etc/odoo/odoo.conf) with grep for db_host etc. from the environment, but it
# does not CREATE the file if absent -- so Odoo runs with no db_name (the
# shared Postgres instance also holds `openelis`, so /web/login answers 303 to
# /web/database/selector rather than 200) and no addons_path naming Bahmni's
# own add-ons. Staging mounts a file carrying the image's own options and
# answers 200. The image ships exactly what this script copies out; nothing
# here is invented.
#
# Same create+cp+rm technique as scripts/extract-ui-config.sh's pull_tree:
# the container never starts. An existing config/odoo/odoo.conf is an
# operator's own edit and is left alone.
#
# usage: [CT=docker|podman] [COMPOSE_JSON_FILE=path] scripts/seed-odoo-conf.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# A fresh `bash scripts/seed-odoo-conf.sh` subprocess never inherits the
# caller's shell functions (ok/skip/fail/... are not exported) -- source
# lib.sh whenever they are missing, standalone or wired alike (same shape as
# fix-mount-ownership.sh, its sibling in this same review round).
type ok >/dev/null 2>&1 || . "${HERE}/../install/lib.sh"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"

# Respect an already-exported CT; only setup_compose's own runtime detection
# when CT is unset (setup_compose always overwrites CT from detect_runtime,
# which would silently replace an operator's explicit CT=docker with podman
# on macOS).
if [ -z "${CT:-}" ]; then
  setup_compose
elif [ -z "${COMPOSE_CMD:-}" ]; then
  if [ "${CT}" = docker ]; then
    COMPOSE_CMD="docker compose"
  else
    COMPOSE_CMD="docker-compose"
    [ -n "${DOCKER_HOST:-}" ] || export DOCKER_HOST="$(podman_socket)"
  fi
fi
export CT COMPOSE_CMD

begin_task "seed-odoo-conf: the odoo image's own /etc/odoo/odoo.conf"

DEST="${CLINIC_DIR}/config/odoo/odoo.conf"
# pin_dbfilter FILE : a clinic runs Odoo on the SHARED PostgreSQL, beside the
# openelis database. The image's conf says `dbfilter = .*` -- right on staging,
# where Odoo's PostgreSQL holds one database, wrong here: two databases match,
# so /web/login answers 303 to /web/database/selector and XML-RPC callers must
# name a database Odoo would not pick by itself (still 303 with the image's
# conf in place; /web/database/list returns odoo AND openelis). Only the
# image's match-everything default is rewritten, to the
# conf's own db_name; any other value is an operator's choice and stays.
pin_dbfilter(){
  local f="$1" db t
  db="$(sed -nE 's/^db_name[[:space:]]*=[[:space:]]*([A-Za-z0-9_-]+)[[:space:]]*$/\1/p' "$f" | head -1)"
  [ -n "$db" ] || return 0
  grep -qE '^dbfilter[[:space:]]*=[[:space:]]*\.\*[[:space:]]*$' "$f" || return 0
  t="$(mktemp "${f}.XXXXXX")"
  sed -E "s/^dbfilter[[:space:]]*=[[:space:]]*\.\*[[:space:]]*\$/dbfilter = ^${db}\$/" "$f" > "$t" && chmod 644 "$t" && mv "$t" "$f"
  ok "config/odoo/odoo.conf: dbfilter pinned to ^${db}\$ (shared PostgreSQL also holds openelis)"
}

if [ -f "$DEST" ]; then
  if [ "${DRY}" = 1 ]; then info "would pin dbfilter in the existing config/odoo/odoo.conf if it is still the image's '.*'"; else pin_dbfilter "$DEST"; fi
  skip "config/odoo/odoo.conf already exists -- an operator's edits win"
  exit 0
fi

# COMPOSE_JSON_FILE is a testability hook: tests feed a fixture through it
# instead of a real compose config.
json="${COMPOSE_JSON_FILE:-}"
cleanup_json=0
if [ -z "$json" ]; then
  json="$(mktemp)"; cleanup_json=1
  ( cd "${CLINIC_DIR}" && compose config --format json ) > "$json" || fail "compose config --format json failed"
fi
# `[ cond ] && rm ...` would return the test's own (non-)zero status when
# cond is false -- fine standalone, but this runs as the EXIT trap, where a
# non-zero return re-triggers lib.sh's ERR trap on the way out (found the hard
# way in fix-mount-ownership.sh's own first draft). An explicit if is always 0.
cleanup(){ if [ "$cleanup_json" = 1 ]; then rm -f "$json"; fi; }
trap cleanup EXIT

image="$(python3 - "$json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
svc = (data.get("services") or {}).get("odoo")
print(svc.get("image", "") if svc and svc.get("image") else "")
PY
)"
[ -n "$image" ] || fail "no 'odoo' service (with an image) in the merged compose config"

if [ "${DRY}" = 1 ]; then
  info "would copy ${image}:/etc/odoo/odoo.conf -> config/odoo/odoo.conf"
  exit 0
fi

mkdir -p "$(dirname "$DEST")"
tmp="$(mktemp -d)"
cid="$(ct create "$image")" || { rm -rf "$tmp"; fail "could not create a container from ${image}"; }
if ! ct cp "${cid}:/etc/odoo/odoo.conf" "${tmp}/odoo.conf" >/dev/null 2>&1; then
  ct rm "$cid" >/dev/null 2>&1 || true
  rm -rf "$tmp"
  fail "${image} has no /etc/odoo/odoo.conf"
fi
ct rm "$cid" >/dev/null 2>&1 || true

# accepted only if it looks like what a Bahmni Odoo actually needs -- a plain
# empty/renamed odoo.conf from an unrelated image must never be planted here
if ! grep -q '^db_name' "${tmp}/odoo.conf" || ! grep -q 'bahmni-addons' "${tmp}/odoo.conf"; then
  rm -rf "$tmp"
  fail "${image}:/etc/odoo/odoo.conf is not the Bahmni Odoo image's conf (no db_name, or no bahmni-addons in addons_path)"
fi

chmod 644 "${tmp}/odoo.conf"; mv "${tmp}/odoo.conf" "$DEST"; rm -rf "$tmp"
ok "config/odoo/odoo.conf seeded from ${image}"
pin_dbfilter "$DEST"
