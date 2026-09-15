#!/usr/bin/env bash
# SUPERSEDED 2026-09-09 on clinic nodes by retire-mysql-origin-guard.sh: the Groovy filters
# and the person/person_name stamping triggers are retired; the loop guard is
# sessionVariables=sql_log_bin=0 on the clinic sinks (sync-core F-047).
# ADDED 2026-09-02 (sync-core F-019). Applies the ADR-003 write-origin FILTERS to a
# node's MySQL connectors. Until now these existed only as prose in MODIFICATIONS.md
# and as live state in Kafka Connect — no committed definition, so a rebuilt node
# would silently come up with no guard at all.
#
# THE BUG THIS ENCODES THE FIX FOR. The source filter was written as
#     return o == null || o == '<node>';
# copied from a first draft that assumed NULL was harmless. It is not: with every
# node permitting NULL on both the publish and the accept side, an unstamped row is
# published by everyone and accepted by everyone. On the PostgreSQL/clinlims path
# that produced 341,175 messages for a 9-row table and filled the cloud's disk.
#
# WHY THE FIX IS PUBLISH-SIDE ONLY. Verified against the deployed groovy-4.0.22:
#     o = null ; o == null || o == 'rawach'  -> true    (old source: PUBLISHES nulls)
#     o = null ; o == 'rawach'               -> false   (new source: does not)
#     o = null ; o != 'rawach'               -> true    (sink: accepts, unchanged)
# The sink already behaves correctly for NULL, because the hub legitimately holds
# unstamped rows and a clinic should accept them. Only the publish side was wrong.
#
# WHY THERE IS NO BACKFILL HERE, unlike the clinlims equivalent. Surveyed 2026-09-02:
# 121,727 unstamped person rows and ~121,730 unstamped person_name rows PER NODE.
# With binlog_format=ROW and binlog_row_image=FULL, one changed row is one binlog
# event is one Kafka message, with no statement-level collapsing. A three-node
# backfill would touch ~730,375 rows and originate ~2.2M messages (~3.6M counting
# mirrored copies) — a bounded flood, not a runaway, but the same shape that took
# the cloud down. It would also overwrite the peer's unstamped rows with the
# backfilling node's name, destroying provenance for every one of them.
# The rows came from a common seed and are already converged; freezing them costs
# nothing, and any future edit is stamped by the trigger and syncs normally.
#
# NOTE ON THE HUB. The cloud deliberately has NO origin filter on either side. That
# is ADR-003's asymmetry, not an omission: spokes publish only their own writes, the
# hub publishes everything (which is what makes clinic-to-clinic relay possible), and
# spoke sinks drop their own echo. The cloud's sinks need no filter because they
# consume only clinic topics, which are already filtered at source.
#
# Usage:  ./openmrs/apply-mysql-origin-filter.sh <node-name>   # e.g. rawach | ghated
#         Run ON the clinic node, against its local Kafka Connect at :8083.
set -euo pipefail
NODE="${1:?usage: $0 <node-name>}"
BASE="${CONNECT_URL:-http://localhost:8083}"

COND_SRC="{ -> def r = (value.op == 'd' ? value.before : value.after); if (r == null) return true; if (r.schema().field('sync_origin') == null) return true; def o = r.get('sync_origin'); return o == '${NODE}'; }()"
COND_SINK="{ -> def r = (value.op == 'd' ? value.before : value.after); if (r == null) return true; if (r.schema().field('sync_origin') == null) return true; def o = r.get('sync_origin'); return o != '${NODE}'; }()"

python3 - "$BASE" "$NODE" "$COND_SRC" "$COND_SINK" <<'PY'
import json, sys, time, urllib.request
BASE, NODE, C_SRC, C_SINK = sys.argv[1:5]

def get(p):
    return json.load(urllib.request.urlopen(BASE + p, timeout=30))

def put(name, cfg):
    cfg.pop("name", None)
    body = json.dumps(cfg).encode()
    for i in range(8):
        try:
            r = urllib.request.Request(f"{BASE}/connectors/{name}/config", data=body,
                                       headers={"Content-Type": "application/json"}, method="PUT")
            with urllib.request.urlopen(r, timeout=60) as x:
                return x.status
        except Exception as e:
            if i == 7:
                raise
            time.sleep(5)

changed = 0
for name in sorted(get("/connectors")):
    cfg = get(f"/connectors/{name}/config")
    if "filterOrigin" not in cfg.get("transforms", ""):
        continue
    klass = cfg.get("connector.class", "")
    is_src = "mysql.MySqlConnector" in klass
    # SCOPE: this script owns the MySQL/openmrs guard only. The clinlims (PostgreSQL)
    # connectors carry their own guard with a different topic regex and are managed by
    # openelis/apply-write-origin-guard.sql. An earlier version of this script matched
    # on "filterOrigin" alone and rewrote clinlims-clinic-sink as collateral — harmless
    # then only because the two conditions happen to be equivalent for NULL.
    is_sink = "jdbc.JdbcSinkConnector" in klass and "openmrs" in cfg.get("topics", "")
    if not (is_src or is_sink):
        print(f"  skip (not a MySQL/openmrs connector): {name}")
        continue
    want = C_SRC if is_src else C_SINK
    if cfg.get("transforms.filterOrigin.condition") == want:
        print(f"  already correct: {name}")
        continue
    cfg["transforms.filterOrigin.condition"] = want
    print(f"  updated HTTP {put(name, cfg)}: {name}")
    changed += 1
print(f"--- {changed} connector(s) updated on node '{NODE}' ---")
PY
