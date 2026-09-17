# hub/

The sync layer (Kafka, Schema Registry, Kafka Connect) as its own compose
project, split out of `cloud/` so one hub can serve several clinics.
Kafka UI is added by the installer's later task.

Attaches to a base stack's Docker network via `KAFKA_BASE_NETWORK` (e.g.
`cloud_default`) -- it does not run standalone.

Copy `.env.example` to `.env`; `hub/install/` (later tasks) composes
`hub/.env` from the fleet config rather than hand-filled secrets.
