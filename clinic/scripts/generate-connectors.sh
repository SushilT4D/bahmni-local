#!/usr/bin/env bash
# Regenerates every connector config in clinic/connectors/ from the templates in
# scripts/templates/ and the table lists in sync/tables/. Passwords stay ${...}
# placeholders; register-connectors.sh fills them in when it uploads.
# The work is split into generate/mysql-source.sh, generate/mysql-sinks.sh and
# generate/postgres.sh.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -f "${HERE}/../connectors/"*.json
for part in mysql-source mysql-sinks postgres; do
  bash "${HERE}/generate/${part}.sh"
done
