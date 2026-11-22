#!/usr/bin/env bash
# Usage: clinic/scripts/pull-clinical-forms.sh <ssh-host> <openmrs-container>
# Copies the hub's form files (/home/bahmni/clinical_forms in its OpenMRS container, translations/ included)
# into clinic/bahmni_home/clinical_forms, the copy clinics mount when no forms repo is configured.
# Files are added or updated, never deleted: observations saved with an old form version need its file.
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: $0 <ssh-host> <openmrs-container>" >&2; exit 1; }
HOST=$1
CONTAINER=$2
DEST="$(cd "$(dirname "$0")/.." && pwd)/bahmni_home/clinical_forms"
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
