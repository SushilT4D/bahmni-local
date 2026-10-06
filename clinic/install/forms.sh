#!/usr/bin/env bash
# The observation forms' files on a clinic node. Sourced after lib.sh by task
# 075, task 080 and scripts/update-forms.sh. bash 3.2 compatible.
#
# A form is two things that must travel together:
#   - rows: form (name, version, uuid, published, retired) and form_resource,
#     whose pointer row names the form's file as
#     /home/bahmni/clinical_forms/<uuid>.json. The hub is the only node that
#     publishes forms; the rows reach a clinic by sync (hub/tables.conf) or
#     with the seed. A clinic never creates them: its Initializer does not
#     load forms (initializer.sh) and its forms folder is read-only.
#   - files: <uuid>.json and translations/<uuid>.json in the forms folder,
#     which docker-compose.yml mounts at /home/bahmni/clinical_forms (and its
#     translations/ where the form module reads translations), from
#     FORMS_DIR with mode FORMS_MOUNT_MODE, both in clinic/.env.
#
# With a forms repo configured (FORMS_REPO_URL, FORMS_REPO_KEY), clinic/forms
# is a clone of it, made and fast-forwarded with git using the deploy key by
# path, and the forms folder is clinic/forms/clinical_forms, read-only. The
# repo holds clinical_forms/<uuid>.json, clinical_forms/translations/,
# MANIFEST.tsv and tools/check-concepts.sh, and only ever adds files: an old
# version's file stays, because saved observations still open with it. So a
# clone newer than the database is always safe, and an older one is caught by
# the row/file check.
#
# With none configured, the forms folder is the frozen copy tracked in this
# repo, clinic/bahmni_home/clinical_forms, read-write. clinic/forms is unused.
#
# The forms repo's concept check is called as
#   tools/check-concepts.sh --known <concepts> --known-forms <forms>
# from the root of the incoming tree: <concepts> holds every concept uuid that
# exists and is not retired in this node's OpenMRS, <forms> every form uuid
# published and not retired there, one per line. Its findings are warnings: a
# form missing a concept opens with a field that saves nothing, and the fix is
# to deliver the concept the way the hub got it, not to hold the form back,
# whose rows arrive by sync either way.
#
# The row/file check is the gate: every published, unretired form row's file
# must be in the forms folder. A file with no row is fine (its rows have not
# synced yet, or it is an old version kept for saved observations).

FORMS_CLONE_DIR="${FORMS_CLONE_DIR:-${CLINIC_DIR}/forms}"
FORMS_FROZEN_DIR="${FORMS_FROZEN_DIR:-${CLINIC_DIR}/bahmni_home/clinical_forms}"
FORMS_PREFIX="/home/bahmni/clinical_forms/"

# forms_folder_for URL / forms_mode_for URL : the forms folder a node with
# (or without) a forms repo mounts, and the mount's mode
forms_folder_for(){ if [ -n "$1" ]; then printf '%s\n' "${FORMS_CLONE_DIR}/clinical_forms"; else printf '%s\n' "${FORMS_FROZEN_DIR}"; fi; }
forms_mode_for(){ if [ -n "$1" ]; then echo ro; else echo rw; fi; }

# forms_folder_verdict DIR : the mount source must exist, hold forms, and have
# the translations/ folder the second mount takes. A missing source would be
# created empty by the runtime (inside a clone, as root) and OpenMRS would
# start with no form files.
forms_folder_verdict(){
  local d="$1" n
  [ -d "$d" ] || { printf '%s does not exist, so OpenMRS would start with no form files. Installer task 075 sets it up (a clone of the forms repo, or the frozen copy); on a running node, clinic/scripts/update-forms.sh does.\n' "$d"; return 1; }
  [ -d "$d/translations" ] || { printf '%s has no translations/ folder, which OpenMRS mounts for the form translations; the runtime would create it empty. The forms repo must carry clinical_forms/translations/.\n' "$d"; return 1; }
  n="$(find "$d" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [ "${n:-0}" -gt 0 ] || { printf '%s holds no form file (*.json), so every form would fail to open.\n' "$d"; return 1; }
  printf 'ok %s form files in %s\n' "$n" "$d"
}

# forms_state DIR -> absent | placeholder | clone | foreign. placeholder: an
# empty directory. foreign: anything this file did not put there, which is
# never removed.
forms_state(){
  local d="$1"
  [ -e "$d" ] || { echo absent; return 0; }
  [ -d "$d" ] || { echo foreign; return 0; }
  [ -d "$d/.git" ] && { echo clone; return 0; }
  [ -z "$(find "$d" -mindepth 1 2>/dev/null | head -1)" ] && { echo placeholder; return 0; }
  echo foreign
}

# forms_key_verdict PATH : a deploy key ssh will accept: present, readable,
# private to its owner. Its contents are never read here.
forms_key_verdict(){
  local k="$1" perm
  [ -n "$k" ] || { printf 'ok no deploy key (git uses its own ssh setup)\n'; return 0; }
  [ -f "$k" ] || { printf 'FORMS_REPO_KEY names %s, which does not exist on this machine\n' "$k"; return 1; }
  [ -r "$k" ] || { printf 'FORMS_REPO_KEY names %s, which this user cannot read\n' "$k"; return 1; }
  perm="$(ls -l "$k" | cut -c5-10)"
  [ "$perm" = "------" ] || { printf 'FORMS_REPO_KEY %s is readable by other users; ssh refuses such a key: chmod 600 %s\n' "$k" "$k"; return 1; }
  printf 'ok deploy key %s\n' "$k"
}

# forms_git ARGS... : git with the deploy key, never prompting. The key is
# passed by path only.
forms_git(){
  if [ -n "${FORMS_REPO_KEY:-}" ]; then
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -i $(printf '%q' "${FORMS_REPO_KEY}") -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new" git "$@"
  else
    GIT_TERMINAL_PROMPT=0 git "$@"
  fi
}

# forms_upstream_verdict DIR : a clone may only move forward to what the forms
# repo holds. Run after a fetch. Prints uptodate | ff, or the refusal.
forms_upstream_verdict(){
  local d="$1" head up dirty
  dirty="$(git -C "$d" status --porcelain 2>/dev/null)"
  [ -z "$dirty" ] || { printf 'clinic/forms has local changes (%s); the forms come only from the forms repo. Move clinic/forms aside and run again to take a fresh clone.\n' "$(printf '%s' "$dirty" | head -3 | tr '\n' ' ')"; return 1; }
  up="$(git -C "$d" rev-parse -q --verify '@{u}' 2>/dev/null)" || { printf 'clinic/forms has no upstream branch to follow; move it aside and run again to take a fresh clone.\n'; return 1; }
  head="$(git -C "$d" rev-parse HEAD)"
  if [ "$head" = "$up" ]; then printf 'uptodate\n'; return 0; fi
  if git -C "$d" merge-base --is-ancestor "$head" "$up"; then printf 'ff\n'; return 0; fi
  printf 'clinic/forms is at %s, which the forms repo (%s) does not contain: not a fast-forward. The forms repo is the only source of forms and its history is never rewritten; move clinic/forms aside and run again to take a fresh clone.\n' "$(git -C "$d" rev-parse --short HEAD)" "$(git -C "$d" rev-parse --short "$up")"
  return 1
}

# forms_sql QUERY : runs one SELECT against this node's openmrs database,
# rows on stdout, tab-separated, no header.
forms_sql(){
  [ -n "${CT:-}" ] || setup_compose
  printf '%s' "$1" | ct exec -i "${COMPOSE_PROJECT_NAME:?}-bahmni-mysql-1" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N openmrs'
}

# forms_known_concepts OUT / forms_known_forms OUT : the two lists the concept
# check takes (see the top of this file). FORMS_CONCEPTS_FILE and
# FORMS_KNOWN_FORMS_FILE supply lists taken elsewhere instead.
forms_known_concepts(){
  if [ -n "${FORMS_CONCEPTS_FILE:-}" ]; then cp "${FORMS_CONCEPTS_FILE}" "$1"; return; fi
  forms_sql 'select uuid from concept where retired=0' > "$1" 2>/dev/null
}
forms_known_forms(){
  if [ -n "${FORMS_KNOWN_FORMS_FILE:-}" ]; then cp "${FORMS_KNOWN_FORMS_FILE}" "$1"; return; fi
  forms_sql 'select uuid from form where published=1 and retired=0' > "$1" 2>/dev/null
}

# forms_concept_warn TREE : runs TREE's tools/check-concepts.sh against this
# node's concepts and published forms and shows what it finds. Never stops
# anything: every finding is a WARN.
forms_concept_warn(){
  local tree="$1" known kforms rc=0 out
  [ -f "$tree/tools/check-concepts.sh" ] || { warn "concept check: the forms repo has no tools/check-concepts.sh; not checked"; return 0; }
  known="$(mktemp "${TMPDIR:-/tmp}/forms-concepts.XXXXXX")"; kforms="$(mktemp "${TMPDIR:-/tmp}/forms-published.XXXXXX")"
  if ! forms_known_concepts "$known" || [ ! -s "$known" ]; then
    rm -f "$known" "$kforms"; warn "concept check: could not read this node's concepts; not checked"; return 0
  fi
  forms_known_forms "$kforms" || : > "$kforms"
  out="$( cd "$tree" && bash tools/check-concepts.sh --known "$known" --known-forms "$kforms" 2>&1 )" || rc=$?
  rm -f "$known" "$kforms"
  [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/    /'
  if [ "$rc" = 0 ]; then ok "concept check: no form misses a concept this node has (any WARN above is the checker's)"
  else warn "concept check (rc=${rc}): the forms above reference concepts this node's OpenMRS lacks; those fields will not save until the concepts arrive (the way the hub got them). The forms are taken anyway: their rows come from the hub regardless"; fi
  return 0
}

# forms_sync CHECK DRY : brings clinic/forms to what the configured forms repo
# holds (clone, or fast-forward only). CHECK 1 runs the concept check on the
# incoming tree first (warnings only); DRY 1 shows what would change (the
# commits and the MANIFEST.tsv lines) and changes nothing in clinic/. Sets
# FORMS_OLD_REV, FORMS_NEW_REV and FORMS_CHANGED (0 or 1).
forms_sync(){
  local check="$1" dry="$2" st url="${FORMS_REPO_URL:-}" v origin tmp parent
  FORMS_OLD_REV=""; FORMS_NEW_REV=""; FORMS_CHANGED=0
  st="$(forms_state "${FORMS_CLONE_DIR}")"
  if [ -z "$url" ]; then
    [ "$st" != clone ] || fail "clinic/forms is a clone of a forms repo, but no forms repo is configured (FORMS_REPO_URL is empty). Set FORMS_REPO_URL, or move clinic/forms aside to run from the frozen copy"
    return 0
  fi
  v="$(forms_key_verdict "${FORMS_REPO_KEY:-}")" || fail "$v"
  case "$st" in
    foreign) fail "clinic/forms holds files the installer did not put there; move it aside and run again" ;;
    clone)
      origin="$(git -C "${FORMS_CLONE_DIR}" config --get remote.origin.url || true)"
      [ "$origin" = "$url" ] || fail "clinic/forms is a clone of ${origin:-an unknown repo}, not of FORMS_REPO_URL (${url}); move clinic/forms aside and run again to clone the configured repo"
      FORMS_OLD_REV="$(git -C "${FORMS_CLONE_DIR}" rev-parse HEAD)"
      forms_git -C "${FORMS_CLONE_DIR}" fetch --quiet origin || fail "could not fetch the forms repo (${url}); check the network and the deploy key. The forms already here keep working"
      v="$(forms_upstream_verdict "${FORMS_CLONE_DIR}")" || fail "$v"
      FORMS_NEW_REV="$(git -C "${FORMS_CLONE_DIR}" rev-parse '@{u}')"
      if [ "$v" = uptodate ]; then ok "forms repo: clinic/forms is at $(git -C "${FORMS_CLONE_DIR}" rev-parse --short HEAD), what the forms repo holds"; return 0; fi
      if [ "$dry" = 1 ]; then
        info "would: fast-forward clinic/forms $(git -C "${FORMS_CLONE_DIR}" rev-parse --short HEAD) -> $(git -C "${FORMS_CLONE_DIR}" rev-parse --short '@{u}'):"
        git -C "${FORMS_CLONE_DIR}" log --oneline 'HEAD..@{u}' | sed 's/^/    /'
        info "MANIFEST.tsv changes:"
        git -C "${FORMS_CLONE_DIR}" diff 'HEAD' '@{u}' -- MANIFEST.tsv | sed -n '/^[-+][^-+]/p' | sed 's/^/    /'
        info "form files:"
        git -C "${FORMS_CLONE_DIR}" diff --stat 'HEAD' '@{u}' -- clinical_forms | sed 's/^/    /'
        return 0
      fi
      if [ "$check" = 1 ]; then
        tmp="$(mktemp -d "${TMPDIR:-/tmp}/forms-incoming.XXXXXX")"
        git -C "${FORMS_CLONE_DIR}" archive '@{u}' | tar -x -C "$tmp"
        forms_concept_warn "$tmp"
        rm -rf "$tmp"
      fi
      git -C "${FORMS_CLONE_DIR}" merge --quiet --ff-only '@{u}' || fail "could not fast-forward clinic/forms"
      FORMS_CHANGED=1
      ok "forms repo: clinic/forms fast-forwarded $(printf '%s' "${FORMS_OLD_REV}" | cut -c1-7) -> $(git -C "${FORMS_CLONE_DIR}" rev-parse --short HEAD)"
      ;;
    absent|placeholder)
      parent="$(dirname "${FORMS_CLONE_DIR}")"
      tmp="$(mktemp -d "${parent}/.forms.new.XXXXXX")"
      if ! forms_git clone --quiet "$url" "$tmp/forms"; then rm -rf "$tmp"; fail "could not clone the forms repo (${url}); check the network and the deploy key"; fi
      FORMS_NEW_REV="$(git -C "$tmp/forms" rev-parse HEAD)"
      if [ "$dry" = 1 ]; then
        info "would: clone the forms repo into clinic/forms at $(git -C "$tmp/forms" rev-parse --short HEAD); its MANIFEST.tsv:"
        sed 's/^/    /' "$tmp/forms/MANIFEST.tsv" 2>/dev/null || info "  (no MANIFEST.tsv)"
        rm -rf "$tmp"; return 0
      fi
      [ "$check" != 1 ] || forms_concept_warn "$tmp/forms"
      rm -rf "${FORMS_CLONE_DIR}" || { rm -rf "$tmp"; fail "could not remove ${FORMS_CLONE_DIR} to put the clone in its place (a directory the container runtime created is owned by root): sudo rm -rf ${FORMS_CLONE_DIR}, then run again"; }
      mv "$tmp/forms" "${FORMS_CLONE_DIR}"; rm -rf "$tmp"
      FORMS_CHANGED=1
      ok "forms repo: cloned into clinic/forms at $(git -C "${FORMS_CLONE_DIR}" rev-parse --short HEAD)"
      ;;
  esac
}

# forms_rows OUT : "name<TAB>version<TAB>published<TAB>retired<TAB>file" for
# every form row whose form_resource points into the forms folder, file being
# the path under it. FORMS_ROWS_FILE supplies rows taken elsewhere instead.
forms_rows(){
  if [ -n "${FORMS_ROWS_FILE:-}" ]; then cp "${FORMS_ROWS_FILE}" "$1"; return; fi
  forms_sql "select f.name, f.version, f.published, f.retired, substring(r.value_reference, $(( ${#FORMS_PREFIX} + 1 ))) from form f join form_resource r on r.form_id = f.form_id where r.value_reference like '${FORMS_PREFIX}%'" > "$1"
}

# forms_rowfile_report DIR ROWS : every published, unretired form row's file
# must be in DIR. Prints one "missing <file> (<name> v<version>)" line per
# file that is not there, then a summary; files no row points at are counted
# as pending. A pointer into translations/ is not required: a missing
# translation leaves labels untranslated, the form still opens. Returns 1
# when a file is missing.
forms_rowfile_report(){
  local d="$1" rows="$2" TAB name ver pub ret file need=0 miss=0 pending=0 f
  TAB="$(printf '\t')"
  while IFS="$TAB" read -r name ver pub ret file || [ -n "${name}${file}" ]; do
    [ -n "$file" ] || continue
    [ "$pub" = 1 ] && [ "$ret" = 0 ] || continue
    case "$file" in translations/*) continue ;; esac
    need=$((need + 1))
    case "$file" in
      *..*|/*|*[!A-Za-z0-9._/-]*) printf 'missing %s (%s v%s: the pointer is not a plain path under the forms folder)\n' "$file" "$name" "$ver"; miss=$((miss + 1)); continue ;;
    esac
    [ -f "$d/$file" ] || { printf 'missing %s (%s v%s)\n' "$file" "$name" "$ver"; miss=$((miss + 1)); }
  done < "$rows"
  pending="$(for f in "$d"/*.json; do [ -f "$f" ] || continue; printf '%s\n' "${f##*/}"; done \
    | awk -v rows="$rows" 'BEGIN { while ((getline l < rows) > 0) { split(l, a, "\t"); ref[a[5]] = 1 } } !($0 in ref) { n++ } END { print n + 0 }')"
  printf 'summary %s published forms, %s with their file, %s missing; %s files with no form row (not synced yet, or kept for old observations)\n' "$need" "$((need - miss))" "$miss" "$pending"
  [ "$miss" = 0 ]
}

# forms_rowfile_gate DIR STRICT : reads this node's form rows and runs the
# report on DIR. STRICT 1 (a forms repo is configured) fails on a missing
# file; STRICT 0 (the frozen copy) warns.
forms_rowfile_gate(){
  local d="$1" strict="$2" rows out rc=0
  rows="$(mktemp "${TMPDIR:-/tmp}/forms-rows.XXXXXX")"
  forms_rows "$rows" || { rm -f "$rows"; fail "could not read the form rows from openmrs in ${COMPOSE_PROJECT_NAME:-?}-bahmni-mysql-1"; }
  out="$(forms_rowfile_report "$d" "$rows")" || rc=$?
  rm -f "$rows"
  printf '%s\n' "$out" | { grep -v '^summary ' || true; } | sed 's/^/    /'
  if [ "$rc" = 0 ]; then ok "row/file check: $(printf '%s\n' "$out" | sed -n 's/^summary //p')"; return 0; fi
  if [ "$strict" = 1 ]; then
    fail "row/file check: $(printf '%s\n' "$out" | sed -n 's/^summary //p'). Each form listed above would fail to open. The forms repo must hold every file the database points at: pull its latest (it only adds files); if the latest lacks them, the hub's forms have not been exported to it yet"
  fi
  warn "row/file check: $(printf '%s\n' "$out" | sed -n 's/^summary //p'). Each form listed above fails to open on this node; the frozen copy lacks its file. A forms repo (FORMS_REPO_URL) carries them"
}

# forms_manifest_diff OLD NEW : MANIFEST.tsv lines that changed (< before, > now)
forms_manifest_diff(){ diff "$1" "$2" 2>/dev/null | grep -E '^[<>]' || true; }
