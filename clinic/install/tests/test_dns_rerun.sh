#!/usr/bin/env bash
# A re-run of the LAN-name step over ssh has no terminal for sudo, so it must
# not ask for root when nothing changed: same config, dnsmasq running and the
# name already answering with this machine's address. A changed config or a
# wrong answer still restarts dnsmasq (macOS dnsmasq never follows a new
# address on its own). sudo, brew, dig, systemctl and pgrep are stubs on PATH
# that record what they were asked to do; nothing touches the real /etc.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
T="$(mktemp -d "${TMPDIR:-/tmp}/dns-rerun.XXXXXX")"; trap 'rm -rf "$T"' EXIT
B="${T}/bin"; mkdir -p "$B" "${T}/etc" "${T}/brew"
cat > "${B}/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_LOG}"
case " $* " in *" /etc"*) exit 0 ;; esac
exec "$@"
EOF
cat > "${B}/brew" <<'EOF'
#!/usr/bin/env bash
case "$1" in --prefix) printf '%s\n' "${STUB_BREW}" ;; esac
exit 0
EOF
cat > "${B}/dig" <<'EOF'
#!/usr/bin/env bash
[ -n "${STUB_ANSWER}" ] && printf '%s\n' "${STUB_ANSWER}"
exit 0
EOF
cat > "${B}/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in is-active) exit "${STUB_ACTIVE:-0}" ;; esac
exit 0
EOF
printf '#!/usr/bin/env bash\nexit "${STUB_ACTIVE:-0}"\n' > "${B}/pgrep"
printf '#!/usr/bin/env bash\nexit 0\n' > "${B}/dnsmasq"
chmod +x "${B}"/*
export PATH="${B}:${PATH}" STUB_LOG="${T}/sudo.log" STUB_BREW="${T}/brew" STUB_ANSWER=10.0.0.5 STUB_ACTIVE=0
export DNS_ETC="${T}/etc"

step(){ # PLATFORM [UPSTREAMS] : one run of the install step, sudo log reset first
  : > "${STUB_LOG}"
  ( . "${HERE}/../lib.sh"; . "${HERE}/../dns.sh"
    lan_iface(){ echo en0; }; lan_ip(){ echo 10.0.0.5; }
    DRY=0; DNS_UPSTREAMS="${2:-1.1.1.1}"
    "dns_install_$1" bahmni.clinic ) > "${T}/out" 2>&1
}
restarted(){ grep -qE 'services restart dnsmasq|systemctl restart dnsmasq' "${STUB_LOG}"; }

for p in macos linux; do
  step "$p"
  restarted && ok_ "${p}: first run restarts dnsmasq" || bad "${p}: first run did not restart dnsmasq"
  step "$p"
  [ -s "${STUB_LOG}" ] && bad "${p}: unchanged config, correct answer still ran sudo: $(tr '\n' ';' < "${STUB_LOG}")" \
    || ok_ "${p}: unchanged config with a correct answer runs no sudo"
  grep -q '^  skip dnsmasq restart' "${T}/out" && ok_ "${p}: says why it skipped" || bad "${p}: no skip line"
  step "$p" 9.9.9.9
  restarted && ok_ "${p}: changed config restarts dnsmasq" || bad "${p}: changed config did not restart"
  STUB_ANSWER=10.0.0.9 step "$p" 9.9.9.9
  restarted && ok_ "${p}: wrong answer restarts dnsmasq" || bad "${p}: wrong answer did not restart"
  STUB_ANSWER='' step "$p" 9.9.9.9
  restarted && ok_ "${p}: no answer restarts dnsmasq" || bad "${p}: no answer did not restart"
  STUB_ACTIVE=1 step "$p" 9.9.9.9
  restarted && ok_ "${p}: stopped dnsmasq is restarted" || bad "${p}: stopped dnsmasq was not restarted"
done
# the resolver file is written once and then left alone, even when dnsmasq restarts
STUB_ANSWER=10.0.0.9 step macos 9.9.9.9
restarted && ! grep -q 'resolver' "${STUB_LOG}" && ok_ "macOS: restart leaves a correct resolver alone" \
  || bad "macOS: resolver rewritten although it holds nameserver 127.0.0.1"
exit $((fails > 0))
