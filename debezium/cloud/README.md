# Remote Setup

> ### ⚠️ This file describes the original two-node setup and has not been updated since 2026-08-14
>
> It was written for the first `local -> remote` pilot. The lab is now **three
> nodes** — two clinics (Rawach, Ghated) and a cloud hub that **relays between
> clinics** — and the mechanisms below changed substantially during Aug–Sep 2026.
> Verified stale points in this file, as of 2026-09-14:
>
> - **The cloud is described as a passive receiver** ("receives replicated data
>   and applies it to MySQL"). It is now an **authoring node and a relay**: it
>   publishes its own writes and forwards clinic-authored rows to the other clinic.
> - **`tables.conf` here carries 7 table entries**, and the per-table sink model
>   described below no longer holds for Odoo and OpenELIS.
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


This directory contains the configuration for the **remote** server that receives replicated data and applies it to MySQL.

## Components

- **Zookeeper** - Kafka coordination
- **Kafka** - Remote message broker (receives events from local)
- **Kafka Connect** - Runs JDBC sink connector
- **JDBC Sink Connector** - Applies changes to remote MySQL

## Quick Start

1. **Copy environment template**:
   ```bash
   cp .env.example .env
   ```

2. **Configure `.env`** with your settings:
   - Remote MySQL connection details
   - Kafka topics to consume

3. **Generate table configuration**:
   ```bash
   # Generate KAFKA_TOPICS from tables.conf
   ../../scripts/generate-table-config.sh cloud
   # Copy the output to your .env file
   ```

4. **Generate sink connector configurations**:
   ```bash
   # Creates individual connector configs for each table
   ./scripts/generate-sink-connectors.sh
   ```

5. **Update .env with generated values**:
   ```bash
   # Add KAFKA_TOPICS from ../../scripts/generate-table-config.sh cloud
   ```

6. **Start services**:
   ```bash
   docker-compose up -d
   ```

7. **Install JDBC connector**:
   ```bash
   ./scripts/install-jdbc-connector.sh
   ```

8. **Register sink connectors**:
   ```bash
   # Register all sink connectors (one per table)
   ./scripts/register-all-sink-connectors.sh
   ```

## Files

- `docker-compose.yml` - Remote infrastructure
- `connectors/` - Generated sink connector configurations (one per table)
- `tables.conf` - Table configuration (easy to extend)
- `scripts/` - Setup and management scripts
- `.env.example` - Environment variables template

## Adding More Tables

See `../ARCHITECTURE.md` for detailed instructions on adding tables (Table-Based Configuration System section).

Quick steps:
1. Add table to `tables.conf`: `table_name:primary_key`
2. Run `../../scripts/generate-table-config.sh cloud` to update topics
3. Run `./scripts/generate-sink-connectors.sh` to create connector configs
4. Run `./scripts/register-all-sink-connectors.sh` to register new connectors

## Network Requirements

The remote Kafka must be accessible from the local machine for MirrorMaker to push events.

Ports that need to be accessible:
- **9092** - Kafka broker
- **8083** - Kafka Connect REST API (optional, for management)

