#!/usr/bin/env bash
# Fix ownership of writable bind mounts before services start.
# Usage: scripts/fix-mount-ownership.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load installer helpers when invoked as a standalone subprocess.
type ok >/dev/null 2>&1 || . "${HERE}/../install/lib.sh"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"
setup_compose

begin_task "fix-mount-ownership: bind-mounted data directories"

# Services whose writable bind mounts need ownership checks.
SERVICES="odoo kafka kafka-connect mirrormaker-connect"

# Allow tests to supply a Compose config fixture.
json="${COMPOSE_JSON_FILE:-}"
cleanup_json=0
if [ -z "$json" ]; then
  json="$(mktemp)"; cleanup_json=1
  compose_json > "$json" || fail "compose config could not be read as JSON"
fi
# Keep the EXIT trap successful when no temporary config was created.
cleanup(){ if [ "$cleanup_json" = 1 ]; then rm -f "$json"; fi; }
trap cleanup EXIT

# Include only writable, in-tree bind-mounted directories from Compose config.
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

# Never chown directories containing tracked files.
tracked_dir(){
  command -v git >/dev/null 2>&1 || return 1
  [ -n "$(git -C "${CLINIC_DIR}" ls-files -- "$1" 2>/dev/null || true)" ]
}

# owner_of DIR : "uid gid" (macOS stat), empty on error.
owner_of(){ stat -f '%u %g' "$1" 2>/dev/null || true; }

prev_service=""; svc_uid=""; svc_gid=""; svc_root=0
while true; do
  # EOF ends the generated mount list normally.
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
      else
        # Rootless podman over virtiofs does not map host-side ownership 1:1;
        # a chown that does not take here is a known limit, not a defect to
        # stop the install over.
        warn "${service}: ${rel} chown to ${svc_uid}:${svc_gid} did not take (now ${new_u:-?}:${new_g:-?}) -- rootless podman/virtiofs does not map ownership 1:1; leaving as is"
      fi
      ;;
  esac
done <<EOF
$mounts
EOF
