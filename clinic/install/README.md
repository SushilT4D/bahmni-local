# clinic/install — install a clinic machine, then seed it at go-live

Two sittings, two people, on a fresh macOS (rootless podman) or Linux (Docker) host:

    # the operator, before the machine ships (no hub data needed)
    clinic/install/install.sh --clinics                                          # who is registered
    clinic/install/install.sh --clinic <slug> --secrets <hub secrets file> --dry-run
    clinic/install/install.sh --clinic <slug> --secrets <hub secrets file> [--versions <file>] [--cert-hostname <name>] [--baseline <dir>]

    # clinic staff, on site, at go-live, with the folder the operator copied
    clinic/install/seed.sh --seed <folder> [--discard-baseline-data] [--dry-run]

`install.sh` builds the host, the images and the name service, and starts Bahmni on
a disposable baseline (IPLIT's own database images, pinned in `sync/versions.env`;
`--baseline <dir>` supplies `openmrs.sql.gz`, `odoo.sql.gz` and `openelis.sql.gz`
instead). No sync runs and nothing is captured. It ends with the machine marked
INSTALLED (`clinic/.install-state`).

`seed.sh` refuses a seed folder with no manifest, a dump older than six days (the
hub keeps a week of changes; `SEED_MAX_AGE_DAYS`), a damaged dump, a dump from the
wrong OpenMRS or Odoo version or taken before the hub partitioned its address ids,
a machine whose LAN name no longer points at it, a machine already seeded, and
records entered before seeding (unless `--discard-baseline-data`). Then it replaces
the three databases with the hub's, strides them, sets the site identity, checks the
hub credentials, starts the feeds and the sync layer, and proves the node. It ends
SEEDED; the operator then joins the clinic to the hub. A seed that stops part-way
is run again as is: it redoes the restore from the start.

Staff open `https://bahmni.clinic/` (Bahmni, `/openmrs`, `/openelis`) and
`https://odoo.bahmni.clinic/` (Odoo). The certificate is self-signed: each device
accepts the browser warning once per name. dnsmasq on this machine answers for both
names with its current address; the clinic router must hand out this machine as the
ONLY DNS server and reserve its address. To test from another computer without the
router, point both names at the machine in that computer's hosts file.

`--clinic` composes the twelve answers itself: identity from `sync/fleet/<slug>.env`
(MRN prefix, site number, phone), the residue from `sync/clinics.txt` (the only
place it lives), the hub endpoint from `sync/hub.env`, and the four hub credentials
from `--secrets` (the operator's hub secrets file). Whatever
is still missing is asked on the terminal — the certificate hostname always, unless
`--cert-hostname` is given — and the result is kept in `~/clinic-<slug>.env` (mode
600) so a resume needs nothing typed again. With no terminal and a value missing
it fails naming the file to put it in. `--answers <file>` remains the hand-written
path for a clinic that is not registered (`clinic.env.example`).

## Application image versions

`sync/versions.env` holds the default version of every image. The application
images — the IPLIT and Bahmni ones, listed in `lib.sh` `IMAGE_KEYS` — can be
chosen per install; the sync layer (Kafka, MirrorMaker, Debezium) cannot.

| Key | Default image |
|---|---|
| `OPENMRS_IMAGE_NAME` | `infoiplitin/openmrs` |
| `ODOO_IMAGE_NAME` | `bahmni/odoo-16` |
| `ODOO_CONNECT_IMAGE_TAG` | `bahmni/odoo-connect` |
| `OPENELIS_IMAGE_TAG` | `bahmni/openelis` |
| `BAHMNI_WEB_IMAGE` | `infoiplitin/bahmni-iplit-web` (the UI the clinic's nginx serves) |
| `BAHMNI_CONFIG_IMAGE` | `infoiplitin/clinic-config-indiadistro` (the config tree) |
| `IMPLEMENTER_INTERFACE_IMAGE_TAG` | `bahmni/implementer-interface` |
| `PATIENT_DOCUMENTS_TAG` | `bahmni/patient-documents` |
| `ATOMFEED_CONSOLE_IMAGE_TAG` | `bahmni/atomfeed-console` |

Two ways to choose, like the hub secrets:

- **A file**, `--versions <file>`, one `KEY=value` per line. A `*_TAG` key takes a
  tag; the others take a full image reference, or a bare tag that keeps the image
  name:

      BAHMNI_WEB_IMAGE=bhs-0.0.34
      OPENELIS_IMAGE_TAG=1.1.0-111

- **The terminal.** With `--clinic` and no `--versions`, the installer asks
  `keep the defaults? [Y/n]`; answering `n` shows each image with its default, and
  Enter keeps it.

Each image that differs from its default is kept in `~/clinic-<slug>.env`, so a
resume makes the same choice; it is written into `clinic/.env`, and `seed.sh` reads
it from there. The run log names every image that differs. To choose again, pass
`--versions`, or delete the answers file.

OpenMRS, Odoo and OpenELIS change their database schema when they start, and the
hub holds the same tables. A version of these three that differs from the hub's
breaks lockstep, and the installer warns: upgrade the hub first, then every clinic.
The UI and the three tools can differ from the hub safely. At a clinic the
config tree loads only the Initializer domains the node keeps (see "Initializer
domains"; the master data itself comes from the hub), so a config version
other than the hub's needs its changes read first, and a new folder in it is
refused before the stack starts.

The hub link is SASL over TLS when `sync/hub.env` says
`REMOTE_KAFKA_SECURITY_PROTOCOL=SASL_SSL`: task 090 builds MirrorMaker's
truststore from the hub's certificate in `sync/hub-ca.pem`, and task 020 stops
if that file is missing. `SASL_PLAINTEXT` is for a hub that has no certificate;
the password and every record then cross the network unencrypted.

Registered today: manpur, bedawal, ghated, rawach, bagdunda, kojawada (residues
1–6), azure (7, the test clinic), and morwal, which has no residue and is refused
until the operator allocates one. Secrets are never in the repo: it is public.

Tasks run in order and each ends with a check read back from the live system;
a failing check stops the run and prints how to resume (`--from NNN`); a bare
command that fails under `set -e` prints a `FAILED rc=N: <command as written>` line
with its call chain (bash 4+), so a STOPPED never arrives without a culprit. Task 080
pins the OpenMRS JVM options in `.env` before it starts the stack (a node composed
before that fix is repaired on resume), proves odoo-connect is parked before it sets
the feed markers, and treats a container Docker restarted during the OpenMRS wait as
a crash loop: it fails at once with the log lines instead of after 25 minutes. Every
task is idempotent (it skips what is already done), but this is a FRESH-INSTALL
tool: an existing `clinic/.env` is a refusal.

It refuses to start when: the slug is not registered, or has no row in
`sync/clinics.txt`, or another row holds its residue (the operator allocates,
commits, pushes first); `clinic/.env` exists;
the alias would be another node's; disk < 45 GB (`CLINIC_MIN_DISK_GB`), RAM < 8 GB (a Mac needs 16 GB: its podman machine gets 10 GB), or a stack port is
taken.

It never touches the hub, the ledgers or GitHub. Task 110 prints the hub join
for the operator (`skills/install-clinic.sh join <slug>` in the workspace).

Not in this version: upgrades of an existing node, per-site certificates (mTLS) or ACLs (unmet fleet-wide),
a per-node registration `defaultIdentifierPrefix` (task 070 prints the edit).

Tests: `bash clinic/install/tests/run.sh` (no runtime needed). On Darwin this
runs the whole suite a second time under `/bin/bash` -- macOS's own stock
bash 3.2, not whatever `bash` resolves to on `PATH` -- so a script that
accidentally needs bash 4+ is caught here, not on a clinic Mac.
Shape credit: the `initialize/` tree on `main`.

## Forms

An observation form is two things that travel together:

- **rows** in OpenMRS: `form` (name, version, uuid, published, retired) and
  `form_resource`, whose pointer row names the form's file,
  `/home/bahmni/clinical_forms/<uuid>.json`;
- **files** in the forms folder: `<uuid>.json` and `translations/<uuid>.json`.

Forms are published only on the hub, in the form builder. A clinic does not
author them:

- **Rows by sync.** `form` and `form_resource` are hub tables
  (`hub/tables.conf`). A clinic gets the hub's rows with its seed and every
  later change through the down sync, so a form has the same id, uuid and
  version on every node. That matters because a saved observation names its
  form by name and version.
- **Files by the forms repo.** The operator's private forms repo holds
  `clinical_forms/<uuid>.json`, `clinical_forms/translations/<uuid>.json`,
  `MANIFEST.tsv` (one row per form version: `form_name`, `version`, `uuid`,
  `published`, `retired`, `file`, empty for a version with no file, `source`,
  `exported_at`), exported from the hub's forms folder. It only ever adds files: an old version's file stays, because
  observations saved with it still open with it. Task 075 clones it into
  `clinic/forms` (node-local, gitignored), and the openmrs service mounts
  `clinic/forms/clinical_forms` at `/home/bahmni/clinical_forms`, and its
  `translations/` where the form module reads translations, **read-only**. The
  mounts never create a missing folder: if `clinic/forms` is missing, OpenMRS
  does not start, rather than starting with no forms.
- **No form builder.** The `implementer-interface` service is in no profile
  the clinic starts (only in its own, `implementer-interface`), the proxy
  starts without it, and `extract-ui-config.sh` removes its home page tile. If
  someone starts it by hand, the read-only mount stops it writing a form's
  file; the form builder writes the form's row over REST before the file, so
  the mount alone does not keep a row from being written. The proxy refuses
  that write (see "Master data writes refused at the proxy" below).
- **No forms from the Initializer** (see "Initializer domains" below).

Two answers name the forms repo:

| Key | Value |
|---|---|
| `FORMS_REPO_URL` | the repo's SSH clone address |
| `FORMS_REPO_KEY` | the path on this machine to the repo's read-only deploy key, mode 600 (one key per clinic, so one clinic can be revoked alone) |

They go in a hand-written answers file or, with `--clinic`, in the `--secrets`
file (and are then kept in `~/clinic-<slug>.env`). Task 075 writes both into
`clinic/.env`, where the seed sitting and `update-forms.sh` read them, together
with the folder `docker-compose.yml` mounts and whether it is read-only
(`FORMS_DIR`, `FORMS_READ_ONLY`). Git gets the key by path; nothing prints its
contents. The key path must be absolute and plain (letters, digits, `. _ / -`);
a relative path in the answers is kept as an absolute one, from where the
installer runs. Git trusts the git host's key the first time it sees it; to pin
it, put the host's key in the installing user's `~/.ssh/known_hosts` first.

The forms repo is data to a clinic: its files are read and mounted
read-only (a commit carrying a symlink is refused, since OpenMRS would
follow it), and nothing in it is executed (anything else the repo carries,
such as its own tools, is never run here). The concept check below is this
repo's `check-form-concepts.py`. Write access to the forms repo therefore
decides which forms a clinic shows, but cannot run code on a clinic.

**Without a forms repo** (both empty) the node mounts the frozen copy tracked
in this repo, `clinic/bahmni_home/clinical_forms`, read-write. That is a
transition: it goes once every node runs from the forms repo.

`clinic/forms` only moves forward. A checkout with local edits, with commits the
forms repo lacks, or cloned from another URL is refused. To start again from
the forms repo, move it aside and run `update-forms.sh` straight away, which
takes a fresh clone: until it has, OpenMRS cannot be recreated, because its
forms mount refuses a missing folder. One run at a time changes
`clinic/forms` (a lock, `clinic/.forms.lock`, taken over when its run is gone
or after an hour); a clone an earlier run did not finish
(`clinic/.forms.new.XXXXXX`) is removed by the next run.

### The checks at seed

After the database is restored, task 075:

1. runs the concept check on a copy of the incoming tree,

       check-form-concepts.py --repo <tree> --known <concepts> --known-forms <forms>

   with two lists read from this node's OpenMRS (SELECT only): every concept uuid that
   exists and is not retired, and every form uuid that is published and not
   retired, one per line. The checker exits 0 when nothing is missing, 1 when
   a form misses concepts, 2 when it cannot run. Every non-zero exit is a
   **warning** here, and when the check could not run the output says
   "concepts NOT checked": a form that uses a concept the node lacks opens
   with a field that saves nothing, and the fix is to deliver that concept the
   way the hub got it; the form's rows arrive from the hub either way.
2. runs the **row/file check** on every form row and its file pointer rows:
   every published, unretired form must have a pointer row, the pointer must be
   a plain path inside the forms folder (a pointer anywhere else is a failure,
   named), and its file must be there. Translation pointers are not required.
   A failure **stops the seed** with the list (form, version, file). Pull the
   forms repo's latest, which only ever adds files; if it still lacks the file,
   the hub's forms have not been exported to it yet. A file with no row is fine
   (counted as pending). Retired versions whose file is missing (many old ones
   point at files that exist nowhere) are counted in a warning with their
   first uuids, since observations saved with them do not open; so are
   pointers of retired or unpublished forms outside the forms folder. On the
   frozen copy a missing file is a warning.

Task 080 does not start the stack while the forms folder is missing, holds no
form or has no `translations/`, or, with a forms repo, while the mount is not
the clone, read-only; at seed it runs the row/file check again. Install checks
neither concepts nor rows: the baseline database is replaced at seed.

### Updating the forms on a running node

    clinic/scripts/update-forms.sh --dry-run    # the incoming commits and MANIFEST.tsv changes; changes nothing
    clinic/scripts/update-forms.sh

fetches the forms repo, fast-forwards `clinic/forms` (refusing local edits or
history the repo lacks), runs the concept check (warnings), runs the row/file
check and prints a summary. It **never restarts OpenMRS**: OpenMRS reads a
form's file when the form is opened, so users see a new version after reloading
the page. It only ever adds form files to what the node has; the node's form
rows come from its seed and the down sync. Exit codes, for a schedule: 0
`clinic/forms` is current and every published form has its file; 1 a check
refused (act on the FAIL line); 3 the forms repo could not be reached (the
forms already here keep working; the next run tries again); 4 another run holds
`clinic/forms`. With no forms repo configured it reports the frozen copy and
exits 0.

Schedule it every 15 minutes, as the user that owns the checkout:

- Linux: a cron line, `*/15 * * * * <checkout>/clinic/scripts/update-forms.sh >> <log file> 2>&1`,
  or a systemd timer running the same command;
- macOS: a launchd agent with `StartInterval` 900 running the same command.

The rows and the files travel separately. A form row can arrive before its
file; that form then fails to open until the next pull, and the row/file check
names it. The hub's forms are exported to the forms repo right after they are
published, and clinics pull often, to keep that gap short. A file can also
arrive before its rows; nothing shows it until they do.

**A node seeded before forms came down by sync** takes them by a **reseed**.
The seed is the baseline: it brings the hub's form rows, seed task 050 grants
the sink user the form tables, and task 075 clones the forms repo. The down
sinks carry only later changes, so registering them on such a node would keep
any form row it already has that differs from the hub's, and the row/file
check reads only the node's own rows, so it could not notice.
`update-forms.sh` on that node only adds form files; it does not bring its
rows into line with the hub's.

**Recreating OpenMRS on a running node** (after `update-forms.sh` points the
forms mount at the clone, after `extract-ui-config.sh` takes a new config
image, after an edit of `clinic/.env`):

    clinic/scripts/recreate-openmrs.sh --check    # the checks only; changes nothing
    clinic/scripts/recreate-openmrs.sh

runs the checks task 080 runs before OpenMRS starts (the JVM options, the
forms mount, the Initializer domain list against the config tree) and only
then recreates openmrs alone, with the node's compose setup (`clinic/.env`'s
`COMPOSE_FILE`, the fleet's profiles, docker compose or docker-compose over the
podman socket). A refused check recreates nothing. Recreate OpenMRS this way,
not with a compose command by hand.

**Retiring a form.** Forms are never deleted. A bad version is retired on the
hub (or its previous content published again as a new version); the retired
flag comes down by sync, and the file stays in the forms repo for the
observations saved with it.

**The hub is the source.** Forms are published on the hub, exported to the
forms repo, and only then pulled by clinics. The hub keeps its forms folder
across upgrades, captures `form` and `form_resource`, and is the only node
where the form builder is used.

### Initializer domains

At every start the Initializer module loads each domain folder of the config
tree (`masterdata/configuration`). Almost every domain writes master data the
hub owns and sends down: forms (a form it does not know becomes a new version
numbered by this node), concepts, drugs, locations, roles, programs, the
address hierarchy, and config changesets that change concepts. So the openmrs
service passes

    -Dinitializer.domains=${OPENMRS_INITIALIZER_DOMAINS:-<the clinic default>}

The clinic default is the inclusion list `globalproperties,idgen`: those two
write this node's own settings and identifier sources, and no other domain
loads, whatever folders a config release adds. On a seeded node the first
start then writes only `global_property`, `liquibasechangeloglock` and
`scheduler_task_config`; no master table changes.

An exclusion list (a leading `!`) is still accepted as an override. The one
that keeps the same two domains for today's config tree names every other
domain the tree carries a folder for:

    !bahmniforms,roles,privileges,concepts,conceptsets,conceptclasses,conceptsources,drugs,ocl,locations,addresshierarchy,programs,programworkflows,programworkflowstates,attributetypes,visittypes,ordertypes,personattributetypes,relationshiptypes,appointmentspecialities,appointmentservicedefinitions,liquibase

`OPENMRS_INITIALIZER_DOMAINS` replaces the default, as an optional answer
(task 020 writes it into `clinic/.env`) or in `clinic/.env` directly:
comma-separated, no spaces, a leading `!` for an exclusion list, otherwise an
inclusion list. The same check runs on every path that starts
OpenMRS on a config tree or a domain list it has not run with: task 080
before the stack starts, `clinic/scripts/extract-ui-config.sh` on a new config
tree before it replaces the current one (a refused tree leaves `extracted/` as
it was, and the run exits non-zero), and `clinic/scripts/recreate-openmrs.sh`.
It refuses:

- a name the module does not have (it knows 52; the module itself would only
  warn and leave that domain loading);
- a config folder holding a file for any domain that would load, other than
  `globalproperties` and `idgen`. An exclusion list leaves every unnamed domain
  on, so a config release that adds a folder (`htmlforms` and `ampathforms`
  also write forms) is refused here instead of loading silently. The default
  inclusion list passes the same check by construction;
- a config folder holding a file whose name is not one of the 52 domains, under
  either kind of list: a newer module may have that domain and load it.

Do not put `-Dinitializer.domains` in `OMRS_JAVA_SERVER_OPTS`: task 080 and
`recreate-openmrs.sh` take it out of `clinic/.env` (and say what it carried),
so the property is passed once.

### Master data writes refused at the proxy

The clinic's proxy (`clinic/proxy/bahmni-nginx.openelis.conf`, the file the
proxy service mounts) answers any method other than GET, HEAD and OPTIONS with
403 and the plain-text message

    Master data is maintained at the hub; this change is refused at this clinic

on the paths that write the master data the hub sends down, and logs each
refusal as a line ending `master data write refused: master data is
maintained at the hub`. The paths are:

- the OpenMRS REST resources of those tables and their sub-resources:
  `concept` (names, descriptions, mappings, attributes), `conceptclass`,
  `conceptsource`, `conceptreferenceterm`, `conceptreferencetermmap`,
  `conceptattributetype`, `conceptdatatype`, `conceptmaptype`, `drug`
  (ingredients), `drugreferencemap`, `location` (attributes), `locationtag`,
  `locationattributetype`, `program`, `workflow` (states),
  `programattributetype`, `visittype`, `visitattributetype`, `ordertype`,
  `orderfrequency`, `personattributetype`, `relationshiptype`,
  `providerattributetype`, `encounterrole`, `patientidentifiertype`,
  `privilege`, `role`, `form` (resources), `metadatamapping/...` and
  `openconceptlab/...`;
- FHIR `Location` and `Medication`;
- the form builder's `bahmniie/form/...` writers (save, publish,
  translations, form privileges); printing a filled form (`jsonToPdf`) passes;
- the admin app's CSV uploads of concepts, concept sets, drugs and reference
  terms (`bahmnicore/admin/upload/...`), the `reference-data/...` writers, and
  the distribution module's `bahmnicore/distro/location...` and
  `addConceptAnswer` writers;
- the legacy admin pages that write the same tables (`/openmrs/dictionary/`,
  `/openmrs/admin/concepts/`, `/openmrs/admin/forms/`, and the location,
  program, visit type, person attribute and relationship type, identifier
  type, role, privilege, encounter role and provider attribute type pages),
  and the metadata sharing import and metadata mapping pages.

Paths match on whole segments, ignoring case (`concept` does not catch
`conceptsearch`, `program` does not catch `programenrollment`). The check runs
before nginx picks a location, so the exact, prefix and regex routes (the form
definition route among them) refuse alike. Reads pass, and so does every
patient-flow write: patient, person, visit, encounter, obs, orders, program
enrollment, appointments, documents, and the patient, encounter, program and
lab CSV uploads. Users and providers are not refused here: a user's password
and preferences, and a provider's attributes, are saved at the clinic.

This stops authoring masters through the browser. It does not stop anyone who
reaches OpenMRS's port or the database without the proxy; the hub-to-clinic
checksum (`clinic/scripts/master-checksum.sh`) shows a row changed that way.
`clinic/install/tests/test_proxy_master_writes.sh` holds the path list, the
patient-flow list and a write path for every DOWN table of
`hub/table-verdicts.conf`; with a container runtime it also serves the
configuration from the proxy's nginx image against a stub upstream and sends
the requests.

## macOS (Apple Silicon)

The runtime is rootless **podman**, driven through `docker-compose` over
`DOCKER_HOST` (never `podman-compose`) -- see `host-macos.sh` for Homebrew,
the podman machine and the LaunchAgent that starts it, and the containers, at login.

IPLIT's `OPENMRS_IMAGE_NAME` is `linux/amd64`-only. On an arm64 host, task 040
does not pull it -- it runs `openmrs/build-native.sh`, which extracts
`/usr/local/tomcat`, `/openmrs`, `/etc/bahmni-emr` and `/home/bahmni` out of
the pinned image (`create`+`cp`, the source is never executed) onto a native
arm64 base (`OPENMRS_ARM64_BASE_IMAGE`, pinned in `sync/versions.env`: same OS
family and JDK build as the source) and tags the result
`OPENMRS_RUN_IMAGE`, which `docker-compose.yml` prefers over
`OPENMRS_IMAGE_NAME`. Measured on an Apple M5 Pro: bare
Tomcat+WAR start in 2.3 s native vs 26 s under QEMU emulation (~11x); an
emulated image took 51 minutes with modules loading. Every
x86 clinic is untouched by this: `OPENMRS_RUN_IMAGE` is never set there.

`bahmni/odoo-16` and `bahmni/atomfeed-console` have no arm64 build and run
emulated regardless -- preflight names both on an arm64 host. Odoo 10 ran
this way on Ghated for three weeks: usable, not fast.

The podman machine's memory is sized from host RAM, not a fixed 12 GiB: 55%
of host RAM, rounded down to a multiple of 1024 MiB and capped at 12288,
refused below a 10 GiB floor (host-macos.sh's `podman_machine_size`;
preflight's own `macos-facts` block enforces the same floor, plus a warning
above 55%, on every later run). The 55% ceiling is Rawach's own 18 GB Mac's
rule: a 15 GB (83%) VM there made macOS swap fill the disk, and the
Virtualization framework killed it four times in one day. An existing
machine is never resized automatically, only warned about.

## After a power cut

Every service carries a restart policy, so the container runtime brings the
stack back when the machine boots. Two settings are manual, once per machine:

- **PC:** in the firmware setup, set the machine to power on when AC power
  returns.
- **Mac:** turn on automatic login for the clinic user (System Settings >
  Users & Groups). FileVault must be off. The installer sets power-on after a
  power failure itself and warns about the other two.

A node installed before the restart policies were added picks them up when
its containers are recreated, once, in `clinic/`:
`docker compose --profile local --profile debezium --profile openelis up -d`
(on macOS: `docker-compose` with the same arguments and `DOCKER_HOST` set to
the podman machine's socket; `clinic/.env`'s `COMPOSE_FILE` names the compose
files on both). Without the profiles the
command recreates nothing, since every service is in one. Run
`clinic/scripts/recreate-openmrs.sh --check` first: it runs the checks the
installer runs before OpenMRS starts.

