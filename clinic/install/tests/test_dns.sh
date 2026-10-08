#!/usr/bin/env bash
# The dnsmasq config the installer writes: the LAN name and odoo.<name> follow
# the interface's live address, nothing else is answered locally, no DHCP.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${HERE}/../lib.sh"; . "${HERE}/../dns.sh"; CLINIC_DIR="${HERE}/.."; . "${HERE}/../state.sh"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
c="$(dnsmasq_conf bahmni.clinic eth0 '1.1.1.1 8.8.8.8')"
has(){ printf '%s\n' "$c" | grep -qxF "$1" && ok_ "has: $1" || bad "missing: $1"; }
has 'interface-name=bahmni.clinic,eth0'
has 'interface-name=odoo.bahmni.clinic,eth0'
has 'local=/bahmni.clinic/'
has 'no-resolv'
has 'server=1.1.1.1'
has 'server=8.8.8.8'
has 'bind-dynamic'
has 'listen-address=127.0.0.1'
has 'interface=eth0'
printf '%s\n' "$c" | grep -qE '^dhcp-' && bad "DHCP directive present" || ok_ "no DHCP"
printf '%s\n' "$c" | grep -qE '^address=' && bad "a fixed address is pinned" || ok_ "no pinned address"
# macOS dnsmasq has no bind-dynamic: binding named interfaces there fixes the
# addresses present at start, so a lease that changes later is never served.
# Wildcard binding, answering only the local subnets, follows any address.
m="$(dnsmasq_conf bahmni.clinic en0 '1.1.1.1' macos)"
printf '%s\n' "$m" | grep -qxF 'local-service' && ok_ "macOS: answers local subnets only" || bad "macOS: no local-service"
printf '%s\n' "$m" | grep -qE '^(bind-dynamic|bind-interfaces|interface=)' && bad "macOS: names an option macOS dnsmasq lacks or a fixed interface" || ok_ "macOS: no bind option it cannot honour"
printf '%s\n' "$m" | grep -qxF 'interface-name=odoo.bahmni.clinic,en0' && ok_ "macOS: names follow en0's address" || bad "macOS: no interface-name"
grep -q 'dnsmasq_conf "$name" "$ifc" "${DNS_UPSTREAMS}" macos' "${HERE}/../dns.sh" && ok_ "macOS installer renders the macOS form" || bad "macOS installer renders the Linux form"
# the gate asks the address LAN devices ask, not loopback
grep -q 'lan_resolve "$name" "$ip"' "${HERE}/../tasks/005-seed-gate.sh" && ok_ "seed gate asks the LAN address" || bad "seed gate asks loopback"
case "$(lan_name_verdict 10.0.0.9 10.0.0.5 bahmni.clinic)" in *"--only 010"*) ok_ "a moved machine's refusal names the re-point command" ;; *) bad "moved-machine refusal names no fix" ;; esac
# dnsmasq is still starting when its service manager returns: the check waits
# on a named budget instead of reading one early empty answer as a failure
D="$(sed -n '/^dns_check()/,/^}/p' "${HERE}/../dns.sh")"
printf '%s' "$D" | grep -q 'DNS_WAIT_S' && ok_ "dns_check waits on a named budget" || bad "dns_check reads one answer and fails"
printf '%s' "$D" | grep -q 'within' && ok_ "its FAIL names the budget" || bad "its FAIL does not name the budget"
# the Linux package starts dnsmasq on install, and its stock wildcard bind
# collides with systemd-resolved: our config must be in place first
L="$(sed -n '/^dns_install_linux()/,/^}/p' "${HERE}/../dns.sh" | grep -v "would:")"
w="$(printf '%s\n' "$L" | grep -n 'bahmni-clinic.conf' | head -1 | cut -d: -f1)"
i="$(printf '%s\n' "$L" | grep -nE 'apt[-_]get install' | head -1 | cut -d: -f1)"
[ -n "$w" ] && [ -n "$i" ] && [ "$w" -lt "$i" ] && ok_ "linux: config written before the package is installed" || bad "linux: config not written before apt-get install (w=$w i=$i)"
M="${HERE}/../host-macos.sh"
grep -q 'ip_unprivileged_port_start=80' "$M" && ok_ "macOS: podman machine may bind ports from 80" || bad "macOS: no low-port sysctl"
grep -q 'dns_install_macos' "$M" && ok_ "macOS host installs dnsmasq" || bad "macOS host does not install dnsmasq"
grep -q 'dns_install_linux' "${HERE}/../host-linux.sh" && ok_ "Linux host installs dnsmasq" || bad "Linux host does not install dnsmasq"
exit $((fails > 0))
