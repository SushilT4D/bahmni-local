#!/usr/bin/env bash
# Writes every connector config this clinic uploads to Kafka Connect into
# clinic/connectors/, from the templates in scripts/templates/ and the table
# lists in sync/tables/. Passwords stay ${...} placeholders, filled in by
# register-connectors.sh at upload time, so no generated file holds one.
#
# usage: scripts/generate-connectors.sh [PART...]
#   mysql-source  the OpenMRS source (generate/mysql-source.sh)
#   mysql-sinks   the OpenMRS down sinks (generate/mysql-sinks.sh)
#   postgres      the Odoo and OpenELIS sources and down sinks (generate/postgres.sh)
# With no PART, all three.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
parts=("$@"); [ ${#parts[@]} -gt 0 ] || parts=(mysql-source mysql-sinks postgres)
for p in "${parts[@]}"; do
  case "$p" in
    mysql-source|mysql-sinks|postgres) bash "${HERE}/generate/${p}.sh" ;;
    *) echo "generate-connectors.sh: unknown part '$p' (mysql-source, mysql-sinks or postgres)" >&2; exit 2 ;;
  esac
done
