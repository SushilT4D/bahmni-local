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
with its call chain (bash 4+), so a STOPPED never arrives without a culprit. Every
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

Tests: `bash clinic/install/tests/run.sh` (no runtime needed).
Shape credit: Sushil's `initialize/` on `main`.
