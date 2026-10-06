# Changelog

Decisions that change how a node is laid out. Newest first; `git log` on this
file gives the date of each.

## Forms

- The hub owns forms. They are published only on the hub; a clinic never
  creates or changes one. A form's rows (`form`, `form_resource`) come down by
  sync, like users and providers, so a form has the same id, uuid and version
  on every node, which is what a saved observation's form name and version
  refer to. The clinic's sink user is granted every table `hub/tables.conf`
  lists (`clinic/scripts/grant-down-tables.sh` on a node seeded before).
- A form's files come from the operator's private forms repo, exported from
  the hub: cloned into `clinic/forms` with a per-clinic read-only deploy key,
  fast-forward only, and mounted read-only at `/home/bahmni/clinical_forms`
  (`FORMS_DIR`, `FORMS_MOUNT_MODE`). The repo only adds files. With no forms
  repo the node mounts the frozen copy in `clinic/bahmni_home/clinical_forms`,
  read-write, until every node runs from the repo.
- Every published, unretired form row must have its file: the installer stops
  a seed otherwise, and `clinic/scripts/update-forms.sh` (scheduled, every 15
  minutes) fails with the list. A concept a form needs and the node lacks is a
  warning, not a refusal. Taking new forms never restarts OpenMRS.
- At a clinic the Initializer loads no forms and no other master data the hub
  owns: `-Dinitializer.domains` from `OPENMRS_INITIALIZER_DOMAINS`, by default
  an exclusion list keeping only `globalproperties` and `idgen`. The installer
  refuses an unknown domain name and a config folder for any other domain that
  would load. See `clinic/install/README.md`.
- This replaces loading forms through the Initializer from a mount over the
  config tree's `bahmniforms`: the Initializer numbers the versions it creates
  per node, so the same form had different versions on different nodes, and a
  form whose name and version already existed on a node failed to load.

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
