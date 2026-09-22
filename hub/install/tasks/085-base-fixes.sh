#!/usr/bin/env bash
# Three fixes to the base stack's OWN files that this installer would otherwise
# not carry, so a hub rebuilt from install.sh would lose them: the login stopgap
# in the base proxy, the quiet odoo-connect log, and InnoDB sizing for the base
# MySQL.
#
# The login stopgap: IPLIT's UI (bahmni-iplit-web bhs-0.0.27) asks OpenMRS for the logged-in
# user's roles with `v=custom:(username,uuid,person:(uuid,),privileges:(name,
# retired),userProperties)` -- a trailing comma inside `person:(uuid,)` -- and
# webservices.rest 2.50.0 answers HTTP 400 to the resulting empty property
# name, so nobody can log in. mod_rewrite lines in the base stack's own Apache
# proxy conf strip a comma sitting directly before a closing parenthesis
# (literal or percent-encoded) from any /openmrs query -- same semantics as
# the clinic's nginx-side stopgap (clinic/proxy/bahmni-nginx.conf), ported
# to Apache's own directives.
#
# The quiet log: odoo-connect (bahmni/odoo-connect:1.0.0) logs at DEBUG with no
# rolling policy and fills a small OS disk. Mount the clinic's own
# quieter logback (clinic/odoo/logback-erp-connect.xml -- already tracked in
# this repo and already what every clinic mounts) over the image's, through
# the base stack's own docker-compose.override.yml, and recreate only that
# one service.
#
# Both edits land OUTSIDE this checkout, in the base stack's own directory on
# the hub HOST (BASE_DIR below -- e.g. /home/bahmni-hub/iplit-base for the
# Azure hub) -- never under hub/ itself, so task
# 090's git-dirty-under-hub/ check is untouched by this task.
#
# Idempotent both ways: the rewrite rules' own pattern / an exact mount-line match
# short-circuits a repeat run to a plain "ok", never a second edit. DRY prints
# would: lines naming the real file and the real fact it found (marker
# present or not, anchor line or not) and changes NOTHING on disk -- unlike
# most tasks here, this one still reads its real target files under DRY
# (never writes), because "would: do something" to a file this task cannot
# even confirm exists is not a preview worth trusting. The clinic installer
# once shipped a dry run that wrote a real file and then blocked the real run
# behind it; nothing below writes under DRY.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "85 · base fixes (login stopgap, quiet odoo-connect log, InnoDB sizing)"

# ---------------------------------------------------------------------------
# stopgap-rules:begin
# The Apache mod_rewrite block itself -- inserted verbatim before the
# /openmrs ProxyPass line (see stopgap_insert below). Marked off on its own
# (comma_strip_ref below documents the same semantics in a form a table test
# can actually run) so hub/install/tests/test_base_fixes.sh can grep its text
# directly for the properties the stopgap requires, without a live Apache to ask.
#
# Two RewriteCond/RewriteRule pairs, the two-comma case FIRST: mod_rewrite has
# no equivalent of nginx's "apply the same regex twice" trick (the nginx-side
# fix, clinic/proxy/bahmni-nginx.conf, applies its `if` block twice for
# exactly this reason), so a query carrying two `,)`-shaped commas needs its
# own rule, evaluated before the single-comma fallback -- otherwise the
# single-comma rule's greedy `(.*)` would only ever strip the LAST one.
# `(?:,|%2C)(\)|%29)` matches a literal comma or `%2C`, immediately before a
# literal `)` or `%29`, case-insensitively ([NC]) -- literal, percent-encoded,
# and mixed forms in one alternation. [PT] passes the rewritten request
# through to mod_proxy's own ProxyPass (not an internal Apache redirect);
# [NE] stops the substitution from being re-escaped (a comma or paren the
# rule leaves behind must not turn back into %2C/%29).
stopgap_block(){
  cat <<'APACHE_BLOCK'
    # login stopgap (hub/install 085). IPLIT's UI
    # (bahmni-iplit-web bhs-0.0.27) asks OpenMRS for the logged-in user's
    # roles with v=custom:(username,uuid,person:(uuid,),privileges:(name,
    # retired),userProperties) -- a trailing comma before a closing
    # parenthesis inside person:(uuid,) -- and webservices.rest 2.50.0
    # (OpenMRS iplit-1.2.0) answers HTTP 400 to the resulting empty property
    # name, so nobody can log in. Strip a comma that sits
    # directly before a close paren, literal or percent-encoded
    # (case-insensitive), from any /openmrs request's query string. The
    # two-comma case is matched and rewritten FIRST -- a query can carry more
    # than one such comma, and unlike nginx's `if` (clinic/proxy/
    # bahmni-nginx.conf runs the same regex twice for this reason)
    # mod_rewrite has no repeat-until-clean loop -- falling through to the
    # single-comma rule only when the two-comma pattern does not match.
    RewriteCond %{REQUEST_URI} ^/openmrs/
    RewriteCond %{QUERY_STRING} ^(.*)(?:,|%2C)(\)|%29)(.*)(?:,|%2C)(\)|%29)(.*)$ [NC]
    RewriteRule ^(.*)$ $1?%1%2%3%4%5 [PT,NE]
    RewriteCond %{REQUEST_URI} ^/openmrs/
    RewriteCond %{QUERY_STRING} ^(.*)(?:,|%2C)(\)|%29)(.*)$ [NC]
    RewriteRule ^(.*)$ $1?%1%2%3 [PT,NE]
    # login stopgap end
APACHE_BLOCK
}
# stopgap-rules:end

# comma-strip-ref:begin
# comma_strip_ref STRING : reference implementation of the same rule the
# Apache block above (and the clinic's nginx `if` blocks) apply -- strip
# every comma that sits directly before a close paren, literal or
# percent-encoded, case-insensitively. Not used by the running proxy itself
# (Apache's own RewriteRule is what actually runs); this exists so the
# semantics can be table-tested with no Apache available at all.
comma_strip_ref(){
  python3 -c '
import re, sys
s = sys.argv[1]
pat = re.compile(r"(?:,|%2C)(\)|%29)", re.IGNORECASE)
sys.stdout.write(pat.sub(lambda m: m.group(1), s))
' "$1"
}
# comma-strip-ref:end

# stopgap-insert:begin
# stopgap_insert FILE : idempotent. It does not anchor on `ProxyPass /openmrs`,
# which in IPLIT's file sits at SERVER scope (lines 20 and 36, before any
# <VirtualHost>); mod_rewrite rules there are not inherited by the vhosts, so
# the block would have been inserted and done nothing. The block that works on
# the hub sits INSIDE the first <VirtualHost *:443>, directly after the
# secure reporting_session cookie rule (the RewriteRule carrying
# `CO=reporting_session` and ending `:true:true]`). That rule is the anchor;
# FAIL naming FILE if it is missing, since inserting blind into an unknown
# layout is worse than refusing. A file that already carries the rewrite
# rules -- inserted by this task or by hand --
# is a no-op -- a second copy of the rules is never added. Under DRY: read real
# facts, write nothing. For a real run: back FILE up once (never overwrite an
# existing backup) and insert stopgap_block immediately AFTER the anchor line.
stopgap_insert(){
  local f="$1" rule='(?:,|%2C)(\)|%29)' anchor_ln tmp blockfile backup
  # backup's own value expands ${f} -- assigned in its OWN statement, never on
  # the same `local NAME=VALUE ...` line as f itself: bash expands every
  # value on a single `local`/`declare` line against the state BEFORE that
  # line ran, so `local f="$1" backup="${f}.x"` silently gives backup an
  # EMPTY (not $f-prefixed) value -- caught live by this task's own tests
  # (hub/install/tests/test_base_fixes.sh), not by inspection.
  backup="${f}.bak-pre-login-stopgap"
  if grep -qF "$rule" "$f" 2>/dev/null; then
    ok "login stopgap: ${f} already carries the comma-stripping rewrite rules (inserted by this task or by hand)"
    return 0
  fi
  anchor_ln="$(grep -nE 'RewriteRule.*CO=reporting_session.*:true:true\]' "$f" 2>/dev/null | head -n1 | cut -d: -f1)"
  [ -n "$anchor_ln" ] || fail "login stopgap: no secure reporting_session cookie rule (RewriteRule ... CO=reporting_session ... :true:true]) found in ${f} -- cannot anchor the rewrite block inside the 443 vhost (is BASE_DIR=${BASE_DIR:-<unset>} really the base stack's own proxy-config?)"
  if [ "${DRY}" = 1 ]; then
    info "would: back up ${f} to ${backup} (if not already present) and insert the comma-stripping rewrite block after line ${anchor_ln} (the reporting_session cookie rule, inside the 443 vhost)"
    return 0
  fi
  [ -f "$backup" ] || cp "$f" "$backup"
  blockfile="$(mktemp "${f}.stopgapblock.XXXXXX")"
  { printf '\n'; stopgap_block; } > "$blockfile"
  tmp="$(mktemp "${f}.stopgapinsert.XXXXXX")"
  awk -v ln="$anchor_ln" -v bf="$blockfile" \
    '{print} NR==ln{while ((getline line < bf) > 0) print line}' \
    "$f" > "$tmp"
  rm -f "$blockfile"
  mv "$tmp" "$f"
  ok "login stopgap: inserted the rewrite block into ${f} after line ${anchor_ln}"
}
# stopgap-insert:end

# ---------------------------------------------------------------------------
# override-edit:begin
# override_python FILE MOUNT : the actual line editor. No YAML-merge
# helper exists anywhere in this installer today (grep -n override turns up
# nothing but test-only compose overrides for THIS repo's own hub/ stack, a
# different thing entirely -- BASE_DIR's override.yml lives outside this
# checkout), so this is a careful, marker-guarded text insertion, exactly as
# the job calls for -- never a full YAML parser. It handles, in order:
# no file at all -> create one; a `services:` key but no `odoo-connect:`
# service -> add one; an `odoo-connect:` service with no `volumes:` key ->
# add one; an `odoo-connect:` service that already has a `volumes:` list ->
# append our entry to THAT list, never a second `odoo-connect:` key (the
# fixture this is aimed at: the base's own odoo-connect may have no volumes:
# key at all -- but a future override carrying one must not get a duplicate
# service block). Docker/podman compose
# indentation convention throughout this repo's own overrides (clinic/
# docker-compose.override.yml): services: at column 0, a service name at 2
# spaces, its keys at 4, a list item at 6. Idempotent: the exact mount line
# already present anywhere in FILE is left alone (prints UNCHANGED).
override_python(){
  python3 - "$1" "$2" "${3:-odoo-connect}" <<'PY'
import re, sys
path, mount = sys.argv[1], sys.argv[2]
service = sys.argv[3] if len(sys.argv) > 3 else 'odoo-connect'
item_line = "      - '%s'" % mount
try:
    text = open(path).read()
except FileNotFoundError:
    text = ""

if item_line in text or ("- %s" % mount) in text or ("'%s'" % mount) in text:
    print("UNCHANGED"); sys.exit(0)

lines = text.split("\n") if text else []

svc_idx = None
for i, l in enumerate(lines):
    if re.match(r'^services:\s*$', l):
        svc_idx = i
        break

if svc_idx is None:
    block = ["services:", "  " + service + ":", "    volumes:", item_line]
    if lines and lines[-1] == "":
        lines = lines[:-1] + [""] + block + [""]
    elif lines:
        lines = lines + [""] + block + [""]
    else:
        lines = block + [""]
    open(path, "w").write("\n".join(lines))
    print("CREATED"); sys.exit(0)

n = len(lines)
oc_idx = None
i = svc_idx + 1
while i < n:
    l = lines[i]
    if re.match(r'^\S', l):
        break
    if re.match(r'^  ' + re.escape(service) + r':\s*$', l):
        oc_idx = i
        break
    i += 1

if oc_idx is None:
    j = svc_idx + 1
    while j < n and (lines[j] == "" or re.match(r'^\s', lines[j])):
        j += 1
    block = ["  " + service + ":", "    volumes:", item_line]
    lines[j:j] = block
    open(path, "w").write("\n".join(lines))
    print("ADDED_SERVICE"); sys.exit(0)

vol_idx = None
i = oc_idx + 1
while i < n:
    l = lines[i]
    if l == "":
        i += 1
        continue
    indent = len(l) - len(l.lstrip(" "))
    if indent <= 2:
        break
    if indent == 4 and re.match(r'^    volumes:\s*$', l):
        vol_idx = i
        break
    i += 1

if vol_idx is None:
    block = ["    volumes:", item_line]
    lines[oc_idx + 1:oc_idx + 1] = block
    open(path, "w").write("\n".join(lines))
    print("ADDED_VOLUMES_KEY"); sys.exit(0)

lines[vol_idx + 1:vol_idx + 1] = [item_line]
open(path, "w").write("\n".join(lines))
print("ADDED_ITEM")
PY
}

# override_ensure FILE MOUNT_TARGET : idempotent; backs FILE up once
# (never overwrites an existing backup -- and only when FILE already exists;
# a fresh hub has none to back up) before editing it. DRY prints would: and
# changes nothing.
override_ensure(){ # FILE TARGET [SERVICE] [SOURCE] [TAG]
  local f="$1" target="$2" service="${3:-odoo-connect}" src="${4:-./odoo-connect-logback.xml}" tag="${5:-quiet log}" mount result backup
  # Same bash gotcha as stopgap_insert above: backup's value (which expands ${f})
  # is assigned in its own statement, never on the shared `local` line.
  backup="${f}.bak-pre-override"
  mount="${src}:${target}:ro"
  if [ -f "$f" ] && grep -qF "$mount" "$f" 2>/dev/null; then
    ok "${tag}: ${f} already mounts ${src} onto ${service}"
    return 0
  fi
  if [ "${DRY}" = 1 ]; then
    info "would: back up ${f} to ${backup} (if it exists and no backup is already present) and add ${mount} to its ${service}: service"
    return 0
  fi
  if [ -f "$f" ]; then
    [ -f "$backup" ] || cp "$f" "$backup"
  fi
  result="$(override_python "$f" "$mount" "$service")" || fail "${tag}: could not edit ${f}"
  ok "${tag}: ${f} -- ${result} (${service} mount)"
}
# override-edit:end
# ---------------------------------------------------------------------------

# BASE_DIR: the base stack's own docker-compose project directory on the hub
# HOST -- an ambient override, the same class as KAFKA_CONTAINER/CONNECT_URL/
# HUB_MIN_DISK_GB (hub/install/lib.sh), required every run including a
# `--from 085` resume. Deliberately required, never defaulted: nothing else
# in this installer stores or can discover a FILESYSTEM path for the base
# stack -- every other base coordinate (BASE_MYSQL_CONTAINER, BASE_PG_
# CONTAINER, KAFKA_BASE_NETWORK, hub_compose_env in lib.sh) names a docker
# object, never a directory -- and a wrong silent default would edit the
# wrong host's files on a second hub. The Azure hub's own value is
# /home/bahmni-hub/iplit-base; that value is cited
# here for the operator's benefit only, never baked in as a fallback.
[ -n "${BASE_DIR:-}" ] || fail "BASE_DIR is required in the environment -- the base stack's own docker-compose project directory on this host (e.g. /home/bahmni-hub/iplit-base for the Azure hub), which nothing else in this installer stores or can discover"
[ -d "$BASE_DIR" ] || fail "BASE_DIR=${BASE_DIR} is not a directory"

PROXY_CONF="${BASE_DIR}/proxy-config/bahmni-proxy.conf"
OVERRIDE_FILE="${BASE_DIR}/docker-compose.override.yml"
LOGBACK_SRC="${REPO_DIR}/clinic/odoo/logback-erp-connect.xml"
LOGBACK_DST="${BASE_DIR}/odoo-connect-logback.xml"
LOGBACK_MOUNT_TARGET="/run/bahmni-erp-connect/bahmni-erp-connect/WEB-INF/classes/logback.xml"
# <project>-<service>-1 : docker/podman compose's own default container-
# naming convention (iplit-base-proxy-1, iplit-base-odoo-connect-1 on the
# Azure hub). Overridable (same class as KAFKA_CONTAINER) for a hub whose
# COMPOSE_PROJECT_NAME was set explicitly, and for this task's own tests.
BASE_PROXY_CONTAINER="${BASE_PROXY_CONTAINER:-$(basename "$BASE_DIR")-proxy-1}"
BASE_ODOO_CONNECT_CONTAINER="${BASE_ODOO_CONNECT_CONTAINER:-$(basename "$BASE_DIR")-odoo-connect-1}"

# --- the login stopgap ------------------------------------------------------
[ -f "$PROXY_CONF" ] || fail "login stopgap: proxy conf not found: ${PROXY_CONF} (BASE_DIR=${BASE_DIR} -- is this really the base stack's own compose directory?)"
stopgap_insert "$PROXY_CONF"

if [ "${DRY}" != 1 ]; then
  setup_compose
  running="$(ct inspect --format '{{.State.Running}}' "$BASE_PROXY_CONTAINER" 2>/dev/null || true)"
  [ "$running" = true ] || fail "login stopgap: base proxy container ${BASE_PROXY_CONTAINER} running=${running:-<not found>} (want true) -- cannot config-test or reload it"

  cfg_out="$(ct exec "$BASE_PROXY_CONTAINER" httpd -t 2>&1)" && cfg_ok=1 || cfg_ok=0
  if [ "$cfg_ok" != 1 ]; then
    cfg_out="$(ct exec "$BASE_PROXY_CONTAINER" apachectl -t 2>&1)" && cfg_ok=1 || cfg_ok=0
  fi
  if [ "$cfg_ok" = 1 ]; then
    ok "login stopgap: ${BASE_PROXY_CONTAINER}'s Apache config test passes after the edit"
  else
    [ -f "${PROXY_CONF}.bak-pre-login-stopgap" ] && cp "${PROXY_CONF}.bak-pre-login-stopgap" "$PROXY_CONF"
    fail "login stopgap: Apache config test failed inside ${BASE_PROXY_CONTAINER} after the edit -- restored ${PROXY_CONF} from its backup. httpd/apachectl said: ${cfg_out}"
  fi
  if ct exec "$BASE_PROXY_CONTAINER" httpd -k graceful >/dev/null 2>&1; then
    ok "login stopgap: reloaded ${BASE_PROXY_CONTAINER} gracefully (httpd -k graceful)"
  else
    warn "login stopgap: graceful reload of ${BASE_PROXY_CONTAINER} did not answer 0 -- the config is valid and written, but the running Apache may still be serving the pre-edit config until its next restart/reload"
  fi
fi

# --- the quiet odoo-connect log ---------------------------------------------
if [ "${DRY}" = 1 ]; then
  info "would: copy ${LOGBACK_SRC} to ${LOGBACK_DST} (mode 644); ensure ${OVERRIDE_FILE} mounts it read-only onto ${LOGBACK_MOUNT_TARGET} for odoo-connect; recreate only ${BASE_ODOO_CONNECT_CONTAINER} unless its mounts already include that path"
else
  setup_compose
  [ -f "$LOGBACK_SRC" ] || fail "quiet log: ${LOGBACK_SRC} not found in this checkout"
  cp "$LOGBACK_SRC" "$LOGBACK_DST"
  chmod 644 "$LOGBACK_DST"
  ok "quiet log: copied the quiet logback to ${LOGBACK_DST} (mode 644)"

  override_ensure "$OVERRIDE_FILE" "$LOGBACK_MOUNT_TARGET"

  if ( cd "$BASE_DIR" && ${COMPOSE_CMD:?setup_compose first} config -q ); then
    ok "quiet log: ${OVERRIDE_FILE} still parses (docker compose config -q)"
  else
    [ -f "${OVERRIDE_FILE}.bak-pre-override" ] && cp "${OVERRIDE_FILE}.bak-pre-override" "$OVERRIDE_FILE"
    fail "quiet log: docker compose config -q failed against ${BASE_DIR} after the override edit -- restored ${OVERRIDE_FILE} from its backup"
  fi

  running="$(ct inspect --format '{{.State.Running}}' "$BASE_ODOO_CONNECT_CONTAINER" 2>/dev/null || true)"
  [ "$running" = true ] || fail "quiet log: base odoo-connect container ${BASE_ODOO_CONNECT_CONTAINER} running=${running:-<not found>} (want true) -- cannot recreate it"

  mounted="$(ct inspect --format '{{range .Mounts}}{{.Destination}} {{end}}' "$BASE_ODOO_CONNECT_CONTAINER" 2>/dev/null || true)"
  case " $mounted " in
    *" ${LOGBACK_MOUNT_TARGET} "*) already_mounted=1 ;;
    *) already_mounted=0 ;;
  esac

  if [ "$already_mounted" = 1 ]; then
    ok "quiet log: ${BASE_ODOO_CONNECT_CONTAINER} already mounts ${LOGBACK_MOUNT_TARGET} -- nothing to recreate"
  else
    ( cd "$BASE_DIR" && ${COMPOSE_CMD} up -d --no-deps odoo-connect ) \
      && ok "quiet log: recreated ${BASE_ODOO_CONNECT_CONTAINER} (up -d --no-deps odoo-connect)" \
      || fail "quiet log: docker compose up -d --no-deps odoo-connect failed against ${BASE_DIR}"
    mounted="$(ct inspect --format '{{range .Mounts}}{{.Destination}} {{end}}' "$BASE_ODOO_CONNECT_CONTAINER" 2>/dev/null || true)"
    case " $mounted " in
      *" ${LOGBACK_MOUNT_TARGET} "*) ok "quiet log: ${BASE_ODOO_CONNECT_CONTAINER}'s mounts now include ${LOGBACK_MOUNT_TARGET}" ;;
      *) fail "quiet log: ${BASE_ODOO_CONNECT_CONTAINER} was recreated but its mounts still lack ${LOGBACK_MOUNT_TARGET} (got: ${mounted:-<none>})" ;;
    esac
  fi
fi

# base-sizing:begin
# The base stack's MySQL (openmrsdb) runs on the image's defaults: a 128 MB
# buffer pool and a 100 MB redo log for a 7 GB database, so every read misses
# the cache. One conf.d file, sized from the memory the host gives it, mounted
# read-only through my.cnf's !includedir. Twin of clinic/install/lib.sh's
# mysql_pool_mb / mysql_tuning_cnf -- the same rule on both sides, checked by
# tests/test_base_fixes.sh against that file.
base_pool_mb(){ # MEM_MB -> buffer pool MB: a quarter, 128 MB steps, 512..4096
  local mem="${1:-0}" mb
  case "$mem" in ''|*[!0-9]*) mem=0 ;; esac
  mb=$(( mem / 4 / 128 * 128 ))
  [ "$mb" -gt 4096 ] && mb=4096
  [ "$mb" -lt 512 ] && mb=512
  printf '%s\n' "$mb"
}
base_tuning_cnf(){ # POOL_MB -> the conf.d file's text
  printf '# rendered by hub/install from the memory this host gives its database server\n[mysqld]\ninnodb_buffer_pool_size = %sM\ninnodb_redo_log_capacity = 512M\n' "$1"
}
# base-sizing:end

# --- InnoDB sizing for the base MySQL (openmrsdb) ---------------------------
TUNING_CNF="${BASE_DIR}/openmrsdb-tuning.cnf"
TUNING_TARGET="/etc/mysql/conf.d/sync-tuning.cnf"
BASE_MYSQL_SERVICE="${BASE_MYSQL_SERVICE:-openmrsdb}"
BASE_MYSQL_CONTAINER="${BASE_MYSQL_CONTAINER:-$(basename "$BASE_DIR")-${BASE_MYSQL_SERVICE}-1}"
base_mem_mb="${NODE_MEM_MB:-$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)}"
base_pool="$(base_pool_mb "$base_mem_mb")"
if [ "${DRY}" = 1 ]; then
  info "would: render ${TUNING_CNF} (buffer pool ${base_pool} MB from ${base_mem_mb} MB host memory, redo log 512 MB); ensure ${OVERRIDE_FILE} mounts it read-only onto ${TUNING_TARGET} for ${BASE_MYSQL_SERVICE}; recreate only ${BASE_MYSQL_CONTAINER} unless its mounts already include that path; read innodb_buffer_pool_size back from the server"
else
  base_tuning_cnf "$base_pool" > "${TUNING_CNF}.new" && chmod 644 "${TUNING_CNF}.new"
  if [ -f "$TUNING_CNF" ] && cmp -s "$TUNING_CNF" "${TUNING_CNF}.new"; then rm -f "${TUNING_CNF}.new"; ok "innodb sizing: ${TUNING_CNF} unchanged (buffer pool ${base_pool} MB)"
  else mv "${TUNING_CNF}.new" "$TUNING_CNF"; ok "innodb sizing: rendered ${TUNING_CNF} (buffer pool ${base_pool} MB from ${base_mem_mb} MB host memory, redo log 512 MB)"; fi
  override_ensure "$OVERRIDE_FILE" "$TUNING_TARGET" "$BASE_MYSQL_SERVICE" "./openmrsdb-tuning.cnf" "innodb sizing"
  if ( cd "$BASE_DIR" && ${COMPOSE_CMD:?setup_compose first} config -q ); then
    ok "innodb sizing: ${OVERRIDE_FILE} still parses (docker compose config -q)"
  else
    [ -f "${OVERRIDE_FILE}.bak-pre-override" ] && cp "${OVERRIDE_FILE}.bak-pre-override" "$OVERRIDE_FILE"
    fail "innodb sizing: docker compose config -q failed against ${BASE_DIR} after the override edit -- restored ${OVERRIDE_FILE} from its backup"
  fi
  mounted="$(ct inspect --format '{{range .Mounts}}{{.Destination}} {{end}}' "$BASE_MYSQL_CONTAINER" 2>/dev/null || true)"
  case " $mounted " in
    *" ${TUNING_TARGET} "*) ok "innodb sizing: ${BASE_MYSQL_CONTAINER} already mounts ${TUNING_TARGET} -- nothing to recreate" ;;
    *)
      # a MySQL recreate is a short OpenMRS outage; the Debezium source reconnects on its own
      ( cd "$BASE_DIR" && ${COMPOSE_CMD} up -d --no-deps "$BASE_MYSQL_SERVICE" ) \
        && ok "innodb sizing: recreated ${BASE_MYSQL_CONTAINER} (up -d --no-deps ${BASE_MYSQL_SERVICE})" \
        || fail "innodb sizing: docker compose up -d --no-deps ${BASE_MYSQL_SERVICE} failed against ${BASE_DIR}"
      ;;
  esac
  got_b=0
  for i in $(seq 1 24); do
    got_b="$(ct exec "$BASE_MYSQL_CONTAINER" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -h127.0.0.1 -uroot -N -e "select @@innodb_buffer_pool_size"' 2>/dev/null)" || true
    case "$got_b" in ''|*[!0-9]*) got_b=0 ;; esac
    [ "$got_b" -gt 0 ] && break; sleep 5
  done
  [ "$(( got_b / 1048576 ))" -ge "$base_pool" ] && ok "innodb sizing: innodb_buffer_pool_size $(( got_b / 1048576 )) MB in force (read back from the server)" \
    || fail "innodb sizing: the server reports $(( got_b / 1048576 )) MB, the file says ${base_pool} MB -- the conf.d mount is not in force"
fi
