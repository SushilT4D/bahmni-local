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
grep -q '05-clinic-resolver.sh:/docker-entrypoint.d/05-clinic-resolver.sh' "$Y" && ok_ "the resolver script is mounted into the proxy" || bad "resolver script not mounted"
# patient search: the UI sends POST, OpenMRS serves the search on GET only
blk="$(awk '/location = \/openmrs\/ws\/rest\/v1\/bahmnicore\/distro\/patient\/search/{p=1} p{print} p&&/}/{exit}' "$C")"
[ -n "$blk" ] && ok_ "an exact route for the patient search" || bad "no exact route for /openmrs/ws/rest/v1/bahmnicore/distro/patient/search"
printf '%s\n' "$blk" | grep -q 'proxy_method GET;' && ok_ "it forwards the search as GET" || bad "the search route does not set proxy_method GET"
printf '%s\n' "$blk" | grep -qE 'proxy_pass http://openmrs_app;' && ok_ "to OpenMRS, URI unchanged" || bad "the search route does not proxy_pass to openmrs_app without a URI"
# encounter calls: IPLIT's two stay with the module, the rest go to stock bahmnicore
for p in findWith createDrugOrder; do
  awk "/location = \/openmrs\/ws\/rest\/v1\/bahmnicore\/distro\/bahmniencounter\/$p /{p=1} p{print} p&&/}/{exit}" "$C" | grep -qF 'proxy_pass http://openmrs_app;' \
    && ok_ "distro/bahmniencounter/$p stays with the IPLIT module" || bad "no pass-through route for distro/bahmniencounter/$p"
done
blk="$(awk '/location \^~ \/openmrs\/ws\/rest\/v1\/bahmnicore\/distro\/bahmniencounter /{p=1} p{print} p&&/}/{exit}' "$C")"
[ -n "$blk" ] && ok_ "a prefix route for the other encounter calls" || bad "no ^~ route for /openmrs/ws/rest/v1/bahmnicore/distro/bahmniencounter"
printf '%s\n' "$blk" | grep -qF 'rewrite ^/openmrs/ws/rest/v1/bahmnicore/distro/bahmniencounter(.*)$ /openmrs/ws/rest/v1/bahmnicore/bahmniencounter$1 break;' \
  && ok_ "they go to stock bahmnicore/bahmniencounter, suffix kept" || bad "the encounter prefix route does not rewrite to bahmnicore/bahmniencounter"
printf '%s\n' "$blk" | grep -q 'proxy_method' && bad "the encounter route changes the method" || ok_ "the method is kept"
# condition history: nothing serves it, so the proxy answers an empty list
blk="$(awk '/location = \/openmrs\/ws\/rest\/emrapi\/conditionhistory /{p=1} p{print} p&&/}/{exit}' "$C")"
[ -n "$blk" ] && ok_ "an exact route for the condition history" || bad "no exact route for /openmrs/ws/rest/emrapi/conditionhistory"
printf '%s\n' "$blk" | grep -qF "return 200 '[]';" && printf '%s\n' "$blk" | grep -qF 'default_type application/json;' \
  && ok_ "it answers an empty JSON list" || bad "the condition history route does not answer an empty JSON list"
# form translations: a 500 from the module becomes the empty list the UI renders labels from
blk="$(awk '/location = \/openmrs\/ws\/rest\/v1\/bahmniie\/form\/translations /{p=1} p{print} p&&/}/{exit}' "$C")"
[ -n "$blk" ] && ok_ "an exact route for the form translations" || bad "no exact route for /openmrs/ws/rest/v1/bahmniie/form/translations"
printf '%s\n' "$blk" | grep -qF 'proxy_pass http://openmrs_app;' && ok_ "it asks OpenMRS first, URI unchanged" || bad "the translations route does not proxy_pass to openmrs_app without a URI"
printf '%s\n' "$blk" | grep -qF 'error_page 500 = @no_form_translations;' && ok_ "a 500 goes to the no-translations answer" || bad "the translations route does not send a 500 to @no_form_translations"
printf '%s\n' "$blk" | grep -qF 'error_page 501 502 =500 /internalError.html;' && printf '%s\n' "$blk" | grep -qF 'error_page 503 /maintenance.html;' \
  && ok_ "the server's other error pages are kept" || bad "the translations route drops the server's other error pages"
blk="$(awk '/location @no_form_translations /{p=1} p{print} p&&/}/{exit}' "$C")"
printf '%s\n' "$blk" | grep -qF "return 200 '[]';" && printf '%s\n' "$blk" | grep -qF 'default_type application/json;' \
  && ok_ "the no-translations answer is an empty JSON list" || bad "@no_form_translations does not answer an empty JSON list"
# form definitions: `<=` in event scripts is written as `&lt;=` for the UI's render read only
blk="$(awk '/map \$args \$form_script_le /{p=1} p{print} p&&/}/{exit}' "$C")"
printf '%s\n' "$blk" | grep -qF 'resources' && printf '%s\n' "$blk" | grep -qF '"&lt;=";' && ok_ "the UI's form render read gets &lt;=" || bad "the form_script_le map does not give &lt;= for v=custom:(resources:(value))"
printf '%s\n' "$blk" | grep -qF 'default "<=";' && ok_ "every other read keeps <=" || bad "the form_script_le map default is not <="
blk="$(awk '/location ~ \^\/openmrs\/ws\/rest\/v1\/form\/\[0-9a-fA-F-\]\+\$ /{p=1} p{print} p&&/}/{exit}' "$C")"
[ -n "$blk" ] && ok_ "a route for one form's definition" || bad "no regex route for /openmrs/ws/rest/v1/form/<uuid>"
printf '%s\n' "$blk" | grep -qF "sub_filter '<=' \$form_script_le;" && printf '%s\n' "$blk" | grep -qF 'sub_filter_once off;' \
  && printf '%s\n' "$blk" | grep -qF 'sub_filter_types application/json;' && ok_ "it rewrites every <= in the JSON body" || bad "the form route does not sub_filter <= in JSON"
printf '%s\n' "$blk" | grep -qF 'proxy_set_header Accept-Encoding   "";' && ok_ "it asks for an uncompressed body" || bad "the form route does not clear Accept-Encoding"
for h in Host X-Real-IP X-Forwarded-For X-Forwarded-Proto; do
  printf '%s\n' "$blk" | grep -qE "proxy_set_header $h " && ok_ "it keeps the $h header" || bad "the form route drops the $h header"
done
printf '%s\n' "$blk" | grep -qF 'proxy_pass http://openmrs_app;' && ok_ "to OpenMRS, URI unchanged" || bad "the form route does not proxy_pass to openmrs_app without a URI"
exit $((fails > 0))
