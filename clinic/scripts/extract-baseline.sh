#!/usr/bin/env bash
# Copies the three baseline dumps out of the pinned database images into DEST
# as openmrs.sql.gz, odoo.sql.gz and openelis.sql.gz. The images are created,
# never run (--platform linux/amd64: they are amd64 images and are only read).
# Usage: CT=docker|podman scripts/extract-baseline.sh DEST
set -euo pipefail
CT="${CT:-docker}"; DEST="${1:?usage: extract-baseline.sh DEST}"
die(){ printf '  FAIL %s\n' "$*" >&2; exit 1; }
: "${BASELINE_OPENMRS_IMAGE:?set in sync/versions.env}" "${BASELINE_ODOO_IMAGE:?set in sync/versions.env}" "${BASELINE_OPENELIS_IMAGE:?set in sync/versions.env}"
mkdir -p "$DEST"; TMPD="$(mktemp -d "${DEST}/.x.XXXXXX")"; trap 'rm -rf "$TMPD"' EXIT
take(){ # IMAGE PATH-IN-IMAGE OUT-NAME
  local img="$1" p="$2" out="$3" cid f
  "$CT" pull --platform linux/amd64 "$img" >/dev/null 2>&1 || true
  cid="$("$CT" create --platform linux/amd64 "$img" 2>/dev/null)" || die "cannot create a container from ${img} (pull it first: ${CT} pull --platform linux/amd64 ${img})"
  f="$TMPD/$(basename "$p")"
  if ! "$CT" cp "${cid}:${p}" "$f" >/dev/null 2>&1; then "$CT" rm "$cid" >/dev/null 2>&1 || true; die "${img} has no ${p}"; fi
  "$CT" rm "$cid" >/dev/null 2>&1 || true
  case "$f" in *.gz) mv "$f" "$DEST/${out}.sql.gz" ;; *) gzip -c "$f" > "$DEST/${out}.sql.gz"; rm -f "$f" ;; esac
  gzip -t "$DEST/${out}.sql.gz" || die "${out}.sql.gz from ${img} is not valid gzip"
  printf '  ok   baseline %s <- %s:%s\n' "$out" "$img" "$p"
}
take "$BASELINE_OPENMRS_IMAGE"  /docker-entrypoint-initdb.d/openmrsdb_backup.sql.gz openmrs
take "$BASELINE_ODOO_IMAGE"     /docker-entrypoint-initdb.d/odoodb_backup.sql.gz   odoo
take "$BASELINE_OPENELIS_IMAGE" /resources/openelis_backup.sql                      openelis
