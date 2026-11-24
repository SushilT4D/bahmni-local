#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"; export CLINIC_DIR
REPO_DIR="${REPO_DIR:-$(cd "${HERE}/../.." && pwd)}"; export REPO_DIR
. "${HERE}/../install/lib.sh"
usage(){ cat <<'EOF2'
Usage: clinic/scripts/fetch-cloud-forms.sh [--apply] [--key FILE] [--out DIR] [--openmrs NAME] [--mysql NAME]
  --apply         copy missing or changed form files into the clinic's forms folder (never deletes),
                  then upsert the cloud's form and form_resource rows into the clinic database
  --key FILE      ssh identity for ubuntu@<REMOTE_KAFKA_BOOTSTRAP_SERVERS host>
  --out DIR       where to save the fetch (default clinic/cloud-forms/<timestamp>)
  --openmrs NAME  cloud OpenMRS container, when the name search picks the wrong one
  --mysql NAME    cloud MySQL container, when the name search picks the wrong one
  -h, --help      show this help
EOF2
}
trap 'rc=$?; [ "$rc" = 0 ] || { echo >&2; usage >&2; }' EXIT
OUT=""; R_OMRS=""; R_MY=""; KEY=""; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --key) KEY="${2:?--key needs a file}"; shift 2 ;;
    --out) OUT="${2:?--out needs a directory}"; shift 2 ;;
    --openmrs) R_OMRS="${2:?--openmrs needs a name}"; shift 2 ;;
    --mysql) R_MY="${2:?--mysql needs a name}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

E="${CLINIC_DIR}/.env"
[ -f "$E" ] || fail "no ${E}: this is not an installed node"
HOST="$(env_get "$E" REMOTE_KAFKA_BOOTSTRAP_SERVERS | cut -d, -f1 | sed -E 's/:[0-9]+$//')"
LOCAL_FORMS="$(env_get "$E" FORMS_DIR)"; LOCAL_FORMS="${LOCAL_FORMS:-${CLINIC_DIR}/bahmni_home/clinical_forms}"
if [ "$APPLY" = 1 ]; then
  [ "$(env_get "$E" FORMS_READ_ONLY)" != true ] || fail "the forms folder ${LOCAL_FORMS} is mounted read-only from a forms repo; update that repo, then clinic/scripts/update-forms.sh"
  [ -d "$LOCAL_FORMS" ] || fail "no forms folder ${LOCAL_FORMS}"
fi
[ -n "$HOST" ] || fail "REMOTE_KAFKA_BOOTSTRAP_SERVERS is not set in ${E}"
HOST="ubuntu@${HOST}"
r(){ if [ -n "$KEY" ]; then ssh -i "$KEY" -o IdentitiesOnly=yes "$HOST" "$@"; else ssh "$HOST" "$@"; fi; }
OUT="${OUT:-${CLINIC_DIR}/cloud-forms/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

names="$(r "sudo -n docker ps --format '{{.Names}}'")" || fail "could not list containers on ${HOST} (ssh, then sudo -n docker ps)"
[ -n "$R_OMRS" ] || R_OMRS="$(printf '%s\n' "$names" | grep -i openmrs | grep -viE 'db|mysql' | head -1)"
[ -n "$R_MY" ]   || R_MY="$(printf '%s\n' "$names" | grep -iE 'mysql|openmrs.*db' | head -1)"
[ -n "$R_OMRS" ] || fail "no OpenMRS container on ${HOST}: pass --openmrs"
[ -n "$R_MY" ]   || fail "no MySQL container on ${HOST}: pass --mysql"
log "cloud ${HOST}: openmrs ${R_OMRS}, mysql ${R_MY}"

FORMS_SQL="select f.form_id, f.name, f.version, f.uuid, f.published, f.retired, f.date_created, f.date_changed,
 r.form_resource_id, r.name as resource_name, r.value_reference, r.datatype, r.uuid as resource_uuid
 from form f left join form_resource r on r.form_id = f.form_id order by f.name, f.version, r.form_resource_id"

remote_mysql(){ r "sudo -n docker exec -i $R_MY sh -c 'MYSQL_PWD=\"\$MYSQL_ROOT_PASSWORD\" exec mysql -uroot -B openmrs'"; }
printf '%s\n' "$FORMS_SQL" | remote_mysql > "$OUT/forms.tsv" || fail "could not read the form rows from ${R_MY}"
ok "forms.tsv: $(($(wc -l < "$OUT/forms.tsv") - 1)) rows"

r "sudo -n docker exec $R_MY sh -c 'MYSQL_PWD=\"\$MYSQL_ROOT_PASSWORD\" exec mysqldump -uroot --no-create-info --complete-insert --skip-extended-insert --skip-triggers --single-transaction openmrs form form_resource'" > "$OUT/forms.sql" \
  || fail "could not dump form and form_resource from ${R_MY}"
ok "forms.sql: $(grep -c '^INSERT' "$OUT/forms.sql") inserts"

rm -rf "$OUT/clinical_forms"
r "sudo -n docker cp $R_OMRS:/home/bahmni/clinical_forms -" | tar -C "$OUT" -xf - \
  || fail "could not copy /home/bahmni/clinical_forms from ${R_OMRS}"
links="$(find "$OUT/clinical_forms" -type l)"
if [ -n "$links" ]; then
  [ "$APPLY" = 0 ] || fail "the cloud folder holds symlinks, which OpenMRS would follow; nothing applied: ${links}"
  warn "the cloud folder holds symlinks, which a clinic refuses: ${links}"
fi
ok "clinical_forms: $(find "$OUT/clinical_forms" -type f | wc -l | tr -d ' ') files"

COMPOSE_PROJECT_NAME="$(env_get "$E" COMPOSE_PROJECT_NAME)"; COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-bahmni}"
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"
[ -n "${CT:-}" ] || setup_compose
key(){ awk -F'\t' 'NR > 1 { print $4 "\t" $2 "\t" $3 "\t" $5 "\t" $6 }' | sort -u; }
key < "$OUT/forms.tsv" > "$OUT/.cloud.keys"
printf '%s\n' "$FORMS_SQL" | ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -B openmrs' | key > "$OUT/.local.keys" \
  || fail "could not read the form rows from ${MY}"

{
  echo "# compared $(date '+%F %T'): cloud ${HOST} vs clinic ${MY} and ${LOCAL_FORMS}"
  echo "# rows: uuid, name, version, published, retired"
  echo "## form rows only on the cloud"
  comm -23 "$OUT/.cloud.keys" "$OUT/.local.keys"
  echo "## form rows only on the clinic, or differing in name/version/published/retired"
  comm -13 "$OUT/.cloud.keys" "$OUT/.local.keys"
  echo "## files missing from the clinic folder"
  ( cd "$OUT/clinical_forms" && find . -type f | sed 's|^\./||' | sort ) | while IFS= read -r f; do
    [ -e "$LOCAL_FORMS/$f" ] || echo "$f"
  done
  echo "## files that differ"
  ( cd "$OUT/clinical_forms" && find . -type f | sed 's|^\./||' | sort ) | while IFS= read -r f; do
    [ ! -e "$LOCAL_FORMS/$f" ] || cmp -s "$OUT/clinical_forms/$f" "$LOCAL_FORMS/$f" || echo "$f"
  done
  echo "## form_resource files named on the cloud but absent from its folder"
  awk -F'\t' 'NR > 1 && $11 ~ /^\/home\/bahmni\/clinical_forms\// { sub(/^\/home\/bahmni\/clinical_forms\//, "", $11); print $11 }' "$OUT/forms.tsv" | sort -u | while IFS= read -r f; do
    [ -e "$OUT/clinical_forms/$f" ] || echo "$f"
  done
} > "$OUT/compare.txt"
rm -f "$OUT/.cloud.keys" "$OUT/.local.keys"

log ""
cat "$OUT/compare.txt"
log ""
if [ "$APPLY" = 0 ]; then
  log "fetched into ${OUT}; nothing was changed on the cloud or this clinic (--apply copies the files)"
  exit 0
fi
added=0; changed=0
while IFS= read -r f; do
  if [ ! -e "$LOCAL_FORMS/$f" ]; then added=$((added + 1))
  elif cmp -s "$OUT/clinical_forms/$f" "$LOCAL_FORMS/$f"; then continue
  else changed=$((changed + 1)); fi
  mkdir -p "$(dirname "$LOCAL_FORMS/$f")" && cp "$OUT/clinical_forms/$f" "$LOCAL_FORMS/$f" && chmod 644 "$LOCAL_FORMS/$f" || fail "could not write ${LOCAL_FORMS}/${f}"
done < <(cd "$OUT/clinical_forms" && find . -type f | sed 's|^\./||' | sort)
ok "files applied to ${LOCAL_FORMS}: ${added} added, ${changed} updated"

local_mysql(){ ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B --default-character-set=utf8mb4 openmrs'; }
stage(){
  echo "SET NAMES utf8mb4;"
  echo "CREATE TEMPORARY TABLE cf_form LIKE form; CREATE TEMPORARY TABLE cf_form_resource LIKE form_resource;"
  grep '^INSERT INTO `form' "$OUT/forms.sql" | sed -E 's/^INSERT INTO `(form|form_resource)` /INSERT INTO `cf_\1` /'
}
cols(){ printf "select group_concat(concat('\`',column_name,'\`') order by ordinal_position) from information_schema.columns where table_schema='openmrs' and table_name='%s';\n" "$1" | local_mysql; }
FC="$(cols form)"; RC="$(cols form_resource)"
[ -n "$FC" ] && [ -n "$RC" ] || fail "could not read the form and form_resource columns from ${MY}"
upd(){ printf '%s' "$1" | tr ',' '\n' | sed 's/.*/&=VALUES(&)/' | paste -sd, -; }

clash="$( { stage; cat <<SQL
select 'form', c.form_id, c.uuid, l.form_id, l.uuid from cf_form c join form l on l.form_id = c.form_id and l.uuid <> c.uuid;
select 'form', c.form_id, c.uuid, l.form_id, l.uuid from cf_form c join form l on l.uuid = c.uuid and l.form_id <> c.form_id;
select 'form_resource', c.form_resource_id, c.uuid, l.form_resource_id, l.uuid from cf_form_resource c join form_resource l on l.form_resource_id = c.form_resource_id and l.uuid <> c.uuid;
select 'form_resource', c.form_resource_id, c.uuid, l.form_resource_id, l.uuid from cf_form_resource c join form_resource l on l.uuid = c.uuid and l.form_resource_id <> c.form_resource_id;
SQL
} | local_mysql)" || fail "could not stage the cloud form rows in ${MY}"
[ -z "$clash" ] || fail "clinic form rows clash with the cloud's (table, cloud id, cloud uuid, clinic id, clinic uuid); nothing applied to the database:
${clash}"

counts="$( { stage; cat <<SQL
START TRANSACTION;
select count(*) from cf_form c where not exists (select 1 from form l where l.form_id = c.form_id);
INSERT INTO form (${FC}) SELECT ${FC} FROM cf_form ON DUPLICATE KEY UPDATE $(upd "$FC");
select row_count();
select count(*) from cf_form_resource c where not exists (select 1 from form_resource l where l.form_resource_id = c.form_resource_id);
INSERT INTO form_resource (${RC}) SELECT ${RC} FROM cf_form_resource ON DUPLICATE KEY UPDATE $(upd "$RC");
select row_count();
COMMIT;
SQL
} | local_mysql)" || fail "the form rows could not be written to ${MY}; the transaction was rolled back"
set -- $counts
ok "form rows: $1 added, $(( ($2 - $1) / 2 )) updated; form_resource rows: $3 added, $(( ($4 - $3) / 2 )) updated"
info "OpenMRS was not restarted: it reads a form's file when the form is opened"
