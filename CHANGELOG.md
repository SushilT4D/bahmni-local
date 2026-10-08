# Changelog

Decisions that change how a node is laid out. Newest first; `git log` on this
file gives the date of each.

## Master data writes at a clinic

- A clinic's proxy refuses any method but GET, HEAD and OPTIONS on the paths
  that write the master data the hub sends down: the OpenMRS REST and FHIR
  resources of those tables, the form builder's writers, the admin app's
  concept, drug and reference-term CSV uploads, the reference-data writers,
  and the legacy admin pages. It answers 403 with "Master data is maintained
  at the hub; this change is refused at this clinic" and logs the refusal.
  Reads and patient-flow writes pass. Users and providers are not refused. It
  is a control on the browser path only; a row changed past the proxy shows in
  the master-data checksum. See `clinic/install/README.md`.

## Forms

- The hub owns forms. They are published only on the hub. A clinic does not
  run the form builder (the `implementer-interface` service is in no profile
  the clinic starts, and the home page has no tile for it), its Initializer
  loads no forms, and its forms folder is read-only. A form's rows (`form`,
  `form_resource`) come down by sync, like users and providers, so a form has
  the same id, uuid and version on every node, which is what a saved
  observation's form name and version refer to. A node takes the hub's form
  rows as its baseline with its seed; sync carries later changes. The clinic's
  sink user is granted every table `hub/tables.conf` lists.
- A form's files come from the operator's private forms repo, exported from
  the hub: cloned into `clinic/forms` with a per-clinic read-only deploy key,
  fast-forward only, one run at a time, and mounted read-only at
  `/home/bahmni/clinical_forms` (`FORMS_DIR`, `FORMS_READ_ONLY`). The mounts
  never create a missing folder: OpenMRS does not start without its forms.
  The repo only adds files. With no forms repo the node mounts the frozen copy
  in `clinic/bahmni_home/clinical_forms`, read-write, until every node runs
  from the repo.
- Every published, unretired form must have a pointer row into the forms
  folder and its file there: the installer stops a seed otherwise, and
  `clinic/scripts/update-forms.sh` (scheduled, every 15 minutes) fails with the
  list. A concept a form needs and the node lacks is a warning, not a refusal,
  found by the checker the node already runs. Taking new forms never restarts
  OpenMRS.
- At a clinic the Initializer loads no forms and no other master data the hub
  owns: `-Dinitializer.domains` from `OPENMRS_INITIALIZER_DOMAINS`, by default
  the inclusion list `globalproperties,idgen`; an exclusion list is accepted as
  an override. An unknown
  domain name, a config folder for any other domain that would load, and a
  folder whose name is not a known domain are refused before OpenMRS starts:
  by the installer, by `clinic/scripts/extract-ui-config.sh` before a new
  config tree replaces the current one, and by
  `clinic/scripts/recreate-openmrs.sh`, the way to recreate OpenMRS on a
  running node. See `clinic/install/README.md`.
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
