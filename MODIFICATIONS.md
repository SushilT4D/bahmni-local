# Deviations from `SushilT4D/bahmni-local` @ `339dd91`

Goal was to run Sushil's stack **unmodified**. Two things made that impossible, and
everything else here is host-specific configuration. This file is the complete list —
review it against Sushil's real setup when he sends his `.env`.

## A. Forced changes to tracked files (1)

### A1. `docker-compose.yml` — the committed file does not parse
**Upstream state:** the file ends with a bare top-level `volumes:` key with nothing under
it. `docker compose config` fails with:
```
validating docker-compose.yml: volumes must be a mapping
```
Separately, the `restore_volumes` service (profile `restore`) references six named volumes
that are never declared: `bahmni-patient-images`, `bahmni-document-images`,
`bahmni-clinical-forms`, `bahmni-lab-results`, `bahmni-uploaded-files`,
`bahmni-queued-reports`.

**Change made (minimal):** declared those volumes (plus `configuration_checksums`) under the
existing empty `volumes:` key — i.e. filled in what the key was evidently meant to contain.
Nothing else in the file was touched. The pristine copy is kept at `docker-compose.yml.orig`:
```bash
diff docker-compose.yml.orig docker-compose.yml
```
**→ Logged as finding BL-024. Worth reporting upstream.**

## B. Files we had to create (not in the repo)

### B1. `.env` — gitignored upstream, so absent
74 variables (29 mandatory `${VAR:?}`). Reconstructed by reading every `${VAR}` reference in
the compose. Each line is tagged `[OK] / [GUESS] / [LOCAL] / [OFF]` — the `[GUESS]` ones are
what to replace from Sushil's real file. **There is no `.env.example` upstream (BL-025).**

### B2. `certs/cert.pem` + `certs/key.pem`
Self-signed (`CN=bahmni.local`), because `proxy` mounts `${CERTIFICATE_PATH}:/etc/tls:ro` and
`bahmni-nginx.conf` requires `cert.pem`/`key.pem`. Sushil's `scripts/config.sh` uses `mkcert`.

### B3. Bind-mount directories
`data/…`, `files/…`, `config/…`, `odoo-addons/`, etc. Created empty so Docker doesn't
create them root-owned.

## C. Host-specific values (in `.env` only — no repo files touched)

| Setting | Sushil / BHS | Here | Why |
|---|---|---|---|
| `BAHMNI_PROXY_HTTP_PORT` | 80 | **8081** | keeps 80 free |
| `BAHMNI_PROXY_HTTPS_PORT` | 443 | **9443** | 443 and 8443 are taken by `IPNExtens` on this Mac |
| `CONTAINER_DATA_PATH` | (BHS path) | repo root | the compose expects `htdocs/` + `bahmni_config/` directly under it |
| Odoo Postgres port | 5432 | **not started** | host Postgres already owns 5432 — must remap before starting the `odoo` profile |

## D. Tooling differences (no file changes)

- **Docker instead of Podman.** `proxy/build.sh` and `systemdate/build.sh` call `podman build`.
  We ran the identical `docker build` against the same Dockerfiles and tags
  (`bahmni-local/proxy:1.0`, `bahmni-local/systemdate:1.0`). Same images, different CLI.
- **Skipped the OpenMRS WAR-transplant build** (`openmrs/build.sh`). That script exists to work
  around "Podman's MIME type compatibility issues" with the source image; on Docker we simply
  pull `infoiplitin/openmrs:iplit-1.0.0-662-4` (public, verified) and set `OPENMRS_IMAGE_NAME`
  to it. **Sushil may build a different image — confirm.**

## E. Deliberately NOT started

- **`debezium` profile.** `mm2.properties` points `remote.bootstrap.servers` at
  **`hmis.bhs.org.in:9092` — BHS production**. Starting it unmodified would replicate from this
  laptop into production. Plan: repoint at the Mac mini (`kafka.xoyo.ad`) as the "cloud" node.
- **`odoo` profile** — pending the 5432 remap and an unverified `ODOO_DB_IMAGE_NAME`.
- `cdss`, `snowstorm-lite`, `restore`, `atomfeed-console`, `bahmni-web` (profile `unused`).

## Open questions for Sushil
1. Can you share your `.env` (minus the `REMOTE_KAFKA_*` production credentials)?
2. Is the top-level `volumes:` block missing upstream, or lost in the squash to `339dd91`?
3. What is your real `CONFIG_IMAGE_NAME`? (`bahmni/default-config:latest` is a guess.)
4. What is `ODOO_DB_IMAGE_NAME`? `bahmni/odoo-db-16:1.0.0` isn't public.
5. Do you build OpenMRS via `openmrs/build.sh`, or pull the IPLIT image directly?

## F. D-phase additions (2026-08-18 evening — hospital sync side)

| # | What | Why |
|---|---|---|
| F1 | **Reconstructed `config/mirrormaker/`** (mm2.properties.template with alias `source`, `start-mm2.sh` SASL-injector, log4j.properties) | The compose mounts all three; NONE are in the repo (new finding BL-026). start-mm2.sh behaviour reconstructed from setup-mirrormaker.sh's own comments; alias `source` per the sink generator's topic names (his committed template's `local` alias is stale) |
| F2 | `.env` sync block filled from the mini's E3 report | bootstrap = samyogas-mac-mini.tailca2651.ts.net:9092, SASL/PLAIN `mirrormaker` — never hmis.bhs.org.in |
| F3 | Dummy `certs/kafka/kafka.truststore.p12` | compose mounts it as a file; unused under SASL_PLAINTEXT |
| F4 | Quoted `OMRS_JAVA_*` values in `.env` | his scripts `source` .env as shell; unquoted spaces break them (his real .env must be quoted — ask) |
| F5 | `KAFKA_TOPIC_PATTERNS` left unset | so setup-mirrormaker.sh generates the explicit 12-table pattern (never `.*`) |
| F6 | podman→docker shim (`/tmp/podshim`) + `MYSQL_SERVICE` env override | run configure-pk-offsets.sh unmodified on Docker with compose-prefixed container name |
| F7 | **PK striding APPLIED**: increment=10 offset=1, 11 tables re-seeded (person→230001, visit→625001, encounter→528001 …) via his script | BL-004's mechanism, now in force; clinics.txt authored (h1:1) |
| F8 | Debezium MySQL user `debezium` created (REPLICATION SLAVE/CLIENT etc.) | source connector prerequisite |
| F9 | Docker Desktop VM 8092→12288 MiB | debezium profile adds ~5 JVMs |

## ADDED (not in Sushil's repo): `scripts/check-sink-tasks.sh`

**Date:** 2026-08-20 · **Reason:** BL-038 / BL-039

Sushil's `scripts/check-sink-connectors.sh` inspects **one** connector at a time (default `person`)
and pretty-prints its status JSON. It makes no pass/fail judgement and does not sweep, so the
condition we hit on 2026-08-20 — **7 of 19 sink tasks `FAILED` while every connector object still
read `RUNNING`** — produces no signal from it.

`check-sink-tasks.sh` sweeps every connector, judges on **task** state (not connector state), exits
non-zero when any task is not RUNNING, and can `--restart` failed tasks. It also prints the caveat
that a task with nothing to write cannot prove its connection is alive.

This is an **addition**, not an edit — `check-sink-connectors.sh` is untouched.

## MODIFIED: `debezium/cloud/connectors/mysql-sink-connector.json.template`

**Date:** 2026-08-20 · **Reason:** BL-039

Added `connection.restart.on.errors=true`, `errors.retry.timeout=-1`,
`errors.retry.delay.max.ms=60000`, `flush.max.retries=10`.

Debezium ships `connection.restart.on.errors` defaulted to **false**, which makes any
connection-level error unrecoverable: the task dies permanently while the connector still
reports RUNNING. Observed twice on 2026-08-20 — once from overnight idle exceeding MySQL's
8h `wait_timeout`, once from the cloud MySQL restart — each time killing exactly the seven
registration-path sinks with no alert. Also applied to the 19 live connectors via
`PUT /connectors/<name>/config`.

Upstream caveat honoured: the doc warns this can risk inconsistency where the sink DB uses
**asynchronous replication**. Both sink databases here are single instances.

## ADDED: down-direction (cloud → clinic) connectors and tooling

**Date:** 2026-08-20 · Files:
`debezium/cloud/connectors/mysql-cloud-source-connector.json.template`,
`debezium/cloud/scripts/generate-cloud-source-connector.sh`,
`debezium/local/connectors/mysql-local-sink-connector.json.template`,
`scripts/generate-local-sink-connectors.sh`,
`scripts/register-local-sink-connectors.sh`,
`config/mirrormaker/mm2.properties` (`remote->source` flow).

BL-033 recorded that the down direction was designed and partly tooled but its connector
configs were absent. These are those configs.

## SCHEMA CHANGE (both sides): `patient_identifier.location_id` DROP DEFAULT

**Date:** 2026-08-20 · **Reason:** BL-044 · **Applied to clinic AND cloud (lockstep, L-005)**

```sql
ALTER TABLE patient_identifier ALTER COLUMN location_id DROP DEFAULT;
UPDATE patient_identifier SET location_id = NULL WHERE location_id = 0;  -- cloud only, repair
```

The column is nullable but carried `DEFAULT 0`. Debezium copies a column's default into the
Kafka Connect schema, and `Struct.get()` substitutes the schema default whenever the stored
value is null — so every NULL `location_id` was published as `0`, an invalid location, making
121,643 synced patients unreadable through the cloud API. Dropping the default leaves type,
nullability and data untouched; it only stops the schema from lying.

**Reversible:** `ALTER TABLE patient_identifier ALTER COLUMN location_id SET DEFAULT 0;`

## STRIDING as server flags (both nodes) — not `SET PERSIST`

**Date:** 2026-08-20 · **Reason:** BL-045 · clinic `docker-compose.override.yml`, cloud likewise

```
clinic (Rawach): --auto-increment-increment=10 --auto-increment-offset=4
cloud:           --auto-increment-increment=10 --auto-increment-offset=10   → ids ≡ 0 (mod 10)
```

Per Sushil's map (Manpur 1, Bedawal 2, Ghated 3, Rawach 4, Bagdunda 5, Kojawada 6; cloud 10).
Server flags rather than `SET PERSIST` because PERSIST does not exist on MySQL 5.6 (the cloud),
is lost when the datadir is recreated, and — demonstrated live — **silently overrides the
command-line flag**: a stale `mysqld-auto.cnf` pinned offset=1 while the compose file plainly
said 4. Cleared with `RESET PERSIST`.

Verified: a patient registered after the change got `person_id = 230144` (residue 4).

## ADDED: OpenELIS at the clinic (Module 28 implementation)

**Date:** 2026-08-20 · Files: `docker-compose.override.yml` (two new blocks + a
`bahmni-postgres` block), `openelis/start-no-migrate.sh` (new), `.env` (new keys).
**Sushil's `docker-compose.yml` is untouched.**

The clinic stack has never had OpenELIS — `bahmni-lab` is Lab Lite, a static nginx
bundle, so there was no lab database at all. This adds one.

| # | What | Why |
|---|---|---|
| G1 | `clinlims` restored into the existing **`bahmni-postgres`** container as database `openelis` | Module 28 decision (i): reuse the clinic's Postgres rather than add a third. Consequences recorded as BL-052. |
| G2 | `bahmni-postgres` joins the `openelis` profile; published on **127.0.0.1:5433** | 5432 belongs to the host Homebrew Postgres (`bahmni_dev`, `memory_db`) and must never be taken. |
| G3 | `bahmni-postgres` command → `wal_level=logical`, `max_replication_slots=10`, `max_wal_senders=10` | Debezium `pgoutput` needs logical decoding; the base image ships `wal_level=replica`. |
| G4 | New `openelis` service, profile `openelis`, `bahmni/openelis:1.1.0-111`, **127.0.0.1:8052** | Net-new; not in Sushil's compose. Profile-gated so it never starts by accident. |
| G5 | `.env` gains `OPENELIS_{HOST,PORT,DB_*,ATOMFEED_*}` and `OPENMRS_{PORT,ATOMFEED_*}` | **Closes BL-048** — these were interpolated by two boot scripts but defined nowhere. |
| G6 | All **115** `clinlims` sequences strided: `INCREMENT BY 10`, residue **4** (Rawach), each restarted *above* its own seed range | Postgres analogue of the MySQL striding. Verified: consecutive sample ids 94, 104, 114 vs. seed max 81. |

### ⚠️ G7 — `start.sh` replaced by `openelis/start-no-migrate.sh`

**The upstream image cannot complete its own boot migration against PostgreSQL.**
Liquibase 1.9.5 never detects `clinlims.databasechangeloglock`, so `waitForLock` issues
`CREATE TABLE` on every retry — succeeding once, then failing `already exists` until it
gives up and `start.sh`'s `set -e` kills the container. Observed as a permanent restart
loop (RestartCount 10).

**This is not our configuration and not a version skew.** Reproduced identically on
**PostgreSQL 14** and on a throwaway **PostgreSQL 9.6.24** — the exact version the dump
was taken from — with the same image and the same dump. It also fails with the lock table
*absent*, so it is not simply "the dump already has it".

`start-no-migrate.sh` replicates `start.sh` exactly except the two liquibase steps. Safe
here because the dump is already migrated (`databasechangelog` carries 142 changesets);
the risk it accepts is a changeset newer than the dump, which would surface at runtime.

**Possible explanation for a long-standing mystery.** Module 06 recorded that BHS
production runs `…-openelisdb-1` **with no OpenELIS application container** — "a database
with nothing apparently in front of it." An app that cannot finish its boot migration is a
mechanical explanation for exactly that.

### G9 — the proxy turned every upstream 500 into a 404

**Date:** 2026-08-28 · Files: `proxy/bahmni-nginx.openelis.conf`,
`proxy/htdocs/internalError.html` (new), `docker-compose.override.yml` (proxy mount).

`error_page 500 501 502 = /internalError.html;` used the **bare `=`**, which takes the
response status from the target — and `internalError.html` did not exist in the image. So
`proxy_intercept_errors on` caught each upstream 500 and served the client a **404**.

That is not cosmetic. It made one OpenELIS defect read as two different faults: the clinic
reported "missing page" while the cloud, which is not behind this proxy, reported "server
error" for the identical request. It also disguises an application error as a routing
error, which is the wrong place to start debugging.

Fixed by pinning the status and shipping the page:

```nginx
error_page 500 501 502 =500 /internalError.html;
```

Verified against a genuinely-500ing route
(`/openelis/ajaxQueryXML?provider=SampleEntryTestsForTypeProvider&…`): **404 → 500**, with
the upstream confirmed at 500 by querying the container directly on `:8052`.

**Sushil's `proxy/bahmni-nginx.conf` has the same two lines** (47–48) and is baked into the
image, so any stock deployment masks 500s the same way. Not edited here — ours is the
mounted copy and the only one in force. Worth reporting upstream.

### G10 — the home page's Lab tile pointed at the wrong origin

**Date:** 2026-08-28 · File: `proxy/bahmni-nginx.openelis.conf` (`location /lab`).

`/lab` answered `301 → http://localhost/lab/` — port dropped, scheme downgraded — so the
Lab tile on the Bahmni home dashboard led nowhere. The config link itself was never wrong:
`extension.json` has `"url": "/lab"`, correctly root-relative.

Two independent causes, and fixing only one leaves it broken:

1. **The upstream builds an absolute redirect and drops the port itself.** Confirmed by
   calling `bahmni-lab` directly: `Host: localhost:9443` still returns
   `Location: http://localhost/lab/`. So `proxy_set_header Host` alone does **not** fix it.
   Handled with `proxy_redirect ~^https?://[^/]+(/lab.*)$ $1;`, which also corrects scheme.
2. **nginx then re-absolutises the relative Location** using the port it *listens* on
   (443). This container is published to the host on **9443**, which nginx cannot know, so
   443 is treated as the https default and omitted — reproducing the bug. Handled with
   `absolute_redirect off;` scoped to the location.

Cause 2 is invisible whenever the published and listening ports match, which is exactly why
an isolated test on `8099:8099` passed while the real proxy still failed. **Any
published-port ≠ listen-port mapping hits this**, so it is worth checking the other proxied
routes that issue redirects.

Verified: `Location: /lab/` (relative), following it gives **200** at
`https://localhost:9443/lab/`. `/openelis/`, `/bahmni/home`, `/implementer-interface`
unchanged. (`/atomfeed-console` still returns 000 — that is BL-008, pre-existing.)

No URL is templated from `.env` for any of this, deliberately: root-relative links plus
relative redirects are correct on localhost, on the tailnet host and in production without
knowing the origin, whereas an env-substituted absolute URL would bake one in per node —
the failure class BL-048 already recorded.

### ⚠️ G8 — the image prints the database password on every boot
`migrateDb.sh` runs under `set -e -x`, so it echoes the full liquibase command line —
including `--password=…` — to stdout, which the compose ships to **loki**. The clinic
password was rotated after this was noticed. `start-no-migrate.sh` does not run that
script, so the leak is gone locally, but it is present in any stock deployment.

### Verified after boot
- OpenELIS serves its login page on `127.0.0.1:8052/openelis/` (HTTP 302 → login form).
- `clinlims` **triggers = 0** and trigger-returning functions = 0 *after* the app booted —
  this is **BL-051 resolved with runtime evidence**, and it is what makes Module 28's
  Gate 2 (sink writes bypass the app, so no feed event is born) hold.
- ATOM bookmarks rewritten to `http://openmrs:8080/openmrs/ws/atomfeed/{patient,encounter,lab}/recent`;
  OpenELIS reaches the OpenMRS patient feed (HTTP 200).
- Tripwire baseline: `clinlims.event_records` MAX(id) = **80**, unmoved by boot.

## ADDED: bidirectional clinlims CDC sync (Module 28 §9) — 2026-08-21

Builds on the OpenELIS-at-clinic section above. Both nodes now sync lab data both ways.

| # | What | Why |
|---|---|---|
| S1 | **`bahmni-postgres` bumped 14→15** (`docker-compose.override.yml`); old datadirs at `data/postgresql.pg14*` (gitignored) | PG15 publication row filters are the loop-prevention mechanism (S3). Disposable instance: clinlims only, Odoo unused. |
| S2 | `openelis/setup-clinlims-sync.sql` — strides 115 sequences (residue via GUC), `REPLICA IDENTITY FULL` on synced tables, creates the filtered publication | one script, both nodes (residue 4 clinic / 0 cloud) |
| S3 | **Publication `dbz_clinlims_owned` `FOR TABLE … WHERE (id%10=residue)`** over sample/sample_item/analysis/result | per-row single-writer (L-001 at row granularity) enforced by the DB — a sink-written row carries the other residue and is never re-captured. No scripting SMT (the Connect workers have no JSR223 engine; adding one risks the live MySQL sync). Feed tables NEVER in it (Gate 1). |
| S4 | `connectors/clinlims-source-connector.json` (clinic 8083) — Debezium PostgresConnector, `publication.autocreate.mode=disabled`, slot `dbz_clinlims_up` | needs `clinlims` role `WITH REPLICATION` |
| S5 | `connectors/clinlims-clinic-sink.json` (clinic 8083) — JDBC sink, consumes `remote.bahmni-cloud.clinlims.*`, writes DIRECT to Postgres (Gate 2) | down direction |
| S6 | cloud `clinlims-cloud-source` + `clinlims-cloud-sink` (mini 8083) | up sink + down source; live configs on the mini with password injected at POST |
| S7 | `config/mirrormaker/mm2.properties` — both topic allowlists extended with `clinlims.(sample\|sample_item\|analysis\|result)` | MM2 carries the new topics both ways. **It only discovers new topics on restart / refresh interval.** |

**Connector config files carry placeholder passwords** (`__ELISPW__`); the live connectors
inject from `.env` (clinic) or the mini at POST time. Never commit the real password.

**Verified** (Module 28 §9.3): RAW-SYNC-TEST-1 clinic→cloud and CLOUD-SYNC-TEST-1 cloud→clinic,
each exactly once, no loop; both clinlims.event_records=80, cloud OpenMRS event_records=951145.
The live 121k-patient MySQL sync recovered to 10/10 tasks after the MM2 restarts.

## MODIFIED: two review fixes to our own tooling — 2026-08-28

Found by a review of this branch against `339dd91`, prompted by a live incident: seven
cloud sink tasks were FAILED under `RUNNING` connectors (BL-039 again), two patient
registrations never reached the cloud, and the cloud RAW counter had diverged from the
clinic's — arming a duplicate MRN (BL-071). Both files below are **ours**, not Sushil's.

| # | What | Why |
|---|---|---|
| R1 | `scripts/check-sink-tasks.sh` — order-independent argument parsing: the host is the one positional, `--restart` / `--restart-all` / `--help` are flags, and an unknown `--flag` exits 2 instead of becoming a hostname | `HOST="${1:-localhost}"` special-cased only the literal `--restart`, so `check-sink-tasks.sh --restart-all` — the form this script's own usage block recommends after a database restart — took the flag as the host and died with `cannot reach Kafka Connect at http://--restart-all:8083`, restarting nothing. The recovery command most likely to be typed during an outage was the one that silently did nothing. |
| R2 | `scripts/generate-local-sink-connectors.sh` — **L-008 ownership guard**, the mirror of the one already in `debezium/cloud/scripts/generate-sink-connectors.sh`: refuses to emit a down-direction sink for any table listed in `debezium/local/tables.conf` | The guard existed in the up direction only. A table added to `debezium/cloud/tables.conf` that the clinic also authors would get a sink writing cloud rows into a clinic-authored table; the clinic captures that table and these sinks write straight to MySQL with no `sql_log_bin` guard, so the write re-enters the binlog, ships up, is applied, and comes back down — an **unbounded loop**, with no MySQL equivalent of the clinlims publication row filter to break it. One line in the wrong `tables.conf` was all it took. |

**R2 detail.** The table list is now read once into an array and the whole list is
validated *before* any file is written, so a refusal leaves nothing behind. That is
deliberately stricter than the up-direction guard, which `exit 1`s mid-loop and can leave
a half-regenerated `connectors/` directory (still open — see below). The read loop also
gained the `|| [[ -n "$line" ]]` fallback the up generator already had; without it a
`tables.conf` saved with no trailing newline silently drops the last table's sink while
the run still reports success. `TABLES_CONF` / `UP_TABLES_CONF` are now overridable so
the guard can be exercised without editing a live config.

**Verified 2026-08-28:**
- `bash -n` clean on both.
- R1: `check-sink-tasks.sh badhost.invalid --restart-all` now reports `badhost.invalid`
  (flag no longer consumed as the host); `--bogus` exits 2 with `unknown option`; the
  no-argument sweep still lists all 10 clinic connectors.
- R2 positive: still generates **7** connectors, and `diff -r` against the output of the
  pre-change script (run from `git show HEAD:`) is **identical** — no happy-path change.
- R2 negative: a `tables.conf` containing `person:person_id` is refused by name, with
  **0 files written**.

**Not fixed, still open** (from the same review, in rough severity order): the cloud sink
generator no longer reproduces the live working configs (`table.name.format.default` is
`openmrs.person` live vs `person` generated; live has `auto.create`/`auto.evolve` where
the generator emits `schema.evolution`), so regenerating would regress production sinks;
`openelis/setup-clinlims-sync.sql` is labelled idempotent but `DROP PUBLICATION` on a live
node opens a silent capture gap; `check-sink-tasks.sh` restarts only `tasks/0` while
reporting on every task; `register-local-sink-connectors.sh` strips the port from
`LOCAL_CONNECT_URL` before handing the host to the verifier; the up-direction guard's
mid-loop `exit 1`; the up sink shape is defined twice (heredoc + template) — the exact
split that caused the 2026-08-27 six-sink failure; and `start-mm2.sh` leaves SASL
credentials in `/tmp/mm2-runtime.properties` with default permissions.

## MODIFIED: BL-039 durable fix — idle no longer kills sink tasks — 2026-08-28

Recovery from the 2026-08-28 outage restarted the dead tasks but changed nothing about the
cause. This is the cause. Two layers, one of which turned out not to work.

### Layer 1 (primary): `wait_timeout` was never a decision

Both nodes ran MySQL's stock `wait_timeout = 28800` (8h). The container command lines set
charset, binlog, server-id, log expiry and the striding flags — and said nothing about
timeouts. So the value that killed the registration path every morning was simply the
default nobody had looked at. Raised to **604800 (7 days)**, which outlives any realistic
idle window including a long weekend.

| Where | Change |
|---|---|
| both nodes, live | `SET GLOBAL wait_timeout = 604800; SET GLOBAL interactive_timeout = 604800` — takes effect for NEW connections, so no database restart was needed |
| `docker-compose.override.yml` (clinic) | `--wait-timeout=604800 --interactive-timeout=604800` appended to `bahmni-mysql` `command:` |
| `debezium/cloud/docker-compose.override.yml` (mini) | same two flags appended to `openmrsdb` `command:` (backup at `.bak-2026-08-28`) |

Verified: `@@GLOBAL.wait_timeout = 604800` on both, and a fresh session inherits it. Both
compose files re-rendered with `docker compose config` and checked to confirm the existing
flags survived — an override **replaces** `command`, it does not merge, so every pre-existing
flag (striding, binlog, server-id) had to still be there afterwards. They are.

Headroom checked before the change: `max_connections = 151` on both, with 68 in use on the
cloud (60 of them `sink`) and 46 on the clinic. A long timeout means a leaked connection
persists, so this is worth re-checking if sink counts grow.

### Layer 2 (secondary, unproven): pool lifetime

`connection.pool.timeout: 300` applied to all 21 sinks (13 cloud, 8 clinic) live via
GET → merge → PUT, and added to every file that authors sink config:
`debezium/cloud/scripts/generate-sink-connectors.sh`,
`debezium/cloud/connectors/mysql-sink-connector.json.template`,
`debezium/local/connectors/mysql-local-sink-connector.json.template`,
`connectors/clinlims-{clinic,cloud}-sink.json`.

**Treat this as unproven.** The shipped default is already 1800, and it did not prevent the
45,376,505 ms (12h36m) stale connection that caused the outage — so the key may not be wired
through to the pool at all. It is layer 2 precisely because layer 1 is the one with evidence.

### ⚠️ `connection.pool.min_size=0` DOES NOT WORK — do not retry it

The plan was `min_size=0` so idle pools drain completely. Applied to all 21 sinks, and
**4 of 13 cloud sinks died on boot**:

```
org.hibernate.service.spi.ServiceException: Unable to create requested service
  [org.hibernate.engine.jdbc.env.spi.JdbcEnvironment]
Caused by: Unable to determine Dialect without JDBC metadata
```

Hibernate needs a live connection at startup to probe the database dialect; an empty pool
has none. It failed on only 4 of 13 because it is a startup race — which makes it worse than
a clean failure, not better. Reverted to the default `min_size=5` on all 21 sinks; all
15 cloud and 10 clinic connectors returned to RUNNING tasks. The comment blocks in the
generator and both templates record this so nobody tries it again.

**Consequence:** each sink still holds 5 idle connections indefinitely (60 on the cloud,
35 on the clinic). Those connections are no longer reaped at 8h, so the failure is prevented
rather than merely made rarer — but the pool is not shrinking, and the only thing standing
between us and a repeat is the server-side timeout.

### Layer 2 MEASURED — it does nothing

Two samples, 317 seconds apart, no traffic in between:

| | cloud | clinic |
|---|---|---|
| T0 15:33:39 | 60 conns, idle 512–517s | — |
| T1 15:38:56 | 60 conns, idle 829–834s | 35 conns, idle 836–839s |

Connection ages advanced 1:1 with wall-clock and **not one connection was recycled**, at
idle ages already 2.8x the configured 300s. `connection.pool.timeout` does not expire idle
connections at `min_size` — whatever it maps to, it is not an idle reaper. Combined with
`min_size=0` being unusable, **the pool cannot be made to cycle through this connector's
config at all.**

So there is no second layer. `wait_timeout=604800` is the entire fix, and the sinks will go
on holding 60 (cloud) and 35 (clinic) connections indefinitely — now simply never reaped.
The key and its comment blocks are kept as the record of the experiment, explicitly marked
inert so nobody counts it as protection.

### Still open Also still unmonitored: nothing alarms
on task state, so the next occurrence of anything in this class is found by a human noticing.
