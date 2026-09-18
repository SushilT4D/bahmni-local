#!/usr/bin/env bash
# Pure static checks over the hub's own tracked files -- no docker, no network,
# no hub/.env. Two classes, both found by the final whole-branch review:
#
#  1. WAIT-LOOP LINT (Important 3). Every task runs under `set -euo pipefail`
#     with lib.sh's ERR trap armed, so a BARE command substitution assignment
#     inside a for/while/until body -- `code="$(curl ...)"` -- aborts the whole
#     task the first time the command fails. In a WAIT loop that is exactly the
#     normal case: the first poll of a service that is still starting fails,
#     and the loop that exists to retry never gets a second iteration. Three
#     real instances shipped this way (070-connect.sh's kafka-ui wait,
#     080-sources.sh's wait_running and wait_slot). The fix is `|| true` (or
#     `|| var=default`) on the same logical line, which also keeps `set -e`
#     from ever seeing the failure.
#
#  2. CONNECTOR/GENERATOR HYGIENE (Important 4, Important 8). No tracked
#     connector template may hardcode a base container name (the two-container
#     IPLIT base would send Odoo's up-sinks at the OpenELIS instance), and every
#     script that RENDERS a connector config with a live password substituted in
#     must create it mode 600, never the default 644.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB="$(cd "$HERE/../.." && pwd)"
fails=0
ok(){ printf '  ok   %s\n' "$*"; }
bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }

# --- 1. wait-loop lint ------------------------------------------------------
# Reports every `NAME="$(...)"` assignment that sits inside a for/while/until
# body and carries no `||` guard on the same logical line. Loop depth is
# tracked by the shell's own `do`/`done` word pairs (a one-line
# `for i in ...; do ...; done` opens and closes on the same line, so the
# offending assignment has to be BETWEEN them to count).
# The guard must come AFTER the substitution closes -- `x="$(cmd)" || true`,
# never `x="$(cmd || true)"`. Two reasons the outside form is the one this lint
# demands: a `||` INSIDE the substitution is frequently not a guard at all
# (Postgres string concatenation, `select slot_name || '|' || active`, is
# exactly what 080-sources.sh's slot read and 050-base-db.sh's sequence read
# send), and no purely textual check can tell those apart; and the outside form
# is the one whose status `set -e` actually inspects, so it reads the way it
# behaves. (Note for future edits: `local x="$(cmd)" || guard` is a different
# trap -- `local`'s own exit status masks the substitution's, so the guard can
# never fire. Declare `local` separately from the assignment inside a loop.)
lint_out="$(python3 - "$HUB/install/tasks" <<'PY'
import os, re, sys
root = sys.argv[1]
assign = re.compile(r'^\s*(?:local\s+)?[A-Za-z_][A-Za-z0-9_]*="\$\(')
opener = re.compile(r'(?<![\w-])do(?![\w-])')
closer = re.compile(r'(?<![\w-])done(?![\w-])')
bad = []


def guarded(line):
    return re.search(r'\)"\s*\|\|', line) is not None


def logical_lines(path):
    # A trailing backslash continues the LOGICAL line, so `x="$(cmd)" \` on one
    # physical line and `|| fail "..."` on the next is one guarded statement.
    buf, start = '', 0
    for n, line in enumerate(open(path), 1):
        if not buf:
            start = n
        stripped = line.rstrip('\n')
        if stripped.endswith('\\'):
            buf += stripped[:-1] + ' '
            continue
        yield start, buf + stripped
        buf = ''
    if buf:
        yield start, buf


for name in sorted(os.listdir(root)):
    if not name.endswith('.sh'):
        continue
    depth = 0
    for n, line in logical_lines(os.path.join(root, name)):
        code = line.split('#', 1)[0] if not line.lstrip().startswith('#') else ''
        if depth > 0 and assign.match(line) and not guarded(line):
            bad.append('%s:%d: %s' % (name, n, line.strip()[:160]))
        depth += len(opener.findall(code)) - len(closer.findall(code))
        if depth < 0:
            depth = 0
for b in bad:
    print(b)
PY
)"
if [ -z "$lint_out" ]; then
  ok "no unguarded \$(...) assignment inside any for/while/until body in hub/install/tasks/"
else
  printf '%s\n' "$lint_out" | while IFS= read -r l; do printf '       %s\n' "$l"; done
  bad "$(printf '%s\n' "$lint_out" | grep -c .) unguarded \$(...) assignment(s) inside a loop body (see above) -- add '|| true' so the wait loop can actually retry"
fi

# --- 2a. no tracked connector template hardcodes a base container name ------
# The four up-sink templates used to dial jdbc:postgresql://openelisdb:5432/...
# outright. On IPLIT's two-container base that name is the OPENELIS instance,
# so the two Odoo sinks would have written Odoo rows into the wrong Postgres.
# They carry ${BASE_PG_CONTAINER}/${BASE_ELIS_CONTAINER} now, substituted at
# registration time by connectors/_render_connector.py from hub/.env.
hits="$(grep -l 'openelisdb' "$HUB"/connectors/*.json "$HUB"/connectors/*.template 2>/dev/null || true)"
[ -z "$hits" ] && ok "no file under hub/connectors/ carries the literal container name 'openelisdb'" \
  || bad "these hub/connectors files still hardcode 'openelisdb': $(printf '%s ' $hits)"
for f in odoo-cloud-sink-all odoo-ghated-sink-all; do
  grep -q '\${BASE_PG_CONTAINER}' "$HUB/connectors/${f}.json" \
    && ok "${f}.json dials \${BASE_PG_CONTAINER}" || bad "${f}.json does not reference \${BASE_PG_CONTAINER}"
done
for f in clinlims-cloud-sink-all clinlims-ghated-sink-all; do
  grep -q '\${BASE_ELIS_CONTAINER}' "$HUB/connectors/${f}.json" \
    && ok "${f}.json dials \${BASE_ELIS_CONTAINER}" || bad "${f}.json does not reference \${BASE_ELIS_CONTAINER}"
done

# --- 2b. every renderer of a password-bearing config creates it mode 600 ----
for g in scripts/generate-cloud-source-connector.sh scripts/generate-sink-connectors.sh; do
  grep -qE '^umask 077' "$HUB/$g" && ok "${g##*/} sets umask 077 before it writes a rendered config" \
    || bad "${g##*/} does not set umask 077 -- a rendered config carrying a live password would be world-readable"
done
grep -q 'chmod 600 "\$GENERATED"' "$HUB/install/tasks/080-sources.sh" \
  && ok "080-sources.sh chmods the rendered mysql source config to 600" \
  || bad "080-sources.sh does not chmod the rendered mysql source config to 600"

printf '%s\n' "$fails failure(s)"; exit $((fails>0))
