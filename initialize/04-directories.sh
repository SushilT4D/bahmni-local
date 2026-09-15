#!/usr/bin/env bash
# Create project data/config directories.
set -euo pipefail
INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${INIT_DIR}/lib.sh"
parse_task_args "$@"
begin_task "04 · Data / config directories"

dirs=(
  certs/ca certs/kafka
  config/bahmni-app config/odoo config/mirrormaker config/kafka-connect
  data/bahmni-clinical-forms data/bahmni-document-images data/bahmni-patient-images
  data/bahmni-uploaded-files data/bahmni-lab-results
  data/kafka data/kafka-connect data/mirrormaker data/mysql data/odoo
  data/postgresql data/zookeeper data/configuration_checksums data/openmrs/lucene
  files/odoo files/postgresql
  logs/zookeeper
  connectors
)

missing=0
for d in "${dirs[@]}"; do
  if [[ ! -d "${PROJECT_DIR}/${d}" ]]; then
    missing=$((missing + 1))
  fi
done

if [[ "${missing}" -eq 0 && "${FORCE}" != true ]]; then
  skip "directory tree already present under ${PROJECT_DIR}"
  exit 0
fi

for d in "${dirs[@]}"; do
  mkdir -p "${PROJECT_DIR}/${d}"
done
ok "Directory tree ready under ${PROJECT_DIR}"
