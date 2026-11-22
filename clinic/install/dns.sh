#!/usr/bin/env bash
# Sets up dnsmasq so clinic devices reach Bahmni and Odoo by the clinic's LAN name.
DNS_UPSTREAMS="${DNS_UPSTREAMS:-1.1.1.1 8.8.8.8}"

dnsmasq_conf(){ # NAME IP UPSTREAMS : address=/NAME/ also answers odoo.NAME
  local u
  printf '# rendered by the clinic installer\n'
  printf 'local-service\nno-resolv\n'
  for u in $3; do printf 'server=%s\n' "$u"; done
  printf 'local=/%s/\naddress=/%s/%s\n' "$1" "$1" "$2"
}

lan_resolve(){ # NAME [SERVER] -> first A record; SERVER defaults to 127.0.0.1.

  { dig +short +time=2 +tries=1 "$1" A "@${2:-127.0.0.1}" 2>/dev/null || true; } | grep -E '^[0-9.]+$' | head -1 || true
}

DNS_ETC="${DNS_ETC:-/etc}"
dns_wrong_answer(){ # NAME -> why NAME, asked at LAN_IP, is not LAN_IP; nothing when it is
  local got; got="$(lan_resolve "$1" "${LAN_IP}")"
  [ "$got" = "${LAN_IP}" ] || printf "%s answers '%s', not %s" "$1" "${got:-nothing}" "${LAN_IP}"
}

dns_main_conf_ok(){ # PREFIX : the main dnsmasq.conf holds only the conf-dir line; any other setting (an old listen-address, address=) overrides the rendered file
  local main="$1/etc/dnsmasq.conf"
  [ "$(grep -vE '^[[:space:]]*(#|$)' "$main" 2>/dev/null)" = "conf-dir=$1/etc/dnsmasq.d/,*.conf" ]
}

dns_restart_reason(){ # NAME : why dnsmasq needs a (root) restart; nothing when it does not
  local name="$1" prefix new
  command -v brew >/dev/null 2>&1 && brew list --formula dnsmasq >/dev/null 2>&1 || { printf 'dnsmasq not installed'; return 0; }
  prefix="$(brew --prefix)"
  dns_main_conf_ok "$prefix" || { printf 'main config changes'; return 0; }
  new="$(dnsmasq_conf "$name" "${LAN_IP}" "${DNS_UPSTREAMS}")"
  [ "$new" = "$(cat "${prefix}/etc/dnsmasq.d/bahmni-clinic.conf" 2>/dev/null)" ] || { printf 'config changes'; return 0; }
  pgrep -x dnsmasq >/dev/null 2>&1 || { printf 'dnsmasq not running'; return 0; }
  dns_wrong_answer "$name"
}

dns_resolver_ok(){ # NAME
  grep -qxF 'nameserver 127.0.0.1' "${DNS_ETC}/resolver/${1##*.}" 2>/dev/null
}

dns_root_pending(){ # NAME : the dnsmasq steps that need sudo, comma-separated; nothing when none
  local r out=''
  r="$(dns_restart_reason "$1")"; [ -z "$r" ] || out="dnsmasq restart (${r})"
  dns_resolver_ok "$1" || out="${out:+${out}, }${DNS_ETC}/resolver/${1##*.}"
  printf '%s' "$out"
}

dns_install_macos(){ # NAME
  local name="$1" prefix d main conf why
  if [ "${DRY}" = 1 ]; then
    info "would: brew install dnsmasq; reduce \$(brew --prefix)/etc/dnsmasq.conf to its conf-dir line (old one kept as dnsmasq.conf.bak); write \$(brew --prefix)/etc/dnsmasq.d/bahmni-clinic.conf for ${name} and odoo.${name}; sudo brew services restart dnsmasq unless the config is unchanged and ${name} already answers ${LAN_IP}; /etc/resolver/${name##*.} -> 127.0.0.1 unless it already says so"
    return 0
  fi

  why="$(dns_restart_reason "$name")"
  if brew list --formula dnsmasq >/dev/null 2>&1; then skip "dnsmasq installed"; else run brew install dnsmasq; fi
  prefix="$(brew --prefix)"
  d="${prefix}/etc/dnsmasq.d"; main="${prefix}/etc/dnsmasq.conf"; conf="${d}/bahmni-clinic.conf"
  mkdir -p "$d"
  if ! dns_main_conf_ok "$prefix"; then
    [ ! -s "$main" ] || [ -e "${main}.bak" ] || cp "$main" "${main}.bak"
    printf 'conf-dir=%s/,*.conf\n' "$d" > "$main"
    ok "${main} holds only conf-dir (earlier settings kept in ${main}.bak)"
  fi
  dnsmasq_conf "$name" "${LAN_IP}" "${DNS_UPSTREAMS}" > "$conf"

  if [ -z "$why" ]; then
    skip "dnsmasq restart: config unchanged, dnsmasq running, ${name} already answers ${LAN_IP}"
  else
    info "dnsmasq restarts (${why})"
    sudo -n brew services restart dnsmasq >/dev/null || fail "sudo brew services restart dnsmasq needs a password: the installer asks for it when it starts; run it from a terminal"
  fi

  if dns_resolver_ok "$name"; then
    skip "${DNS_ETC}/resolver/${name##*.} already sends .${name##*.} to 127.0.0.1"
  else
    { sudo -n mkdir -p "${DNS_ETC}/resolver" && printf 'nameserver 127.0.0.1\n' | sudo -n tee "${DNS_ETC}/resolver/${name##*.}" >/dev/null; } \
      || fail "writing ${DNS_ETC}/resolver/${name##*.} needs sudo: the installer asks for it when it starts; run it from a terminal"
  fi

  ok "dnsmasq answers ${LAN_IP} for ${name} and odoo.${name}"
}

dns_check(){ # NAME : both names answer LAN_IP
  local name="$1" ip="${LAN_IP}" got n
  [ "${DRY}" = 1 ] && { info "would: check ${name} and odoo.${name} resolve to this machine"; return 0; }
  local budget="${DNS_WAIT_S:-30}" t
  for n in "$name" "odoo.${name}"; do
    t=0
    got="$(lan_resolve "$n" "$ip")"
    while [ "$got" != "$ip" ] && [ "$t" -lt "$budget" ]; do sleep 2; t=$((t + 2)); got="$(lan_resolve "$n" "$ip")"; done
    [ -n "$got" ] && [ "$got" = "$ip" ] && ok "${n} -> ${ip} (dnsmasq)" \
      || fail "${n} did not resolve to ${ip} within ${budget}s (DNS_WAIT_S), last answer '${got:-nothing}': dnsmasq --test -C \$(brew --prefix)/etc/dnsmasq.conf on macOS; check that nothing else holds port 53"
  done
}
