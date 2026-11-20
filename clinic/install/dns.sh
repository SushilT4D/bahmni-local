#!/usr/bin/env bash
# Sets up dnsmasq so clinic devices reach Bahmni and Odoo by the clinic's LAN name.
DNS_UPSTREAMS="${DNS_UPSTREAMS:-1.1.1.1 8.8.8.8}"

dnsmasq_conf(){ # NAME IFACE UPSTREAMS
  local name="$1" ifc="$2" u
  printf '# rendered by the clinic installer\n'
  printf 'local-service\nno-resolv\n'
  for u in $3; do printf 'server=%s\n' "$u"; done
  printf 'local=/%s/\ninterface-name=%s,%s\ninterface-name=odoo.%s,%s\n' "$name" "$name" "$ifc" "$name" "$ifc"
}

lan_iface(){ route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'; }

lan_ip(){
  local i; i="$(lan_iface)"
  ipconfig getifaddr "$i" 2>/dev/null || true
}

lan_resolve(){ # NAME [SERVER] -> first A record; SERVER defaults to 127.0.0.1.

  { dig +short +time=2 +tries=1 "$1" A "@${2:-127.0.0.1}" 2>/dev/null || true; } | grep -E '^[0-9.]+$' | head -1 || true
}

DNS_ETC="${DNS_ETC:-/etc}"
dns_wrong_answer(){ # NAME -> why NAME, asked at this machine's LAN address, is not that address; nothing when it is

  local ip got; ip="$(lan_ip)"; got="$(lan_resolve "$1" "$ip")"
  [ -n "$ip" ] && [ "$got" = "$ip" ] || printf "%s answers '%s', this machine is '%s'" "$1" "${got:-nothing}" "${ip:-unknown}"
}

dns_install_macos(){ # NAME
  local name="$1" ifc prefix d conf new res why=''
  if [ "${DRY}" = 1 ]; then
    info "would: brew install dnsmasq; write \$(brew --prefix)/etc/dnsmasq.d/bahmni-clinic.conf for ${name} and odoo.${name}; sudo brew services restart dnsmasq unless the config is unchanged and ${name} already answers with this machine's address; /etc/resolver/${name##*.} -> 127.0.0.1 unless it already says so"
    return 0
  fi

  ifc="$(lan_iface)"; [ -n "$ifc" ] || fail "no default network interface: connect this Mac to the clinic network (Ethernet) and re-run --from 010"
  if brew list --formula dnsmasq >/dev/null 2>&1; then skip "dnsmasq installed"; else run brew install dnsmasq; fi
  prefix="$(brew --prefix)"
  d="${prefix}/etc/dnsmasq.d"
  mkdir -p "$d"
  grep -qxF "conf-dir=${d}/,*.conf" "${prefix}/etc/dnsmasq.conf" 2>/dev/null || printf 'conf-dir=%s/,*.conf\n' "$d" >> "${prefix}/etc/dnsmasq.conf"
  conf="${d}/bahmni-clinic.conf"
  new="$(mktemp "${TMPDIR:-/tmp}/bahmni-clinic.XXXXXX")"
  dnsmasq_conf "$name" "$ifc" "${DNS_UPSTREAMS}" > "$new"
  if cmp -s "$new" "$conf"; then :; else cat "$new" > "$conf"; why="config changed"; fi
  rm -f "$new"

  [ -n "$why" ] || pgrep -x dnsmasq >/dev/null 2>&1 || why="dnsmasq not running"
  [ -n "$why" ] || why="$(dns_wrong_answer "$name")"
  if [ -z "$why" ]; then
    skip "dnsmasq restart: config unchanged, dnsmasq running, ${name} already answers with this machine's address"
  else
    info "dnsmasq restarts (${why}); it listens on port 53, which needs root: macOS asks for your password"
    sudo brew services restart dnsmasq >/dev/null
  fi

  res="${DNS_ETC}/resolver/${name##*.}"
  if grep -qxF 'nameserver 127.0.0.1' "$res" 2>/dev/null; then
    skip "${res} already sends .${name##*.} to 127.0.0.1"
  else
    sudo mkdir -p "${DNS_ETC}/resolver"
    printf 'nameserver 127.0.0.1\n' | sudo tee "$res" >/dev/null
  fi

  ok "dnsmasq answers for ${name} and odoo.${name} on ${ifc}"
}

dns_check(){ # NAME : both names answer with this machine's address
  local name="$1" ip got n
  [ "${DRY}" = 1 ] && { info "would: check ${name} and odoo.${name} resolve to this machine"; return 0; }
  local budget="${DNS_WAIT_S:-30}" t
  ip="$(lan_ip)"
  for n in "$name" "odoo.${name}"; do
    t=0
    got="$(lan_resolve "$n" "$ip")"
    while [ "$got" != "$ip" ] && [ "$t" -lt "$budget" ]; do sleep 2; t=$((t + 2)); got="$(lan_resolve "$n" "$ip")"; done
    [ -n "$got" ] && [ "$got" = "$ip" ] && ok "${n} -> ${ip} (dnsmasq)" \
      || fail "${n} did not resolve to ${ip} within ${budget}s (DNS_WAIT_S), last answer '${got:-nothing}': dnsmasq --test -C \$(brew --prefix)/etc/dnsmasq.conf on macOS; check that nothing else holds port 53"
  done
}
