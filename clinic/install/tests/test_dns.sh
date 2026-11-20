#!/usr/bin/env bash
# The dnsmasq config the installer writes: the LAN name and odoo.<name> follow
# the interface's live address, nothing else is answered locally, no DHCP.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${HERE}/../lib.sh"; . "${HERE}/../dns.sh"; CLINIC_DIR="${HERE}/.."; . "${HERE}/../state.sh"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
c="$(dnsmasq_conf bahmni.clinic en0 '1.1.1.1 8.8.8.8')"
has(){ printf '%s\n' "$c" | grep -qxF "$1" && ok_ "has: $1" || bad "missing: $1"; }
has 'interface-name=bahmni.clinic,en0'
has 'interface-name=odoo.bahmni.clinic,en0'
has 'local=/bahmni.clinic/'
has 'no-resolv'
has 'server=1.1.1.1'
has 'server=8.8.8.8'
printf '%s\n' "$c" | grep -qE '^dhcp-' && bad "DHCP directive present" || ok_ "no DHCP"
printf '%s\n' "$c" | grep -qE '^address=' && bad "a fixed address is pinned" || ok_ "no pinned address"
# macOS dnsmasq has no bind-dynamic: wildcard binding, answering only the
# local subnets, follows any address.
has 'local-service'
printf '%s\n' "$c" | grep -qE '^(bind-dynamic|bind-interfaces|interface=)' && bad "names an option macOS dnsmasq lacks or a fixed interface" || ok_ "no bind option macOS dnsmasq cannot honour"
# dnsmasq is still starting when its service manager returns: the check waits
# on a named budget instead of reading one early empty answer as a failure
D="$(sed -n '/^dns_check()/,/^}/p' "${HERE}/../dns.sh")"
printf '%s' "$D" | grep -q 'DNS_WAIT_S' && ok_ "dns_check waits on a named budget" || bad "dns_check reads one answer and fails"
printf '%s' "$D" | grep -q 'within' && ok_ "its FAIL names the budget" || bad "its FAIL does not name the budget"
M="${HERE}/../host-macos.sh"
grep -q 'ip_unprivileged_port_start=80' "$M" && ok_ "macOS: podman machine may bind ports from 80" || bad "macOS: no low-port sysctl"
grep -q 'dns_install_macos' "$M" && ok_ "macOS host installs dnsmasq" || bad "macOS host does not install dnsmasq"
exit $((fails > 0))
