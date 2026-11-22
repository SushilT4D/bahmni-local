#!/usr/bin/env bash
# Usage: clinic/scripts/pull-clinical-forms.sh [<openmrs-container>]
# Copies the hub's form files (/home/bahmni/clinical_forms in its OpenMRS container, translations/ included)
# into clinic/bahmni_home/clinical_forms, the copy clinics mount when no forms repo is configured.
# Files are added or updated, never deleted: observations saved with an old form version need its file.
# The hub is the host in clinic/.env's REMOTE_KAFKA_BOOTSTRAP_SERVERS; the container defaults to the
# hub's one running OpenMRS (not its database).
set -euo pipefail

CLINIC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOST="$(sed -n 's/^REMOTE_KAFKA_BOOTSTRAP_SERVERS=//p' "${CLINIC_DIR}/.env" 2>/dev/null | tail -1 | cut -d, -f1 | sed -E 's/:[0-9]+$//')"
[ -n "$HOST" ] || { echo "REMOTE_KAFKA_BOOTSTRAP_SERVERS is not set in ${CLINIC_DIR}/.env" >&2; exit 1; }
CONTAINER="${1:-$(ssh "$HOST" "sudo -n docker ps --format '{{.Names}}'" | grep -i openmrs | grep -vi db | head -1)}"
[ -n "$CONTAINER" ] || { echo "no OpenMRS container found on $HOST: pass its name" >&2; exit 1; }
DEST="${CLINIC_DIR}/bahmni_home/clinical_forms"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ssh "$HOST" "sudo -n docker exec $CONTAINER tar -C /home/bahmni -cf - clinical_forms" | tar -C "$TMP" -xf -
[ -d "$TMP/clinical_forms" ] || { echo "no clinical_forms came back from $HOST:$CONTAINER" >&2; exit 1; }

links="$(find "$TMP/clinical_forms" -type l)"
[ -z "$links" ] || { printf 'refused: the hub folder holds symlinks, which OpenMRS would follow:\n%s\n' "$links" >&2; exit 1; }

added=0; changed=0; same=0
while IFS= read -r f; do
  rel="${f#"$TMP/clinical_forms/"}"
  if [ ! -e "$DEST/$rel" ]; then added=$((added + 1))
  elif cmp -s "$f" "$DEST/$rel"; then same=$((same + 1)); continue
  else changed=$((changed + 1)); fi
  mkdir -p "$(dirname "$DEST/$rel")"
  cp "$f" "$DEST/$rel"
  printf '  %s\n' "$rel"
done < <(find "$TMP/clinical_forms" -type f | sort)

echo "clinical_forms from $HOST:$CONTAINER: $added added, $changed updated, $same unchanged -> ${DEST}"
echo "Commit clinic/bahmni_home/clinical_forms; each clinic gets the files when it pulls and reruns --from 075."
