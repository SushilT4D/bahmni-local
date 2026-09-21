#!/usr/bin/env bash
# The clinic stack against IPLIT's staging (review of 2026-09-21): the UI and
# config come from the pinned IPLIT images through clinic/extracted/, one config
# tree feeds the proxy, OpenMRS and OpenELIS, and the settings staging carries
# for this OpenMRS 1.2.0 / Odoo 16 pairing are present.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; CL="${HERE}/../.."; RP="${CL}/.."
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
has(){ grep -vE '^[[:space:]]*#' "$1" | grep -qE -- "$2"; }
svc(){ # FILE SERVICE : that service's block, comments dropped
  awk -v s="  $2:" '$0==s{p=1;next} p&&/^  [A-Za-z]/{exit} p' "$1" | grep -vE '^[[:space:]]*#'; }
Y="$CL/docker-compose.yml"; O="$CL/docker-compose.override.yml"

# pins
for k in BAHMNI_WEB_IMAGE BAHMNI_CONFIG_IMAGE; do grep -qE "^$k=infoiplitin/[a-z-]+:[A-Za-z0-9._-]+" "$RP/sync/versions.env" && ok_ "sync/versions.env pins $k" || bad "sync/versions.env does not pin $k to an infoiplitin image"; done
grep -E '^BAHMNI_(WEB|CONFIG)_IMAGE=' "$RP/sync/versions.env" | grep -q ':latest' && bad "a UI/config pin is :latest" || ok_ "neither pin is :latest"

# wiring: one extracted tree, three consumers
svc "$Y" proxy   | grep -q 'BAHMNI_UI_DIR'     && ok_ "proxy serves the UI from BAHMNI_UI_DIR" || bad "proxy does not mount BAHMNI_UI_DIR"
svc "$Y" proxy   | grep -q 'BAHMNI_CONFIG_DIR' && ok_ "proxy serves the config from BAHMNI_CONFIG_DIR" || bad "proxy does not mount BAHMNI_CONFIG_DIR"
svc "$Y" openmrs | grep -q 'BAHMNI_CONFIG_DIR.*:/etc/bahmni_config' && ok_ "openmrs reads BAHMNI_CONFIG_DIR" || bad "openmrs does not mount BAHMNI_CONFIG_DIR at /etc/bahmni_config"
svc "$O" openelis | grep -q 'BAHMNI_CONFIG_DIR.*:/etc/bahmni_config' && ok_ "openelis reads BAHMNI_CONFIG_DIR" || bad "openelis does not mount BAHMNI_CONFIG_DIR at /etc/bahmni_config"
{ svc "$Y" proxy; svc "$Y" openmrs; svc "$O" openelis; } | grep -qE 'CONTAINER_DATA_PATH[^:]*/(htdocs/bahmni|bahmni_config)|\./bahmni-config' && bad "a consumer still mounts a committed tree" || ok_ "no consumer mounts a committed tree"
svc "$Y" bahmni-config | grep -q 'BAHMNI_CONFIG_IMAGE' && ok_ "bahmni-config service runs the pinned image, not default-config:latest" || bad "bahmni-config service is not on BAHMNI_CONFIG_IMAGE"
for k in BAHMNI_UI_DIR BAHMNI_CONFIG_DIR; do grep -qE "^$k=" "$CL/.env.example" && ok_ ".env.example carries $k" || bad ".env.example lacks $k (AL-010)"; done
grep -qE '^/?clinic/extracted(\.prev)?/?|^extracted' "$RP/.gitignore" "$CL/.gitignore" 2>/dev/null && ok_ "extracted/ is gitignored" || bad "extracted/ is not gitignored"
has "$HERE/../tasks/020-env.sh" 'put BAHMNI_UI_DIR' && has "$HERE/../tasks/020-env.sh" 'put BAHMNI_CONFIG_DIR' && ok_ "020 renders both paths" || bad "020 does not render BAHMNI_UI_DIR / BAHMNI_CONFIG_DIR"
[ -f "$HERE/../tasks/045-ui-config.sh" ] && has "$HERE/../tasks/045-ui-config.sh" 'extract-ui-config.sh' && ok_ "task 045 runs the extraction" || bad "no task 045 running scripts/extract-ui-config.sh"

# settings staging carries
svc "$O" odoo-connect | grep -qE 'IS_ODOO_16:.*true' && ok_ "odoo-connect has IS_ODOO_16=true" || bad "odoo-connect lacks IS_ODOO_16=true"
svc "$Y" openmrs | grep -q 'OMRS_DB_DRIVER_CLASS' && ok_ "openmrs passes OMRS_DB_DRIVER_CLASS" || bad "openmrs lacks OMRS_DB_DRIVER_CLASS"
svc "$Y" openmrs | grep -q 'LUCENE_SEARCH_INDEXING_STRATEGY' && ok_ "openmrs passes LUCENE_SEARCH_INDEXING_STRATEGY" || bad "openmrs lacks LUCENE_SEARCH_INDEXING_STRATEGY"
grep -qE '^OMRS_DB_DRIVER_CLASS=com\.mysql\.cj\.jdbc\.Driver' "$CL/.env.example" && grep -qE '^LUCENE_SEARCH_INDEXING_STRATEGY=manual' "$CL/.env.example" && ok_ ".env.example carries staging's two values" || bad ".env.example lacks the driver class / lucene strategy"
svc "$Y" openmrs | grep -qE 'hibernate_(show|format)_sql:.*"true"' && bad "openmrs still prints every SQL statement" || ok_ "openmrs SQL printing is off"

# the proxy's health must mean "a browser gets the UI": IPv4, TLS, the login page
svc "$Y" proxy | grep -q 'https://127.0.0.1/bahmni/home/index.html' && ok_ "proxy healthcheck asks for the login page over IPv4/TLS" || bad "proxy has no meaningful healthcheck (the image's wget http://localhost can never pass)"
grep -c 'echo "\$body" >&2' "$CL/connectors/register-odoo.sh" | grep -qx 0 && ok_ "register-odoo.sh never prints an unmasked render" || bad "register-odoo.sh echoes \$body unmasked on a render failure"

# F-080 stopgap: strip the UI's trailing comma before OpenMRS sees it
for f in bahmni-nginx.conf bahmni-nginx.openelis.conf; do has "$CL/proxy/$f" 'F-080' || grep -q 'F-080' "$CL/proxy/$f" && grep -vE '^[[:space:]]*#' "$CL/proxy/$f" | grep -qE 'set \$args' && ok_ "$f rewrites the trailing comma (F-080)" || bad "$f has no F-080 trailing-comma rewrite"; done

# landing page: the Odoo tile must use THIS node's own port, not IPLIT's
# erp-<host> DNS convention (manpur, 2026-09-21: that name does not resolve)
has "$CL/proxy/htdocs/index.html" 'linkPort' && ok_ "index.html's getAppLink understands linkPort" || bad "index.html has no linkPort branch in getAppLink"
has "$CL/proxy/htdocs/index.html" 'window\.location\.hostname' && ok_ "index.html's linkPort branch uses window.location.hostname (not .host, which carries the current port)" || bad "index.html's linkPort branch does not use window.location.hostname"
has "$CL/docker-compose.override.yml" "proxy/htdocs/index\.html:/usr/share/nginx/html/index\.html:ro" && ok_ "override mounts proxy/htdocs/index.html so an edit needs no image rebuild" || bad "docker-compose.override.yml does not mount proxy/htdocs/index.html"
exit "$fails"
