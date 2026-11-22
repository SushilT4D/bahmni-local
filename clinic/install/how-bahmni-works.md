# How the clinic installer works

The explanations that used to be comments in `clinic/install/`, grouped by file. Each entry is followed by the line of code it described.

## `dns.sh`

The clinic LAN name. dnsmasq on this machine answers for <LAN_NAME> and
odoo.<LAN_NAME> with the address the default-route interface has NOW
(interface-name=), so a machine that gets a new address after it is moved
keeps answering correctly without a re-run. Every other name is forwarded
to public resolvers: the clinic router hands this machine out as DNS, so
forwarding back to the router would loop. No DHCP: the router keeps that.
bash 3.2 compatible.

> Before: `DNS_UPSTREAMS="${DNS_UPSTREAMS:-1.1.1.1 8.8.8.8}"`

dnsmasq on macOS listens on the addresses the machine has when it starts; the
router's DHCP reservation keeps this machine's address fixed (README).
local-service answers only hosts on its own subnets.

> Before: `printf 'local-service\nno-resolv\n'`

Ask the machine's LAN address to see what clinic devices see.

> Before: `{ dig +short +time=2 +tries=1 "$1" A "@${2:-127.0.0.1}" 2>/dev/null || true; } | grep -E '^[0-9.]+$' | head -1`

Root steps run only when something changed, so a re-run over ssh, where sudo
has no terminal to ask on, goes through without a person. DNS_ETC moves /etc
for the tests.

> Before: `DNS_ETC="${DNS_ETC:-/etc}"`

Asked at the LAN address, as clinic devices ask: macOS dnsmasq keeps
answering on 127.0.0.1 after the address changes, while the new address
gets no answer until dnsmasq restarts.

> Before: `local ip got; ip="$(lan_ip)"; got="$(lan_resolve "$1" "$ip")"`

A running dnsmasq with an unchanged config can still be wrong: it listens
only on the addresses it found at start, so after a new LAN address the
answer check fails and it restarts.

> Before: `[ -n "$why" ] || pgrep -x dnsmasq >/dev/null 2>&1 || why="dnsmasq not running"`

dnsmasq is still starting when its service manager returns

> Before: `t=0`

## `forms.sh`

The observation forms' files on a clinic node. Sourced after lib.sh by task
075, task 080, scripts/update-forms.sh and scripts/recreate-openmrs.sh.
bash 3.2 compatible.

A form is two things that must travel together:
  - rows: form (name, version, uuid, published, retired) and form_resource,
    whose pointer row names the form's file as
    /home/bahmni/clinical_forms/<uuid>.json. The hub is the only node that
    publishes forms; the rows reach a clinic by sync (sync/tables/openmrs.conf [down]) or
    with the seed. A clinic does not create them: its Initializer does not
    load forms (initializer.sh), its stack does not run the form builder, and
    its forms folder is read-only.
  - files: <uuid>.json and translations/<uuid>.json in the forms folder,
    which docker-compose.yml mounts at /home/bahmni/clinical_forms (and its
    translations/ where the form module reads translations), from
    FORMS_DIR, read-only when FORMS_READ_ONLY is true, both in clinic/.env.
    The mounts never create a missing source: OpenMRS refuses to start
    instead of starting with no forms.

With a forms repo configured (FORMS_REPO_URL, FORMS_REPO_KEY), clinic/forms
is a clone of it, made and fast-forwarded with git using the deploy key by
path, and the forms folder is clinic/forms/clinical_forms, read-only. The
repo holds clinical_forms/<uuid>.json, clinical_forms/translations/ and
MANIFEST.tsv, and only ever adds files: an old version's file stays, because saved observations still open with it. So a
clone newer than the database is always safe, and an older one is caught by
the row/file check. One run at a time changes clinic/forms: a lock
(clinic/.forms.lock) is taken around the clone or fast-forward.

With none configured, the forms folder is the frozen copy tracked in this
repo, clinic/bahmni_home/clinical_forms, read-write. clinic/forms is unused.

The concept check is this repo's check-form-concepts.py, run on a copy of
the incoming tree with <concepts> (every concept uuid that exists and is not
retired in this node's OpenMRS) and <forms> (every form uuid published and
not retired there). The forms repo is data to a clinic: its files are read
and mounted read-only, and nothing in it is executed, so write access to it
cannot run code on a clinic. The check's findings are warnings: a form
missing a concept opens with a field that saves nothing, and the fix is to
deliver the concept the way the hub got it, not to hold the form back, whose
rows arrive by sync either way. When the check cannot run, the run says
"concepts NOT checked".

The row/file check is the gate: every published, unretired form must have a
pointer row, its pointer must be a plain path inside the forms folder, and
its file must be there. A file with no row is fine (its rows have not synced
yet, or it is an old version kept for saved observations). Retired versions
whose file is missing, and pointers of retired or unpublished forms outside
the forms folder, are warnings.

The config package's stock demo forms (demo-forms.conf) are retired, never
deleted, on a node whose OpenMRS holds them: a clinic that keeps its own
database across an upgrade from a stack that loaded every Initializer domain.
Only those uuids are touched, and only on this node: clinics do not send form
rows up (sync/tables/openmrs.conf [up]).

Exit codes, for a schedule: 1 a check refused (act on the FAIL line), 3 the
forms repo could not be reached (the forms already here keep working), 4
another run holds the lock.

What every refusal of clinic/forms tells the operator to do.

> Before: `FORMS_ASIDE="move clinic/forms aside, then at once run clinic/scripts/update-forms.sh (or the installer task a`

forms_folder_for URL / forms_read_only_for URL : the forms folder a node with
(or without) a forms repo mounts, and whether the mount is read-only

> Before: `forms_folder_for(){ if [ -n "$1" ]; then printf '%s\n' "${FORMS_CLONE_DIR}/clinical_forms"; else printf '%s\n'`

forms_folder_verdict DIR : the mount source must exist, hold forms, and have
the translations/ folder the second mount takes. The mounts refuse a missing
source, so OpenMRS would not start.

> Before: `forms_folder_verdict(){`

a symlink in the forms folder is followed inside the container, read-only
mount or not: a form "file" pointing at /proc/self/environ would serve
OpenMRS's environment, passwords included, to anyone opening the form

> Before: `l="$(find "$d" -type l 2>/dev/null | head -1)"`

forms_tree_symlinks GITDIR REV : prints the paths REV of the clone at GITDIR
carries as symlinks (none for a forms repo; see forms_folder_verdict)

> Before: `forms_tree_symlinks(){ git -C "$1" ls-tree -r "$2" | awk -F'\t' '$1 ~ /^120000 / {print $2}'; }`

forms_mount_verdict DIR READ_ONLY URL : the forms mount docker-compose.yml
will make from clinic/.env (FORMS_DIR, FORMS_READ_ONLY, FORMS_REPO_URL) is
one OpenMRS may start on. Every path that starts or recreates OpenMRS runs
it first (task 080, scripts/recreate-openmrs.sh).

> Before: `forms_mount_verdict(){`

forms_state DIR -> absent | placeholder | clone | foreign. placeholder: an
empty directory. foreign: anything this file did not put there, which is
never removed.

> Before: `forms_state(){`

forms_key_verdict PATH : a deploy key ssh will accept: an absolute path of
plain characters (git hands it to ssh through /bin/sh, and every caller runs
from its own directory), present, readable, private to its owner. Its
contents are never read here.

> Before: `forms_key_verdict(){`

forms_git ARGS... : git with the deploy key, never prompting. The key is
passed by path only; forms_key_verdict has made it a plain absolute path.
accept-new trusts the git host's key the first time it is seen: put the
host's key in this user's ~/.ssh/known_hosts before the first run to pin it.

> Before: `forms_git(){`

forms_upstream_verdict DIR : a clone may only move forward to what the forms
repo holds. Run after a fetch. Prints uptodate | ff, or the refusal.

> Before: `forms_upstream_verdict(){`

forms_sql QUERY : runs QUERY against this node's openmrs database, rows on
stdout, tab-separated, no header. Every query is a SELECT except the stock
demo forms' retirement (forms_retire_demo_sql).

> Before: `forms_sql(){`

forms_known_concepts OUT / forms_known_forms OUT : the two lists the concept
check takes (see the top of this file). FORMS_CONCEPTS_FILE and
FORMS_KNOWN_FORMS_FILE supply lists taken elsewhere instead.

> Before: `forms_known_concepts(){`

The stock demo forms: the list, the reason recorded on each, and the user
recorded as retiring them (1, the admin user every OpenMRS database has).

> Before: `FORMS_DEMO_LIST="${FORMS_DEMO_LIST:-${INSTALL_DIR}/demo-forms.conf}"`

forms_demo_uuids [FILE] : the uuids FILE (default FORMS_DEMO_LIST) lists, one
per line, comments dropped. A line that is not exactly one lowercase uuid is
refused, named, and nothing is printed, so only uuids reach the SQL built
from the list. A list with no uuid is refused too: the SQL needs at least one.

> Before: `forms_demo_uuids(){`

forms_retire_demo_sql UUID... : the statement that retires those forms where
they are not retired yet, then three counts, one per line: the forms it
retired, the forms of the list this node holds, and those of them still not
retired (0 when it worked). It changes rows only by uuid IN (the list), and
deletes nothing.

> Before: `forms_retire_demo_sql(){`

forms_retire_demo : retires, on this node, every stock demo form it holds
that is not retired yet, and says how many: 0 on a node that never loaded
them, and on every run after the first. Fails unless every listed form this
node holds reads back retired. Safe to re-run.

> Before: `forms_retire_demo(){`

unquoted on purpose: one argument per uuid, each checked by forms_demo_uuids

> Before: `out="$(forms_sql "$(forms_retire_demo_sql $uuids)")" || fail "could not retire the stock demo forms in openmrs`

forms_concept_warn TREE : runs the concept check on TREE, a copy of the
incoming forms, against this node's concepts and published forms, and shows
what it finds. The checker is this repo's check-form-concepts.py, which
reads TREE as data; nothing in the forms repo is executed. Never stops
anything: every finding is a WARN. Sets FORMS_CONCEPTS_UNCHECKED=1 when the
concepts could not be checked.

> Before: `forms_concept_warn(){`

the checker's exits: 0 nothing blocked, 1 a form misses concepts, 2 it could not run

> Before: `case "$rc" in`

forms_lock / forms_unlock : one run at a time changes clinic/forms. The lock
is a directory beside it holding the owner's pid. A lock whose pid is gone is
taken over; one whose run is alive is never taken, however old (git's ssh
gives up on a stalled connection, so a live run ends). A lock with no pid
(its run died before writing one) is taken over once older than
FORMS_LOCK_STALE_MIN minutes (default 60). Taking over renames the old lock
aside first, which only one run can do, and checks that what it renamed is
the lock it judged, so two runs that both judge it stale never both hold it.
A run that hangs keeps its lock until it is ended. forms_lock returns
FORMS_RC_BUSY, with the FAIL line, when another run holds it.

> Before: `forms_lock_dir(){ printf '%s\n' "${FORMS_LOCK:-$(dirname "${FORMS_CLONE_DIR}")/.forms.lock}"; }`

Only one run can rename it; a run that loses the rename tries mkdir again.
What was renamed must be the lock judged above: if another run took over
first and made a fresh lock in between, it is put back and this run backs off.

> Before: `if mv "$l" "${l}.stale.$$" 2>/dev/null; then`

forms_sync CHECK DRY : brings clinic/forms to what the configured forms repo
holds (clone, or fast-forward only), holding the lock. CHECK 1 runs the
concept check on the incoming tree first (warnings only); DRY 1 shows what
would change (the commits and the MANIFEST.tsv lines) and changes nothing in
clinic/. Sets FORMS_OLD_REV, FORMS_NEW_REV, FORMS_CHANGED (0 or 1) and
FORMS_CONCEPTS_UNCHECKED (0 or 1). A refusal ends the caller with the exit
code above.

> Before: `forms_sync(){`

The work runs in a subshell so that every refusal in it (fail, an exit)
comes back here, where the lock is released. -e is set again inside: a
subshell tested with || would run with it off.

> Before: `case "$-" in *e*) e=1 ;; esac`

an interrupted clone leaves a .forms.new.XXXXXX beside clinic/forms; with
the lock held, any made before the lock was taken is dead

> Before: `{ find "$parent" -maxdepth 1 -type d -name '.forms.new.??????' ! -newer "$(forms_lock_dir)" 2>/dev/null || tru`

mv onto an existing directory would put the clone inside it

> Before: `[ ! -e "${FORMS_CLONE_DIR}" ] || { rm -rf "$tmp"; fail "${FORMS_CLONE_DIR} appeared while the clone was made; `

forms_rows OUT : one line per form row and pointer row of it,
"uuid<TAB>name<TAB>version<TAB>published<TAB>retired<TAB>pointer", pointer
being the form_resource value_reference of a file pointer (a file-storage
datatype, or any value that is a path) in full, or empty for a form with
none. Every form is listed, whatever its pointer: the report judges them.
FORMS_ROWS_FILE supplies rows taken elsewhere instead.

> Before: `FORMS_ROWS_SQL="select f.uuid, f.name, f.version, f.published, f.retired, coalesce(r.value_reference, '') from`

forms_rowfile_report DIR ROWS : every published, unretired form's pointer
must be a plain path inside the forms folder (FORMS_PREFIX) whose file is in
DIR. Prints one "missing <what> (<name> v<version>...)" line per failure
(no pointer row, a pointer outside the folder, a file that is not there),
then a summary; files no row points at are counted as pending. A pointer
into translations/ is not required: a missing translation leaves labels
untranslated, the form still opens. Lines starting "warn " are warnings:
retired versions whose file is missing (saved observations made with them
do not open) and pointers of retired or unpublished forms outside the
folder. Returns 1 when a published form misses its file.

> Before: `forms_rowfile_report(){`

published, unretired forms with no pointer row (translations do not count)

> Before: `nop="$(awk -F'\t' -v pre="${FORMS_PREFIX}" '`

a translation pointer is not required, but one that climbs out of the
folder is judged below like any other pointer

> Before: `case "$ptr" in *..*) ;; "${FORMS_PREFIX}translations/"*) continue ;; esac`

forms_rowfile_gate DIR STRICT : reads this node's form rows and runs the
report on DIR. STRICT 1 (a forms repo is configured) fails on a missing
file; STRICT 0 (the frozen copy) warns. The report's warnings are WARN lines
either way.

> Before: `forms_rowfile_gate(){`

forms_manifest_diff OLD NEW : MANIFEST.tsv lines that changed (< before, > now)

> Before: `forms_manifest_diff(){ diff "$1" "$2" 2>/dev/null | grep -E '^[<>]' || true; }`

## `host-macos.sh`

macOS host layer: Homebrew, podman, the podman machine, DOCKER_HOST for
docker-compose, a LaunchAgent that starts the machine at login, dnsmasq for
the clinic LAN name, and ports 80/443 for the proxy. Rootless podman.

podman_machine_size HOST_MIB HOST_CPUS : sets MACHINE_MIB / MACHINE_CPUS for
a NEW machine (never called to resize an existing one -- see host_macos
below). memory = min(12288, 55% of host RAM), rounded DOWN to a multiple of
1024 -- Ghated's own machine (8 CPU/12288 MiB on a 24 GB host) is exactly
this rule's ceiling. 55% is the rule Rawach's 18 GB needs: a 15 GB (83%) VM
on an 18 GB Mac made macOS swap fill the disk, and the Virtualization
framework killed the VM four times in one day. cpus = host cpus minus 2,
capped at 8, floored at 2.

> Before: `podman_machine_size(){`

A 16 GiB Mac mini is the clinic machine: 55% of it is below the stack's
10 GiB, so it gets the 10 GiB anyway (62%) and nothing else should run on it.

> Before: `[ "$mem" -ge 10240 ] || [ "$host_mib" -lt 16384 ] || mem=10240`

Under DRY=1 nothing may reach the network, yet the Homebrew
`curl | bash` line evaluates its command substitution to build the
would-print string BEFORE run() ever gets called, so run()'s own DRY
check never got a chance) and still wrote to disk (`mkdir -p` for the
LaunchAgent ran unconditionally, outside run() entirely). Both bugs share
one root cause: run() only ever guards the exact command handed to it, so
anything upstream of that call -- a command substitution in its
arguments, or a plain statement never passed to run() at all -- still
executes for real. Fixed here by never reaching any of that code under
DRY: one guard at the top, nothing below it (brew, podman, mkdir,
launchctl) runs at all.

> Before: `if [ "${DRY}" = 1 ]; then`

never resized automatically -- a warning here, since preflight's own
macos-facts block already FAILs on this every run after the first.

> Before: `existing_mib="$(podman machine inspect --format '{{.Resources.Memory}}' 2>/dev/null || true)"`

podman_socket calls `podman machine inspect`, which does not exist to call
yet on a fresh host: DRY, or podman genuinely absent from PATH (brew
install above only ran for real outside DRY), both skip it rather than
crash with rc=127 on a Mac with no podman installed.

> Before: `if [ "${DRY}" = 1 ] || ! command -v podman >/dev/null 2>&1; then`

LaunchAgent: start the machine at login, then the containers that carry a
restart policy (podman does not reattach them by itself on macOS). The job
exits once they are started, and launchd ends every process a job leaves
behind, the machine's VM included, unless the job sets AbandonProcessGroup.

> Before: `plist="${HOME}/Library/LaunchAgents/com.bahmni.clinic.start-at-login.plist"`

## `initializer.sh`

What the Initializer module may load at a clinic. bash 3.2 compatible, and
needs nothing from lib.sh. The verdict runs on every path that starts OpenMRS
on a config tree or a domain list it has not run with yet: task 080 (before
the stack starts), scripts/extract-ui-config.sh (on a new tree, before it
replaces the current one) and scripts/recreate-openmrs.sh.

At every start OpenMRS copies the config tree's masterdata/configuration into
its configuration directory, and the Initializer loads each domain folder it
finds there. Almost every domain writes master data the cloud server owns and clinics
pull (forms, concepts, drugs, locations, roles, programs, the address
hierarchy) or runs config changesets that do. Loaded at a clinic, it would
create or renumber those rows locally, so the clinic's rows would no longer
be the hub's. Forms make it concrete: the Initializer creates any form it does
not know as a new version numbered by this node, while saved observations
name their form by name and version.

docker-compose.yml passes the setting to OpenMRS as a Java system property:
  -Dinitializer.domains=${OPENMRS_INITIALIZER_DOMAINS:-<INITIALIZER_DOMAINS_DEFAULT>}
Comma-separated, no spaces. A leading ! makes it an exclusion list (every
other domain loads); otherwise it is an inclusion list (only those load). The
module only warns about a name it does not know, which leaves that domain
loading, so initializer_domains_verdict refuses unknown names here.

The default is the inclusion list globalproperties,idgen: those two write this
node's own settings and identifier sources, and no other domain loads,
whatever folders a config release adds. An exclusion list is still accepted
as an override. It leaves every unnamed domain on, so a config release that
adds a folder for one (htmlforms, ampathforms and metadatasharing also write
forms) would load it silently: the verdict therefore refuses any folder
holding a file for a domain that would load, other than the kept two, and,
under either kind of list, any folder holding a file whose name is not a
domain known here (a newer module may have it).

The module's 52 domains (its Domain enum, lower case, underscores removed).

> Before: `INITIALIZER_DOMAINS_KNOWN="addresshierarchy ampathforms ampathformstranslations appointmentservicedefinitions `

The domains a clinic may load from the config tree.

> Before: `INITIALIZER_DOMAINS_KEPT="globalproperties idgen"`

docker-compose.yml's default; tests/test_initializer.sh holds the two equal.

> Before: `INITIALIZER_DOMAINS_DEFAULT='globalproperties,idgen'`

initializer_domains_verdict VALUE CONFIG_DIR : VALUE is what
-Dinitializer.domains will carry; CONFIG_DIR is the config tree OpenMRS
mounts (BAHMNI_CONFIG_DIR). Prints "ok ..." and returns 0, or prints the
refusal and returns 1.

> Before: `initializer_domains_verdict(){`

split on commas only; the character check above leaves nothing to glob

> Before: `local oldifs="$IFS"; IFS=,`

Every folder the tree carries is judged, not only the names known here: a
newer module can have a domain this list lacks, and an exclusion list would
leave it loading.

> Before: `local strange="" p`

## `install.sh`

missing; clinic/.env holds them all from task 020 on.

> Before: `set -euo pipefail`

clinic/.env first; a value it lacks comes from sync/clinics.json or
--secrets, and a missing feed password is generated. Nothing secret
is printed.

> Before: `load_inputs(){ # SLUG`

the defaults, and --versions, so the prompt shows what this run would use

> Before: `set -a; . "${VERSIONS_FILE}"; set +a`

Every key must have a value. Secrets are never printed.

> Before: `REQUIRED="CLINIC_SLUG RESIDUE MRN_PREFIX SITE_NUMBER CLINIC_PHONE CERT_HOSTNAME REMOTE_KAFKA_BOOTSTRAP_SERVERS`

The fleet's image pins (sync/versions.env), then --versions for the
application images (lib.sh IMAGE_KEYS). Every task sees the same values.

> Before: `set -a; . "${VERSIONS_FILE}"; set +a`

--- run log ----------------------------------------------------------------
Every stop this week had to be pasted by hand from a terminal, and nobody
could say how long a task took on a given host. Tee the whole run,
APPENDING, with one header line per run and one line per task naming its
wall-clock seconds and result. `exec > >(tee -a "$log") 2>&1` never puts
tee in THIS script's own pipeline (unlike `... | tee "$log"`), so `set -e`
under pipefail still sees only this script's own exit status, not tee's --
and it works under bash 3.2 (macOS stock), verified on /bin/bash. A dry run
never touches $HOME: it logs under ${TMPDIR:-/tmp} instead. Secrets never
reach the log beyond what already reaches the terminal (nothing here prints
one).
_INSTALL_LOG_STARTED stops a run that is already logging from printing a
second header into the same file; INSTALL_LOG is exported so it resolves to
the same path.

> Before: `if [ "$DRY" = 1 ]; then`

Every task is idempotent, so a machine already installed runs the whole
install again, or any part of it with --from and --only.

> Before: `. "${INSTALL_DIR}/state.sh"`

## `lib.sh`

Shared helpers for clinic/install: begin_task / ok / skip / fail, one task per
file, --force-free idempotence; derived identity, the residue ledger, the .env
quoting contract, podman behind one wrapper.

bash 3.2 compatible on purpose: macOS ships 3.2. No associative arrays, no
mapfile, no ${var,,}.

> Before: `set -o pipefail`

port_in_use PORT : something on this host listens on TCP PORT. netstat sees
every listener whoever owns it; lsof run as a normal user on macOS sees only
that user's sockets, so a port held by a root service would pass unseen.

> Before: `port_in_use(){`

The branch a clinic installs from; preflight refuses another unless EXPECTED_BRANCH names it.

> Before: `INSTALL_BRANCH="${INSTALL_BRANCH:-main}"`

Every task runs under set -e, so a bare command that fails ends the task with
no FAIL line: the runner prints STOPPED and nothing names the culprit (first
live clinic, manpur: three silent stops in one evening -- df -g, a $(...)
assignment, a psql heredoc). Print the failing command AS WRITTEN (never
expanded, so no secret value can reach the log), its exit status and the call
chain. -E so the trap also fires inside functions and $(...); guarded
failures (if / && / || / while) never trip an ERR trap, so ok/fail lines and
probes stay quiet.

> Before: `_on_err(){`

BASH_COMMAND names the LAST command of a failed pipeline, not the one that
failed (manpur: "sed" was blamed for a grep with no match) -- show them all.

> Before: `case "$ps" in *' '*) pipe=" (pipeline statuses: ${ps}; the first non-zero is the culprit)" ;; esac`

Armed only where set -e is already on (every task and install.sh set it before
sourcing): the trap exists to name what -e kills, and the test suites run
failing commands unguarded on purpose. bash 3.2 also fires ERR for a guarded
probe inside $(...), which would print a misleading FAILED line on a Mac dry
run; arm it on bash 4+ only; macOS's own bash 3.2 keeps the plain STOPPED.

> Before: `case "$-" in *e*) [ "${BASH_VERSINFO[0]}" -ge 4 ] && { set -E; trap _on_err ERR; } ;; esac`

run CMD... : in dry mode prints the command instead of executing it. Wrap
anything with side effects in it; keep reads outside it so a dry run still
reports real facts.

> Before: `run(){ if [ "${DRY}" = 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }`

The clinic runs on macOS with podman: the installer refuses any other host.

> Before: `require_macos(){ [ "$(uname -s)" = Darwin ] || fail "this installer runs on macOS only (found $(uname -s))"; }`

setup_compose: CT is podman; compose runs through the docker-compose binary
over DOCKER_HOST, the podman machine's socket (podman-compose is not used).

> Before: `setup_compose(){`

compose ARGS... : always from the clinic dir, always with the fleet's profiles.

> Before: `compose(){ ( cd "${CLINIC_DIR}" && ${COMPOSE_CMD:?setup_compose first} ${PROFILES} "$@" ); }`

.env editing. This file is read by TWO different parsers that do not agree
on quoting in general: bash `.`-sourcing (every task) and docker compose's
own dotenv reader (for ${VAR} interpolation in a compose file). A scheme
that double-quotes a value on trigger characters but never escapes an
embedded `"` -- a value like
`pass"; touch /tmp/x; echo "` was written to the file as literal shell
code, which RUNS the moment any task `.`-sources it. The one representation
both parsers read identically is a SINGLE-quoted value with no `'` inside
it: bash and docker compose's dotenv both treat everything between a pair
of `'` as fully literal, with no escape processing at all, so nothing in
the value -- `"`, `$`, `` ` ``, `\`, `#`, `;`, a space -- can ever be
reinterpreted by either reader. So:
  - a value using only [A-Za-z0-9_./:@+=-] is written bare, unquoted (the
    common case -- container names, urls, base64 ids -- unchanged from
    before).
  - any other character forces a single-quoted literal, KEY='value'.
  - a value containing a `'` cannot be represented identically for both
    readers (escaping it, e.g. bash's own '\'' trick, is not something
    docker compose's own dotenv parser is guaranteed to read the same way)
    -- refused outright, naming the key, rather than silently picking one
    reader's interpretation over the other's.
Python does the file rewrite so no character in the (already-quoted) value
needs further escaping there.

The VALUE is handed to python3 through the ENVIRONMENT (ENV_PUT_VALUE), never
as an argv element: argv is world-readable while
the process lives (`ps -ef`, /proc/<pid>/cmdline), and every secret this fleet
generates -- all of cloud/.env's, every clinic answer file's -- is written
through this one function, so the old `python3 - "$f" "$k" "$v"` form put each
of them on the process list of the machine composing the file. Only the FILE
and the KEY (neither secret) stay in argv: the python3 substep reads the value
from os.environ and must never read a third sys.argv element.

> Before: `env_put(){`

env_del FILE KEY : removes every KEY= line from FILE, written the way env_put
writes. A file without the key is left untouched.

> Before: `env_del(){`

_env_write FILE KEY : env_put's and env_del's one writer. The new file is
written beside the old one, with its mode, and renamed over it: a reader (a
scheduled script, a compose call) sees the old file or the new one, never a
half-written one, and a crash leaves the old one.

> Before: `_env_write(){`

Under `set -e -o pipefail` (every task), a grep with no match or a tr cut short
by head turns a pipeline non-zero and aborts the caller on the SUCCESS path.
Hence the `|| true` guard. Strips a matching pair of quotes off the ends --
single (env_put's own output) or double (an operator-hand-
written .env, or a file predating this change) -- never an unpaired quote,
and never spawns a subprocess just to do it (env_get is called very often,
e.g. once per CLOUD_KEYS entry in 020-env.sh's round-trip check).

> Before: `env_get(){`

The table lists live in sync/tables/ (openmrs.conf, odoo.conf, openelis.conf),
each with an [up] and a [down] section, read through sync/tables/tables.sh.
tables_rows FILE SECTION : the section's lines, comments and blanks removed,
trimmed. A name that is not a bare lowercase identifier fails, naming its row:
a bad name used to be skipped with only a NOTICE, leaving a table unstrided.

> Before: `tables_rows(){`

subsystem_tables SUBSYSTEM : the [up] tables of odoo or clinlims (openelis),
one per line: what task 050 publishes and task 060 strides.

> Before: `subsystem_tables(){`

down_tables : the table of every OpenMRS [down] row, one per line, in file
order -- every table the clinic's down sinks write, relayed ones included
(clinic/scripts/generate-connectors.sh reads the same rows). The sink user's
grants come from this list, so a table added there is granted wherever the
grants are applied: seed task 050, or clinic/scripts/grant-down-tables.sh on a
node seeded before.

> Before: `down_tables(){`

master_down_tables : the down tables that are master data -- every OpenMRS
[down] row except those marked `clinic=<column>`. Those carry the hub's rows
for one clinic (lab results), which differ on every node by design, so they
are never compared between a clinic and the hub.

> Before: `master_down_tables(){`

sink_grant_sql : one GRANT per down table for the clinic's sink database
user: what a JDBC upsert sink with deletes enabled needs, on that table only.

> Before: `sink_grant_sql(){`

SINK_GRANTS_READ_SQL is the read-back: one "table<TAB>privileges" row per
table the sink user holds a table-level grant on, and one "*<TAB>privileges"
row each for a grant on the whole openmrs database and a global one. A
privilege held at any of the three levels lets the sink write the table.

> Before: `SINK_GRANTS_PRIVS="concat_ws(',', if(Select_priv='Y','Select',null), if(Insert_priv='Y','Insert',null), if(Upd`

sink_grants_missing [TABLE...] : stdin is SINK_GRANTS_READ_SQL's output;
prints every named table (every down table when none is named) the sink user
cannot select, insert, update and delete in, counting the table's own row
and every "*" row together.

> Before: `sink_grants_missing(){`

Kafka cluster id: 22 chars of url-safe base64 over 16 random bytes, what
kafka-storage random-uuid produces, without needing the image.
Kafka's own Uuid.randomUuid() rejects ids whose base64 form starts with "-":
`kafka-storage format -t <id>` (the runbook form) parses it as a flag. The
Confluent image uses --cluster-id=<id>, which is why manpur booted with one.

> Before: `kafka_cluster_id(){ python3 -c 'import uuid,base64`

derive_identity SLUG RESIDUE : sets the nine identity variables (global
constraints in the plan). Slug: lowercase letters and digits, 2-16 chars,
starting with a letter. Residue: 1-9 (10 is the cloud's).

> Before: `derive_identity(){`

The fleet: sync/clinics.json, one object per clinic keyed by its lower-case
slug (site_number, which is also the residue, and mrn_prefix; null = not yet
allocated),
read with jq (configure-pk-offsets.sh and the cloud's sink generator read it
the same way).

> Before: `clinic_get(){ # SLUG FIELD -> the field from sync/clinics.json; nothing when absent or null`

has_placeholders FILE ALLOWLIST : prints every key whose value is empty or
<placeholder>, except keys in the space-separated allowlist.

> Before: `has_placeholders(){`

The cluster alias is this node's own slug and nothing else: an env copied
from another node carries that node's alias, and MirrorMaker would then
publish under the wrong name. With the slug known, equality is the rule;
without it, the names other nodes and the templates use are refused.

> Before: `if [ -n "${2:-}" ]; then`

sync/clinics.json holds a clinic's non-secret identity; clinic/.env the hub
endpoint. Secrets are never in the repo: they come from --secrets or
clinic/.env, which wins over all of these.

Values with a default: a clinic/.env without one takes the default.
ODOO_ATOMFEED_USER
is the hub's own Odoo feed login: the clinic's Odoo is a copy of the hub's, so
odoo-connect logs in with the hub's user and that user's password
(ODOO_ATOMFEED_PASSWORD); both come from the hub's passwords file, and a hub
whose file names no user uses emrsync, the feed login of the hub's Odoo image.

> Before: `INPUT_DEFAULTS="ODOO_ATOMFEED_USER=emrsync"`

--- the hub link --------------------------------------------------------------
cloud_protocol: SASL_SSL (TLS, the default) or SASL_PLAINTEXT, from the
environment, else clinic/.env.

> Before: `cloud_protocol(){`

The hub's certificate: the one given for this run (CLOUD_CA), else the copy the
install kept beside the node's own certificates (task 020), else the fleet's
sync/cloud-ca.pem. The kept copy is what lets a resumed run, or a script run
later without the install's environment, trust the same hub.

> Before: `CLOUD_CA_KEPT="${CLINIC_DIR}/certs/cloud-ca.pem"`

cloud_truststore OUT IMAGE : a PKCS12 truststore holding sync/cloud-ca.pem, made with
the image's keytool. The password comes from REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD
through the container's environment, never its command line.

> Before: `cloud_truststore(){`

mysql_ready CONTAINER : true only when the FINAL server answers an authenticated query
over TCP. `mysqladmin ping` exits 0 even on "Access denied", and the official image's first
boot runs a temporary socket-only server whose root has no password yet; a wait built on
ping passes against it and the restore then dies with ERROR 1045. That server runs --skip-networking,
so 127.0.0.1 is the discriminator. MYSQL_PWD keeps the password off the command line.
--- MySQL sizing -------------------------------------------------------------
The image's defaults (128 MB buffer pool, 100 MB redo log) starve a node with
gigabytes of memory: every read misses the cache and a restore checkpoints
constantly. One conf.d file, sized from the memory the database server can
see, mounted read-only -- never SET PERSIST (lost with the data volume) and
never more `command:` flags (compose replaces the whole list).

> Before: `node_mem_mb(){ # memory the database server can see, in MB; NODE_MEM_MB overrides`

the containers run inside the podman machine, so its memory is the ceiling

> Before: `local m; m="$(podman machine inspect --format '{{.Resources.Memory}}' 2>/dev/null || true)"`

clinic_table : one line per clinic in sync/clinics.json -- slug, site number ("-" = none), MRN prefix.

> Before: `clinic_table(){ jq -r 'to_entries[] | select(.key != "cloud")`

Values a clinic may leave out: the forms repo (task 075; empty = the node
runs the frozen copy in clinic/bahmni_home/clinical_forms) and the
Initializer domain list (task 020 writes it into clinic/.env; empty = the
clinic default, initializer.sh). They come from clinic/.env or --secrets.

> Before: `OPTIONAL_INPUT_KEYS="FORMS_REPO_URL FORMS_REPO_KEY OPENMRS_INITIALIZER_DOMAINS"`

interactive : stdin is a terminal, or INSTALL_INTERACTIVE=1 (tests pipe input in).

> Before: `interactive(){ [ -t 0 ] || [ "${INSTALL_INTERACTIVE:-0}" = 1 ]; }`

ask VAR PROMPT DEFAULT WHERE : keeps a value already set; otherwise asks (empty
answer = DEFAULT) or, with no terminal, fails naming WHERE to put it.

> Before: `ask(){`

ask_secret VAR WHERE : like ask, typed hidden, no default, never echoed.

> Before: `ask_secret(){`

wait_for_http_or_restart URL SECONDS CONTAINER : like wait_for_http, but a
container podman has restarted meanwhile is a crash loop, not a slow boot:
return 2 at once with its last log lines instead of burning the timeout
(first live clinic, manpur: OpenMRS looped for 25 min behind "Running").

> Before: `wait_for_http_or_restart(){`

ensure_stopped CONTAINER : stop it and PROVE it stayed down. A stop that
raced the restart policy left odoo-connect looping on manpur while task 080
believed it was parked, replaying every past event. A container that does not exist
counts as stopped.

> Before: `ensure_stopped(){`

--- OpenMRS JVM options ----------------------------------------------------
infoiplitin/openmrs:iplit-1.0.0-662-4 shipped Java 8u372, whose cgroup v2
metrics code threw a NullPointerException on an Azure Ubuntu 24.04 host the
moment Tomcat registered its MBeans; the container restart-looped behind a
green "Running". -XX:-UseContainerSupport skipped that code, after which the
JVM sized its heap from host RAM -- so the heap is pinned explicitly
regardless (a cap proven on a 121k-patient clinic).

The fleet pin is now
infoiplitin/openmrs:iplit-1.2.0-1200-03, Java 8u432, which does not have the
bug. This function used to ADD the flag to any .env missing it (a template-
era node, repaired on resume, not by hand) -- it must NOT do that any more,
or task 080 would silently reintroduce on every run the exact flag this
task's .env.example edit just removed. An operator's own flag (added by
hand, or left over on a node still running the old image) is left alone
either way: this function only ever adds what is missing, and the flag is no
longer something it considers missing. The heap cap is unrelated to the bug
and stays pinned regardless.

> Before: `OMRS_HEAP_CAP='-Xms512m -Xmx2048m -XX:NewSize=128m -XX:MaxMetaspaceSize=512m'`

The Initializer's domain list is docker-compose.yml's to set, from
OPENMRS_INITIALIZER_DOMAINS (clinic/install/initializer.sh). A
-Dinitializer.domains= left in OMRS_JAVA_SERVER_OPTS (set there by hand)
would put the property on the command line twice, so it is taken out here,
and the value it carried is reported.

> Before: `ensure_openmrs_jvm_opts(){ # ENV_FILE`

topic_events TOPIC : the end offset of partition 0 on this node's broker. A
topic that does not exist yet (nothing written since a fresh seed) has 0
events; its failed lookup must not end a set -e task.

> Before: `topic_events(){`

pull_image IMAGE : the native (arm64) pull; an image published only for amd64
has no arm64 entry, so it is pulled for amd64 instead and runs emulated.

> Before: `pull_image(){ ct pull "$1" || ct pull --platform linux/amd64 "$1"; }`

The fleet's one pin file (lockstep, cloud first -- change here,
nowhere else). REPO_DIR may itself be overridden by a test harness pointing
at a tmp checkout, so this is resolved relative to REPO_DIR, not a fixed path.

> Before: `VERSIONS_FILE="${VERSIONS_FILE:-${REPO_DIR:-$(cd "${INSTALL_DIR}/../.." && pwd)}/sync/versions.env}"`

versions_put FILE : copy every KEY=value of sync/versions.env into FILE (env_put semantics)

> Before: `versions_put(){`

`|| [ -n "$line" ]` : a versions.env saved without a trailing newline on its
last line would otherwise drop that last KEY=value silently (the same class
of bug a table list read the same way would have).

> Before: `while IFS= read -r line || [ -n "$line" ]; do`

the application images this node chose (see IMAGE_KEYS) replace the defaults

> Before: `for k in $IMAGE_KEYS; do eval "v=\${$k:-}"; [ -z "$v" ] || env_put "$f" "$k" "$v"; done`

--- application image versions ------------------------------------------------
IPLIT's and Bahmni's application images. sync/versions.env holds the default
for each; the person installing a clinic may choose another version of any of
them: install.sh --versions <file> (KEY=value lines), or the prompt. The
choice is written into clinic/.env and read back from there by later tasks. The sync layer (Kafka, MirrorMaker,
Debezium) is not here: every node runs the same.

> Before: `IMAGE_KEYS="OPENMRS_IMAGE_NAME ODOO_LOCAL_IMAGE ODOO_CONNECT_IMAGE_TAG OPENELIS_IMAGE_TAG BAHMNI_WEB_IMAGE BAH`

These applications change their database schema when they start, and the hub
holds the same tables: a version that differs from the hub's breaks lockstep.
Upgrade the hub first, then every clinic.

> Before: `SCHEMA_IMAGE_KEYS="OPENMRS_IMAGE_NAME ODOO_LOCAL_IMAGE OPENELIS_IMAGE_TAG"`

pin_get KEY : the default in sync/versions.env, without its inline comment

> Before: `pin_get(){`

image_value KEY INPUT : prints the value to store, or fails. A *_TAG key takes a
tag. The others take a full image reference (it has a / or a :), or a bare tag,
which replaces the default's tag: BAHMNI_WEB_IMAGE=bhs-9.9.9 becomes
infoiplitin/bahmni-iplit-web:bhs-9.9.9.

> Before: `image_value(){`

image_set KEY INPUT : validates and exports KEY

> Before: `image_set(){ local v; v="$(image_value "$1" "$2")" || exit 1; eval "$1=\$v"; export "$1"; }`

image_choices_load FILE : KEY=value lines (comments and blanks skipped); every
key must be an application image, every value valid

> Before: `image_choices_load(){`

image_keys_from FILE : exports every application image FILE (a node's .env)
sets, so a value this node chose wins over the default loaded before it

> Before: `image_keys_from(){`

image_choose : on a terminal, offers to keep the defaults; otherwise asks for
each image, Enter keeping the value shown

> Before: `image_choose(){`

image_choices_report : names each application image that differs from its
default, and warns where that breaks lockstep with the hub

> Before: `image_choices_report(){`

--- phases -------------------------------------------------------------------

> Before: `run_tasks(){ # RESUME_HINT : every task in order; ONLY / FROM honoured`

has_text BODY NEEDLE : judge a captured value whole. Under pipefail,
`printf "$body" | grep -q` fails when the match is FOUND: grep exits at the
first hit and the writer's next chunk dies of SIGPIPE.

> Before: `has_text(){ case "$1" in *"$2"*) return 0 ;; esac; return 1; }`

elis_page_ok CODE BODY : the page OpenELIS lands on answers 200, names
OpenELIS, and is not Tomcat's own error page (which names the path it could
not serve, "/openelis/", so the word alone proves nothing). The body is
judged whole, never piped into `grep -q`: grep stops at the first match, the
writer dies of SIGPIPE on its next chunk, and under pipefail a page that
matched reads as one that did not.

> Before: `elis_page_ok(){`

capture_filter_check : the source connector's capture filter as Kafka
Connect holds it (GET .../config of the registered connector, never the
generated file), against this node: its residue must be the
auto_increment_offset the running MySQL issues ids on, and its floors the
ones task 050 recorded on this machine (.install-state). sync/origin-filter.sh holds the rules.
Prints "ok ..." lines, or the refusal and returns 1. CONNECT_URL overrides
the Connect address.

> Before: `capture_filter_check(){`

The source connector's signal table, in the structure Debezium documents for
its source signal channel: three columns in this order, the first the key. A
row inserted there (type execute-snapshot) asks the connector for an
incremental snapshot, the way a clinic sends rows it wrote before a table
was captured. With the connector's default (not read-only) incremental
snapshot, the connector writes its own window markers into the table, so its
database user may insert, update and delete there. Created at seed; the
seed's dump does not carry it, because the hub has none.
Each takes the OpenMRS database (DATABASE_NAME, default openmrs), the one the
source connector's include list and signal collection name.

> Before: `signal_table_db(){ printf '%s' "${1:-${DATABASE_NAME:-openmrs}}"; }`

what information_schema says of it: column, type, nullable, key; then the
privileges the debezium user holds on it

> Before: `signal_table_read_sql(){`

signal_table_verdict [DB] : stdin is signal_table_read_sql's output (tab-
separated). Prints "ok ..." or what is wrong and returns 1.

> Before: `signal_table_verdict(){`

signal_capture_verdict CONFIG_JSON : a registered source configuration must
read signals from the source channel and capture the table it names, or a
signal inserted there is never seen. Prints "ok ..." or the refusal.

> Before: `signal_capture_verdict(){`

signal_capture_check : signal_capture_verdict on the configuration Kafka
Connect holds for mysql-source-connector.

> Before: `signal_capture_check(){`

clinlims_down_sink_verdict STATUS_FILE CONFIG_FILE : the OpenELIS down sink
(clinlims-clinic-sink-all) as Kafka Connect holds it: STATUS_FILE is its
/status answer, CONFIG_FILE its /config. Passes when the connector and every
task (at least one) are RUNNING and it still claims its replication origin
and carries this clinic's filter; otherwise names what was read. Without the
sink, lab results entered at the hub never reach this clinic's OpenELIS.

> Before: `clinlims_down_sink_verdict(){`

clinlims_down_sink_check : clinlims_down_sink_verdict on what Kafka Connect
answers now.

> Before: `clinlims_down_sink_check(){`

## `state.sh`

Machine state (none -> SEEDED), the obs and orders floors measured from the
restored data, and the rules the installer checks on the seed and the databases. Pure functions: no runtime is touched here,
so every rule is tested without one. bash 3.2 compatible.

> Before: `STATE_FILE="${STATE_FILE:-${CLINIC_DIR}/.install-state}"`

seed_floor_tables TABLES_CONF : the tables whose floor sync/tables/openmrs.conf [up]
takes from the seed (table:pk:seed), one per line. A list the reader refuses
fails, with the reader's reason on stderr.

> Before: `seed_floor_tables(){`

The clinical tables whose id counter the striding step lifts above the floor
task 050 records for them (FLOOR_OBS, FLOOR_ORDERS), whether or not
sync/tables/openmrs.conf [up] lists them. A clinic writes obs and orders from
its first consultation. With the counter the dump restored, those ids fall
below the floor, among ids the hub's own rows use, so once the tables are
synced the hub could not tell the clinic's rows from its own, and a row
could carry an id the hub already has. drug_order's and test_order's key is
orders.order_id, so neither has a counter of its own.

> Before: `SEED_COUNTER_TABLES="obs orders"`

seed_floor_residue_sql TABLE FLOOR : counts the seeded rows at or above the
floor that are not on the hub's residue 0.

> Before: `seed_floor_residue_sql(){`

seed_floor_residue_verdict TABLE FLOOR COUNT : at or above the floor, a
residue names the node that wrote the row, and every row the seed carries
there must be the hub's (residue 0). A row on a clinic's residue would pass
that clinic's capture filter, so its edits would be published as the
clinic's own and overwrite the hub's row; the hub writes above the floor
while the dump runs, so this is read, not assumed.

> Before: `seed_floor_residue_verdict(){`

seed_floor_pk TABLE TABLES_CONF : the primary key a floor is measured on:
obs_id and order_id for the counter tables, otherwise the table's own line.

> Before: `seed_floor_pk(){ # TABLE CONF`

seed_floor_plan TABLE RECORDED MAX_ID : a floor is the id below which every
row is the hub's: the next multiple of 10 above the highest id the restored
table holds, so floor + residue is on this clinic's residue. "set FLOOR" when
none is recorded; "keep FLOOR" when one is. A recorded floor is never moved:
once this clinic writes rows, a floor measured again would rise above them,
and the sync layer, which tells this clinic's rows from the hub's by the
floor, would stop publishing them. A recorded floor that is not a positive
multiple of 10 is refused.

> Before: `seed_floor_plan(){ # TABLE RECORDED MAX_ID`

record_seed_floors TABLES_CONF READER : seed_floor_plan for every table whose
floor comes from the seed and each SEED_COUNTER_TABLES table, recorded in
.install-state as FLOOR_<TABLE>. READER TABLE PK prints the restored table's
highest id; it is read only when no floor is recorded, so a re-run reads
nothing and changes nothing. Prints one "ok ..." line per table, or the
refusal.

> Before: `record_seed_floors(){ # CONF READER -- READER TABLE PK prints the restored table's highest id`

seed_counter_plan TABLE AUTO_INCREMENT FLOOR RESIDUE : what the striding step
does with a SEED_COUNTER_TABLES counter. The first id this clinic may write is
the first id on its residue at or above the floor (floor 5000000, residue 3:
5000003). "set FIRST" when the counter is below it (the dump restored the
hub's max + 1 from below the floor); "keep" when it is at or above FIRST,
whatever its last digit: MySQL, striding 10 apart on this residue, issues the
next id on this residue at or above the counter (the counter_floor_verdict
arithmetic). Such a counter is normal: after a restart MySQL derives the
counter from the largest id, so it need not be on this residue. Moving it back would never be
right: a rerun after this clinic wrote rows must not reissue their ids.

> Before: `seed_counter_plan(){`

counter_floor_verdict TABLE AUTO_INCREMENT FLOOR RESIDUE
With auto_increment_increment 10 and offset RESIDUE, the next id MySQL issues
is the smallest value at or above AUTO_INCREMENT that is RESIDUE mod 10. It
must be at or above FLOOR + RESIDUE: below the floor, ids belong to the hub's
legacy rows, and a row written there could carry an id the hub already has.

> Before: `counter_floor_verdict(){`

counter_floor_verdicts TABLES_CONF RESIDUE READER : counter_floor_verdict for
every table whose floor comes from the seed, against the floor this machine
recorded by task 050: each table the list takes from the seed, and each
SEED_COUNTER_TABLES table with a recorded floor, listed or not. READER TABLE
prints that table's AUTO_INCREMENT. Prints one "ok ..." line per table, or
the first refusal and returns 1. A table list that cannot be read is a
refusal: checking no table is never a pass, because a broken list would
otherwise skip every counter.

> Before: `counter_floor_verdicts(){`

mysql_stride_verdict "INCREMENT OFFSET" RESIDUE : MySQL must issue ids 10
apart on this clinic's residue; with any other pair a new row lands on
another node's residue whatever its counter says.

> Before: `mysql_stride_verdict(){`

node_counters_verdict STATE TABLES_CONF RESIDUE READER : the id counter check
for a machine whose install state is STATE. READER TABLE prints the table's
AUTO_INCREMENT; READER --stride prints MySQL's "increment offset". On a
seeded machine every floored counter must still be at or above its floor and
MySQL must stride on this residue: a restored database or a reset counter
would hand out ids that rows written elsewhere already carry. Any other
machine has no floors yet (task 050 records them and the striding step
checks the counters itself), so it prints "skip" and the reason.

> Before: `node_counters_verdict(){`

Order numbers. OpenMRS issues ORD-<k> from the global property
order.nextOrderNumberSeed, which is node-local and not synced, and every
seeded node starts with the value the seed carries. Two nodes issuing from
the same value would write the same order number for different orders, and
the orders table does not refuse a duplicate. So each node issues from its
own range: a clinic of residue r from r x 10,000,000 + 1 to
(r + 1) x 10,000,000 - 1, the hub below 10,000,000, where every number issued
before clinics wrote orders already lies.

> Before: `ORDER_RANGE_WIDTH=10000000`

order_seed_range RESIDUE : prints "FIRST LAST", the order numbers this clinic
may issue. A residue outside 1..9 has no clinic range.

> Before: `order_seed_range(){`

order_seed_owner VALUE : whose range VALUE lies in, in words.

> Before: `order_seed_owner(){`

order_seed_plan VALUE RESIDUE : what task 060 does with the seed's value.
"keep" when it is already in this clinic's range (a rerun after orders were
issued must not move it back); "set FIRST" when it is the hub's value the
seed carries, or absent (OpenMRS would otherwise start at 1, in the hub's
range); refused when it is in another clinic's range or not a number, which
only a database copied from another clinic, or edited, can hold.

> Before: `order_seed_plan(){`

order_seed_sql FIRST : the statement that sets the property, creating the row
when the seed lacks it (global_property.uuid is NOT NULL).

> Before: `order_seed_sql(){`

order_seed_verdict VALUE RESIDUE : the value read back must be in this
clinic's range. Within 1,000,000 of the top it still passes, with a warning
on stderr: the range is nearly used up, and past its top the numbers would be
the next clinic's.

> Before: `order_seed_verdict(){`

--- OpenELIS floors: where this clinic's own ids of a table begin ------------
Every clinic pulls from the cloud server the OpenELIS rows its lab users wrote
(sync/tables/{odoo,openelis}.conf [down]); each clinic keeps a row only when its routing column
names an id this clinic minted (clinic/scripts/clinlims-down-filter.sh). The
clinic's OpenELIS source, in turn, publishes a lab account or signature only
when this clinic minted it (UP_CLINLIMS_OWN_ROWS).
Every id of a table the seed restored is the hub's, on any residue; this
clinic's own ids start where the striding step restarts that table's
sequence. So the floor of each table a routed row points at is recorded from
the sequence BEFORE the stride, as the striding step computes its restart:
    floor = (last_value / 10 + 1) * 10
and the first id this clinic mints is floor + residue, or higher where the
table holds rows above its sequence (the stride starts above them). It is written once,
as CLINLIMS_FLOOR_<TABLE> in .install-state: a re-run after the clinic has
minted ids reads a higher last_value, and a floor moved up would drop this
clinic's earlier rows, so an existing value is kept.

clinlims_floor_tables : the tables whose floor a routed OpenELIS down row is
compared with (sync/tables/tables.sh" openelis routes, third field), then the
tables the clinic's OpenELIS source publishes only above the clinic's floor
(UP_CLINLIMS_OWN_ROWS, sync/tables/tables.sh), once each.

> Before: `clinlims_floor_tables(){`

clinlims_seq_sql TABLE : psql input printing one line "<sequence>|<last_value>"
for TABLE's id sequence: the column's own (pg_get_serial_sequence), else the
clinlims.<table>_seq OpenELIS assigns ids from; no line when neither exists.
last_value is read from the sequence itself, as the striding step reads it
(pg_sequences shows NULL for a sequence whose value was set but not yet used).

> Before: `clinlims_seq_sql(){`

clinlims_floor_plan TABLE RECORDED READ : what the striding step does with
TABLE's floor. RECORDED is the value already in .install-state (empty: none);
READ is clinlims_seq_sql's answer. Prints "keep FLOOR" or "set FLOOR", or the
refusal (status 1).

> Before: `clinlims_floor_plan(){`

record_clinlims_floors READER : for each floor table, keeps a recorded floor
or records one from READER TABLE (a command printing clinlims_seq_sql's
answer from the clinic's OpenELIS database, read before the stride). Prints
"ok <KEY>=<floor> (recorded|kept)" per table; on the first refusal prints it
and returns 1, having recorded nothing for that table or any after it.

> Before: `record_clinlims_floors(){`

## `tasks/000-preflight.sh`

Everything that can refuse, refuses here, before a machine is touched.

> Before: `set -euo pipefail`

1. identity is allocated, and only to us (a node with no residue cannot join)

> Before: `r="$(clinic_residue "${CLINIC_SLUG}")"`

clinical data to the hub: off (the default) or test, nothing else

> Before: `. "${INSTALL_DIR}/../../sync/tables/tables.sh"`

1b. a machine already in service: MySQL strides on this residue and each
floored id counter is still at or above its floor (a restored database or a
reset counter would hand out ids that rows written elsewhere already carry).
A machine not in service yet has no floors, and the line says so.

> Before: `. "${INSTALL_DIR}/state.sh"`

TABLE -> its AUTO_INCREMENT; --stride -> "increment offset".
PREFLIGHT_AUTO_INCREMENT ("table=n ...") and PREFLIGHT_STRIDE stand in for MySQL.

> Before: `preflight_mysql_read(){`

2. fresh install only
A dry run renders a real clinic/.env (later tasks read it to say what they
would do), and a real run that follows would refuse it as "already exists".
Task 020 stamps a dry-run render on its first
line; a stamped file is a leftover, not a live node, so a real run moves it
aside -- never deletes it -- and carries on. An unstamped .env is a live
node's and is still refused.

> Before: `if [ -e "${CLINIC_DIR}/.env" ]; then`

4. host facts

> Before: `require_cmd git; require_cmd python3; require_cmd jq "brew install jq / apt install jq"; require_cmd openssl; `

df -Pk: -P stops a long device name from wrapping and misaligning $4.

> Before: `avail_gb="$(( $(df -Pk "${CLINIC_DIR}" | awk 'NR==2{print $4}') / 1048576 ))"`

A warning, not a refusal: one CPU installs, but OpenMRS's first boot took
36 min on manpur's 1-vCPU VM against 7 min on the hub's four.

> Before: `cpus="${PREFLIGHT_CPUS:-$(sysctl -n hw.ncpu)}"`

The clinic runs on Apple Silicon. Task 040 builds OpenMRS and Odoo natively
(both are published for amd64 only); bahmni/atomfeed-console runs emulated.

> Before: `arch="${PREFLIGHT_ARCH:-$(uname -m)}"`

The podman machine's own memory, not the DRY-safe defaults task 010 uses to
CREATE one: a machine that already exists and is undersized is a live
problem today, not a future one -- checked here, before anything is pulled
into it. No machine yet is fine (task 010 creates one, sized by
host-macos.sh's own rule) and is not a FAIL.

> Before: `machine_mib="${PREFLIGHT_MACHINE_MIB:-}"`

## `tasks/020-env.sh`

Render clinic/.env: derived identity, the ten absolute path keys at clinic/,
generated secrets, the pasted five, fleet constants. Written to a temp file and
moved into place only after the compose config gate passes.

> Before: `set -euo pipefail`

paths -- every one absolute, every one under clinic/ (a stale one
makes the runtime mount an empty directory silently)

> Before: `put CONTAINER_DATA_PATH "${CLINIC_DIR}"`

MySQL sizing: one conf.d file the compose file mounts read-only (a restore
runs for hours on the image's 128 MB buffer pool). Rendered here, beside
the env, from the memory the database server can see; a dry run renders it
too, since it is regenerated on every run and holds no secret.

> Before: `mem_mb="$(node_mem_mb)"`

identity (derived by install.sh; never the example's values)

> Before: `for k in BHS_LOCATION COMPOSE_PROJECT_NAME MYSQL_SERVER_NAME LOCAL_CLUSTER_ALIAS BHS_LOCATION_OFFSET MYSQL_SER`

the values later tasks and scripts need, kept on the node: clinic/.env is
their source of truth

> Before: `put CLINIC_SLUG "${CLINIC_SLUG}"; put RESIDUE "${RESIDUE}"; put MRN_PREFIX "${MRN_PREFIX}"; put SITE_NUMBER "$`

optional: unset leaves docker-compose.yml's clinic default (initializer.sh)

> Before: `[ -z "${OPENMRS_INITIALIZER_DOMAINS:-}" ] || put OPENMRS_INITIALIZER_DOMAINS "${OPENMRS_INITIALIZER_DOMAINS}"`

fleet constants the example does not carry (Rawach's live .env does)

> Before: `put OPENMRS_MEM_LIMIT 6g`

the hub

> Before: `put REMOTE_KAFKA_BOOTSTRAP_SERVERS "${REMOTE_KAFKA_BOOTSTRAP_SERVERS}"`

keep the certificate this install was given, so every later sitting trusts the same hub

> Before: `if [ "$proto" = SASL_SSL ] && [ "${DRY}" != 1 ] && [ "${CLOUD_CA}" != "${CLOUD_CA_KEPT}" ]; then`

hub credentials (from the operator's secrets file; the seed's databases carry the matching users)
and secrets born here (generated)

> Before: `put OPENMRS_ATOMFEED_PASSWORD "${OPENMRS_ATOMFEED_PASSWORD}"`

the sink-role scripts (task 050) reuse these; the template ships
CLINLIMS_SINK_PASSWORD="" and a blank would have cleared the role's password

> Before: `put ODOO_SINK_PASSWORD "$(gen_secret)"; put CLINLIMS_SINK_PASSWORD "$(gen_secret)"`

stamped so task 000 of the real run knows this file is a leftover and
moves it aside instead of refusing the node

> Before: `S="$(mktemp "${CLINIC_DIR}/.env.render.XXXXXX")"`

## `tasks/030-dirs-certs.sh`

Bind-mount directories from the RENDERED compose config (never a hand list),
so a new mount in the compose is created here without editing this file;
then the per-node certificate.

> Before: `set -euo pipefail`

Sources that are directories today or do not exist yet -> mkdir. Existing
files (config files, jars) are left alone.

> Before: `compose config 2>/dev/null | awk '/^ *source: /{print $2}' | grep -E "^${CLINIC_DIR}/" | sort -u | while read `

Read the SAN from the text dump: `x509 -ext` exists only in OpenSSL 1.1.1+,
not in LibreSSL (macOS's stock openssl), and a failed read inside a pipeline
would end this task silently under pipefail.

> Before: `text="$(openssl x509 -noout -text -in "$C/cert.pem" 2>/dev/null)" || fail "could not read ${C}/cert.pem with $`

## `tasks/040-images.sh`

Images the stack needs before anything starts: pulled ones, the three built
locally, the OpenMRS fallback for podman, and the Connect plugin jars.

> Before: `set -euo pipefail`

OpenMRS: IPLIT's image is amd64 only, so it is rebuilt natively for arm64
(openmrs/build.sh -- 2.3 s bare Tomcat+WAR vs 26 s emulated) and the
result is written to OPENMRS_RUN_IMAGE, which docker-compose.yml prefers over
OPENMRS_IMAGE_NAME.

> Before: `info "rebuilding OpenMRS natively -- ${omrs} is amd64-only and would run emulated"`

the local builds (their scripts call podman by name)

> Before: `if ct image inspect "bahmni-local/proxy:$(env_get "$E" PROXY_IMAGE_TAG)" >/dev/null 2>&1; then skip "proxy ima`

Odoo: Bahmni publishes it for amd64 only; odoo/build.sh builds the native
arm64 image ODOO_LOCAL_IMAGE names, and skips it when it already exists.

> Before: `odoo_img="$(env_get "$E" ODOO_LOCAL_IMAGE)"`

Pull each registry image individually. `docker compose pull` is all-or-nothing
and also tries to pull the two locally-built images (bahmni-local/proxy,
bahmni-local/systemdate) -- they are built by proxy/build.sh and systemdate/
build.sh, not a compose `build:` section, so --ignore-buildable does NOT skip
them; their inevitable "pull access denied" then aborts and "Interrupts" every
real pull (first live run, manpur). Per-image pull skips what is already present
(the local builds, openmrs) and the bahmni-local/* local-only names, retries
transient failures (a fresh VM IP can hit Docker Hub's anonymous rate limit --
`docker login` raises it), and one failure never stops the others.

> Before: `for img in $(compose config --images 2>/dev/null | sort -u); do`

Connect plugin jars: scripting (fetched, gitignored). The replication-origin claim
is config-only -- see the
hibernate.agroal.initialSQL key in each clinic-side sink connector's own JSON.

> Before: `J="${CLINIC_DIR}/config/kafka-connect"`

## `tasks/045-ui-config.sh`

IPLIT's UI and config, copied out of the two images pinned in sync/versions.env
into clinic/extracted/ (gitignored, node-local). The clinic's one nginx serves
them and OpenMRS + OpenELIS read the same config tree -- no second web server,
no hand-taken copy in the repo. Safe to re-run: an
unchanged source is skipped.

> Before: `set -euo pipefail`

A node whose .env was rendered before this task existed (manpur, mid-install)
gets the pins and the two paths here; on a fresh install 020 already wrote them.

> Before: `versions_put "$E"`

Belt and braces on top of extract-ui-config.sh's own hold_ocl: a first boot
imported the CIEL dictionary for hours because two OCL zips sat in the
config tree OpenMRS reads. Prove they are really out of
the served tree rather than trusting the extraction script's own move.

> Before: `ocl_zips="$(find "$CF/masterdata/configuration/ocl" -name '*.zip' 2>/dev/null)"`

## `tasks/050-databases.sh`

Databases up, each restored from the hub's seed unless it is already there
(a re-run keeps what it finds; no database is ever dropped), the obs and
orders floors recorded from the restored data, then the sync users, roles and
publications. Roles BEFORE restore so the
dumps' OWNER TO / GRANT lines resolve; sql_log_bin=0 so the restore is not
replayed to Kafka (the source connector starts later with snapshot no_data).

> Before: `set -euo pipefail`

bahmni-mysql has no compose healthcheck; ask each server directly

> Before: `hm=0`

the rendered conf.d file must be in force in the RUNNING server, not just on disk

> Before: `want_mb="$(sed -nE 's/^innodb_buffer_pool_size *= *([0-9]+)M$/\1/p' "${CLINIC_DIR}/config/mysql/sync-tuning.cn`

the flags must be in Config.Cmd, not only in the compose file

> Before: `ct inspect "$MY" --format '{{.Config.Cmd}}' | grep -q -- "--auto-increment-offset=${RESIDUE}" && ok "mysql run`

Stock MySQL (128 MB buffer pool, 100 MB redo log) checkpoints constantly
while loading a multi-gigabyte dump, and on a small cloud disk (about 500
IOPS) the restore then takes hours at near-total iowait -- so the load runs
with a larger pool and redo log, set for the restore only. The skip rule
cannot be "the person table exists": that is also true of a restore that was
interrupted at a later table, and a rerun would carry on with half a
database. Pure functions, tested in tests/test_restore_050.sh.

> Before: `restore_pool_mb(){ mysql_pool_mb "$1"; }   # the node's standing size (lib.sh); the restore adds the redo log `

definer_sql : stdin is a dump; prints a CREATE USER + GRANT for every
DEFINER account it names. A trigger or view whose definer does not exist
fails the first statement that fires it (ERROR 1449), and a dump taken
elsewhere names that server's accounts, not this one's. The accounts are
locked: nobody logs in as them, they only own the objects.

> Before: `definer_sql(){`

--- MySQL: openmrs

> Before: `DONE="${CLINIC_DIR}/.openmrs-restore.done"`

a node restored before this marker existed, or an interrupted restore: count to tell them apart

> Before: `info "openmrs exists with no completion marker; counting the dump's tables to tell a finished restore from an `

The obs and orders floors, measured from the restored openmrs once and kept
in .install-state (state.sh record_seed_floors). The striding step lifts the
counters above them and the sync layer tells this clinic's rows from the
hub's by them.

> Before: `v="$(record_seed_floors "${REPO_DIR}/sync/tables/openmrs.conf" max_id)" || fail "$v"`

The dumps carry liquibasechangelog.ID as varchar(63). A module changeset
whose id is longer cannot be recorded -- not even as MARK_RAN -- so that
module (and every module needing it) fails to start on every boot. 255 is
Liquibase's own width; the table is never captured by sync.

> Before: `printf 'SET sql_log_bin=0; ALTER TABLE openmrs.liquibasechangelog MODIFY ID VARCHAR(255) NOT NULL;\n' | mysql_`

The dump carries the source's search.indexVersion, so OpenMRS would take this
node's empty search index as current and no patient could be found. A blank
value makes OpenMRS rebuild the index when it next starts (task 080).

> Before: `printf "SET sql_log_bin=0; UPDATE openmrs.global_property SET property_value='' WHERE property='search.indexVe`

The sink user writes only the tables the down sinks write: every
sync/tables/openmrs.conf [down] row (lib.sh down_tables), each granted on its own and read
back, so a table added to that file is granted here and a sink is never
refused its first INSERT.

> Before: `grants="$(sink_grant_sql)" || fail "could not build the sink user's grants from sync/tables/openmrs.conf [down`

The source connector's signal table (lib.sh signal_table_ddl), created here
rather than carried by the dump, and read back: without it no catch-up of
rows written before a table was captured can be asked for.

> Before: `printf '%s;\n%s;\nFLUSH PRIVILEGES;\n' "$(signal_table_ddl)" "$(signal_table_grant)" | mysql_root >/dev/null |`

--- PostgreSQL: roles, sink roles, databases, restores

> Before: `psql_pg <<SQL`

The Odoo seed carries ir_attachment rows for its compiled CSS/JS bundles, and
each row points at a file in the SOURCE node's filestore. This node has no
such file, so every asset request would answer 500 and the login page would
render unstyled. Drop the bundle rows now, before Odoo ever starts here: Odoo
rebuilds the bundles on its first request. Only the bundle rows -- other
attachments (images, dashboards) are content, not cache, and stay.

> Before: `n="$(printf '%s\n' "delete from ir_attachment where res_model='ir.ui.view' and name like '%assets%'" | ct exec`

sink roles AFTER the databases exist and are restored: they connect with
`psql -d odoo` / `-d openelis` and GRANT ON ALL TABLES, so the DBs and their
tables must exist first (first live clinic, manpur: they ran before createdb).
Always call these -- they are idempotent (reuse the .env password, CREATE-or-
ALTER the role). The old `grep .env ||` guard skipped them when the password was
present, which stranded a node whose earlier run appended the password but failed
before creating the role (exactly what the create-before-DB bug above caused).

> Before: `NODE="${CLINIC_SLUG}" PG_CONTAINER="$PG" bash odoo/create-odoo-sink-role.sh "${CLINIC_SLUG}"`

Publications are created by the installer, not expected inside the dump:
a dump seeded from the hub carries no
publication at all -- staging has 0. The table list is derived at run time from
sync/tables/{odoo,openelis}.conf [up], the same file the striding SQL (task 060)
and the MirrorMaker whitelist read, so there is exactly one place that says which
tables are synced. dbz_heartbeat is deliberately left OUT of this list: task 080 runs
scripts/apply-slot-heartbeat.sh once Connect is up, and that script creates the
heartbeat table and ALTER PUBLICATION ... ADD TABLE's it in itself (idempotent, checks
NOT EXISTS first) -- adding it here too would just mean this ALTER strips it back out
on the next re-run of this task, only for the heartbeat script to re-add it. One owner
per piece of the publication.

> Before: `sync_publication(){ # db  subsystems-prefix  pg-schema  pubname`

## `tasks/060-striding.sh`

Per-row ownership before the first application write: MySQL striding (server flags are
set; this moves the captured tables' AUTO_INCREMENT above their floors, and the
obs and orders counters above the floors task 050 recorded, whether or not
they are captured yet), the order-number counter in this clinic's own range,
Postgres sequences at the residue (mandatory even though the dumps carry
INCREMENT BY 10 -- the restored last_value sits in Rawach's residue), and the
replication origins the customizer jar needs.

> Before: `set -euo pipefail`

obs and orders: a clinic writes both from its first consultation, whether or
not sync/tables/openmrs.conf [up] lists them yet, and an id below the floor
is one the hub's own rows use. Each counter moves to the first id on this
clinic's residue at or above the floor task 050 recorded from the restored
data, and is read back. A counter
already at or above that id is left as it is.

> Before: `. "${INSTALL_DIR}/state.sh"`

Read each seed-floored table's counter back rather than trusting the ALTER:
the next id it issues must be at or above floor + residue. A table list that
cannot be read fails here rather than checking no table.

> Before: `. "${INSTALL_DIR}/state.sh"`

order numbers: this clinic's own range, set before OpenMRS first starts and
read back rather than trusting the write
(the row's value, or empty when the seed lacks the row; no answer at all is a
database that is not answering, never taken as "absent")

> Before: `gp_sql="select concat('v=', coalesce(max(property_value), '')) from openmrs.global_property where property='or`

Before the OpenELIS sequences are strided: where this clinic's own ids of
each table the hub's OpenELIS down rows are routed by begin (state.sh
record_clinlims_floors), read from the sequence as it stands, recorded once.
The OpenELIS down filter (scripts/clinlims-down-filter.sh, task 090) reads
them from .install-state.

> Before: `elis_seq(){ clinlims_seq_sql "$1" | ct exec -i "$PG" psql -U postgres -d openelis -v ON_ERROR_STOP=1 -At; }`

Each OpenELIS sequence restarts above the largest id of the tables it numbers
(scripts/sql/openelis/apply-sequence-striding.sql), and the script fails naming any that
is not, after it strides.

> Before: `o="$(ct exec -i "$PG" psql -U postgres -d openelis -v ON_ERROR_STOP=1 -v residue="${RESIDUE}" -qAt -f /dev/std`

Same table list the publication and MirrorMaker whitelist use (sync/tables/{odoo,openelis}.conf [up]'s
odoo: rows, the :all aggregate row excluded, trimmed and validated by subsystem_tables)
-- one source of truth, passed to the SQL as a comma-separated psql variable rather
than duplicated as a second hard-coded array.

> Before: `ODOO_TABLES="$(subsystem_tables odoo | tr '\n' ',' | sed 's/,$//')"`

The four address and attribute id sequences (village_village, state_district,
district_subdistrict, res_partner_attributes) get RESTART WITH'd by the SQL
above but, on a fresh clinic, are never nextval()'d before this task runs --
so pg_sequences.last_value reads NULL (is_called=false) even though the
RESTART value IS set. So the check reads last_value and is_called from the
sequence itself (a direct select does not consume nextval).
increment_by is safe to read from pg_sequences either way; the
residue has to come from the sequence object itself, which reports the
internal counter regardless of is_called.

> Before: `address_seq_bad=""`

## `tasks/070-site-identity.sh`

Business identifiers: MRN and accession numbers are NOT the sync key, so
striding does not protect them. OpenELIS and Odoo are set
here (node-local SQL). The registration prefix lives in a TRACKED config file
shared by the fleet, so it is checked and the exact edit printed, never
written -- a dirty tree would fail every node's drift check. The idgen source
needs a fresh UUID and a config-image rebuild; printed as a hand-step.

> Before: `set -euo pipefail`

`|| true`: under set -e a missing file would end the task with no FAIL line.

> Before: `appjson_prefix(){ { jq -r '.config.defaultIdentifierPrefix // empty' "$1" 2>/dev/null || true; } | head -1; }`

lab_site_code SITE_NUMBER : OpenELIS's site code for the SITEYEARNUM lab number.
That format is exactly 13 characters (a 5-character site code, the two-digit
year, a 6-digit counter), and OpenELIS refuses any other length when a sample
is saved, after generating it from the site code: a one-digit code makes every
sample save fail. So the site number is written padded to five digits.

> Before: `lab_site_code(){ case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1 ] && [ "$1" -le 99999 ] || retur`

The config tree the services read, filled by task 045.

> Before: `CFG_DIR=""; [ -f "${CLINIC_DIR}/.env" ] && CFG_DIR="$(env_get "${CLINIC_DIR}/.env" BAHMNI_CONFIG_DIR 2>/dev/nu`

the tree the services mount is empty: nothing after this can work

> Before: `fail "no registration app.json under ${CFG_DIR#${CLINIC_DIR}/}: the UI/config extraction has not run -- resume`

node-local tree: the prefix is this node's to write (task 045 normally has)

> Before: `if [ "${DRY}" = 1 ]; then info "would: set defaultIdentifierPrefix ${cur:-<none>} -> ${MRN_PREFIX} in ${APP#${`

## `tasks/075-forms.sh`

The forms folder OpenMRS mounts at /home/bahmni/clinical_forms (forms.sh).
With a forms repo (FORMS_REPO_URL, FORMS_REPO_KEY in clinic/.env or --secrets): a clone of
it in clinic/forms, fast-forwarded on every run, whose clinical_forms/ is
mounted read-only. Without one: the frozen copy in
clinic/bahmni_home/clinical_forms, read-write. clinic/.env gets FORMS_DIR and
FORMS_READ_ONLY for docker-compose.yml. At seed, after the database is
restored, the incoming forms' concepts are checked (warnings only) and every
published form row must find its file: with a forms repo a missing file
stops the seed. Safe to re-run.

> Before: `set -euo pipefail`

clinic/.env names the forms repo for
scripts/update-forms.sh, which reads nothing else. A relative key path is
taken from where the installer runs, and kept absolute: the schedule runs
update-forms.sh from elsewhere.

> Before: `case "${FORMS_REPO_KEY}" in`

The concept and row/file checks run against the restored database.

> Before: `forms_sync 1 0`

FORMS_MOUNT_MODE was the mount setting before FORMS_READ_ONLY; compose no longer reads it

> Before: `grep -q '^FORMS_MOUNT_MODE=' "$E" && { env_del "$E" FORMS_MOUNT_MODE; info "removed FORMS_MOUNT_MODE from clin`

## `tasks/080-stack.sh`

The application stack. odoo-connect is started LAST and only after its
atom-feed markers are parked at the head of each feed: the seed carries the
event_records that made Rawach replay ~303k events through the hub.

> Before: `set -euo pipefail`

BEFORE sourcing .env: compose gives an exported shell variable precedence over
the file, so a stale export here would hide the repaired value from `up`.

> Before: `ensure_openmrs_jvm_opts "$E"`

The clinic mounts CONTAINER_DATA_PATH/config/odoo read-write at /etc/odoo;
task 030 creates it empty, which hides the odoo image's OWN odoo.conf (no
db_name, no addons_path -- /web/login 303s to /web/database/selector rather
than answering 200, fix-round-1 review vs. staging). Seed it BEFORE the
ownership sweep below, so the file this creates gets chowned along with the
rest of config/odoo rather than needing its own pass.

> Before: `bash "${CLINIC_DIR}/scripts/seed-odoo-conf.sh" || fail "seed-odoo-conf.sh reported a FAIL above"`

Odoo answered HTTP 500 on every request on manpur: its image
runs as uid 101, task 030 makes this node's bind-mount data dirs with a
plain mkdir -p (owned by the login user), and uid 101 could not write
/var/lib/odoo/.local. Kafka/kafka-connect/mirrormaker-connect are the same
class of defect (a non-1000 image uid), so they are swept here too, once,
before anything in this profile set is started -- images are present since
task 040, and every directory this sweeps already exists since task 030, so
one call here also covers what 090 starts later (kafka,
kafka-connect, mirrormaker-connect: no separate call there).

> Before: `bash "${CLINIC_DIR}/scripts/fix-mount-ownership.sh" || fail "fix-mount-ownership.sh reported a FAIL above"`

OpenMRS mounts the forms folder (FORMS_DIR, FORMS_READ_ONLY; forms.sh). The
mount refuses a missing source, so the stack does not start until task 075
has set it up, and a node with a forms repo runs only from that repo's
clone, read-only. At seed, every published form row in the restored
database must find its file. scripts/recreate-openmrs.sh runs the same
check.

> Before: `. "${INSTALL_DIR}/forms.sh"`

The Initializer must not write rows the hub owns here: the domain list
docker-compose.yml hands OpenMRS is checked against the module's domains and
the extracted config tree before anything starts (initializer.sh), as
scripts/extract-ui-config.sh does for a new tree and
scripts/recreate-openmrs.sh does before it recreates OpenMRS.

> Before: `. "${INSTALL_DIR}/initializer.sh"`

The FIRST boot is the long one: the Initializer loads the masterdata CSVs into
the seeded database once (checksums persist under CONTAINER_DATA_PATH, later
boots skip them). Measured: 17 min on Rawach, 36 min on manpur's 1-vCPU VM --
which a fixed 25 min budget cut off while OpenMRS was still starting.

> Before: `boot_s="${OPENMRS_BOOT_TIMEOUT_S:-3600}"`

The four hub credentials were written at install; the hub may have rotated
one since. Check each against the data just restored before any feed runs.

> Before: `omrs_login(){ # USER PASS -> 0 if OpenMRS authenticates them`

OPENELIS_ATOMFEED_* is an OpenELIS account (OpenMRS and odoo-connect log in
to OpenELIS with it to read its feeds); OpenELIS offers no plain login check,
so it is proven when those feeds run, not here.

> Before: `odoo_login_ok(){`

odoo-connect (stopped above) and OpenELIS keep their feed bookmarks in the
seed's copies of the hub's databases: park both at this node's own feeds
(scripts/park-feed-markers.sh; an empty feed has its bookmark removed).

> Before: `bash scripts/park-feed-markers.sh || fail "the feed bookmarks were not parked (reason above); odoo-connect is `

OpenMRS's reader of OpenELIS's results is defined but not started at boot:
park its bookmark at this node's OpenELIS feed and start it (restarts
OpenMRS while odoo-connect is still stopped).

> Before: `bash scripts/start-lab-result-reader.sh || fail "OpenMRS's lab-result reader was not started (reason above); o`

a dead odoo-connect would pass the replay check below with 0 events: prove it is up and has not restarted

> Before: `state="$(ct inspect --format '{{.State.Running}} {{.RestartCount}}' "$OC" 2>/dev/null || printf 'false 0')"`

OpenMRS rebuilds its search index in the background after this restore
(task 050 cleared search.indexVersion). Until it finishes, no patient can be
found by identifier or name, so the seed is not done until one can.

> Before: `MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"`

## `tasks/090-local-sync.sh`

The clinic's own sync layer, in the order the repo scripts expect. Judged on
TASK state, never connector state.

> Before: `set -euo pipefail`

kafka-ui is NOT in this first up: it is gated on kafka-connect's health, and
compose gives up on a slow Connect long before Connect does (manpur, 1 vCPU:
"dependency failed to start: container kafka-connect is unhealthy"). The wait
for Connect is ours, on a named budget; the UI follows and is never fatal.

> Before: `( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium up -d kafka kafka-connect >/dev/null )`

kafka-ui is an admin convenience that costs ~300 MB the node may not have:
started only when asked for (CLINIC_KAFKA_UI=1), or by hand later.

> Before: `if [ "${CLINIC_KAFKA_UI:-0}" = 1 ]; then`

Every connector config, from sync/tables/ and scripts/templates/, with passwords
left as placeholders (scripts/generate-connectors.sh), the floors from
.install-state. Each group is uploaded below once what it depends on is in
place.

> Before: `SEED_MANIFEST="${STATE_FILE}" bash scripts/generate-connectors.sh >/dev/null \`

The capture filter as Connect holds it, not as the file says (lib.sh
capture_filter_check): a wrong residue drops every change this clinic makes,
silently.

> Before: `v="$(capture_filter_check)" || fail "$v"`

Both sources send this clinic's rows up; both subsystems have a down sink.
The Odoo down sink takes the hub's master rows. The OpenELIS down sink takes
the hub's lab test catalogue and lab accounts whole, and of the result,
analysis and sample rows a hub lab user wrote for a sample a clinic sent out
only this clinic's (clinic/scripts/clinlims-down-filter.sh: the routing
column at or above this clinic's floor, on its residue; deletes dropped). It
claims replication origin cloud_openelis (the Odoo
down sink holds cloud_odoo; an origin is held by one session at a time), so this
clinic's OpenELIS source, which decodes with origin=none, never sends those
rows back up. The floors are recorded by task 060 before it strides; without
them (or the residue) the filter cannot be written and this task stops.
The OpenELIS down sink never applies a delete (`delete.enabled` false, and
the filter drops every delete), unlike the Odoo down sink. A delete event
carries only the row's `id` (the hub's tables keep the default replica
identity), so a `result` delete cannot be routed by its `analysis_id`. A
catalogue row the hub deleted may still be referenced by this clinic's own
analyses; its delete would fail on the foreign key and stop the sink. The
hub retires a test rather than deleting it.
The OpenELIS source publishes a lab account or signature only when this
clinic minted it, and the OpenELIS down sink keeps only this clinic's rows:
generate/postgres.sh wrote both filters from the floors task 060 recorded.

> Before: `bash scripts/register-connectors.sh odoo-source-connector clinlims-source-connector odoo-clinic-sink-all clinl`

after the Postgres connectors are registered, not before: the heartbeat script patches the two PG
source connectors' configs (GET then PUT), so they must exist, and it takes
BOTH source names (first live clinic, manpur: it was called with one name
and one line too early -- "$5: unbound variable"). Its DB half (heartbeat
table + publication membership) is idempotent; the seed already carries both.

> Before: `bash scripts/apply-slot-heartbeat.sh "${CT}" "${COMPOSE_PROJECT_NAME}-bahmni-postgres-1" postgres odoo-source-`

Restart FAILED tasks ONCE before anything judges them:
nine mysql-local-sink-* tasks FAILED on a bad pool setting; the template was
fixed and the connectors re-registered (HTTP 200) -- eight recovered,
mysql-local-sink-role_role stayed FAILED for hours, because Connect does not
restart a FAILED task when a PUT leaves that connector's config unchanged
from its own point of view, and nothing else here restarts it. This round
runs once, by connector+task id, strictly before the poll below can judge a
FAILED task -- and the poll's own first iteration sleeps 15s before its
first read, so a task restarted here always gets at least one poll interval
before the poll can call it FAILED again.

> Before: `JQ_FAILED_TASK_IDS='to_entries[] | .key as $c | (.value.status.tasks[]? | select(.state=="FAILED") | "\($c) \(`

Judged on TASK state, polled: a small host needs more than the old
fixed 30 s to start fourteen connectors. A connector with no task at all is
NOT running (any() over an empty list is false and used to pass). A FAILED
task never heals by waiting, so it ends the wait at once.

> Before: `JQ_NOT_RUNNING='to_entries[] | select((.value.status.tasks | length) == 0 or (.value.status.tasks | any(.state`

Two nodes installed under one clinic slug are exact twins -- same residue,
same topic prefix, same MirrorMaker alias -- so both would mint the same ids
and both would mirror into the hub's topics for this clinic. The ledger
cannot see a second live host; the hub can: a live node's MirrorMaker
heartbeat topic <alias>.heartbeats advances about once a second. Read its
end offset on the hub twice, before this node's MirrorMaker exists, and
refuse if it moved. TWIN_GUARD_SKIP=1 is the conscious override.

> Before: `twin_offset(){ # TOPIC ; kafka-get-offsets output on stdin -> end offset, 0 for an absent topic, empty when un`

MirrorMaker assigns a topic that appears after it started only on its next
topic refresh, so a fresh node's first event (the install probe, minutes
from now) would sit unmirrored until then. Create the node's up topics
first, from the same pattern MirrorMaker is given, so they are assigned at
start; the source connectors then write into existing topics.

> Before: `mm2_up_topics(){ # MM2_PROPERTIES ALIAS -> one plain topic name per line`

On a rerun of this task the node's OWN MirrorMaker from the earlier run is
still producing heartbeats, which would read as a twin. Stop it before the
two reads; it is started again below with the freshly rendered properties.

> Before: `if [ "$(ct inspect --format '{{.State.Running}}' mirrormaker-connect 2>/dev/null || true)" = true ]; then`

the client properties live only inside the kafka container, for the two reads

> Before: `if cloud_tls; then ct exec -i kafka sh -c 'umask 077; cat > /tmp/twin-guard.p12' < "$TS"; fi`

The hub remembers a node by its alias: MirrorMaker keeps its read position
per alias in mm2-offsets.<alias>.internal on the hub and seeks each topic
to that position at start. A reinstalled node's topics start again at 0,
so its first events sit below the remembered position and are skipped
for ever, silently -- unless the remembered position happens to lie past
the empty topic's end, when the consumer resets to the beginning; which
topics lose events depends on the previous node's history. A fresh node
(every up topic empty) therefore drops the hub's remembered position, now,
while the twin guard has just proven no other node under the alias is
alive. Re-mirroring what a previous node already sent is harmless: every
hub sink is an idempotent upsert. A rerun on a node that has already
mirrored keeps the position -- it is this node's own.

> Before: `mm2_reset_needed(){ # TWIN_QUIET(0|1) LOCAL_EVENTS HUB_HAS_OFFSETS(0|1) [FORCE(0|1)] -> yes | no`

FORCE: the operator states the hub's position belongs to a previous node
even though this node has already mirrored (a node reinstalled before this
check existed); still only with the alias proven quiet.

> Before: `case "${2:-x}" in ''|*[!0-9]*) echo no; return ;; esac`

MirrorMaker must have taken the node's own Odoo topic, not only heartbeats

> Before: `odoo_topic="$(printf '%s\n' "$up_topics" | grep '\.odoo\.all$' | head -1)"`

## `tasks/100-exit-checks.sh`

The node's own proof: preflight green, and a value written that could not
pre-exist, read back through the application, not a row count.

> Before: `set -euo pipefail`

odoo-connect and the XML-RPC marker below can both look fine against a dead
Odoo (/var/lib/odoo owned by the wrong uid -- HTTP 500 on
every request, including XML-RPC, which curl-retries into looking like a
slow start rather than a permanent failure) -- so prove the login PAGE
itself answers first. Odoo 16 builds its asset bundle on the first hit, so
this is retried, not a single probe. ODOO_BOOT_TIMEOUT_S (default 120,
probed every 10s) names the wait so its own message never drifts from what
actually ran.

> Before: `N="${LAN_NAME:-bahmni.clinic}"`

elis_page_ok (lib.sh) judges the page. OpenELIS is still starting when OpenMRS
first answers, minutes longer on a small machine, so it is probed on a named
budget (OPENELIS_BOOT_TIMEOUT_S, default 300, every 10s).

> Before: `elis_boot_s="${OPENELIS_BOOT_TIMEOUT_S:-300}"`

a 200 page with a broken stylesheet looks the same to curl: read back the
CSS bundle the page names (a seed's bundle rows point at files this node
does not have; task 050 drops them)

> Before: `css_path="$(lan_get "$O" /web/login | grep -oE 'href="[^"]*assets_frontend[^"]*\.css"' | head -1 | sed -E 's/h`

have started and written (a start that resets a counter shows here). A table
list that cannot be read fails here rather than checking no table.

> Before: `. "${INSTALL_DIR}/state.sh"`

The capture filter, read back from the connector Connect is running now (the
same check as the sync step; a re-registration since then shows here).

> Before: `v="$(capture_filter_check)" || fail "$v"`

the OpenELIS down sink, read from Connect (lib.sh clinlims_down_sink_check)

> Before: `v="$(clinlims_down_sink_check)" || fail "$v"`

the order-number counter, read now that OpenMRS has started (a start that
loads global properties over it shows here)

> Before: `seed_now="$(printf "select property_value from openmrs.global_property where property='order.nextOrderNumberSe`

## `tasks/110-hub-join.sh`

The clinic's authority ends here. The hub side is the operator's: "Per clinic"
in cloud/SETUP.md. Printed, never executed.

> Before: `set -euo pipefail`

nothing is installed or syncing in a dry run, so the join steps are not printed as if it were

> Before: `info "would: print the steps the operator runs to join this clinic to the hub"`

## `scripts/create-clinlims-sink-role.sh` and `scripts/create-odoo-sink-role.sh`

The OpenELIS down sinks must log in as a role the OpenELIS application never
uses. Only `clinlims_sink` is granted the replication-origin functions
(`scripts/sql/apply-replication-origin.sql`), and the origin is what keeps a
replicated write from being captured and sent up again.

The password is read by sourcing `.env`, the way every consumer reads it.
Cutting the line instead keeps inline comments and padding as part of the value;
on the cloud that once produced a role whose password no consumer could match.
An empty value counts as missing: the `.env` template ships
`CLINLIMS_SINK_PASSWORD=""`, and taking that as the password would clear it.
A blank key is replaced in place, not appended, so first-match readers never see
the blank line; writing through `cat` keeps the file's mode.

The password is generated from a bounded read of `/dev/urandom`. An unbounded
`tr </dev/urandom | head -c 32` gets SIGPIPE when `head` exits, and under
`pipefail` the assignment fails with 141.

The role's SQL runs from a file with `psql -f`, never `-c`. A failing statement
echoes its own text, so with `-c` a password once leaked into an ERROR CONTEXT
line; with `-f` the error names a file and line instead.

The grants are read back with `has_table_privilege` on each `[down]` table,
rather than trusted, so a sink is never refused its first write.

For Odoo, the write-origin guard trigger tells a replicated write from a local
one by `session_user`, so the Odoo sinks need `odoo_sink`, a role Odoo itself
never uses. The same need held back the OpenELIS guard until `clinlims_sink`
existed.

## `openmrs/build.sh` and `openmrs/Dockerfile`

IPLIT's OpenMRS image is linux/amd64 only. On Apple Silicon podman runs it under
QEMU: a bare Tomcat+WAR start took 26,153 ms on Ghated, and an earlier pinned
image took 51 minutes with modules loading. The native rebuild starts the same
Tomcat+WAR in about 2,330–2,394 ms (~11x faster); it builds in about 27 s and
the image is about 844 MB.

The script copies the four trees the image needs to run (`/usr/local/tomcat`,
`/openmrs`, `/etc/bahmni-emr`, `/home/bahmni`) onto `amazoncorretto:8u432-al2`:
the same OS family (Amazon Linux 2) and the same Corretto 8u432 JDK at the same
`JAVA_HOME`, so no override is needed. The application bytes are unchanged; only
the CPU build underneath differs.

A multi-stage `COPY --from=<amd64 stage>` is refused by rootless podman/buildah
6.1.0 ("unsupported MIME type for compression") before any COPY runs. So the
script runs `create --platform linux/amd64`, then `cp` for each tree into a build
context, then a single-stage build with plain COPY. The source image is never
run under emulation.

The build context lives under `CLINIC_DIR`, on the checkout's filesystem: a
cross-device `mktemp` under `/tmp` has broken podman builds before. The cleanup
trap uses `if` rather than `[ cond ] && rm` so it always returns 0; a non-zero
EXIT trap re-triggers `lib.sh`'s ERR trap (the same pitfall as in
`scripts/seed-odoo-conf.sh`).

The built image is labelled with the source and base image ids, and a later run
skips the build when both still match (`--force` rebuilds anyway). A source image
with no `/openmrs/bahmni_startup.sh` or no `openmrs.war` is refused, so a changed
layout never silently produces a broken tag.

In the Dockerfile: the `/openmrs/*.sh` scripts call `mysql`, `envsubst`,
`setfacl` and `curl`; `tar`, `gzip`, `shadow-utils` and `procps-ng` fill in what
the base assumes but does not ship. Tomcat's APR connector (`native-jni-lib`) is
the only x86 native code in the copied trees; without it Tomcat logs one INFO
line and falls back to NIO. `TOMCAT_NATIVE_LIBDIR` and `LD_LIBRARY_PATH` are
dropped because they pointed at it. The source's ENTRYPOINT, `tini`, is an x86
binary that no `/openmrs/*.sh` script calls, so it is not copied and
`bahmni_startup.sh` runs as PID 1.

## `clinic/scripts/checksum-exclusions.conf`

takes of each table, one <table>.<column> per line, each with its reason.
Every other column of every row is compared, so a column listed here is a
column whose difference between the hub and a clinic is expected and harmless.
Nothing is implied: a column is excluded only by a line in this file.

A module that starts at a clinic creates its privileges with a uuid of the
node's own; the hub's row then overwrites it by name, the privilege's key.
Nothing refers to a privilege by uuid.

> Before: `privilege.uuid`
