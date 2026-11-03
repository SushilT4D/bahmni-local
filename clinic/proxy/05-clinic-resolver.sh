#!/bin/sh
# Runs at proxy start (the nginx image runs /docker-entrypoint.d/*.sh). Writes
# the resolver the proxy uses to re-resolve its app upstreams, taken from this
# container's own resolv.conf: Docker and podman put their DNS at different
# addresses, so it cannot be written into nginx.conf. valid=10s: an app
# container that restarts with a new address is reached again within seconds.
RESOLV_CONF="${RESOLV_CONF:-/etc/resolv.conf}"
OUT="${OUT:-/etc/nginx/clinic-resolver.conf}"
ns="$(awk '/^nameserver/{print $2; exit}' "$RESOLV_CONF")"
case "$ns" in *:*) ns="[$ns]" ;; esac
printf 'resolver %s valid=10s ipv6=off;\n' "${ns:-127.0.0.11}" > "$OUT"
