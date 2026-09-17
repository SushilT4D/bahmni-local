# cloud/

The base Bahmni application stack (OpenMRS, Odoo, OpenELIS) and the proxy in
front of them -- the hub's counterpart to a clinic's `clinic/`.

## The sync layer has moved

Kafka, Schema Registry, Kafka Connect, kafka-ui, and the up/down connector
configs used to be documented here. They are their own compose project now,
split out so one hub can serve several clinics -- see `hub/README.md` for
the install command, `hub/.env` keys, tasks, and the join/leave hand-off.
