#!/usr/bin/env bash
# Builds ODOO_LOCAL_IMAGE from ODOO_BAHMNI_IMAGE + ODOO_BASE_IMAGE
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${HERE}/../.env"

get(){ v="${!1:-}"; [ -n "$v" ] || v="$(sed -n "s/^$1=//p" "$ENV_FILE" | tail -1)"; [ -n "$v" ] || { echo "$1 is not set in the environment or $ENV_FILE" >&2; exit 1; }; printf '%s' "$v"; }   # the environment (the installer's pins) wins over .env
LOCAL="$(get ODOO_LOCAL_IMAGE)"
BAHMNI="$(get ODOO_BAHMNI_IMAGE)"
BASE="$(get ODOO_BASE_IMAGE)"

if podman image exists "$LOCAL"; then
  echo "$LOCAL already exists"
  exit 0
fi

podman build \
  --build-arg ODOO_BAHMNI_IMAGE="$BAHMNI" \
  --build-arg ODOO_BASE_IMAGE="$BASE" \
  -t "$LOCAL" \
  "$HERE"
