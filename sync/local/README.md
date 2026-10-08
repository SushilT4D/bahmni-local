# sync/local — what a clinic captures and sends up

This directory holds data, not a stack: the clinic's Kafka, Kafka Connect and
MirrorMaker run from `clinic/docker-compose.yml`, and the clinic installer
(`clinic/install/`) drives everything below through the scripts in
`clinic/scripts/`.

| Path | Read by | What it says |
|---|---|---|
| `tables.conf` | `clinic/scripts/generate-table-config.sh`, `generate-connectors.sh`, `configure-pk-offsets.sh`, `setup-mirrormaker.sh`; the hub's `generate-cloud-source-connector.sh` and `generate-sink-connectors.sh` | The OpenMRS tables a clinic captures and sends to the hub (clinic → hub). The hub's own list (hub → clinic) is `hub/tables.conf`. |
| `connectors/` | `clinic/scripts/generate-connectors.sh`, `generate-local-sink-connectors.sh` | Templates for the Debezium MySQL source and the clinic's local JDBC sinks. Rendered output goes to `connectors/generated/` (git-ignored). |
| `mirrormaker-config/mm2.properties.template` | `clinic/scripts/setup-mirrormaker.sh` | MirrorMaker 2 settings for the clinic → hub copy. Rendered to `mm2.properties` (git-ignored). |

To add a table to clinic → hub sync, add it to `tables.conf` and re-run the
clinic installer's sync phase; the generators read it from here.

The source connector also captures its signal table, `openmrs.debezium_signal`,
which the clinic seed creates. It is not a line in `tables.conf` (the reader
refuses one): a row inserted there asks the connector for an incremental
snapshot, and the table itself has no topic sent to the hub and no sink.
`clinic/scripts/catch-up-clinical.sh` writes those rows.
