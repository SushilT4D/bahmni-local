#!/usr/bin/env bash
# The clinic LAN name. dnsmasq on this machine answers for <LAN_NAME> and
# odoo.<LAN_NAME> with the address the default-route interface has NOW
# (interface-name=), so a machine that gets a new address after it is moved
# keeps answering correctly without a re-run. Every other name is forwarded
# to public resolvers: the clinic router hands this machine out as DNS, so
# forwarding back to the router would loop. No DHCP: the router keeps that.
# bash 3.2 compatible.
DNS_UPSTREAMS="${DNS_UPSTREAMS:-1.1.1.1 8.8.8.8}"

dnsmasq_conf(){ # NAME IFACE UPSTREAMS [linux|macos]
  local name="$1" ifc="$2" u
  printf '# rendered by the clinic installer\n'
  if [ "${4:-linux}" = macos ]; then
    # dnsmasq on macOS has no bind-dynamic: it listens on the addresses the
    # machine has when it starts, and an address gained later is not served
    # until dnsmasq restarts. The router's DHCP reservation keeps this
    # machine's address fixed (README); a machine that moves anyway is caught
    # by the seed gate. local-service answers only hosts on its own subnets.
    printf 'local-service\nno-resolv\n'
  else
    # bind-dynamic follows address changes on Linux and leaves systemd-resolved's
    # 127.0.0.53 alone
    printf 'interface=%s\nlisten-address=127.0.0.1\nbind-dynamic\nno-resolv\n' "$ifc"
  fi
  for u in $3; do printf 'server=%s\n' "$u"; done
  printf 'local=/%s/\ninterface-name=%s,%s\ninterface-name=odoo.%s,%s\n' "$name" "$name" "$ifc" "$name" "$ifc"
}
lan_iface(){
  if [ "$(detect_platform)" = macos ]; then route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'
  else ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'; fi
}
lan_ip(){
  local i; i="$(lan_iface)"
  if [ "$(detect_platform)" = macos ]; then ipconfig getifaddr "$i" 2>/dev/null || true
  else ip -4 -o addr show dev "$i" 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}'; fi
}
lan_resolve(){ # NAME [SERVER] -> first A record; SERVER defaults to 127.0.0.1.
  # Ask the machine's LAN address to see what clinic devices see.
  { dig +short +time=2 +tries=1 "$1" A "@${2:-127.0.0.1}" 2>/dev/null || true; } | grep -E '^[0-9.]+$' | head -1 || true
}

dns_install_macos(){ # NAME
  local name="$1" ifc prefix d
  if [ "${DRY}" = 1 ]; then
    info "would: brew install dnsmasq; write \$(brew --prefix)/etc/dnsmasq.d/bahmni-clinic.conf for ${name} and odoo.${name}; sudo brew services restart dnsmasq; /etc/resolver/${name##*.} -> 127.0.0.1"
    return 0
  fi
  ifc="$(lan_iface)"; [ -n "$ifc" ] || fail "no default network interface: connect this Mac to the clinic network (Ethernet) and re-run --from 010"
  if brew list --formula dnsmasq >/dev/null 2>&1; then skip "dnsmasq installed"; else run brew install dnsmasq; fi
  prefix="$(brew --prefix)"; d="${prefix}/etc/dnsmasq.d"
  mkdir -p "$d"
  grep -qxF "conf-dir=${d}/,*.conf" "${prefix}/etc/dnsmasq.conf" 2>/dev/null || printf 'conf-dir=%s/,*.conf\n' "$d" >> "${prefix}/etc/dnsmasq.conf"
  dnsmasq_conf "$name" "$ifc" "${DNS_UPSTREAMS}" macos > "${d}/bahmni-clinic.conf"
  info "dnsmasq listens on port 53, which needs root: macOS asks for your password once"
  sudo brew services restart dnsmasq >/dev/null
  sudo mkdir -p /etc/resolver
  printf 'nameserver 127.0.0.1\n' | sudo tee "/etc/resolver/${name##*.}" >/dev/null
  ok "dnsmasq answers for ${name} and odoo.${name} on ${ifc}"
}
dns_install_linux(){ # NAME
  local name="$1" ifc
  if [ "${DRY}" = 1 ]; then
    info "would: write /etc/dnsmasq.d/bahmni-clinic.conf for ${name} and odoo.${name}; apt-get install dnsmasq; send ~${name##*.} lookups on this machine to it through systemd-resolved"
    return 0
  fi
  ifc="$(lan_iface)"; [ -n "$ifc" ] || fail "no default network interface"
  # The config goes in BEFORE the package: the package starts dnsmasq on
  # install, and its stock wildcard bind collides with systemd-resolved's
  # 127.0.0.53:53, so the install itself would fail. Ours binds only the LAN
  # interface and 127.0.0.1.
  sudo mkdir -p /etc/dnsmasq.d
  dnsmasq_conf "$name" "$ifc" "${DNS_UPSTREAMS}" | sudo tee /etc/dnsmasq.d/bahmni-clinic.conf >/dev/null
  command -v dnsmasq >/dev/null 2>&1 || apt_get install -y -qq dnsmasq
  sudo systemctl enable dnsmasq >/dev/null 2>&1
  sudo systemctl restart dnsmasq
  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    # this machine resolves its own LAN name through dnsmasq; everything else as before
    sudo mkdir -p /etc/systemd/resolved.conf.d
    printf '[Resolve]\nDNS=127.0.0.1\nDomains=~%s\n' "${name##*.}" | sudo tee /etc/systemd/resolved.conf.d/bahmni-clinic.conf >/dev/null
    sudo systemctl restart systemd-resolved
  fi
  ok "dnsmasq answers for ${name} and odoo.${name} on ${ifc}"
}
dns_check(){ # NAME : both names answer with this machine's address
  local name="$1" ip got n
  [ "${DRY}" = 1 ] && { info "would: check ${name} and odoo.${name} resolve to this machine"; return 0; }
  local budget="${DNS_WAIT_S:-30}" t
  ip="$(lan_ip)"
  for n in "$name" "odoo.${name}"; do
    # dnsmasq is still starting when its service manager returns
    t=0; got="$(lan_resolve "$n" "$ip")"
    while [ "$got" != "$ip" ] && [ "$t" -lt "$budget" ]; do sleep 2; t=$((t + 2)); got="$(lan_resolve "$n" "$ip")"; done
    [ -n "$got" ] && [ "$got" = "$ip" ] && ok "${n} -> ${ip} (dnsmasq)" \
      || fail "${n} did not resolve to ${ip} within ${budget}s (DNS_WAIT_S), last answer '${got:-nothing}': dnsmasq --test -C \$(brew --prefix)/etc/dnsmasq.conf on macOS; check that nothing else holds port 53"
  done
}
