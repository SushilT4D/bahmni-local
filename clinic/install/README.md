# clinic/install — one installer for every clinic node

Takes a fresh macOS (rootless podman) or Linux (Docker) host to a syncing clinic
node of this fleet from three things: this checkout on `feat/bahmni-kraft`, the
clinic's name, and a folder with three database dumps plus their passwords.

    clinic/install/install.sh --clinics                                  # who is registered
    clinic/install/install.sh --clinic <slug> --seed ~/seed --dry-run    # every refusal, no changes
    clinic/install/install.sh --clinic <slug> --seed ~/seed [--cert-hostname <name>]

`--clinic` composes the twelve answers itself: identity from `sync/fleet/<slug>.env`
(MRN prefix, site number, phone), the residue from `sync/clinics.txt` (the only
place it lives), the hub endpoint from `sync/hub.env`, and the four passwords from
`<seed>/secrets.env` (written by the operator's `install-clinic.sh seed`). Whatever
is still missing is asked on the terminal — the certificate hostname always, unless
`--cert-hostname` is given — and the result is kept in `~/clinic-<slug>.env` (mode
600) so a resume needs nothing typed again. With no terminal and a value missing
it fails naming the file to put it in. `--answers <file>` remains the hand-written
path for a clinic that is not registered (`clinic.env.example`).

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
commits, pushes first); a seed file is missing or not gzip; `clinic/.env` exists;
the alias would be another node's; disk < 60 GB, RAM < 8 GB, or a stack port is
taken.

It never touches the hub, the ledgers or GitHub. Task 110 prints the hub join
for the operator (`skills/install-clinic.sh join <slug>` in the workspace).

Not in this version: LAN hostname / dnsmasq (see `initialize/` on `main`),
upgrades of an existing node, mTLS or per-site ACLs (L-007, unmet fleet-wide),
a per-node registration `defaultIdentifierPrefix` (task 070 prints the edit).

Tests: `bash clinic/install/tests/run.sh` (no runtime needed). On Darwin this
runs the whole suite a second time under `/bin/bash` -- macOS's own stock
bash 3.2, not whatever `bash` resolves to on `PATH` -- so a script that
accidentally needs bash 4+ is caught here, not on a clinic Mac.
Shape credit: Sushil's `initialize/` on `main`.

## macOS (Apple Silicon)

The runtime is rootless **podman**, driven through `docker-compose` over
`DOCKER_HOST` (never `podman-compose`) -- see `host-macos.sh` for Homebrew,
the podman machine and the LaunchAgent that restarts it at login.

IPLIT's `OPENMRS_IMAGE_NAME` is `linux/amd64`-only. On an arm64 host, task 040
does not pull it -- it runs `openmrs/build-native.sh`, which extracts
`/usr/local/tomcat`, `/openmrs`, `/etc/bahmni-emr` and `/home/bahmni` out of
the pinned image (`create`+`cp`, the source is never executed) onto a native
arm64 base (`OPENMRS_ARM64_BASE_IMAGE`, pinned in `sync/versions.env`: same OS
family and JDK build as the source) and tags the result
`OPENMRS_RUN_IMAGE`, which `docker-compose.yml` prefers over
`OPENMRS_IMAGE_NAME`. Measured on Ghated (Apple M5 Pro, 2026-09-21): bare
Tomcat+WAR start in 2.3 s native vs 26 s under QEMU emulation (~11x); the
previous pinned image took 51 minutes emulated with modules loading. Every
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
