#!/bin/bash
# Generates the hub's MySQL (OpenMRS) source connector: captures the [down] tables of
# sync/tables/openmrs.conf into one ordered topic, <server>.openmrs.all, for clinics' MirrorMaker to pull.
# usage: generate-cloud-source-connector.sh [OUT]   (default ./connectors/mysql-cloud-source-connector.json)
set -euo pipefail
# the output holds DEBEZIUM_DB_PASSWORD: written mode 600
umask 077

# ROOT is the repo checkout, HUB_ROOT its cloud directory (template); .env and the output are in the working directory
ROOT="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
HUB_ROOT="${HUB_DIR:-${ROOT}/cloud}"
TEMPLATE="${HUB_ROOT}/scripts/templates/mysql-cloud-source-connector.json.template"
OUT="${1:-$PWD/connectors/mysql-cloud-source-connector.json}"

[[ -f "$TEMPLATE" ]] || { echo "missing template: $TEMPLATE" >&2; exit 1; }
# settings: the repo .env, then ./.env (which wins)
# shellcheck disable=SC1091
for envf in "${ROOT}/.env" "$PWD/.env"; do
  [[ -f "$envf" ]] && set -a && source "$envf" && set +a
done

# the table list, from the [down] section; an empty list would capture everything
TABLE_INCLUDE_LIST="$("${ROOT}/clinic/scripts/generate-table-config.sh" cloud | grep '^TABLE_INCLUDE_LIST=' | cut -d= -f2-)"
[[ -n "$TABLE_INCLUDE_LIST" ]] || { echo "empty TABLE_INCLUDE_LIST — refusing to emit a source that captures EVERYTHING (loop risk)" >&2; exit 1; }

# template values, with defaults
export ROOT TEMPLATE TABLE_INCLUDE_LIST
export OPENMRS_DB_HOST="${OPENMRS_DB_HOST:?OPENMRS_DB_HOST is not set in .env}"
export OPENMRS_DB_PORT="${OPENMRS_DB_PORT:-3306}"
export OPENMRS_DB_NAME="${OPENMRS_DB_NAME:?OPENMRS_DB_NAME is not set in .env}"
export CLOUD_MYSQL_SERVER_NAME="${CLOUD_MYSQL_SERVER_NAME:-bahmni-cloud}"
export CLOUD_DEBEZIUM_SERVER_ID="${CLOUD_DEBEZIUM_SERVER_ID:-184055}"
export CLOUD_KAFKA_BOOTSTRAP="${CLOUD_KAFKA_BOOTSTRAP:-kafka:29092}"
export DEBEZIUM_DB_USER="${DEBEZIUM_DB_USER:-debezium}"
export DEBEZIUM_DB_PASSWORD="${DEBEZIUM_DB_PASSWORD:-}"
[[ -n "$DEBEZIUM_DB_PASSWORD" ]] || { echo "DEBEZIUM_DB_PASSWORD unset in .env" >&2; exit 1; }

# fill the template and apply the guards (Python below), then write OUT
mkdir -p "$(dirname "$OUT")"
python3 - "$OUT" <<'PYEOF'
import json, os, re, sys
raw = open(os.environ['TEMPLATE']).read()
for k in ('OPENMRS_DB_HOST','OPENMRS_DB_PORT','OPENMRS_DB_NAME','CLOUD_MYSQL_SERVER_NAME',
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
# cloud captures rows that just arrived FROM a clinic and clinics pull them
# straight back -- an infinite loop.
# A down list that grows to include clinic-written tables (person, patient,
# visit, encounter) would put them in this whitelist; the guards below refuse it.
# A comment cannot prevent that. A computed intersection can.
# Clinical rows are written at the clinics, each on its own residue, and the
# hub's tables receive them from the up sinks. Capturing one of them here would
# publish every clinic's rows to every other clinic, and back to the clinic
# that wrote them, through a source with no origin filter. Refused by name, so
# the refusal holds even before the clinic's own list carries the table.
root = os.environ['ROOT']
TABLES = os.path.join(root, 'sync', 'tables', 'openmrs.conf')
def section(path, name):
    """The raw lines of one [name] section of a sync/tables/*.conf file."""
    out, inside, found = [], False, False
    for line in open(path):
        t = line.strip()
        if re.fullmatch(r'\[[a-z]+\]', t):
            inside = t == f'[{name}]'; found = found or inside
            continue
        if inside:
            out.append(line)
    if not found:
        sys.exit(f"{path}: no [{name}] section")
    return out

# Rows marked `clinic=<column>` in sync/tables/openmrs.conf [down]: tables the clinics write, of
# which the hub publishes only the rows it wrote itself (lab results entered at
# the hub); each clinic keeps those whose <column> names a row it wrote. Each
# gets a row filter below; without it such a table would carry every clinic's
# rows to every other clinic. The column is fixed per table, because each
# clinic's sink needs that column's base to tell its own rows from older ones.
ROUTE = {'encounter': 'visit_id', 'obs': 'order_id'}
routed = {}
plain = set()
# Rows marked `changes`: tables the hub authors whose rows every clinic already
# holds; the source captures changes made from now on and none of the rows the
# table holds when the source first snapshots it.
changes = set()
# Rows marked `hub-rows`: tables the hub and the clinics both write, each its own
# rows (the people behind logins at the hub, patients at a clinic). The source
# publishes only the hub's: key at or above the table's floor, ending in 0. The
# floor is the table's base in sync/tables/openmrs.conf [up], read below.
hubrows = {}
for line in section(TABLES, 'down'):
    line = line.split('#', 1)[0].strip()
    parts = line.split(':')
    if line and len(parts) == 3 and not (parts[2] in ('relay', 'changes', 'hub-rows') or parts[2].startswith('clinic=')):
        sys.exit(f"sync/tables/openmrs.conf [down]: {line}: unknown role '{parts[2]}' (relay, hub-rows, changes or clinic=<column>)")
    if line and not (len(parts) == 3 and parts[2].startswith('clinic=')):
        plain.add(parts[0])
    if line and len(parts) == 3 and parts[2] == 'changes':
        changes.add(parts[0])
    if line and len(parts) == 3 and parts[2] == 'hub-rows':
        if ',' in parts[1]:
            sys.exit(f"sync/tables/openmrs.conf [down]: {line}: a hub-rows table is filtered on its key, which must be a single column")
        hubrows[parts[0]] = parts[1]
    if len(parts) == 3 and parts[2].startswith('clinic='):
        col = parts[2][len('clinic='):]
        if parts[0] not in ROUTE:
            sys.exit(f"sync/tables/openmrs.conf [down]: {line}: only encounter and obs carry the hub's lab results to a clinic; "
                     "no other table may be published under clinic=")
        if col != ROUTE[parts[0]] or ',' in parts[1]:
            sys.exit(f"sync/tables/openmrs.conf [down]: {line}: {parts[0]} is kept by a clinic by {ROUTE[parts[0]]} "
                     f"({parts[0]}:<key>:clinic={ROUTE[parts[0]]}), on a single-column key")
        routed[parts[0]] = (parts[1], col)

# Orders and their drug and test details are written at the clinics only. obs is published only
# through its clinic= row above: an unmarked obs row, even beside it, is refused.
never = sorted(({'orders', 'drug_order', 'test_order'} & {t.split('.')[-1] for t in inc.split(',')})
               | ({'obs', 'orders', 'drug_order', 'test_order'} & plain) | ({'obs'} & ({t.split('.')[-1] for t in inc.split(',')} - set(routed))))
if never:
    sys.exit(
        f"REFUSING to generate: the hub never publishes {never}: they are written at\n"
        "  the clinics and reach the hub through its up sinks. Remove them from sync/tables/openmrs.conf [down].")

up = set()
base = {}
for line in section(TABLES, 'up'):
    line = line.strip()
    if line and not line.startswith('#'):
        f = line.split()[0].split(':')
        up.add(f[0])
        if len(f) >= 3 and f[2].isdigit():
            base[f[0]] = int(f[2])
down = {t.split('.')[-1] for t in inc.split(',')}
# A hub-rows table is published behind its floor filter, or not at all: a floor
# that cannot be read refuses the whole source, never a source without the filter.
floor = {}
for t, pk in sorted(hubrows.items()):
    if t not in down:
        continue
    f = base.get(t)
    if not f or f % 10:
        sys.exit(f"REFUSING to generate: {t} is marked hub-rows, and its floor in sync/tables/openmrs.conf [up] "
                 f"({t}:{pk}:<floor>) is {'missing' if not f else f'{f}, not a multiple of 10'}. Without a floor "
                 "the source cannot tell the hub's rows from older ones, which sit on every residue.")
    floor[t] = f
clash = sorted((down & up) - set(routed) - set(floor))
if clash:
    sys.exit(
        f"REFUSING to generate: these tables appear in BOTH direction files: {clash}\n"
        "  (clinic-owned per sync/tables/openmrs.conf [up], and cloud-owned per this one)\n"
        "\n"
        "  A table the clinics write is published by the hub only under a mark in\n"
        "  sync/tables/openmrs.conf [down] that gives it a row filter: `hub-rows` (the hub's own rows of a\n"
        "  table both sides write, at or above its floor and ending in 0) or\n"
        "  `clinic=<column>` (the hub's lab results for one clinic). `relay` is not\n"
        "  published here at all: a hub that passed every clinic's rows on would send each\n"
        "  clinic's patients to every other clinic. An UNMARKED clinic-owned table is\n"
        "  refused, because that is the accident this guard exists to catch.")
# The row filter for each `clinic=` table. A row passes only when the hub wrote
# it: its key ends in 0, the hub's residue. Rows a clinic sent up end in that
# clinic's residue and never pass, so nothing a clinic wrote comes back down.
# Which clinic keeps a passed row is the clinic sink's filter, by <column>.
# Tombstones carry no row and are dropped; a delete still arrives as its own
# change event, with the row in `before`.
# A snapshot of a `clinic=` table reads its structure and none of its rows:
# rows written before the source started answer orders and visits older than
# every clinic's base, which no clinic keeps, and reading them would publish
# millions of rows for every clinic to drop. Changes from the start on are captured.
# A `changes` table is snapshotted the same way: every clinic already holds its
# rows, and only what changes from now on is captured.
cfg = doc['config']
db = os.environ['OPENMRS_DB_NAME']
overrides = []
for t in sorted(changes):
    if f"{db}.{t}" not in inc.split(','):
        continue
    overrides.append(f"{db}.{t}")
    cfg[f"snapshot.select.statement.overrides.{db}.{t}"] = f"SELECT * FROM `{db}`.`{t}` WHERE 1 = 0"
if routed:
    names = [n for n in cfg.get('transforms', '').split(',') if n]
    preds = [n for n in cfg.get('predicates', '').split(',') if n]
    server = os.environ['CLOUD_MYSQL_SERVER_NAME']
    for t, (pk, col) in sorted(routed.items()):
        if f"{db}.{t}" not in inc.split(','):
            continue
        overrides.append(f"{db}.{t}")
        cfg[f"snapshot.select.statement.overrides.{db}.{t}"] = f"SELECT * FROM `{db}`.`{t}` WHERE 1 = 0"
        n = f"hubWrittenRows_{t}"; p = f"topicIs_{t}"
        names.append(n); preds.append(p)
        cfg[f"transforms.{n}.type"] = "io.debezium.transforms.Filter"
        cfg[f"transforms.{n}.language"] = "jsr223.groovy"
        cfg[f"transforms.{n}.null.handling.mode"] = "drop"
        cfg[f"transforms.{n}.condition"] = (
            "def r = value.get('after') != null ? value.get('after') : value.get('before'); "
            f"r != null && key.get('{pk}') instanceof Number && key.get('{pk}').longValue() % 10 == 0")
        cfg[f"transforms.{n}.predicate"] = p
        cfg[f"predicates.{p}.type"] = "org.apache.kafka.connect.transforms.predicates.TopicNameMatches"
        cfg[f"predicates.{p}.pattern"] = "^" + re.escape(f"{server}.{db}.{t}") + "$"
    cfg['transforms'] = ','.join(names)
    cfg['predicates'] = ','.join(preds)
# The row filter for each `hub-rows` table, on the record's key so that an
# update, a delete and its tombstone are judged alike: the key is at or above
# the table's floor and ends in 0. A snapshot of such a table reads the same
# rows and no others.
if floor:
    names = [n for n in cfg.get('transforms', '').split(',') if n]
    preds = [n for n in cfg.get('predicates', '').split(',') if n]
    server = os.environ['CLOUD_MYSQL_SERVER_NAME']
    for t, f in sorted(floor.items()):
        pk = hubrows[t]
        overrides.append(f"{db}.{t}")
        cfg[f"snapshot.select.statement.overrides.{db}.{t}"] = (
            f"SELECT * FROM `{db}`.`{t}` WHERE `{pk}` >= {f} AND `{pk}` % 10 = 0")
        n = f"hubOwnRows_{t}"; p = f"topicIs_{t}"
        names.append(n); preds.append(p)
        cfg[f"transforms.{n}.type"] = "io.debezium.transforms.Filter"
        cfg[f"transforms.{n}.language"] = "jsr223.groovy"
        cfg[f"transforms.{n}.null.handling.mode"] = "evaluate"
        cfg[f"transforms.{n}.condition"] = (
            f"key != null && key.get('{pk}') instanceof Number && "
            f"key.get('{pk}').longValue() >= {f} && key.get('{pk}').longValue() % 10 == 0")
        cfg[f"transforms.{n}.predicate"] = p
        cfg[f"predicates.{p}.type"] = "org.apache.kafka.connect.transforms.predicates.TopicNameMatches"
        cfg[f"predicates.{p}.pattern"] = "^" + re.escape(f"{server}.{db}.{t}") + "$"
    cfg['transforms'] = ','.join(names)
    cfg['predicates'] = ','.join(preds)
    # fail closed: each hub-rows table in the list has its filter, or nothing is written
    for t in floor:
        n = f"hubOwnRows_{t}"
        if n not in cfg['transforms'].split(',') or f">= {floor[t]}" not in cfg.get(f"transforms.{n}.condition", ""):
            sys.exit(f"REFUSING to write: {t} is captured without its row filter {n}")
if overrides:
    cfg['snapshot.select.statement.overrides'] = ','.join(sorted(overrides))
# Route every table into one ordered topic, <server>.openmrs.all, after the filters.
server = os.environ['CLOUD_MYSQL_SERVER_NAME']
names = [n for n in cfg.get('transforms', '').split(',') if n] + ['agg']
cfg['transforms'] = ','.join(names)
cfg['transforms.agg.type'] = 'org.apache.kafka.connect.transforms.RegexRouter'
cfg['transforms.agg.regex'] = re.escape(server) + r'\.' + re.escape(db) + r'\.(' + '|'.join(sorted(down)) + r')$'
cfg['transforms.agg.replacement'] = f"{server}.{db}.all"
json.dump(doc, open(sys.argv[1], 'w'), indent=2)
print(f"  tables captured: {inc}")
if routed:
    print(f"  hub-written rows only: {', '.join(sorted(routed))}")
if changes:
    print(f"  changes only, no existing rows: {', '.join(sorted(changes))}")
if floor:
    print(f"  the hub's own rows only: {', '.join(f'{t} (from {f}, ending in 0)' for t, f in sorted(floor.items()))}")
PYEOF
echo "wrote ${OUT}"
