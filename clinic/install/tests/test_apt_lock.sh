#!/usr/bin/env bash
# On Linux, task 010 meets Ubuntu's automatic updates holding the package lock
# on a freshly booted machine. Every apt-get waits for it (apt_get, lib.sh):
#   - a lock released within the budget: the wait is said, then apt-get runs,
#     itself told to wait for a lock taken in between (DPkg::Lock::Timeout);
#   - a lock still held when the budget runs out: FAIL, naming the process;
#   - no lock: apt-get runs at once; a dry run only says what it would run;
#   - the Linux host layer and the LAN-name install use apt_get, never a bare
#     apt-get.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
# sudo runs its command; fuser reports pid 4242 on the dpkg front-end lock for
# the first $W/held calls; ps names it; apt-get records its arguments
printf '#!/bin/sh\n"$@"\n' > "$W/bin/sudo"
cat > "$W/bin/fuser" <<SH
#!/bin/sh
n=\$(cat "$W/held" 2>/dev/null || echo 0)
if [ "\$1" = /var/lib/dpkg/lock-frontend ] && [ "\$n" -gt 0 ]; then echo \$((n - 1)) > "$W/held"; echo " 4242"; fi
exit 0
SH
printf '#!/bin/sh\necho unattended-upgr\n' > "$W/bin/ps"
printf '#!/bin/sh\necho "$*" >> "%s/apt.log"\n' "$W" > "$W/bin/apt-get"
chmod +x "$W/bin/"*
run(){ # HELD-POLLS TIMEOUT CMD : run CMD with lib.sh, the lock held for HELD-POLLS polls
  echo "$1" > "$W/held"; rm -f "$W/apt.log"
  env PATH="$W/bin:$PATH" DRY="${DRY_RUN:-0}" APT_LOCK_TIMEOUT_S="$2" APT_LOCK_POLL_S=1 bash -c ". '${HERE}/../lib.sh'; $3" 2>&1
}
out="$(run 3 600 'apt_get install -y -qq dnsmasq')"; rc=$?
[ "$rc" = 0 ] && ok_ "a lock released within the budget: apt-get runs after it" || bad "released lock: rc=$rc $out"
case "$out" in *"the package manager is busy (process 4242 unattended-upgr); waiting up to 600s"*) ok_ "the wait is said, naming the holder" ;; *) bad "no wait message: $out" ;; esac
[ "$(cat "$W/apt.log" 2>/dev/null)" = "-o DPkg::Lock::Timeout=600 install -y -qq dnsmasq" ] && ok_ "apt-get itself waits for a lock taken in between (DPkg::Lock::Timeout)" || bad "apt-get args: $(cat "$W/apt.log" 2>/dev/null)"
out="$(run 99 3 'apt_get update -qq')"; rc=$?
[ "$rc" != 0 ] && case "$out" in *"FAIL the package manager is still locked after 3s, held by process 4242 unattended-upgr"*"--from 010"*) true ;; *) false ;; esac && ok_ "a lock held past the budget: FAIL naming the process, and how to resume" || bad "held lock: rc=$rc $out"
[ ! -f "$W/apt.log" ] && ok_ "and apt-get was never run into the lock" || bad "apt-get ran under the lock: $(cat "$W/apt.log")"
out="$(run 0 600 'apt_get update -qq')"; rc=$?
[ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q busy && [ "$(cat "$W/apt.log")" = "-o DPkg::Lock::Timeout=600 update -qq" ] && ok_ "no lock: apt-get runs at once" || bad "no lock: rc=$rc $out"
out="$(DRY_RUN=1 run 99 3 'apt_get install -y -qq podman')"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "  would: sudo apt-get install -y -qq podman" ] && [ ! -f "$W/apt.log" ] && ok_ "dry run: says what it would run, waits for nothing" || bad "dry run: rc=$rc $out"
bare="$(grep -nE '(^|[^_])apt-get (update|install)' "${HERE}/../host-linux.sh" "${HERE}/../dns.sh" | grep -v 'info "would' || true)"
[ -z "$bare" ] && ok_ "host-linux.sh and dns.sh run apt-get only through apt_get" || bad "bare apt-get: $bare"
grep -B1 "get.docker.com | sudo sh" "${HERE}/../host-linux.sh" | grep -q apt_wait_lock && ok_ "the Docker install script waits for the lock first (it runs apt-get itself)" || bad "the Docker install script does not wait for the lock"
exit $((fails > 0))
