# Changelog

Decisions that change how a node is laid out. Newest first; `git log` on this
file gives the date of each.

## Application image versions

- The application images match staging's: UI `bhs-0.0.30`, config `bhs-0.0.20`,
  implementer-interface `1.1.0-74`, patient-documents `1.1.0-32`,
  atomfeed-console `1.0.0-23`. The last three were `latest`, which had moved to
  a different major version than staging runs. OpenELIS stays at `1.1.0-111`.
- `sync/versions.env` holds the defaults. The person installing a clinic may
  choose another version of any application image, with `install.sh --versions
  <file>` or at the prompt. The sync layer is not a per-node choice. See
  `clinic/install/README.md`.

## Kafka layout

- Kafka runs as one node holding both the broker and the controller role, on
  the clinic and on the hub. There is no separate controller container.
- The schema registry is removed. Every connector converts to JSON or raw
  bytes, so nothing registers or reads a schema.
- The clinic's broker has one client listener, on the container network, and
  publishes no host port. The hub's broker publishes only the listener clinics
  dial.
