#!/bin/bash
# generate-cloud-source-connector.sh — render the DOWN-direction Debezium source that
# runs ON THE CLOUD and publishes cloud-owned admin tables as bahmni-cloud.openmrs.*
#
# table.include.list comes from debezium/cloud/tables.conf via generate-table-config.sh,
# so the whitelist can never drift from the declared ownership split (L-001).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEMPLATE="${ROOT}/debezium/cloud/connectors/mysql-cloud-source-connector.json.template"
OUT="${1:-${ROOT}/debezium/cloud/connectors/generated/mysql-cloud-source-connector.json}"

[[ -f "$TEMPLATE" ]] || { echo "missing template: $TEMPLATE" >&2; exit 1; }
# Env: repo root first, then the cloud deployment's own .env (which wins).
# The cloud stack is deployed from debezium/cloud/, so DEBEZIUM_DB_PASSWORD and the
# other cloud-side values live in debezium/cloud/.env, not at the repo root.
# shellcheck disable=SC1091
for envf in "${ROOT}/.env" "${ROOT}/debezium/cloud/.env"; do
  [[ -f "$envf" ]] && set -a && source "$envf" && set +a
done

TABLE_INCLUDE_LIST="$("${ROOT}/scripts/generate-table-config.sh" cloud | grep '^TABLE_INCLUDE_LIST=' | cut -d= -f2-)"
[[ -n "$TABLE_INCLUDE_LIST" ]] || { echo "empty TABLE_INCLUDE_LIST — refusing to emit a source that captures EVERYTHING (loop risk)" >&2; exit 1; }

export ROOT TEMPLATE TABLE_INCLUDE_LIST
export CLOUD_MYSQL_HOST="${CLOUD_MYSQL_HOST:-openmrsdb}"
export CLOUD_MYSQL_PORT="${CLOUD_MYSQL_PORT:-3306}"
export CLOUD_MYSQL_DATABASE="${CLOUD_MYSQL_DATABASE:-openmrs}"
export CLOUD_MYSQL_SERVER_NAME="${CLOUD_MYSQL_SERVER_NAME:-bahmni-cloud}"
export CLOUD_DEBEZIUM_SERVER_ID="${CLOUD_DEBEZIUM_SERVER_ID:-184055}"
export CLOUD_KAFKA_BOOTSTRAP="${CLOUD_KAFKA_BOOTSTRAP:-kafka:29092}"
export DEBEZIUM_DB_USER="${DEBEZIUM_DB_USER:-debezium}"
export DEBEZIUM_DB_PASSWORD="${DEBEZIUM_DB_PASSWORD:-}"
[[ -n "$DEBEZIUM_DB_PASSWORD" ]] || { echo "DEBEZIUM_DB_PASSWORD unset in .env" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
python3 - "$OUT" <<'PYEOF'
import json, os, sys
raw = open(os.environ['TEMPLATE']).read()
for k in ('CLOUD_MYSQL_HOST','CLOUD_MYSQL_PORT','CLOUD_MYSQL_DATABASE','CLOUD_MYSQL_SERVER_NAME',
          'CLOUD_DEBEZIUM_SERVER_ID','CLOUD_KAFKA_BOOTSTRAP','DEBEZIUM_DB_USER',
          'DEBEZIUM_DB_PASSWORD','TABLE_INCLUDE_LIST'):
    raw = raw.replace('${%s}' % k, os.environ[k])
doc = json.loads(raw)
doc['config'] = {k: v for k, v in doc['config'].items() if not k.startswith('//')}
left = [k for k, v in doc['config'].items() if '${' in str(v)]
if left: sys.exit(f"unsubstituted placeholder(s): {left}")
inc = doc['config']['table.include.list']
if not inc or '*' in inc:
    sys.exit("LOOP GUARD: table.include.list must be an explicit cloud-owned list")

# LOOP GUARD, the one that matters. The cloud's binlog also records every
# UP-direction sink write. If any clinic-owned table appears in this whitelist, the
# cloud captures rows that just arrived FROM a clinic and MirrorMaker sends them
# straight back down -- an infinite loop and an L-001 violation.
# This is not hypothetical: on 2026-08-20 debezium/cloud/tables.conf on the cloud host
# had been extended from 7 to 19 tables (its header still said "Cloud -> local sync"),
# so this generator produced a whitelist containing person/patient/visit/encounter.
# A comment cannot prevent that. A computed intersection can.
root = os.environ['ROOT']
up = set()
with open(os.path.join(root, 'debezium', 'local', 'tables.conf')) as fh:
    for line in fh:
        line = line.strip()
        if line and not line.startswith('#'):
            up.add(line.split()[0].split(':')[0])
down = {t.split('.')[-1] for t in inc.split(',')}
clash = sorted(down & up)
if clash:
    sys.exit(
        f"REFUSING to generate: these tables appear in BOTH direction files: {clash}\n"
        "  (clinic-owned per debezium/local/tables.conf, and cloud-owned per this one)\n"
        "\n"
        "  This is NOT a claim that the hub must never capture them. The running hub DOES\n"
        "  capture person and person_name, deliberately. ADR-003 section 7: spokes publish\n"
        "  only their own writes, THE HUB PUBLISHES EVERYTHING, spokes drop their own echo.\n"
        "  That is the mechanism that makes a patient registered at one clinic visible at\n"
        "  another. The hub's up-direction sinks therefore run WITHOUT sql_log_bin=0 by\n"
        "  construction (ADR-004, BL-068); on MySQL 5.6 they could not set it in any case,\n"
        "  SYSTEM_VARIABLES_ADMIN being an 8.0 privilege. The clinics, on 8.0, do set it,\n"
        "  which is what stops the relayed row travelling back up.\n"
        "\n"
        "  The refusal stands because that rule is recorded as DESIGNED BUT UNTESTED\n"
        "  (ADR-003) over an open constitution gap (L-008 unsuperseded, the proposed L-011\n"
        "  never adopted; ADR-004 lists it 'not resolved'). Generating a source config from\n"
        "  an unratified rule would put this file ahead of the decision.\n"
        "\n"
        "  So do not simply add the table here to silence this. If the clinic needs the\n"
        "  table to arrive -- which is the BL-042 case -- mark it with the role field:\n"
        "\n"
        "      person:person_id:relay\n"
        "\n"
        "  `relay` says the CLINIC authors it and the hub only passes it downward. The\n"
        "  clinic's generators then include it (they read every row) while this one still\n"
        "  does not (it reads unmarked rows only), which is the split that lets one file\n"
        "  answer both readers. An UNMARKED clinic-owned table is still refused, because\n"
        "  that is the accident this guard exists to catch.\n"
        "\n"
        "  Marking a table does NOT ratify the relay. The hub keeps publishing only what\n"
        "  the cloud authors until ADR-003 s7 is settled; `generate-table-config.sh cloud\n"
        "  --include-relay` is the explicit opt-in for when it is.")
json.dump(doc, open(sys.argv[1], 'w'), indent=2)
print(f"  tables captured: {inc}")
PYEOF
echo "wrote ${OUT}"
