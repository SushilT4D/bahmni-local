# Local Setup

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

