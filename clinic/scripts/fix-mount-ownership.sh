#!/usr/bin/env bash
# Chown bind-mounted data directories to the uid:gid the image runs as, before
# the stack starts writing to them.
#
# On a Linux Docker host, Odoo 16 answers HTTP 500
# on every request -- PermissionError: [Errno 13] Permission denied:
# '/var/lib/odoo/.local'. Odoo's image runs as uid 101 ('odoo'); task 030
# creates CONTAINER_DATA_PATH's bind sources with a plain `mkdir -p`, so they
# land owned by the login user (1000:1000, mode 775) and uid 101 cannot write.
# Measured on the same host: Kafka and MirrorMaker (uid 1000) only happened to
# work because the login user is ALSO 1000; kafka-connect (uid 1001) cannot
# write /kafka/connect/data. So this is a class of defect, not one directory --
# every service below is swept the same way.
#
# Directories come from the MERGED compose config (docker-compose.yml plus
# docker-compose.override.yml), never from grepping either file by hand, so a
# mount added to either file is picked up here with no edit to this script.
# The uid:gid an image runs as is read with a throwaway container (never the
# real service), and a directory is only touched if its current owner differs.
#
# Standalone, on an already-installed node:
#   cd clinic && CT=docker bash scripts/fix-mount-ownership.sh
# Wired: called from install/tasks/080-stack.sh, right before the stack starts
# (images present since task 040, directories created since task 030).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# A fresh `bash scripts/fix-mount-ownership.sh` subprocess never inherits the
# caller's shell functions (ok/skip/fail/... are not exported) -- source lib.sh
# whenever they are missing, standalone or wired alike.
type ok >/dev/null 2>&1 || . "${HERE}/../install/lib.sh"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"
PLATFORM="${PLATFORM:-$(detect_platform)}"

# Respect an already-exported CT (the documented standalone form pins it
# explicitly, e.g. CT=docker); only setup_compose's own runtime detection when
# CT is unset. setup_compose ALWAYS overwrites CT from detect_runtime, which
# would silently replace an operator's explicit CT=docker with podman on
# macOS -- so it only runs when there is nothing to preserve.
if [ -z "${CT:-}" ]; then
  setup_compose
elif [ -z "${COMPOSE_CMD:-}" ]; then
  if [ "${CT}" = docker ]; then
    COMPOSE_CMD="docker compose"
  else
    COMPOSE_CMD="docker-compose"
    [ -n "${DOCKER_HOST:-}" ] || export DOCKER_HOST="$(podman_socket)"
  fi
fi
export CT COMPOSE_CMD

begin_task "fix-mount-ownership: bind-mounted data directories"

# The class of service this incident belongs to: any service with a
# bind-mounted data directory a non-root image user must write. Add a new one
# here when a new such service is introduced -- the directories themselves
# always come from the merged compose config, never a hand-maintained list.
SERVICES="odoo kafka kafka-controller kafka-connect mirrormaker-connect schema-registry"

# COMPOSE_JSON_FILE is a testability hook: tests feed a fixture through it
# instead of a real compose config.
json="${COMPOSE_JSON_FILE:-}"
cleanup_json=0
if [ -z "$json" ]; then
  json="$(mktemp)"; cleanup_json=1
  ( cd "${CLINIC_DIR}" && compose config --format json ) > "$json" || fail "compose config --format json failed"
fi
# `[ cond ] && rm ...` would return the test's own (non-)zero status when
# cond is false -- fine on its own (guarded), but this runs as the EXIT trap,
# where a non-zero return re-triggers lib.sh's ERR trap on the way out. An
# explicit if always returns 0.
cleanup(){ if [ "$cleanup_json" = 1 ]; then rm -f "$json"; fi; }
trap cleanup EXIT

# One line per candidate: either "SKIP\t<service>\t<reason>" for a service not
# in this profile set's merged config, or "DIR\t<service>\t<image>\t<dir>" for
# an eligible mount -- read-write, type=bind (never a named volume, never a
# file), realpath under CLINIC_DIR (never outside it), and a DIRECTORY on disk
# today (a file mount, even a bind one, is left alone). Lines for one service
# are emitted together, in SERVICES order, so the shell loop below can probe
# the image's uid:gid once per service.
mounts="$(SERVICES="$SERVICES" CLINIC_DIR="$CLINIC_DIR" python3 - "$json" <<'PY'
import json, os, sys

services = os.environ["SERVICES"].split()
clinic_dir = os.path.realpath(os.environ["CLINIC_DIR"])
with open(sys.argv[1]) as f:
    data = json.load(f)
svcs = data.get("services", {}) or {}

for name in services:
    svc = svcs.get(name)
    if svc is None:
        print("SKIP\t%s\tnot in this compose profile set" % name)
        continue
    image = svc.get("image", "")
    for vol in (svc.get("volumes") or []):
        if vol.get("type") != "bind":
            continue
        if vol.get("read_only"):
            continue
        src = vol.get("source") or ""
        if not src:
            continue
        rsrc = os.path.realpath(src)
        if rsrc != clinic_dir and not rsrc.startswith(clinic_dir + os.sep):
            continue
        if not os.path.isdir(rsrc):
            continue
        print("DIR\t%s\t%s\t%s" % (name, image, src))
PY
)"

# tracked_dir DIR : true if `git` tracks any file under DIR in this checkout.
# No candidate directory is tracked today (checked: data/*, files/odoo,
# odoo-addons, config/odoo are all untracked), but a directory that starts
# tracking files later and gets chowned to a container uid would make the
# next `git pull` fail for the login user -- so this is checked before every
# chown, not just today's known-safe set. A node with no `git` binary, or a
# CLINIC_DIR outside any checkout, has no tracked files by definition; guard
# the call so either behaves as "no tracked files" rather than failing the
# whole sweep over an absent binary or a plain (non-git) deployment.
tracked_dir(){
  command -v git >/dev/null 2>&1 || return 1
  [ -n "$(git -C "${CLINIC_DIR}" ls-files -- "$1" 2>/dev/null || true)" ]
}

# stat -c is GNU (Linux); -f is BSD (macOS). Prints "uid gid", empty on error.
owner_of(){
  local d="$1" u g
  u="$(stat -c %u "$d" 2>/dev/null || stat -f %u "$d" 2>/dev/null || true)"
  g="$(stat -c %g "$d" 2>/dev/null || stat -f %g "$d" 2>/dev/null || true)"
  printf '%s %s\n' "$u" "$g"
}

prev_service=""; svc_uid=""; svc_gid=""; svc_root=0
while true; do
  # `read` returning non-zero at end-of-input is how this loop is meant to
  # end; `|| break` makes that explicit so it can never read as a real
  # failure to the ERR trap above (unguarded, it does -- see lib.sh's own
  # comment on _on_err: only if/&&/||/while-guarded failures stay quiet).
  IFS=$'\t' read -r kind a b c || break
  [ -n "$kind" ] || continue
  case "$kind" in
    SKIP)
      skip "${a}: ${b}"
      ;;
    DIR)
      service="$a"; image="$b"; dir="$c"
      rel="${dir#${CLINIC_DIR}/}"
      if tracked_dir "$dir"; then
        skip "${service}: ${rel} holds git-tracked files -- left to the login user"
        continue
      fi
      if [ "$service" != "$prev_service" ]; then
        prev_service="$service"; svc_root=0
        if [ "${DRY}" = 1 ]; then
          svc_uid=""; svc_gid=""
        else
          svc_uid="$(ct run --rm --entrypoint id "$image" -u 2>/dev/null || true)"
          svc_gid="$(ct run --rm --entrypoint id "$image" -g 2>/dev/null || true)"
          if [ -z "$svc_uid" ] || [ -z "$svc_gid" ]; then
            fail "${service}: could not read the uid/gid ${image} runs as (${CT} run --rm --entrypoint id ${image} -u/-g)"
          fi
          if [ "$svc_uid" = 0 ]; then
            svc_root=1
            skip "${service}: image runs as root (uid 0) -- nothing to fix"
          fi
        fi
      fi
      if [ "${DRY}" = 1 ]; then
        info "would chown ${service}: ${rel} (image ${image})"
        continue
      fi
      [ "$svc_root" = 1 ] && continue
      read -r cur_u cur_g <<<"$(owner_of "$dir")"
      if [ "$cur_u" = "$svc_uid" ] && [ "$cur_g" = "$svc_gid" ]; then
        skip "${service}: ${rel} already ${svc_uid}:${svc_gid}"
        continue
      fi
      ct run --rm -u 0 --entrypoint chown -v "${dir}:/fix" "$image" -R "${svc_uid}:${svc_gid}" /fix >/dev/null 2>&1 || true
      read -r new_u new_g <<<"$(owner_of "$dir")"
      if [ "$new_u" = "$svc_uid" ] && [ "$new_g" = "$svc_gid" ]; then
        ok "${service}: ${rel} -> ${svc_uid}:${svc_gid}"
      elif [ "${PLATFORM}" = macos ]; then
        # Rootless podman over virtiofs does not map host-side ownership 1:1;
        # a chown that does not take here is a known limit, not a defect to
        # stop the install over.
        warn "${service}: ${rel} chown to ${svc_uid}:${svc_gid} did not take (now ${new_u:-?}:${new_g:-?}) -- rootless podman/virtiofs does not map ownership 1:1; leaving as is"
      else
        fail "${service}: ${rel} chown to ${svc_uid}:${svc_gid} did not take (now ${new_u:-?}:${new_g:-?}): ${COMPOSE_CMD:-compose} logs ${service}"
      fi
      ;;
  esac
done <<EOF
$mounts
EOF
