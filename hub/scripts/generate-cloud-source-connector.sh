#!/bin/bash
# generate-cloud-source-connector.sh — render the DOWN-direction Debezium source that
# runs ON THE CLOUD and publishes cloud-owned admin tables as bahmni-cloud.openmrs.*
#
# table.include.list comes from hub/tables.conf via generate-table-config.sh,
# so the whitelist can never drift from the declared ownership split.
set -euo pipefail
# The file this script writes carries DEBEZIUM_DB_PASSWORD in plaintext, so it
# is created mode 600, not the default 644. umask
# here rather than a chmod afterwards: a chmod leaves a window in which the
# rendered file is world-readable, however short.
umask 077

# Two roots, resolved separately:
#   ROOT     the REPO checkout -- clinic/scripts/generate-table-config.sh and
#            sync/local/tables.conf, which are repo files wherever the hub tree
#            happens to live;
#   HUB_ROOT the HUB directory -- the template, hub/.env and the default output.
# Both fall back to this script's own location.
ROOT="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
HUB_ROOT="${HUB_DIR:-${ROOT}/hub}"
TEMPLATE="${HUB_ROOT}/connectors/mysql-cloud-source-connector.json.template"
OUT="${1:-${HUB_ROOT}/connectors/generated/mysql-cloud-source-connector.json}"

[[ -f "$TEMPLATE" ]] || { echo "missing template: $TEMPLATE" >&2; exit 1; }
# Env: repo root first, then hub/.env (which wins).
# The sync layer is deployed from hub/, so DEBEZIUM_DB_PASSWORD and the
# other hub-side values live in hub/.env, not at the repo root.
# shellcheck disable=SC1091
for envf in "${ROOT}/.env" "${HUB_ROOT}/.env"; do
  [[ -f "$envf" ]] && set -a && source "$envf" && set +a
done

TABLE_INCLUDE_LIST="$("${ROOT}/clinic/scripts/generate-table-config.sh" cloud | grep '^TABLE_INCLUDE_LIST=' | cut -d= -f2-)"
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
import json, os, re, sys
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
# straight back down -- an infinite loop.
# This is not hypothetical: a cloud tables.conf once grew from 7 to 19 tables
# (its header still said "Cloud -> local sync"),
# so this generator produced a whitelist containing person/patient/visit/encounter.
# A comment cannot prevent that. A computed intersection can.
# Clinical rows are written at the clinics, each on its own residue, and the
# hub's tables receive them from the up sinks. Capturing one of them here would
# publish every clinic's rows to every other clinic, and back to the clinic
# that wrote them, through a source with no origin filter. Refused by name, so
# the refusal holds even before the clinic's own list carries the table.
root = os.environ['ROOT']

# Rows marked `patient=<column>` in hub/tables.conf: tables the clinics write, of
# which the hub publishes only its own rows for a clinic's patient (lab results
# entered at the hub). Each gets a row filter below; without it such a table
# would carry every clinic's rows to every other clinic.
patient = {}
plain = set()
with open(os.path.join(root, 'hub', 'tables.conf')) as fh:
    for line in fh:
        line = line.split('#', 1)[0].strip()
        parts = line.split(':')
        if line and not (len(parts) == 3 and parts[2].startswith('patient=')):
            plain.add(parts[0])
        if len(parts) == 3 and parts[2].startswith('patient='):
            col = parts[2][len('patient='):]
            if not re.fullmatch(r'[a-z_][a-z0-9_]*', col) or ',' in parts[1]:
                sys.exit(f"hub/tables.conf: {line}: patient=<column> needs a single-column key and a plain column name")
            if parts[0] not in ('encounter', 'obs'):
                sys.exit(f"hub/tables.conf: {line}: only encounter and obs carry the hub's lab results for a clinic's patients; "
                         "no other table may be published under patient=")
            patient[parts[0]] = (parts[1], col)

# Orders and drug orders are written at the clinics only. obs is published only
# through its patient= row above: an unmarked obs row, even beside it, is refused.
never = sorted(({'orders', 'drug_order'} & {t.split('.')[-1] for t in inc.split(',')})
               | ({'obs', 'orders', 'drug_order'} & plain) | ({'obs'} & ({t.split('.')[-1] for t in inc.split(',')} - set(patient))))
if never:
    sys.exit(
        f"REFUSING to generate: the hub never publishes {never}: they are written at\n"
        "  the clinics and reach the hub through its up sinks. Remove them from hub/tables.conf.")

up = set()
base = None
with open(os.path.join(root, 'sync', 'local', 'tables.conf')) as fh:
    for line in fh:
        line = line.strip()
        if line and not line.startswith('#'):
            f = line.split()[0].split(':')
            up.add(f[0])
            if f[0] == 'person' and len(f) > 2 and f[2].isdigit():
                base = int(f[2])
down = {t.split('.')[-1] for t in inc.split(',')}
clash = sorted((down & up) - set(patient))
if clash:
    sys.exit(
        f"REFUSING to generate: these tables appear in BOTH direction files: {clash}\n"
        "  (clinic-owned per sync/local/tables.conf, and cloud-owned per this one)\n"
        "\n"
        "  This is NOT a claim that the hub must never capture them. The running hub DOES\n"
        "  capture person and person_name, deliberately. The relay rule: spokes publish\n"
        "  only their own writes, THE HUB PUBLISHES EVERYTHING, spokes drop their own echo.\n"
        "  That is the mechanism that makes a patient registered at one clinic visible at\n"
        "  another. The hub's up-direction sinks therefore run WITHOUT sql_log_bin=0 by\n"
        "  construction; on MySQL 5.6 they could not set it in any case,\n"
        "  SYSTEM_VARIABLES_ADMIN being an 8.0 privilege. The clinics, on 8.0, do set it,\n"
        "  which is what stops the relayed row travelling back up.\n"
        "\n"
        "  The refusal stands because that relay rule is designed but not yet ratified\n"
        "  or tested end to end. Generating a source config from an unratified rule\n"
        "  would put this file ahead of the decision.\n"
        "\n"
        "  So do not simply add the table here to silence this. If the clinic needs the\n"
        "  table to arrive -- a cloud-created user must reach the clinic whole -- mark it\n"
        "  with the role field:\n"
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
        "  the cloud authors until the relay rule is ratified; `generate-table-config.sh cloud\n"
        "  --include-relay` is the explicit opt-in for when it is.")
# The row filter for each `patient=` table. A row passes only when the hub wrote
# it (its key ends in 0, the hub's residue) and its patient belongs to a clinic
# (at or above the person base, not ending in 0). Rows a clinic sent up end in
# that clinic's residue and never pass; nor do central patients' rows.
# Tombstones carry no row and are dropped; a delete still arrives as its own
# change event, with the row in `before`.
if patient:
    if base is None:
        sys.exit("sync/local/tables.conf gives no person base (person:person_id:<base>); the clinic-patient filter needs it")
    cfg = doc['config']
    names = [n for n in cfg.get('transforms', '').split(',') if n]
    preds = [n for n in cfg.get('predicates', '').split(',') if n]
    server = os.environ['CLOUD_MYSQL_SERVER_NAME']; db = os.environ['CLOUD_MYSQL_DATABASE']
    for t, (pk, col) in sorted(patient.items()):
        if f"{db}.{t}" not in inc.split(','):
            continue
        n = f"hubRowsForClinicPatients_{t}"; p = f"topicIs_{t}"
        names.append(n); preds.append(p)
        cfg[f"transforms.{n}.type"] = "io.debezium.transforms.Filter"
        cfg[f"transforms.{n}.language"] = "jsr223.groovy"
        cfg[f"transforms.{n}.null.handling.mode"] = "drop"
        cfg[f"transforms.{n}.condition"] = (
            "def r = value.get('after') != null ? value.get('after') : value.get('before'); "
            f"r != null && key.get('{pk}') instanceof Number && key.get('{pk}').longValue() % 10 == 0 "
            f"&& r.get('{col}') instanceof Number && r.get('{col}').longValue() >= {base}L "
            f"&& r.get('{col}').longValue() % 10 != 0")
        cfg[f"transforms.{n}.predicate"] = p
        cfg[f"predicates.{p}.type"] = "org.apache.kafka.connect.transforms.predicates.TopicNameMatches"
        cfg[f"predicates.{p}.pattern"] = "^" + re.escape(f"{server}.{db}.{t}") + "$"
    cfg['transforms'] = ','.join(names)
    cfg['predicates'] = ','.join(preds)
json.dump(doc, open(sys.argv[1], 'w'), indent=2)
print(f"  tables captured: {inc}")
if patient:
    print(f"  hub rows for clinic patients only: {', '.join(sorted(patient))}")
PYEOF
echo "wrote ${OUT}"
