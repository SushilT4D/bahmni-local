# sync/local — MirrorMaker settings for the clinic → hub copy

This directory holds data, not a stack: the clinic's Kafka, Kafka Connect and
MirrorMaker run from `clinic/docker-compose.yml`, and the clinic installer
(`clinic/install/`) drives everything below through the scripts in
`clinic/scripts/`. The table lists themselves are in `sync/tables/`.

| Path | Read by | What it says |
|---|---|---|
| `mirrormaker-config/mm2.properties.template` | `clinic/scripts/setup-mirrormaker.sh` | MirrorMaker 2 settings for the clinic → hub copy. Rendered to `mm2.properties` (git-ignored). |

To add a table to clinic → hub sync, add it to the `[up]` section of
`sync/tables/openmrs.conf` and re-run the clinic installer's sync phase; the
generators read it from there.

The source connector also captures its signal table, `openmrs.debezium_signal`,
which the clinic seed creates. It is not a line in the table list (the reader
refuses one): a row inserted there asks the connector for an incremental
snapshot, and the table itself has no topic sent to the hub and no sink.
`clinic/scripts/catch-up-clinical.sh` writes those rows.
