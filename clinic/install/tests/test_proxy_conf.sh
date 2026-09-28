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
# A literal upstream is resolved once, at start: when an app container restarts
# with a new address the proxy keeps sending to the old one until it is reloaded.
# The resolver is written at start from the container's own resolv.conf (Docker
# and podman put their DNS at different addresses) and the app upstreams are
# `server ... resolve`, so they are re-resolved with proxy_pass unchanged.
grep -q 'include /etc/nginx/clinic-resolver.conf;' "$C" && ok_ "proxy includes the resolver written at start" || bad "no resolver include"
for pair in openmrs:8080 openelis:8052 odoo:8069; do
  app="${pair%%:*}"
  grep -q "server ${pair} resolve;" "$C" && grep -q "proxy_pass http://${app}_app" "$C" \
    && ok_ "${app} upstream is re-resolved (server ... resolve)" || bad "${app} upstream is a literal, resolved once"
done
R="${HERE}/../../proxy/05-clinic-resolver.sh"
if [ -f "$R" ]; then
  T="$(mktemp -d)"; printf 'search x\nnameserver 10.89.0.1\nnameserver 10.89.0.2\n' > "$T/resolv.conf"
  RESOLV_CONF="$T/resolv.conf" OUT="$T/out.conf" sh "$R" >/dev/null 2>&1
  [ "$(cat "$T/out.conf" 2>/dev/null)" = "resolver 10.89.0.1 valid=10s ipv6=off;" ] && ok_ "resolver written from resolv.conf's first nameserver" || bad "resolver file: $(cat "$T/out.conf" 2>/dev/null)"
  rm -rf "$T"
else bad "no proxy/05-clinic-resolver.sh"; fi
Y2="${HERE}/../../docker-compose.override.yml"
grep -q '05-clinic-resolver.sh:/docker-entrypoint.d/05-clinic-resolver.sh' "$Y2" && ok_ "the resolver script is mounted into the proxy" || bad "resolver script not mounted"
exit $((fails > 0))
