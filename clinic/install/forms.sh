#!/usr/bin/env bash
# The forms OpenMRS loads at start. Sourced after lib.sh by task 075 and by
# scripts/update-forms.sh. bash 3.2 compatible.
#
# clinic/forms/ (gitignored, node-local) is one of two things:
#   - a clone of the operator's private forms repo (FORMS_REPO_URL):
#     bahmniforms/*.json in the Initializer's format, MANIFEST.tsv (the name and
#     version of every form it carries), tools/check-concepts.sh, README.md;
#   - on a node with no forms repo, a copy of the config image's own
#     bahmniforms, marked by the file .from-config-image.
# docker-compose.yml mounts clinic/forms/bahmniforms read-only over the config
# tree's masterdata/configuration/bahmniforms. At start OpenMRS copies that
# tree into its configuration directory and the Initializer loads every form
# file whose checksum changed, creating the form version with the uuid the
# file carries. The extracted config tree is replaced whenever the config image
# changes, so the forms cannot live inside it.
#
# The forms repo's concept check is called as
#   tools/check-concepts.sh --known <file>
# from the root of the tree being checked. <file> holds one concept uuid per
# line: every concept that exists and is not retired in this node's OpenMRS.
# It exits 0 when every concept the forms reference is in the file; otherwise
# it exits non-zero and names the missing ones.

FORMS_DIR="${FORMS_DIR:-${CLINIC_DIR}/forms}"
FORMS_MARK=".from-config-image"
IMAGE_FORMS_DIR="${IMAGE_FORMS_DIR:-${CLINIC_DIR}/extracted/bahmni_config/masterdata/configuration/bahmniforms}"

# forms_mount_verdict DIR : the mount source must exist and hold forms. A
# missing source is created empty by the runtime, and OpenMRS then starts with
# no forms from this tree at all.
forms_mount_verdict(){
  local d="$1" n
  if [ ! -d "$d" ]; then
    printf '%s does not exist, so OpenMRS would start with no forms from it. Installer task 075 fills it (a clone of the forms repo, or the config image'"'"'s forms); on a running node, clinic/scripts/update-forms.sh does.\n' "$d"
    return 1
  fi
  n="$(find "$d" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  if [ "${n:-0}" -eq 0 ]; then
    printf '%s holds no form file (*.json), so OpenMRS would start with no forms from it. Installer task 075 fills it (a clone of the forms repo, or the config image'"'"'s forms); on a running node, clinic/scripts/update-forms.sh does.\n' "$d"
    return 1
  fi
  printf 'ok %s form files in %s\n' "$n" "$d"
}

# forms_state DIR -> absent | placeholder | fallback | clone | foreign
# placeholder: nothing but an empty bahmniforms/ (task 030 creates every bind
# source before anything fills it). foreign: anything this file did not put
# there, which is never removed.
forms_state(){
  local d="$1" extra
  [ -e "$d" ] || { echo absent; return 0; }
  [ -d "$d" ] || { echo foreign; return 0; }
  [ -d "$d/.git" ] && { echo clone; return 0; }
  [ -f "$d/${FORMS_MARK}" ] && { echo fallback; return 0; }
  extra="$(find "$d" -mindepth 1 ! -path "$d/bahmniforms" 2>/dev/null | head -1)"
  if [ -z "$extra" ] && { [ ! -e "$d/bahmniforms" ] || [ -d "$d/bahmniforms" ]; }; then echo placeholder; return 0; fi
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

# forms_populate_fallback DIR SRC : DIR/bahmniforms becomes a copy of the
# config image's forms (SRC), refreshed in place so a running container's
# mount keeps pointing at the same directory.
forms_populate_fallback(){
  local d="$1" src="$2" label
  [ -d "$src" ] || fail "the config tree has no ${src}; task 045 extracts it from BAHMNI_CONFIG_IMAGE"
  mkdir -p "$d/bahmniforms"
  find "$d/bahmniforms" -mindepth 1 -delete
  cp -R "$src/." "$d/bahmniforms/"
  label="$(sed -n 's/^config=//p' "$(dirname "${src%/masterdata/configuration/bahmniforms}")/.source" 2>/dev/null || true)"
  printf 'forms copied from the config image%s; replaced by a clone when FORMS_REPO_URL is set\n' "${label:+ ${label}}" > "$d/${FORMS_MARK}"
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
  printf 'clinic/forms is at %s, which the forms repo (%s) does not contain: not a fast-forward. The forms repo is the only source of forms; move clinic/forms aside and run again to take a fresh clone.\n' "$(git -C "$d" rev-parse --short HEAD)" "$(git -C "$d" rev-parse --short "$up")"
  return 1
}

# forms_known_concepts OUT : every concept uuid that exists and is not retired
# in this node's OpenMRS, one per line. FORMS_CONCEPTS_FILE supplies a list
# taken elsewhere instead.
forms_known_concepts(){
  local out="$1" my n
  if [ -n "${FORMS_CONCEPTS_FILE:-}" ]; then
    [ -s "${FORMS_CONCEPTS_FILE}" ] || fail "FORMS_CONCEPTS_FILE ${FORMS_CONCEPTS_FILE} is missing or empty"
    cp "${FORMS_CONCEPTS_FILE}" "$out"; return 0
  fi
  [ -n "${CT:-}" ] || setup_compose
  my="${COMPOSE_PROJECT_NAME:?}-bahmni-mysql-1"
  printf 'select uuid from concept where retired=0' \
    | ct exec -i "$my" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N openmrs' > "$out" 2>/dev/null \
    || fail "could not read the concept list from openmrs in ${my}"
  n="$(wc -l < "$out" | tr -d ' ')"
  [ "${n:-0}" -gt 0 ] || fail "openmrs in ${my} returned no concepts; the concept check cannot run against an empty dictionary"
}

# forms_check TREE : runs TREE's tools/check-concepts.sh against this node's
# concepts. Refuses on missing concepts unless FORMS_ALLOW_MISSING_CONCEPTS=1,
# which carries on and says so loudly.
forms_check(){
  local tree="$1" known rc=0 out
  [ -f "$tree/tools/check-concepts.sh" ] || fail "the forms repo has no tools/check-concepts.sh; the forms cannot be checked against this node's concepts"
  known="$(mktemp "${TMPDIR:-/tmp}/forms-concepts.XXXXXX")"
  forms_known_concepts "$known"
  out="$( cd "$tree" && bash tools/check-concepts.sh --known "$known" 2>&1 )" || rc=$?
  rm -f "$known"
  [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/    /'
  if [ "$rc" = 0 ]; then ok "concept check: every concept the forms reference exists in this node's OpenMRS"; return 0; fi
  if [ "${FORMS_ALLOW_MISSING_CONCEPTS:-0}" = 1 ]; then
    warn "################################################################"
    warn "concept check FAILED (rc=${rc}) and FORMS_ALLOW_MISSING_CONCEPTS=1 carries on:"
    warn "the forms above reference concepts this node does not have; those fields will not work"
    warn "################################################################"
    return 0
  fi
  fail "concept check failed (rc=${rc}): the forms reference concepts this node's OpenMRS lacks (named above). The node must receive those concepts first. FORMS_ALLOW_MISSING_CONCEPTS=1 carries on regardless"
}

# forms_sync CHECK DRY : brings clinic/forms to what this node should run.
#   CHECK 1 runs the concept check on the incoming forms before they are put
#   in place; DRY 1 reports what would change and changes nothing in clinic/.
# Sets FORMS_OLD_REV and FORMS_NEW_REV (empty for the config image's copy) and
# FORMS_CHANGED (0 or 1).
forms_sync(){
  local check="$1" dry="$2" st url="${FORMS_REPO_URL:-}" v origin tmp parent
  FORMS_OLD_REV=""; FORMS_NEW_REV=""; FORMS_CHANGED=0
  st="$(forms_state "${FORMS_DIR}")"
  if [ -z "$url" ]; then
    case "$st" in
      clone) fail "clinic/forms is a clone of a forms repo, but no forms repo is configured (FORMS_REPO_URL is empty). Set FORMS_REPO_URL, or move clinic/forms aside to run the config image's forms" ;;
      foreign) fail "clinic/forms holds files the installer did not put there; move it aside and run again" ;;
    esac
    if [ "$dry" = 1 ]; then info "would: copy the config image's forms (${IMAGE_FORMS_DIR}) into ${FORMS_DIR}/bahmniforms"; return 0; fi
    forms_populate_fallback "${FORMS_DIR}" "${IMAGE_FORMS_DIR}"
    FORMS_CHANGED=1
    ok "no forms repo configured: ${FORMS_DIR}/bahmniforms holds the config image's forms"
    return 0
  fi
  v="$(forms_key_verdict "${FORMS_REPO_KEY:-}")" || fail "$v"
  case "$st" in
    foreign) fail "clinic/forms holds files the installer did not put there; move it aside and run again" ;;
    clone)
      origin="$(git -C "${FORMS_DIR}" config --get remote.origin.url || true)"
      [ "$origin" = "$url" ] || fail "clinic/forms is a clone of ${origin:-an unknown repo}, not of FORMS_REPO_URL (${url}); move clinic/forms aside and run again to clone the configured repo"
      FORMS_OLD_REV="$(git -C "${FORMS_DIR}" rev-parse HEAD)"
      forms_git -C "${FORMS_DIR}" fetch --quiet origin || fail "could not fetch the forms repo (${url}); check the network and the deploy key"
      v="$(forms_upstream_verdict "${FORMS_DIR}")" || fail "$v"
      FORMS_NEW_REV="$(git -C "${FORMS_DIR}" rev-parse '@{u}')"
      if [ "$v" = uptodate ]; then ok "forms repo: clinic/forms is at $(git -C "${FORMS_DIR}" rev-parse --short HEAD), what the forms repo holds"; return 0; fi
      if [ "$dry" = 1 ]; then
        info "would: fast-forward clinic/forms $(git -C "${FORMS_DIR}" rev-parse --short HEAD) -> $(git -C "${FORMS_DIR}" rev-parse --short '@{u}'):"
        git -C "${FORMS_DIR}" log --oneline 'HEAD..@{u}' | sed 's/^/    /'
        info "MANIFEST.tsv changes:"
        git -C "${FORMS_DIR}" diff 'HEAD' '@{u}' -- MANIFEST.tsv | sed -n '/^[-+][^-+]/p' | sed 's/^/    /'
        info "form files:"
        git -C "${FORMS_DIR}" diff --stat 'HEAD' '@{u}' -- bahmniforms | sed 's/^/    /'
        return 0
      fi
      if [ "$check" = 1 ]; then
        tmp="$(mktemp -d "${TMPDIR:-/tmp}/forms-incoming.XXXXXX")"
        git -C "${FORMS_DIR}" archive '@{u}' | tar -x -C "$tmp"
        ( forms_check "$tmp" ) || { rm -rf "$tmp"; exit 1; }
        rm -rf "$tmp"
      fi
      git -C "${FORMS_DIR}" merge --quiet --ff-only '@{u}' || fail "could not fast-forward clinic/forms"
      FORMS_CHANGED=1
      ok "forms repo: clinic/forms fast-forwarded $(printf '%s' "${FORMS_OLD_REV}" | cut -c1-7) -> $(git -C "${FORMS_DIR}" rev-parse --short HEAD)"
      ;;
    absent|placeholder|fallback)
      parent="$(dirname "${FORMS_DIR}")"
      tmp="$(mktemp -d "${parent}/.forms.new.XXXXXX")"
      if ! forms_git clone --quiet "$url" "$tmp/forms"; then rm -rf "$tmp"; fail "could not clone the forms repo (${url}); check the network and the deploy key"; fi
      FORMS_NEW_REV="$(git -C "$tmp/forms" rev-parse HEAD)"
      if [ "$dry" = 1 ]; then
        info "would: clone the forms repo into clinic/forms at $(git -C "$tmp/forms" rev-parse --short HEAD)$( [ "$st" = fallback ] && printf ', replacing the config image'"'"'s forms'); its MANIFEST.tsv:"
        sed 's/^/    /' "$tmp/forms/MANIFEST.tsv" 2>/dev/null || info "  (no MANIFEST.tsv)"
        rm -rf "$tmp"; return 0
      fi
      if [ "$check" = 1 ]; then ( forms_check "$tmp/forms" ) || { rm -rf "$tmp"; exit 1; }; fi
      rm -rf "${FORMS_DIR}" || { rm -rf "$tmp"; fail "could not remove ${FORMS_DIR} to put the clone in its place (a directory the container runtime created is owned by root): sudo rm -rf ${FORMS_DIR}, then run again"; }
      mv "$tmp/forms" "${FORMS_DIR}"; rm -rf "$tmp"
      FORMS_CHANGED=1
      ok "forms repo: cloned into clinic/forms at $(git -C "${FORMS_DIR}" rev-parse --short HEAD)"
      ;;
  esac
}

# forms_manifest_rows FILE : "name<TAB>version" for every form MANIFEST.tsv
# lists. The header row names the columns: name (or form) and version.
forms_manifest_rows(){
  awk -F'\t' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    !h { for (i = 1; i <= NF; i++) { c = tolower($i); gsub(/[[:space:]]/, "", c); if (c == "name" || c == "form") n = i; if (c == "version") v = i }
         h = 1; if (!n || !v) { print "MANIFEST.tsv: the header names no name/form and version columns" > "/dev/stderr"; exit 2 } next }
    { print $n "\t" $v }
  ' "$1"
}

# forms_sql_quote TEXT : TEXT as a MySQL string literal
forms_sql_quote(){ printf "'%s'" "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g")"; }
