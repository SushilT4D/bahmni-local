# `scripts/` — clinic-node operator scripts

Hand-run scripts for a **clinic node** (Rawach, Ghated). They render config,
register connectors, and read back live state. Nothing here runs automatically:
there is no cron, no entrypoint, and no CI that invokes them.

## Where the authoritative usage lives

**This file does not define the order to run things in.** The operator's
runbooks do, and they are kept outside this repository. Many of the scripts
below are cited there and nowhere inside this repo, so a search confined to
`bahmni-local` reports them as unreferenced when they are in fact
load-bearing. Check the runbooks before concluding anything here is dead.

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
`unregister-connectors.sh`. `register-local-sink-connectors.sh` first reads the
`sink` user's grants and refuses, naming the tables and registering nothing,
when any down sink's table lacks SELECT, INSERT, UPDATE or DELETE.

**Down-table grants** — `grant-down-tables.sh` grants the clinic's `sink`
database user SELECT, INSERT, UPDATE and DELETE on every table
`hub/tables.conf` lists, and reads the grants back. Seed task 050 does the same
when it seeds; run this on a node seeded before a table joined that file, then
regenerate and register the down sinks. `--dry-run` prints the grants.

**Table verdicts** — `check-table-verdicts.sh` holds `hub/tables.conf` and
`sync/local/tables.conf` to `hub/table-verdicts.conf`, the one record of which
node writes each table: a down row must be a hub-written table (DOWN) or a
relayed one, a clinic capture row must be one a clinic writes (UP or relay).
It names every row that breaks the rule and reads files only; run it after
editing either list.

**Verify** — read live state and judge it. `preflight.sh` (VM disk and memory,
MySQL `wait_timeout` floor, PG slot retention, Kafka, connector task states),
`check-sink-tasks.sh`, `check-sink-connectors.sh`, `check-source-connectors.sh`,
`check-mirrormaker.sh`, `check-schema-history.sh`,
`trace-change.sh`, `test-replication.sh`.

> `preflight.sh` runs **entirely on this node** and opens no connections. The
> fan-out across nodes is the operator's own tooling, outside this repo — it
> pipes this same file to each node over SSH, so every node is judged by one
> ruler.

> Prefer `check-sink-tasks.sh`: it sweeps every connector and judges on **task**
> state, not connector state. A connector reports `RUNNING` while its task is
> dead, so a check that reads connector state passes over a broken sink.

**Per-clinic identity and striding** — `configure-pk-offsets.sh` sets this
clinic's MySQL `AUTO_INCREMENT` offset/increment. This is what makes the strided
integer PK collision-free, so it is a precondition for per-row ownership and
the sync key, not a tuning knob.

**Retention and liveness** — `set-schema-history-retention.sh` (the Debezium
schema-history topic must never expire) and `apply-slot-heartbeat.sh` (heartbeat
table plus publication membership in both Postgres databases).

> Seeding a clinic from cloud data is a **manual** step: take the dump and share
> the file. Nothing here SSHes to the hub to dump and download — see the note
> below.

**Forms** — `update-forms.sh` takes new form files from the operator's private
forms repo on a running node, from a schedule or by hand: fast-forward
`clinic/forms` (refusing local edits and history the repo lacks), warn about
concepts the node lacks, and check that every published form row in the
database has its file. It never restarts OpenMRS. `--dry-run` shows the
incoming commits and `MANIFEST.tsv` changes and changes nothing. See
`../install/README.md` ("Forms"). Its one remote is the forms repo's git host,
read-only, with the deploy key `clinic/.env` names; it opens no shell anywhere.
Exit codes: 0 done, 1 a check refused, 3 the forms repo could not be reached,
4 another run holds `clinic/forms`.

**Recreate OpenMRS** — `recreate-openmrs.sh` runs the checks installer task
080 runs before OpenMRS starts (JVM options, the forms mount, the Initializer
domain list against the config tree) and then recreates openmrs alone with the
node's compose setup. The way to make a running node take a new config tree,
forms mount or `clinic/.env` setting; a refused check recreates nothing.
`--check` runs the checks only.

**Ad-hoc probes** — `test-kafka-auth.py`.

## Conventions

- Run from `clinic/` (the compose project directory), not from inside `scripts/`.
  Paths resolve relative to `clinic/`, the scripts read `clinic/.env`, and the
  shared sync definitions are `../sync/` (tables, subsystems, templates, the
  clinics ledger) with the hub tree at `../hub/`.
- `.env` is gitignored; `.env.example` enumerates every variable.
- Rendered connector JSON is gitignored by design — `.gitignore` covers
  `hub/connectors/mysql-sink-*.json`, `hub/connectors/generated/` and
  `sync/local/connectors/generated/`. Templates are tracked, output
  is not: a rendered config carries a live password, so it must never be
  committed. Regenerate rather than copy.

## No SSH lives here

This directory contains **nothing that reaches another machine**, and it should
stay that way. A clinic node talks to `localhost`; it reaches the hub over
Kafka, never a shell. That transport is meant to be mTLS with per-site ACLs
confining each site to its own topics, so a shell from every
clinic to the hub is far wider access than the architecture grants — and this
repo is public.

What used to reach out, and what replaced it (the resolved compose config
references SSH zero times):

| Was | Now |
|---|---|
| `preflight.sh`'s three-node fan-out, with the hub's hostname and a path to one developer's private key | operator wrapper in the Bahmni workspace repo; the checks stayed here, node-local |
| `skills/capacity-preflight.sh` (whole `skills/` dir) | moved to the Bahmni workspace repo — operator tooling |
| `pull-openmrs-db.sh` | dropped; dumps are taken and shared manually |

If you are about to add a script that SSHes somewhere, it belongs in the
operator's repo, not this one.
