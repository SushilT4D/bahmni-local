#!/usr/bin/env bash
# The clinic proxy: 80 and 443 only; Odoo on 443 for any odoo.* host; the main
# vhost is the explicit default; no port or name is written into the config.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="${HERE}/../../proxy/bahmni-nginx.openelis.conf"; Y="${HERE}/../../docker-compose.yml"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
grep -q 'listen 444' "$C" && bad "a 444 listener remains" || ok_ "no 444 listener"
grep -q 'listen 443 ssl default_server;' "$C" && ok_ "main vhost is the default" || bad "main vhost is not default_server"
grep -qF 'server_name ~^odoo\.;' "$C" && ok_ "odoo.* vhost present" || bad "no odoo.* vhost"
grep -qE 'location /odoo' "$C" && bad "an /odoo location exists" || ok_ "no /odoo location"
grep -qE '9443|9444' "$Y" && bad "compose still names 9443/9444" || ok_ "compose has no test ports"
grep -q "BAHMNI_PROXY_HTTPS_PORT:-443}:443" "$Y" && ok_ "443 published" || bad "443 not published"
grep -q "BAHMNI_PROXY_HTTP_PORT:-80}:80" "$Y" && ok_ "80 published" || bad "80 not published"
exit $((fails > 0))
