#!/usr/bin/env bash
# Usage: clinic/scripts/update-forms.sh
# Checks, changing nothing, that every published form has its file in the forms folder; exits 1 with the list otherwise.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"; export CLINIC_DIR
REPO_DIR="${REPO_DIR:-$(cd "${HERE}/../.." && pwd)}"; export REPO_DIR
. "${HERE}/../install/lib.sh"
. "${INSTALL_DIR}/forms.sh"
usage(){ sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }
case "${1:-}" in
  '') ;;
  -h|--help) usage; exit 0 ;;
  *) usage; fail "unknown argument: $1" ;;
esac
E="${CLINIC_DIR}/.env"
[ -f "$E" ] || fail "no ${E}: this is not an installed node"
COMPOSE_PROJECT_NAME=bahmni   # name: in docker-compose.yml
export COMPOSE_PROJECT_NAME
begin_task "forms check"
dir="$(env_get "$E" FORMS_DIR)"
v="$(forms_folder_verdict "$dir")" || fail "$v"
ok "forms: ${v#ok }"
forms_rowfile_gate "$dir" 1
