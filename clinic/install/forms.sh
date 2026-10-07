#!/usr/bin/env bash
# The observation forms' files on a clinic node. Sourced after lib.sh by task
# 075, task 080, scripts/update-forms.sh and scripts/recreate-openmrs.sh.
# bash 3.2 compatible.
#
# A form is two things that must travel together:
#   - rows: form (name, version, uuid, published, retired) and form_resource,
#     whose pointer row names the form's file as
#     /home/bahmni/clinical_forms/<uuid>.json. The hub is the only node that
#     publishes forms; the rows reach a clinic by sync (hub/tables.conf) or
#     with the seed. A clinic does not create them: its Initializer does not
#     load forms (initializer.sh), its stack does not run the form builder, and
#     its forms folder is read-only.
#   - files: <uuid>.json and translations/<uuid>.json in the forms folder,
#     which docker-compose.yml mounts at /home/bahmni/clinical_forms (and its
#     translations/ where the form module reads translations), from
#     FORMS_DIR, read-only when FORMS_READ_ONLY is true, both in clinic/.env.
#     The mounts never create a missing source: OpenMRS refuses to start
#     instead of starting with no forms.
#
# With a forms repo configured (FORMS_REPO_URL, FORMS_REPO_KEY), clinic/forms
# is a clone of it, made and fast-forwarded with git using the deploy key by
# path, and the forms folder is clinic/forms/clinical_forms, read-only. The
# repo holds clinical_forms/<uuid>.json, clinical_forms/translations/ and
# MANIFEST.tsv, and only ever adds files: an old version's file stays, because saved observations still open with it. So a
# clone newer than the database is always safe, and an older one is caught by
# the row/file check. One run at a time changes clinic/forms: a lock
# (clinic/.forms.lock) is taken around the clone or fast-forward.
#
# With none configured, the forms folder is the frozen copy tracked in this
# repo, clinic/bahmni_home/clinical_forms, read-write. clinic/forms is unused.
#
# The concept check is this repo's check-form-concepts.py, run on a copy of
# the incoming tree with <concepts> (every concept uuid that exists and is not
# retired in this node's OpenMRS) and <forms> (every form uuid published and
# not retired there). The forms repo is data to a clinic: its files are read
# and mounted read-only, and nothing in it is executed, so write access to it
# cannot run code on a clinic. The check's findings are warnings: a form
# missing a concept opens with a field that saves nothing, and the fix is to
# deliver the concept the way the hub got it, not to hold the form back, whose
# rows arrive by sync either way. When the check cannot run, the run says
# "concepts NOT checked".
#
# The row/file check is the gate: every published, unretired form must have a
# pointer row, its pointer must be a plain path inside the forms folder, and
# its file must be there. A file with no row is fine (its rows have not synced
# yet, or it is an old version kept for saved observations). Retired versions
# whose file is missing, and pointers of retired or unpublished forms outside
# the forms folder, are warnings.
#
# Exit codes, for a schedule: 1 a check refused (act on the FAIL line), 3 the
# forms repo could not be reached (the forms already here keep working), 4
# another run holds the lock.

FORMS_CLONE_DIR="${FORMS_CLONE_DIR:-${CLINIC_DIR}/forms}"
FORMS_FROZEN_DIR="${FORMS_FROZEN_DIR:-${CLINIC_DIR}/bahmni_home/clinical_forms}"
FORMS_PREFIX="/home/bahmni/clinical_forms/"
FORMS_RC_OFFLINE=3
FORMS_RC_BUSY=4
# What every refusal of clinic/forms tells the operator to do.
FORMS_ASIDE="move clinic/forms aside, then at once run clinic/scripts/update-forms.sh (or the installer task again), which takes a fresh clone. Until then OpenMRS cannot be recreated: its forms mount refuses a missing folder"

forms_fail(){ local rc="$1"; shift; printf '  FAIL %s\n' "$*" >&2; exit "$rc"; }

# forms_folder_for URL / forms_read_only_for URL : the forms folder a node with
# (or without) a forms repo mounts, and whether the mount is read-only
forms_folder_for(){ if [ -n "$1" ]; then printf '%s\n' "${FORMS_CLONE_DIR}/clinical_forms"; else printf '%s\n' "${FORMS_FROZEN_DIR}"; fi; }
forms_read_only_for(){ if [ -n "$1" ]; then echo true; else echo false; fi; }
forms_mount_word(){ if [ "$1" = true ]; then echo read-only; else echo read-write; fi; }

# forms_folder_verdict DIR : the mount source must exist, hold forms, and have
# the translations/ folder the second mount takes. The mounts refuse a missing
# source, so OpenMRS would not start.
forms_folder_verdict(){
  local d="$1" n l
  [ -d "$d" ] || { printf '%s does not exist, so OpenMRS would not start (its forms mount refuses a missing folder). Installer task 075 sets it up (a clone of the forms repo, or the frozen copy); on a running node, clinic/scripts/update-forms.sh does.\n' "$d"; return 1; }
  # a symlink in the forms folder is followed inside the container, read-only
  # mount or not: a form "file" pointing at /proc/self/environ would serve
  # OpenMRS's environment, passwords included, to anyone opening the form
  l="$(find "$d" -type l 2>/dev/null | head -1)"
  [ -z "$l" ] || { printf '%s holds a symlink (%s); a form file must be a plain file, so OpenMRS does not start on it\n' "$d" "$l"; return 1; }
  [ -d "$d/translations" ] || { printf '%s has no translations/ folder, which OpenMRS mounts for the form translations. The forms repo must carry clinical_forms/translations/.\n' "$d"; return 1; }
  n="$(find "$d" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [ "${n:-0}" -gt 0 ] || { printf '%s holds no form file (*.json), so every form would fail to open.\n' "$d"; return 1; }
  printf 'ok %s form files in %s\n' "$n" "$d"
}

# forms_tree_symlinks GITDIR REV : prints the paths REV of the clone at GITDIR
# carries as symlinks (none for a forms repo; see forms_folder_verdict)
forms_tree_symlinks(){ git -C "$1" ls-tree -r "$2" | awk -F'\t' '$1 ~ /^120000 / {print $2}'; }

# forms_mount_verdict DIR READ_ONLY URL : the forms mount docker-compose.yml
# will make from clinic/.env (FORMS_DIR, FORMS_READ_ONLY, FORMS_REPO_URL) is
# one OpenMRS may start on. Every path that starts or recreates OpenMRS runs
# it first (task 080, scripts/recreate-openmrs.sh).
forms_mount_verdict(){
  local d="$1" ro="$2" url="$3" v
  case "$ro" in true|false) ;; *) printf "clinic/.env FORMS_READ_ONLY is '%s'; it is true or false (task 075 sets it)\n" "$ro"; return 1 ;; esac
  if [ -n "$url" ] && { [ "$d" != "$(forms_folder_for "$url")" ] || [ "$ro" != true ]; }; then
    printf "clinic/.env names a forms repo, but the forms mount is %s (%s), not its clone's %s (read-only): installer task 075 sets both (resume --from 075), and on a running node clinic/scripts/update-forms.sh does\n" "$d" "$(forms_mount_word "$ro")" "$(forms_folder_for "$url")"
    return 1
  fi
  v="$(forms_folder_verdict "$d")" || { printf '%s\n' "$v"; return 1; }
  printf '%s (mounted %s)\n' "$v" "$(forms_mount_word "$ro")"
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

# forms_key_verdict PATH : a deploy key ssh will accept: an absolute path of
# plain characters (git hands it to ssh through /bin/sh, and every caller runs
# from its own directory), present, readable, private to its owner. Its
# contents are never read here.
forms_key_verdict(){
  local k="$1" perm
  [ -n "$k" ] || { printf 'ok no deploy key (git uses its own ssh setup)\n'; return 0; }
  case "$k" in /*) ;; *) printf 'FORMS_REPO_KEY is %s, a relative path; give the absolute path (each caller runs from its own directory)\n' "$k"; return 1 ;; esac
  case "$k" in *[!A-Za-z0-9._/-]*) printf 'FORMS_REPO_KEY %s has a character other than letters, digits and . _ / -; git hands the path to ssh through /bin/sh, so keep it plain\n' "$k"; return 1 ;; esac
  [ -f "$k" ] || { printf 'FORMS_REPO_KEY names %s, which does not exist on this machine\n' "$k"; return 1; }
  [ -r "$k" ] || { printf 'FORMS_REPO_KEY names %s, which this user cannot read\n' "$k"; return 1; }
  perm="$(ls -l "$k" | cut -c5-10)"
  [ "$perm" = "------" ] || { printf 'FORMS_REPO_KEY %s is readable by other users; ssh refuses such a key: chmod 600 %s\n' "$k" "$k"; return 1; }
  printf 'ok deploy key %s\n' "$k"
}

# forms_git ARGS... : git with the deploy key, never prompting. The key is
# passed by path only; forms_key_verdict has made it a plain absolute path.
# accept-new trusts the git host's key the first time it is seen: put the
# host's key in this user's ~/.ssh/known_hosts before the first run to pin it.
forms_git(){
  if [ -n "${FORMS_REPO_KEY:-}" ]; then
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -i ${FORMS_REPO_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30 -o ServerAliveInterval=15 -o ServerAliveCountMax=4" git "$@"
  else
    GIT_TERMINAL_PROMPT=0 git "$@"
  fi
}

# forms_upstream_verdict DIR : a clone may only move forward to what the forms
# repo holds. Run after a fetch. Prints uptodate | ff, or the refusal.
forms_upstream_verdict(){
  local d="$1" head up dirty
  dirty="$(git -C "$d" status --porcelain 2>/dev/null)"
  [ -z "$dirty" ] || { printf 'clinic/forms has local changes (%s); the forms come only from the forms repo. To start again from the forms repo, %s.\n' "$(printf '%s' "$dirty" | head -3 | tr '\n' ' ')" "$FORMS_ASIDE"; return 1; }
  up="$(git -C "$d" rev-parse -q --verify '@{u}' 2>/dev/null)" || { printf 'clinic/forms has no upstream branch to follow; %s.\n' "$FORMS_ASIDE"; return 1; }
  head="$(git -C "$d" rev-parse HEAD)"
  if [ "$head" = "$up" ]; then printf 'uptodate\n'; return 0; fi
  if git -C "$d" merge-base --is-ancestor "$head" "$up"; then printf 'ff\n'; return 0; fi
  printf 'clinic/forms is at %s, which the forms repo (%s) does not contain: not a fast-forward. The forms repo is the only source of forms and its history is never rewritten; %s.\n' "$(git -C "$d" rev-parse --short HEAD)" "$(git -C "$d" rev-parse --short "$up")" "$FORMS_ASIDE"
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

# forms_concept_warn TREE : runs the concept check on TREE, a copy of the
# incoming forms, against this node's concepts and published forms, and shows
# what it finds. The checker is this repo's check-form-concepts.py, which
# reads TREE as data; nothing in the forms repo is executed. Never stops
# anything: every finding is a WARN. Sets FORMS_CONCEPTS_UNCHECKED=1 when the
# concepts could not be checked.
forms_concept_warn(){
  local tree="$1" known kforms rc=0 out
  info "concept check:"
  known="$(mktemp "${TMPDIR:-/tmp}/forms-concepts.XXXXXX")"; kforms="$(mktemp "${TMPDIR:-/tmp}/forms-published.XXXXXX")"
  if ! forms_known_concepts "$known" || [ ! -s "$known" ]; then
    rm -f "$known" "$kforms"; FORMS_CONCEPTS_UNCHECKED=1; warn "concept check: could not read this node's concepts; concepts NOT checked"; return 0
  fi
  forms_known_forms "$kforms" || : > "$kforms"
  out="$( "${FORMS_CONCEPT_CHECKER:-${INSTALL_DIR}/check-form-concepts.py}" --repo "$tree" --known "$known" --known-forms "$kforms" 2>&1 )" || rc=$?
  rm -f "$known" "$kforms"
  [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/    /'
  # the checker's exits: 0 nothing blocked, 1 a form misses concepts, 2 it could not run
  case "$rc" in
    0) ok "concept check: no form misses a concept this node has (any WARN above is the checker's)" ;;
    1) warn "concept check (rc=1): the forms above reference concepts this node's OpenMRS lacks; those fields will not save until the concepts arrive (the way the hub got them). The forms are taken anyway: their rows come from the hub regardless" ;;
    *) FORMS_CONCEPTS_UNCHECKED=1
       warn "concept check (rc=${rc}): the checker could not run (its output is above); concepts NOT checked. The forms are taken anyway" ;;
  esac
  return 0
}

# forms_lock / forms_unlock : one run at a time changes clinic/forms. The lock
# is a directory beside it holding the owner's pid. A lock whose pid is gone is
# taken over; one whose run is alive is never taken, however old (git's ssh
# gives up on a stalled connection, so a live run ends). A lock with no pid
# (its run died before writing one) is taken over once older than
# FORMS_LOCK_STALE_MIN minutes (default 60). Taking over renames the old lock
# aside first, which only one run can do, and checks that what it renamed is
# the lock it judged, so two runs that both judge it stale never both hold it.
# A run that hangs keeps its lock until it is ended. forms_lock returns
# FORMS_RC_BUSY, with the FAIL line, when another run holds it.
forms_lock_dir(){ printf '%s\n' "${FORMS_LOCK:-$(dirname "${FORMS_CLONE_DIR}")/.forms.lock}"; }
forms_lock(){
  local l pid i
  l="$(forms_lock_dir)"
  for i in 1 2 3; do
    if mkdir "$l" 2>/dev/null; then printf '%s\n' "$$" > "$l/pid"; return 0; fi
    pid="$(cat "$l/pid" 2>/dev/null || true)"
    if [ -n "$pid" ] && ! ps -p "$pid" >/dev/null 2>&1; then
      warn "taking over ${l}: the run that took it (pid ${pid}) is gone"
    elif [ -z "$pid" ] && [ -n "$(find "$l" -maxdepth 0 -mmin "+${FORMS_LOCK_STALE_MIN:-60}" 2>/dev/null)" ]; then
      warn "taking over ${l}: it names no run and is older than ${FORMS_LOCK_STALE_MIN:-60} min"
    else
      printf '  FAIL another run is changing clinic/forms (pid %s holds %s); this run changed nothing. It runs again on the next schedule, or by hand once that run ends\n' "${pid:-starting}" "$l" >&2
      return "$FORMS_RC_BUSY"
    fi
    # Only one run can rename it; a run that loses the rename tries mkdir again.
    # What was renamed must be the lock judged above: if another run took over
    # first and made a fresh lock in between, it is put back and this run backs off.
    if mv "$l" "${l}.stale.$$" 2>/dev/null; then
      if [ "$(cat "${l}.stale.$$/pid" 2>/dev/null || true)" != "$pid" ]; then
        { [ ! -e "$l" ] && mv "${l}.stale.$$" "$l"; } 2>/dev/null || rm -rf "${l}.stale.$$"
        printf '  FAIL another run took over %s first; this run changed nothing\n' "$l" >&2
        return "$FORMS_RC_BUSY"
      fi
      rm -rf "${l}.stale.$$"
    fi
  done
  printf '  FAIL could not take %s\n' "$l" >&2
  return "$FORMS_RC_BUSY"
}
forms_unlock(){
  local l; l="$(forms_lock_dir)"
  [ "$(cat "$l/pid" 2>/dev/null || true)" = "$$" ] && rm -rf "$l"
  return 0
}

# forms_sync CHECK DRY : brings clinic/forms to what the configured forms repo
# holds (clone, or fast-forward only), holding the lock. CHECK 1 runs the
# concept check on the incoming tree first (warnings only); DRY 1 shows what
# would change (the commits and the MANIFEST.tsv lines) and changes nothing in
# clinic/. Sets FORMS_OLD_REV, FORMS_NEW_REV, FORMS_CHANGED (0 or 1) and
# FORMS_CONCEPTS_UNCHECKED (0 or 1). A refusal ends the caller with the exit
# code above.
forms_sync(){
  local check="$1" dry="$2" vars rc=0 e=0
  FORMS_OLD_REV=""; FORMS_NEW_REV=""; FORMS_CHANGED=0; FORMS_CONCEPTS_UNCHECKED=0
  if [ -z "${FORMS_REPO_URL:-}" ]; then
    [ "$(forms_state "${FORMS_CLONE_DIR}")" != clone ] || fail "clinic/forms is a clone of a forms repo, but no forms repo is configured (FORMS_REPO_URL is empty). Set FORMS_REPO_URL, or move clinic/forms aside to run from the frozen copy"
    return 0
  fi
  forms_lock || exit "$?"
  vars="$(mktemp "${TMPDIR:-/tmp}/forms-sync.XXXXXX")"
  # The work runs in a subshell so that every refusal in it (fail, an exit)
  # comes back here, where the lock is released. -e is set again inside: a
  # subshell tested with || would run with it off.
  case "$-" in *e*) e=1 ;; esac
  set +e
  ( [ "$e" = 1 ] && set -e; _forms_sync "$check" "$dry" "$vars" )
  rc=$?
  [ "$e" = 1 ] && set -e
  forms_unlock
  if [ "$rc" != 0 ]; then rm -f "$vars"; exit "$rc"; fi
  . "$vars"; rm -f "$vars"
}
_forms_sync(){
  local check="$1" dry="$2" vars="$3" st url="${FORMS_REPO_URL:-}" v origin tmp parent d
  trap 'printf "FORMS_OLD_REV=%s\nFORMS_NEW_REV=%s\nFORMS_CHANGED=%s\nFORMS_CONCEPTS_UNCHECKED=%s\n" "${FORMS_OLD_REV}" "${FORMS_NEW_REV}" "${FORMS_CHANGED}" "${FORMS_CONCEPTS_UNCHECKED}" > "'"$vars"'"' EXIT
  parent="$(dirname "${FORMS_CLONE_DIR}")"
  # an interrupted clone leaves a .forms.new.XXXXXX beside clinic/forms; with
  # the lock held, any made before the lock was taken is dead
  { find "$parent" -maxdepth 1 -type d -name '.forms.new.??????' ! -newer "$(forms_lock_dir)" 2>/dev/null || true; } | while IFS= read -r d; do
    if rm -rf "$d"; then info "removed ${d##*/}, a clone an earlier run did not finish"; else warn "could not remove ${d}, a clone an earlier run did not finish"; fi
  done
  st="$(forms_state "${FORMS_CLONE_DIR}")"
  v="$(forms_key_verdict "${FORMS_REPO_KEY:-}")" || fail "$v"
  case "$st" in
    foreign) fail "clinic/forms holds files the installer did not put there; ${FORMS_ASIDE}" ;;
    clone)
      origin="$(git -C "${FORMS_CLONE_DIR}" config --get remote.origin.url || true)"
      [ "$origin" = "$url" ] || fail "clinic/forms is a clone of ${origin:-an unknown repo}, not of FORMS_REPO_URL (${url}); to clone the configured repo, ${FORMS_ASIDE}"
      FORMS_OLD_REV="$(git -C "${FORMS_CLONE_DIR}" rev-parse HEAD)"
      forms_git -C "${FORMS_CLONE_DIR}" fetch --quiet origin || forms_fail "$FORMS_RC_OFFLINE" "could not fetch the forms repo (${url}); check the network and the deploy key. The forms already here keep working"
      v="$(forms_upstream_verdict "${FORMS_CLONE_DIR}")" || fail "$v"
      FORMS_NEW_REV="$(git -C "${FORMS_CLONE_DIR}" rev-parse '@{u}')"
      if [ "$v" = uptodate ]; then ok "forms repo: clinic/forms is at $(git -C "${FORMS_CLONE_DIR}" rev-parse --short HEAD), what the forms repo holds"; return 0; fi
      v="$(forms_tree_symlinks "${FORMS_CLONE_DIR}" '@{u}' | head -3 | tr '\n' ' ')"
      [ -z "$v" ] || fail "the forms repo's latest commit carries symlinks (${v}); a form file must be a plain file (a symlink would be followed inside OpenMRS). clinic/forms is left as it was; fix the forms repo"
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
      tmp="$(mktemp -d "${parent}/.forms.new.XXXXXX")"
      if ! forms_git clone --quiet "$url" "$tmp/forms"; then rm -rf "$tmp"; forms_fail "$FORMS_RC_OFFLINE" "could not clone the forms repo (${url}); check the network and the deploy key"; fi
      FORMS_NEW_REV="$(git -C "$tmp/forms" rev-parse HEAD)"
      v="$(forms_tree_symlinks "$tmp/forms" HEAD | head -3 | tr '\n' ' ')"
      [ -z "$v" ] || { rm -rf "$tmp"; fail "the forms repo carries symlinks (${v}); a form file must be a plain file (a symlink would be followed inside OpenMRS). Nothing was cloned; fix the forms repo"; }
      if [ "$dry" = 1 ]; then
        info "would: clone the forms repo into clinic/forms at $(git -C "$tmp/forms" rev-parse --short HEAD); its MANIFEST.tsv:"
        sed 's/^/    /' "$tmp/forms/MANIFEST.tsv" 2>/dev/null || info "  (no MANIFEST.tsv)"
        rm -rf "$tmp"; return 0
      fi
      [ "$check" != 1 ] || forms_concept_warn "$tmp/forms"
      rm -rf "${FORMS_CLONE_DIR}" || { rm -rf "$tmp"; fail "could not remove ${FORMS_CLONE_DIR} to put the clone in its place (a directory the container runtime created is owned by root): sudo rm -rf ${FORMS_CLONE_DIR}, then run again"; }
      # mv onto an existing directory would put the clone inside it
      [ ! -e "${FORMS_CLONE_DIR}" ] || { rm -rf "$tmp"; fail "${FORMS_CLONE_DIR} appeared while the clone was made; nothing was changed. Run again"; }
      mv "$tmp/forms" "${FORMS_CLONE_DIR}"; rm -rf "$tmp"
      FORMS_CHANGED=1
      ok "forms repo: cloned into clinic/forms at $(git -C "${FORMS_CLONE_DIR}" rev-parse --short HEAD)"
      ;;
  esac
}

# forms_rows OUT : one line per form row and pointer row of it,
# "uuid<TAB>name<TAB>version<TAB>published<TAB>retired<TAB>pointer", pointer
# being the form_resource value_reference of a file pointer (a file-storage
# datatype, or any value that is a path) in full, or empty for a form with
# none. Every form is listed, whatever its pointer: the report judges them.
# FORMS_ROWS_FILE supplies rows taken elsewhere instead.
FORMS_ROWS_SQL="select f.uuid, f.name, f.version, f.published, f.retired, coalesce(r.value_reference, '') from form f left join form_resource r on r.form_id = f.form_id and (r.datatype like '%FileSystemStorageDatatype' or r.value_reference like '/%') order by f.form_id, r.form_resource_id"
forms_rows(){
  if [ -n "${FORMS_ROWS_FILE:-}" ]; then cp "${FORMS_ROWS_FILE}" "$1"; return; fi
  forms_sql "${FORMS_ROWS_SQL}" > "$1"
}

# forms_rowfile_report DIR ROWS : every published, unretired form's pointer
# must be a plain path inside the forms folder (FORMS_PREFIX) whose file is in
# DIR. Prints one "missing <what> (<name> v<version>...)" line per failure
# (no pointer row, a pointer outside the folder, a file that is not there),
# then a summary; files no row points at are counted as pending. A pointer
# into translations/ is not required: a missing translation leaves labels
# untranslated, the form still opens. Lines starting "warn " are warnings:
# retired versions whose file is missing (saved observations made with them
# do not open) and pointers of retired or unpublished forms outside the
# folder. Returns 1 when a published form misses its file.
forms_rowfile_report(){
  local d="$1" rows="$2" TAB uuid name ver pub ret ptr file need=0 miss=0 pending=0 f
  local retmiss=0 retfirst="" outside=0 nop
  TAB="$(printf '\t')"
  # published, unretired forms with no pointer row (translations do not count)
  nop="$(awk -F'\t' -v pre="${FORMS_PREFIX}" '
    { if ($4 == 1 && $5 == 0) req[$1] = $2 " v" $3
      if ($6 != "" && index($6, pre "translations/") != 1) has[$1] = 1 }
    END { for (k in req) if (!(k in has)) print req[k] }' "$rows" | sort)"
  if [ -n "$nop" ]; then
    while IFS= read -r f; do
      printf 'missing - (%s: no form_resource row points at its file)\n' "$f"
      need=$((need + 1)); miss=$((miss + 1))
    done <<EOF
$nop
EOF
  fi
  while IFS="$TAB" read -r uuid name ver pub ret ptr || [ -n "${uuid}${ptr}" ]; do
    [ -n "$ptr" ] || continue
    # a translation pointer is not required, but one that climbs out of the
    # folder is judged below like any other pointer
    case "$ptr" in *..*) ;; "${FORMS_PREFIX}translations/"*) continue ;; esac
    case "$ptr" in
      "${FORMS_PREFIX}"*) file="${ptr#"${FORMS_PREFIX}"}" ;;
      *) if [ "$pub" = 1 ] && [ "$ret" = 0 ]; then
           need=$((need + 1)); miss=$((miss + 1))
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

# forms_rowfile_gate DIR STRICT : reads this node's form rows and runs the
# report on DIR. STRICT 1 (a forms repo is configured) fails on a missing
# file; STRICT 0 (the frozen copy) warns. The report's warnings are WARN lines
# either way.
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
    fail "row/file check: $(printf '%s\n' "$out" | sed -n 's/^summary //p'). Each form listed above would fail to open. The forms repo must hold every file the database points at: pull its latest (it only adds files); if the latest lacks them, the hub's forms have not been exported to it yet"
  fi
  warn "row/file check: $(printf '%s\n' "$out" | sed -n 's/^summary //p'). Each form listed above fails to open on this node; the frozen copy lacks its file. A forms repo (FORMS_REPO_URL) carries them"
}

# forms_manifest_diff OLD NEW : MANIFEST.tsv lines that changed (< before, > now)
forms_manifest_diff(){ diff "$1" "$2" 2>/dev/null | grep -E '^[<>]' || true; }
