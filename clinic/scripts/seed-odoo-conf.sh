#!/usr/bin/env bash
# Seed Odoo's config from the image without starting the container.
# Usage: [COMPOSE_JSON_FILE=path] scripts/seed-odoo-conf.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load installer helpers when invoked as a standalone subprocess.
type ok >/dev/null 2>&1 || . "${HERE}/../install/lib.sh"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"

setup_compose

begin_task "seed-odoo-conf: the odoo image's own /etc/odoo/odoo.conf"

DEST="${CLINIC_DIR}/config/odoo/odoo.conf"
# Limit the image's catch-all dbfilter to Odoo's database on shared PostgreSQL.
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

# Allow tests to supply a Compose config fixture.
json="${COMPOSE_JSON_FILE:-}"
cleanup_json=0
if [ -z "$json" ]; then
  json="$(mktemp)"; cleanup_json=1
  compose_json > "$json" || fail "compose config could not be read as JSON"
fi
# Keep the EXIT trap successful when no temporary config was created.
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
