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

**Verify** — read live state and judge it. `preflight.sh` (VM disk and memory,
MySQL `wait_timeout` floor, PG slot retention, Kafka, connector task states),
`check-sink-tasks.sh`, `check-sink-connectors.sh`, `check-source-connectors.sh`,
`check-mirrormaker.sh`, `check-schema-history.sh`, `check-status.sh`,
`trace-change.sh`, `test-replication.sh`.

> `preflight.sh` runs **entirely on this node** and opens no connections. The
> three-node fan-out that used to live in it is the operator's, and moved to the
> Bahmni workspace repo (`skills/lab-preflight.sh`) on 2026-09-14 — it pipes this
> same file to each node over SSH, so every node is judged by one ruler.

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

**Data movement** — `mysqldump.sh`, `backup_bahmni_lite.sh`,
`restore_bahmni_lite.sh`.

> Seeding a clinic from cloud data is a **manual** step: take the dump and share
> the file. `pull-openmrs-db.sh`, which SSHed to the hub to dump and download,
> was removed on 2026-09-14 — see the note below.

**Recovery** — `fix-offsets.sh`, `restart-connectors.sh`.

**Ad-hoc probes** — `send-to-remote-kafka.{sh,py}`, `test-kafka-auth.py`,
`drop-sync-origin`, `configure_debezium.sh`, `config.sh`.

## Conventions

- Run from `clinic/` (the compose project directory), not from inside `scripts/`.
  Paths resolve relative to `clinic/`, the scripts read `clinic/.env`, and the
  shared sync definitions are `../sync/` (tables, subsystems, templates, the
  clinics ledger) with the hub tree at `../cloud/`.
- `.env` is gitignored; `.env.example` enumerates every variable.
- Rendered connector JSON is gitignored by design — `.gitignore` covers
  `cloud/connectors/mysql-sink-*.json`, `cloud/connectors/generated/` and
  `sync/local/connectors/generated/`. Templates are tracked, output
  is not: a rendered config carries a live password, so it must never be
  committed. Regenerate rather than copy.

## No SSH lives here

This directory contains **nothing that reaches another machine**, and it should
stay that way. A clinic node talks to `localhost`; it reaches the hub over
Kafka, never a shell. Under L-007 that transport is meant to be mTLS with
per-site ACLs confining each site to its own topics, so a shell from every
clinic to the hub is far wider access than the architecture grants — and this
repo is public.

Removed on 2026-09-14, when `git grep` found SSH in exactly three files and the
resolved compose config referenced it zero times:

| Was | Now |
|---|---|
| `preflight.sh`'s three-node fan-out, with the hub's hostname and a path to one developer's private key | operator wrapper in the Bahmni workspace repo; the checks stayed here, node-local |
| `skills/capacity-preflight.sh` (whole `skills/` dir) | moved to the Bahmni workspace repo — operator tooling |
| `pull-openmrs-db.sh` | dropped; dumps are taken and shared manually |

If you are about to add a script that SSHes somewhere, it belongs in the
operator's repo, not this one.
