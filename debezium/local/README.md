# Local Setup

> ### ⚠️ This file describes the original two-node setup and has not been updated since 2026-08-14
>
> It was written for the first `local -> remote` pilot. The lab is now **three
> nodes** — two clinics (Rawach, Ghated) and a cloud hub that **relays between
> clinics** — and the mechanisms below changed substantially during Aug–Sep 2026.
> Verified stale points in this file, as of 2026-09-14:
>
> - **Step 4 cites `./scripts/setup-connectors.sh`, which does not exist here.**
>   (A `setup-connectors.sh` exists only under `../cloud/scripts/`.)
> - **"See `../ARCHITECTURE.md`" — that file does not exist** anywhere in this repo.
> - **`tables.conf` is described as "person, patient, visit"**; it now carries 12
>   table entries (and `../cloud/tables.conf` carries 7).
>
> **What changed since, in brief.** Loop prevention moved out of the application
> and into the database engines (MySQL sinks write with `sql_log_bin=0`;
> PostgreSQL sinks claim a replication origin per pooled connection), replacing
> the `sync_origin` column and triggers that were dropped fleet-wide on
> 2026-09-09. Odoo and OpenELIS now capture into **one ordered topic per
> subsystem** rather than one per table (2026-09-10). Deletes propagate in every
> direction, with sinks keyed on `primary.key.mode=record_key`. Postgres moved
> 15 -> 16 on all three nodes.
>
> **The authoritative documentation is not in this repo.** Architecture,
> runbooks, decision records and the open-follow-up ledger live in the Bahmni
> planning workspace (`docs/sync-core/architecture.md`,
> `docs/sync-core/runbooks/`, `docs/sync-core/adrs/`). Treat the steps below as
> historical unless you have checked them against those.


This directory contains the configuration for the **local** machine that captures changes from MySQL and replicates them to a remote server.

## Components

- **Zookeeper** - Kafka coordination
- **Kafka** - Local message broker (buffers events when offline)
- **Kafka Connect** - Runs Debezium source connector
- **Debezium MySQL Source Connector** - Captures changes from local MySQL
- **MirrorMaker 2.0** - Replicates topics to remote Kafka

## Quick Start

1. **Copy environment template**:
   ```bash
   cp .env.example .env
   ```

2. **Configure `.env`** with your settings:
   - Local MySQL connection details
   - Remote Kafka bootstrap servers

3. **Generate MirrorMaker configuration**:
   ```bash
   ./scripts/setup-mirrormaker.sh
   ```

4. **Generate connector configurations**:
   ```bash
   ./scripts/setup-connectors.sh
   ```

5. **Update .env with generated values**:
   ```bash
   # Add TABLE_INCLUDE_LIST and KAFKA_TOPICS from:
   #   ../../scripts/generate-table-config.sh local
   ```

6. **Start services**:
   ```bash
   docker-compose up -d
   ```

7. **Register source connector**:
   ```bash
   ./scripts/register-source-connector.sh
   ```

8. **Register MirrorMaker connector**:
   ```bash
   ./scripts/register-mirrormaker.sh
   ```

## Files

- `docker-compose.yml` - Local infrastructure
- `connectors/` - Connector configuration templates
- `tables.conf` - Table configuration (person, patient, visit)
- `mirrormaker-config/` - MirrorMaker configuration
- `scripts/` - Setup and management scripts
- `.env.example` - Environment variables template

## Adding More Tables

Canonical lists:
- **This file** (`debezium/local/tables.conf`) — clinic → cloud CDC
- **`../cloud/tables.conf`** — cloud → clinic (users/roles/providers)

Quick steps (local → cloud):
1. Add a line here: `table:pk:base_id` or `table:pk`
2. From repo root: `./scripts/generate-connectors.sh`
3. Copy `TABLE_INCLUDE_LIST` / `KAFKA_TOPICS` into `.env` if needed
4. `./scripts/register-source-connector.sh`

## Offline Behavior

When connectivity to remote Kafka is lost:
- Events continue to be captured from MySQL
- Events are buffered in local Kafka
- MirrorMaker retries connection automatically
- When connectivity returns, buffered events are synced

See `../ARCHITECTURE.md` for details on offline behavior and architecture.

