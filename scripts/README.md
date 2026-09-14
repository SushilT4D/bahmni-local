# scripts/

Operational scripts for a clinic node (Ghated / clinic 2). Entries below are derived from each
script's own header comment and were checked against the tree on 2026-09-14 —
every file named here exists.

> The previous version of this file documented four scripts (`setup-all.sh`,
> `setup-connectors.sh`, and two `*/scripts/setup-connectors.sh`). **None of
> them exists any more**, and none of the 35 scripts actually present was
> listed. It had not been touched since 2026-08-14.

## Before you run anything

Most scripts talk to Kafka Connect's REST API. **This node serves it on 8083**
(the port `docker-compose.yml` health-checks). Seven scripts still target
**8084**, the separate Connect instance from the original MirrorMaker-only
setup — see "Targets port 8084" below before using them.

## Preflight and health

| Script | What it does |
|---|---|
| `preflight.sh` | Node preflight for the three-node lab (F-007, F-017, F-022): reachability, disk, memory |
| `check-sink-tasks.sh` | Sweeps ALL connectors and judges on **task** state, not connector state — a RUNNING connector can sit over a FAILED task |
| `check-source-connectors.sh` | Source (Debezium/MySQL) connector status on this node |
| `check-sink-connectors.sh` | Sink connector status on the remote/cloud side |
| `check-schema-history.sh` | Confirms the Debezium schema-history topic exists and is readable |
| `check-mirrormaker.sh` | Connectivity to the remote Kafka over SASL/SSL |

## Connector lifecycle

| Script | What it does |
|---|---|
| `register-source-connector.sh` | Registers the Debezium MySQL source connector |
| `register-mirrormaker.sh` | Registers the MirrorMaker 2 connector |
| `deploy-connectors.sh` | Waits for Connect, then deploys |
| `unregister-connectors.sh` | Unregisters connectors |
| `fix-offsets.sh` | Walkthrough for inspecting and correcting connector offsets |
| `configure-pk-offsets.sh` | Sets this clinic's MySQL AUTO_INCREMENT spacing (the residue striding that keeps node IDs collision-free) |
| `generate-local-sink-connectors.sh` | Renders the DOWN-direction (cloud -> clinic) sinks, one connector per cloud-owned table from `debezium/cloud/tables.conf`. Output carries an injected password and is gitignored |
| `register-local-sink-connectors.sh` | POSTs those down-direction sinks to this clinic's Kafka Connect worker — the same worker hosting the up-direction Debezium source |

## Generating configuration

| Script | What it does |
|---|---|
| `generate-connectors.sh` | Builds the local Debezium source connector config from `debezium/local/tables.conf` |
| `generate-table-config.sh` | Prints `TABLE_INCLUDE_LIST` / `KAFKA_TOPICS` from `debezium/{local,cloud}/tables.conf` |
| `generate-topics.sh` | Generates the Kafka topic list from the database and table configuration |
| `setup-mirrormaker.sh` | Renders the MirrorMaker 2 config from its template. **Node-specific — never copy another node's `mm2.properties` over this node's** |

## Retention and durability

| Script | What it does |
|---|---|
| `set-schema-history-retention.sh` | F-045: the Debezium schema-history topic must never expire; overrides the 7-day broker default |
| `apply-slot-heartbeat.sh` | F-043: heartbeat table plus publication membership in the `clinlims` database |

## Data movement

| Script | What it does |
|---|---|
| `pull-openmrs-db.sh` | Dumps `openmrs` on the cloud host, downloads it, loads it into local `bahmni-mysql` |
| `trace-change.sh` | Traces a database change through the local components |

## Testing

| Script | What it does |
|---|---|
| `test-replication.sh` | End-to-end replication test |
| `test-kafka-auth.py` | Verifies Kafka endpoint authentication, including that an unauthenticated connection is refused |
| `send-to-remote-kafka.py` / `.sh` | Sends a Debezium-shaped change event straight to the remote Kafka, bypassing local MySQL — exercises Kafka → JDBC sink → remote MySQL |

## Targets port 8084 (the old MirrorMaker-only Connect)

`check-status.sh`, `delete-connectors.sh`, `restart-connectors.sh`,
`update-connector.sh`, `register-mirrormaker.sh`, and parts of
`deploy-connectors.sh` and `trace-change.sh` still address **8084**. Confirm
which Connect instance you mean before running them against this node.

## Known broken or unusable as committed

- `backup_bahmni_lite.sh`, `restore_bahmni_lite.sh` — both `source
  ../backup_restore/*_utils.sh`, and **`backup_restore/` is not present in this
  repo**. They cannot run as committed.
- `configure_debezium.sh` — hardcodes
  `/Applications/MAMP/Library/bin/mysql80/bin/mysql`. MAMP is not installed on
  this node; this is a leftover from an early laptop setup.
- `mysqldump.sh` — a command template with `<REMOTE_HOST>`/`<REMOTE_USER>`
  placeholders, not a runnable script.
- `config.sh` — a workstation bootstrap (`brew install podman-compose`,
  `mkcert`, `mysql-client`), not service configuration. The name misleads.
