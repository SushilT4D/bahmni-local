#!/usr/bin/env bash
# Builds bahmni-local/odoo-connect:<ODOO_CONNECT_IMAGE_TAG> from bahmni/odoo-connect at the same tag.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${HERE}/../.env"

TAG="$(sed -n 's/^ODOO_CONNECT_IMAGE_TAG=//p' "$ENV_FILE" | tail -1)"
[ -n "$TAG" ] || { echo "ODOO_CONNECT_IMAGE_TAG is not set in $ENV_FILE" >&2; exit 1; }
LOCAL="bahmni-local/odoo-connect:${TAG}"

if podman image exists "$LOCAL"; then
  echo "$LOCAL already exists"
  exit 0
fi

podman build --build-arg ODOO_CONNECT_IMAGE_TAG="$TAG" -t "$LOCAL" "$HERE"
