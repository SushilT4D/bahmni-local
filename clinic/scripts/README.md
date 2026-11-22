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

**Connectors** — two scripts.

- `generate-connectors.sh` regenerates every connector config in
  `../connectors/` (the OpenMRS, Odoo and OpenELIS sources and down sinks) from `templates/` and
  `../../sync/tables/`. Passwords stay `${...}` placeholders. Its work is split
  into the scripts in `generate/`.
- `register-connectors.sh` uploads configs from `../connectors/` to Kafka
  Connect, filling in the passwords from `.env`. With no arguments it uploads
  all of them; or name some (`register-connectors.sh mysql-source-connector`,
  `register-connectors.sh 'mysql-local-sink-*'`). Before the OpenMRS down sink
  is uploaded it checks the `sink` user's grants on every `[down]` table and uploads
  nothing if one is missing.

Each database syncs through one ordered topic per direction: the clinic sends
`<server>.openmrs.all`, `<server>.odoo.all` and `<server>.clinlims.all`, and pulls the
cloud server's `bahmni-cloud.<database>.all`. Every table is routed into it, so changes
arrive in commit order (a parent row before its children), and one sink writes each
record to the table it came from.

To change which tables sync, edit `../../sync/tables/` (see its README), then
run both scripts. `unregister-connectors.sh` removes the MySQL source.

**Other rendered config**

| script | renders |
|---|---|
| `generate-table-config.sh` | `TABLE_INCLUDE_LIST` / `KAFKA_TOPICS` |
| `setup-mirrormaker.sh` | `mm2.properties` from the template |

**OpenELIS sink role** — `create-clinlims-sink-role.sh` creates the `clinlims_sink`
role the OpenELIS down sinks log in as, stores its password in `.env`, and checks
its grants on the OpenELIS `[down]` tables. Task 050 runs it; re-run it after a
table joins `sync/tables/openelis.conf [down]`.

**Odoo sink role** — `create-odoo-sink-role.sh` creates the `odoo_sink` role the
Odoo down sinks log in as and stores its password in `.env`. Task 050 runs it.

**Down-table grants** — `grant-down-tables.sh` grants the clinic's `sink`
database user SELECT, INSERT, UPDATE and DELETE on every table
`sync/tables/openmrs.conf [down]` lists, and reads the grants back. Seed task 050 does the same
when it seeds; run this on a node seeded before a table joined that file, then
regenerate and register the down sinks. `--dry-run` prints the grants.

**Table verdicts** — `check-table-verdicts.sh` holds `sync/tables/openmrs.conf [down]` and
`sync/tables/openmrs.conf [up]` to `cloud/table-verdicts.conf`, the one record of which
node writes each table: a down row must be a hub-written table (DOWN) or a
relayed one, a clinic capture row must be one a clinic writes (UP or relay).
It reads `sync/tables/openmrs.conf [up]` with `sync/tables/tables.sh`, the reader
every capture, mirror, striding and sink script uses, so a line those scripts
refuse fails here too; and the tables that reader never lets a clinic capture
must be DOWN or OUT in the verdicts. It names every row that breaks a rule and
reads files only; run it after editing either list or either file.

**Capture filter** — `generate-connectors.sh` gives the source connector a
filter step for every table whose floor comes from the seed or from another
table (`obs`, `orders`, `drug_order`, `test_order`): a change is published only when its key
is at or above the table's floor and on this clinic's residue, so an edit to a
row the hub or another clinic wrote stays here. It takes the residue from
`RESIDUE` in `.env` and the floors from `SEED_MANIFEST` (or, without it, from
the floors the seed recorded in `.install-state`), and writes nothing when
either is missing. `check-source-connectors.sh` reads the filter back from the
registered connector and fails when its residue is not the running MySQL's
`auto_increment_offset` (`MYSQL_OFFSET` overrides the read) or its floors are
not the seed's; a wrong residue drops every change this clinic makes, silently.

**Catch-up** — `catch-up-clinical.sh` sends up the rows of `obs`, `orders`,
`drug_order` and `test_order` this clinic wrote before the source captured those tables, or
that the hub lost after an outage longer than it keeps changes. For each table
it counts the rows this clinic owns (key at or above the floor, on its
residue), then inserts one `execute-snapshot` signal into
`openmrs.debezium_signal` asking the running source connector for an
incremental snapshot of exactly those rows; `drug_order` and `test_order` use
the orders floor.
It refuses when the connector does not capture the table or the signal table.
`--dry-run` prints the count queries and signal rows and touches nothing;
`--status` reads the connector's offsets and names any table still being read.
The hub's sinks upsert on the key, so a second run changes nothing. When it is
done, the hub holds, for this clinic's residue at or above the floor, the
count the run logged for each table.

**OpenELIS down filter** — `clinlims-down-filter.sh` prints the condition of
the clinic's OpenELIS down sink (`scripts/templates/clinlims-clinic-sink-all.json`).
Every clinic pulls from the cloud server the `result`, `analysis` and `sample` rows its lab
users wrote, its lab accounts and its lab test catalogue (`sync/tables/{odoo,openelis}.conf [down]`);
the condition keeps every account and catalogue row it pulls (a sample the
hub moved on names an account; a lab order is matched to the catalogue), and a
lab row only when its
routing column (a result's `analysis_id`, an analysis's or a sample's `id`) is
at or above this clinic's floor for the table that column names and on its
residue, and drops deletes and tombstones. The residue is `RESIDUE`; each floor
is `CLINLIMS_FLOOR_<TABLE>` (environment, `.env`, `SEED_MANIFEST` or
`.install-state`), which installer task 060 records once, from each sequence
before it strides. Without the residue or a floor it prints nothing and names
what is missing, and the installer stops. The
sink claims replication origin `cloud_openelis` so this clinic's OpenELIS source never
sends those rows back up.

**Content checksum** — `master-checksum.sh` prints, per table `sync/tables/openmrs.conf [down]`
lists (with `--reseed`, also the RESEED tables of `cloud/table-verdicts.conf`),
the row count and a checksum over every column of every row except those
`clinic/scripts/checksum-exclusions.conf` names. Run it on the hub (`--container <name>`)
and on a clinic seeded from it and compare the outputs: a row edited in place
shows even when its id and uuid are unchanged. Read-only.

**Verify** — read live state and judge it. `preflight.sh` (VM disk and memory,
MySQL `wait_timeout` floor, PG slot retention, Kafka, connector task states),
`check-sink-tasks.sh`, `check-sink-connectors.sh`, `check-source-connectors.sh`,
`check-mirrormaker.sh`, `check-schema-history.sh`, `check-odoo-roundtrip.sh`
(writes one partner and reads it back through Odoo's API),
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

**Concepts minted at this clinic** — `clinic-minted-concepts.sh --hub-ids
<file>` compares this clinic's concept dictionary (the tables `sync/tables/openmrs.conf [down]`
marks `changes`) with the hub's, read on the hub with `--hub-query`, and lists
every row this clinic minted for itself: a `twin` (the hub holds its uuid under
another id), a `collision` (the hub holds its id with another uuid) or a
`residue` row (on a residue other than the hub's, above the hub's last legacy
id). The concept down sinks start only when it finds none. `--rekey` moves the
twins to the hub's ids in one transaction with binary logging off, rewriting
every reference to them, and checks counts, uuids and references before it
commits; it refuses, changing nothing, on a collision, while OpenMRS runs, or
when a table this clinic sends up (obs) or an unknown column refers to a
moving row.

**Lab catalogue refresh** — `refresh-lab-catalogue.sh "<concept name>"`, run
outside clinic hours after the hub adds or changes a lab test: stops
odoo-connect and OpenELIS, restarts OpenMRS, waits until its search finds the
concept, then starts OpenELIS and odoo-connect, each wait on a named budget.
`--start-readers` runs the last two alone.

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
  shared sync definitions are `../sync/` (the table lists in `sync/tables/`,
  the clinics ledger) with the hub tree at `../cloud/`.
- `.env` is gitignored; `.env.example` enumerates every variable.
- Generated connector JSON is gitignored — `.gitignore` covers
  `cloud/connectors/` and
  `clinic/connectors/`.

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
