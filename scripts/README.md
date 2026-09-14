# `scripts/` — clinic-node operator scripts

Hand-run scripts for a **clinic node** (Rawach, Ghated). They render config,
register connectors, and read back live state. Nothing here runs automatically:
there is no cron, no entrypoint, and no CI that invokes them.

## Where the authoritative usage lives

**This file does not define the order to run things in.** The runbooks do, and
they live in a *different repository* — the `Bahmni` workspace, under
`docs/sync-core/runbooks/`. Thirteen of the scripts below are cited there and
nowhere inside this repo, so a search confined to `bahmni-local` reports them as
unreferenced when they are in fact load-bearing. Check the runbooks before
concluding anything here is dead.

## Groups

**Render config** — read `debezium/{local,cloud}/tables.conf` plus `.env` and
emit connector/topic definitions.

| script | renders |
|---|---|
| `generate-connectors.sh` | the UP-direction Debezium MySQL source connector |
| `generate-local-sink-connectors.sh` | the DOWN-direction (cloud → clinic) sinks |
| `generate-table-config.sh` | `TABLE_INCLUDE_LIST` / `KAFKA_TOPICS` |
| `generate-topics.sh` | the Kafka topic list |
| `setup-mirrormaker.sh` | `mm2.properties` from the template |

**Register / unregister** — talk to the local Kafka Connect REST API.
`register-source-connector.sh`, `register-local-sink-connectors.sh`,
`register-mirrormaker.sh`, `deploy-connectors.sh`, `update-connector.sh`,
`unregister-connectors.sh`, `delete-connectors.sh`.

**Verify** — read live state and judge it. `preflight.sh` (reachability, disk,
clock), `check-sink-tasks.sh`, `check-sink-connectors.sh`,
`check-source-connectors.sh`, `check-mirrormaker.sh`,
`check-schema-history.sh`, `check-status.sh`, `trace-change.sh`,
`test-replication.sh`.

> Prefer `check-sink-tasks.sh`: it sweeps every connector and judges on **task**
> state, not connector state. A connector reports `RUNNING` while its task is
> dead, so a check that reads connector state passes over a broken sink.

**Per-clinic identity and striding** — `configure-pk-offsets.sh` sets this
clinic's MySQL `AUTO_INCREMENT` offset/increment. This is what makes the strided
integer PK collision-free, so it is a precondition for L-008 (per-row ownership)
and L-010 (the sync key), not a tuning knob.

**Retention and liveness** — `set-schema-history-retention.sh` (the Debezium
schema-history topic must never expire) and `apply-slot-heartbeat.sh` (heartbeat
table plus publication membership in both Postgres databases).

**Data movement** — `pull-openmrs-db.sh`, `mysqldump.sh`,
`backup_bahmni_lite.sh`, `restore_bahmni_lite.sh`.

**Recovery** — `fix-offsets.sh`, `restart-connectors.sh`.

**Ad-hoc probes** — `send-to-remote-kafka.{sh,py}`, `test-kafka-auth.py`,
`drop-sync-origin`, `configure_debezium.sh`, `config.sh`.

## Conventions

- Run from the repo root, not from inside `scripts/`. Paths resolve relative to
  the root and the scripts read the root `.env`.
- `.env` is gitignored; `.env.example` enumerates every variable.
- Rendered connector JSON is gitignored by design — `.gitignore` covers
  `debezium/cloud/connectors/mysql-sink-*.json` and both
  `debezium/{local,cloud}/connectors/generated/`. Templates are tracked, output
  is not: a rendered config carries a live password, so it must never be
  committed. Regenerate rather than copy.
