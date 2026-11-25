#!/usr/bin/env bash
# Helpers for the observation forms folder OpenMRS mounts (folder check, row/file check, demo forms).

FORMS_PREFIX="/home/bahmni/clinical_forms/"

forms_folder_verdict(){
  local d="$1" n l
  [ -n "$d" ] || { printf 'FORMS_DIR is not set in clinic/.env, so OpenMRS would not start. Installer task 075 sets it (resume --from 075).\n'; return 1; }
  [ -d "$d" ] || { printf '%s does not exist, so OpenMRS would not start (its forms mount refuses a missing folder). Installer task 075 creates it (resume --from 075).\n' "$d"; return 1; }

  l="$(find "$d" -type l 2>/dev/null | head -1)"
  [ -z "$l" ] || { printf '%s holds a symlink (%s); a form file must be a plain file, so OpenMRS does not start on it\n' "$d" "$l"; return 1; }
  [ -d "$d/translations" ] || { printf '%s has no translations/ folder, which OpenMRS mounts for the form translations. Installer task 075 creates it (resume --from 075).\n' "$d"; return 1; }
  n="$(find "$d" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  printf 'ok %s form files in %s\n' "${n:-0}" "$d"
}

forms_topic_listed(){ # MM2_PROPERTIES ALIAS: does this clinic's MirrorMaker pull the form files topic?
  awk -v k="cloud->$2.topics" -F' *= *' '$1==k{print $2}' "$1" 2>/dev/null | grep -q '\\\.forms\\\.files'
}

forms_sql(){
  [ -n "${CT:-}" ] || setup_compose
  printf '%s' "$1" | ct exec -i "${COMPOSE_PROJECT_NAME:?}-bahmni-mysql-1" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N openmrs'
}

forms_known_concepts(){
  if [ -n "${FORMS_CONCEPTS_FILE:-}" ]; then cp "${FORMS_CONCEPTS_FILE}" "$1"; return; fi
  forms_sql 'select uuid from concept where retired=0' > "$1" 2>/dev/null
}

forms_known_forms(){
  if [ -n "${FORMS_KNOWN_FORMS_FILE:-}" ]; then cp "${FORMS_KNOWN_FORMS_FILE}" "$1"; return; fi
  forms_sql 'select uuid from form where published=1 and retired=0' > "$1" 2>/dev/null
}

FORMS_DEMO_LIST="${FORMS_DEMO_LIST:-${INSTALL_DIR}/demo-forms.conf}"
FORMS_DEMO_REASON="stock demo form from the config package, not used by this clinic"
FORMS_DEMO_RETIRED_BY=1

forms_demo_uuids(){
  local f="${1:-${FORMS_DEMO_LIST}}" out
  [ -f "$f" ] || { printf 'no list of the stock demo forms at %s\n' "$f"; return 1; }
  out="$(awk '{ line = $0; sub(/#.*/, "") } NF {
      u = $1; x = u; n = gsub(/-/, "", x)
      if (NF != 1 || length(u) != 36 || n != 4 || x !~ /^[0-9a-f]+$/ || substr(u, 9, 1) != "-" || substr(u, 14, 1) != "-" || substr(u, 19, 1) != "-" || substr(u, 24, 1) != "-") {
        printf "%s line %d is not one form uuid: %s\n", FILENAME, FNR, line; bad = 1; exit
      }
      out = out u "\n" }
    END { if (bad) exit 1; printf "%s", out }' "$f")" || { printf '%s\n' "$out"; return 1; }
  [ -n "$out" ] || { printf '%s lists no form uuid; it names the stock demo forms to retire, one uuid per line\n' "$f"; return 1; }
  printf '%s\n' "$out"
}

forms_retire_demo_sql(){
  local in="" u
  for u in "$@"; do in="${in}${in:+, }'${u}'"; done
  printf "update form set retired = 1, retired_by = %s, date_retired = now(), retire_reason = '%s' where retired = 0 and uuid in (%s); select row_count(); select count(*) from form where uuid in (%s); select count(*) from form where retired = 0 and uuid in (%s);\n" \
    "${FORMS_DEMO_RETIRED_BY}" "${FORMS_DEMO_REASON}" "$in" "$in" "$in"
}

forms_retire_demo(){
  local uuids out n held left listed
  uuids="$(forms_demo_uuids)" || fail "$uuids"
  listed="$(printf '%s\n' "$uuids" | grep -c .)"

  out="$(forms_sql "$(forms_retire_demo_sql $uuids)")" || fail "could not retire the stock demo forms in openmrs in ${COMPOSE_PROJECT_NAME:-?}-bahmni-mysql-1"
  n="$(printf '%s\n' "$out" | sed -n 1p)"
  held="$(printf '%s\n' "$out" | sed -n 2p)"
  left="$(printf '%s\n' "$out" | sed -n 3p)"
  case "${n}:${held}:${left}" in
    *[!0-9:]*|:*|*:|*::*) fail "retiring the stock demo forms: openmrs answered '$(printf '%s' "$out" | tr '\n' ' ')', not three counts" ;;
  esac

  [ "$left" = 0 ] || fail "retiring the stock demo forms: ${left} of the ${held} this node holds still read back not retired after the update (${n} retired now)"
  ok "stock demo forms: ${n} retired now; this node holds ${held} of the ${listed} in demo-forms.conf, all read back retired, none deleted"
}

forms_concept_warn(){
  local tree="$1" known kforms rc=0 out
  info "concept check:"
  known="$(mktemp "${TMPDIR:-/tmp}/forms-concepts.XXXXXX")"
  kforms="$(mktemp "${TMPDIR:-/tmp}/forms-published.XXXXXX")"
  if ! forms_known_concepts "$known" || [ ! -s "$known" ]; then
    rm -f "$known" "$kforms"; FORMS_CONCEPTS_UNCHECKED=1; warn "concept check: could not read this node's concepts; concepts NOT checked"; return 0
  fi

  forms_known_forms "$kforms" || : > "$kforms"
  out="$( "${FORMS_CONCEPT_CHECKER:-${INSTALL_DIR}/check-form-concepts.py}" --repo "$tree" --known "$known" --known-forms "$kforms" 2>&1 )" || rc=$?
  rm -f "$known" "$kforms"
  [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/    /'

  case "$rc" in
    0) ok "concept check: no form misses a concept this node has (any WARN above is the checker's)" ;;
    1) warn "concept check (rc=1): the forms above reference concepts this node's OpenMRS lacks; those fields will not save until the concepts arrive (the way the hub got them). The forms are taken anyway: their rows come from the hub regardless" ;;
    *) FORMS_CONCEPTS_UNCHECKED=1
       warn "concept check (rc=${rc}): the checker could not run (its output is above); concepts NOT checked. The forms are taken anyway" ;;
  esac

  return 0
}

FORMS_ROWS_SQL="select f.uuid, f.name, f.version, f.published, f.retired, coalesce(r.value_reference, '') from form f left join form_resource r on r.form_id = f.form_id and (r.datatype like '%FileSystemStorageDatatype' or r.value_reference like '/%') order by f.form_id, r.form_resource_id"
forms_rows(){
  if [ -n "${FORMS_ROWS_FILE:-}" ]; then cp "${FORMS_ROWS_FILE}" "$1"; return; fi
  forms_sql "${FORMS_ROWS_SQL}" > "$1"
}

forms_rowfile_report(){
  local d="$1" rows="$2" TAB uuid name ver pub ret ptr file need=0 miss=0 pending=0 f
  local retmiss=0 retfirst="" outside=0 nop
  TAB="$(printf '\t')"

  nop="$(awk -F'\t' -v pre="${FORMS_PREFIX}" '
    { if ($4 == 1 && $5 == 0) req[$1] = $2 " v" $3
      if ($6 != "" && index($6, pre "translations/") != 1) has[$1] = 1 }
    END { for (k in req) if (!(k in has)) print req[k] }' "$rows" | sort)"
  if [ -n "$nop" ]; then
    while IFS= read -r f; do
      printf 'missing - (%s: no form_resource row points at its file)\n' "$f"
      need=$((need + 1))
      miss=$((miss + 1))
    done <<EOF
$nop
EOF
  fi

  while IFS="$TAB" read -r uuid name ver pub ret ptr || [ -n "${uuid}${ptr}" ]; do
    [ -n "$ptr" ] || continue

    case "$ptr" in *..*) ;; "${FORMS_PREFIX}translations/"*) continue ;; esac
    case "$ptr" in
      "${FORMS_PREFIX}"*) file="${ptr#"${FORMS_PREFIX}"}" ;;
      *) if [ "$pub" = 1 ] && [ "$ret" = 0 ]; then
           need=$((need + 1))
           miss=$((miss + 1))
           printf 'missing %s (%s v%s: the pointer is outside the forms folder, %s)\n' "$ptr" "$name" "$ver" "${FORMS_PREFIX}"
         else
           outside=$((outside + 1))
           printf 'outside %s (%s v%s, retired or unpublished: the pointer is outside the forms folder)\n' "$ptr" "$name" "$ver"
         fi

         continue ;;
    esac

    if [ "$ret" = 1 ]; then
      case "$file" in *..*|/*|*[!A-Za-z0-9._/-]*|'') ;; *) [ -f "$d/$file" ] && continue ;; esac
      retmiss=$((retmiss + 1))
      [ "$retmiss" -gt 3 ] || retfirst="${retfirst}${retfirst:+ }${uuid}"
      continue
    fi

    [ "$pub" = 1 ] || continue
    need=$((need + 1))
    case "$file" in
      *..*|/*|*[!A-Za-z0-9._/-]*|'') printf 'missing %s (%s v%s: the pointer is not a plain path under the forms folder)\n' "$file" "$name" "$ver"; miss=$((miss + 1)); continue ;;
    esac

    [ -f "$d/$file" ] || { printf 'missing %s (%s v%s)\n' "$file" "$name" "$ver"; miss=$((miss + 1)); }
  done < "$rows"

  pending="$(for f in "$d"/*.json; do [ -f "$f" ] || continue; printf '%s\n' "${f##*/}"; done \
    | awk -v rows="$rows" -v pre="${FORMS_PREFIX}" 'BEGIN { while ((getline l < rows) > 0) { split(l, a, "\t"); if (index(a[6], pre) == 1) ref[substr(a[6], length(pre) + 1)] = 1 } } !($0 in ref) { n++ } END { print n + 0 }')"
  printf 'summary %s published forms, %s with their file, %s missing; %s files with no form row (not synced yet, or kept for old observations)\n' "$need" "$((need - miss))" "$miss" "$pending"
  [ "$retmiss" = 0 ] || printf 'warn %s retired form versions have no file here (first: %s); observations saved with them do not open\n' "$retmiss" "$retfirst"
  [ "$outside" = 0 ] || printf 'warn %s pointers of retired or unpublished forms are outside the forms folder (listed above); OpenMRS reads them if such a form is opened\n' "$outside"
  [ "$miss" = 0 ]
}

forms_rowfile_gate(){
  local d="$1" strict="$2" rows out rc=0 w
  rows="$(mktemp "${TMPDIR:-/tmp}/forms-rows.XXXXXX")"
  forms_rows "$rows" || { rm -f "$rows"; fail "could not read the form rows from openmrs in ${COMPOSE_PROJECT_NAME:-?}-bahmni-mysql-1"; }
  out="$(forms_rowfile_report "$d" "$rows")" || rc=$?
  rm -f "$rows"
  printf '%s\n' "$out" | { grep -v -e '^summary ' -e '^warn ' || true; } | sed 's/^/    /'
  printf '%s\n' "$out" | sed -n 's/^warn //p' | while IFS= read -r w; do warn "row/file check: ${w}"; done
  if [ "$rc" = 0 ]; then ok "row/file check: $(printf '%s\n' "$out" | sed -n 's/^summary //p')"; return 0; fi
  if [ "$strict" = 1 ]; then
    fail "row/file check: $(printf '%s\n' "$out" | sed -n 's/^summary //p'). Each form listed above fails to open until forms-sync writes its file: read the forms-sync container's log"
  fi

  info "row/file check: $(printf '%s\n' "$out" | sed -n 's/^summary //p'). forms-sync writes each file listed above when it arrives; until then that form does not open"
}
