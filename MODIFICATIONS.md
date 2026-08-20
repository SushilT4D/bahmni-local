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
