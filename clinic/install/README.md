# clinic/install — one installer for every clinic node

Takes a fresh macOS (rootless podman) or Linux (Docker) host to a syncing clinic
node of this fleet from three things: this checkout on `feat/bahmni-kraft`, an
answer file with twelve values, and a folder with three database dumps.

    cp clinic/install/clinic.env.example clinic-<slug>.env   # fill it, chmod 600
    clinic/install/install.sh --answers clinic-<slug>.env --seed ~/seed --dry-run
    clinic/install/install.sh --answers clinic-<slug>.env --seed ~/seed

Tasks run in order and each ends with a check read back from the live system;
a failing check stops the run and prints how to resume (`--from NN`). Every
task is idempotent (it skips what is already done), but this is a FRESH-INSTALL
tool: an existing `clinic/.env` is a refusal.

It refuses to start when: the slug has no row in `sync/clinics.txt` or another
row holds the residue (the operator allocates, commits, pushes first); a seed
file is missing or not gzip; `clinic/.env` exists; the alias would be another
node's; disk < 60 GB, RAM < 8 GB, or a stack port is taken.

It never touches the hub, the ledgers or GitHub. Task 110 prints the hub join
for the operator (`skills/install-clinic.sh join <slug>` in the workspace).

Not in this version: LAN hostname / dnsmasq (see `initialize/` on `main`),
upgrades of an existing node, mTLS or per-site ACLs (L-007, unmet fleet-wide).

Tests: `bash clinic/install/tests/run.sh` (no runtime needed).
Shape credit: Sushil's `initialize/` on `main`.
