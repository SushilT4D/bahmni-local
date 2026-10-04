# Changelog

Decisions that change how a node is laid out. Newest first; `git log` on this
file gives the date of each.

## Kafka layout

- Kafka runs as one node holding both the broker and the controller role, on
  the clinic and on the hub. There is no separate controller container.
- The schema registry is removed. Every connector converts to JSON or raw
  bytes, so nothing registers or reads a schema.
- The clinic's broker has one client listener, on the container network, and
  publishes no host port. The hub's broker publishes only the listener clinics
  dial.
