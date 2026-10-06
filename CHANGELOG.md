# Changelog

Decisions that change how a node is laid out. Newest first; `git log` on this
file gives the date of each.

## Forms

- OpenMRS loads its forms from `clinic/forms/bahmniforms`, mounted read-only over
  the config tree's `bahmniforms`. `clinic/forms` is a clone of the operator's
  private forms repo (`FORMS_REPO_URL` and `FORMS_REPO_KEY` in the answers) or,
  with none configured, a copy of the config image's forms. It is node-local and
  gitignored, and it lives outside `clinic/extracted/`, which a config upgrade
  replaces. The installer does not start OpenMRS without it.
- A forms change reaches a node through `clinic/scripts/update-forms.sh`:
  fast-forward only, a concept check against the node's OpenMRS before the forms
  are put in place, then a restart of OpenMRS alone (the Initializer loads forms
  only at start) and a check that every form in `MANIFEST.tsv` is published under
  its uuid. The hub takes a forms change before the clinics. See
  `clinic/install/README.md`.
- A form is identified on a node by its uuid, never its version: the Initializer
  numbers a loaded form's version itself. The concept check blocks only forms new
  to the node (by uuid); a form the node already publishes only warns.

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
