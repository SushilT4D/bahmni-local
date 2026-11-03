#!/usr/bin/env bash
# First-boot budget: OpenMRS 1.2.0 can take 36 min to answer on
# a 1-vCPU VM -- the Initializer loads 42 masterdata CSVs into a 121k-patient
# database once, on the first boot -- and task 080 gave up at a fixed 25 min.
# The wait is now a named, overridable budget, the FAIL line says what the
# proxy last answered, and preflight warns on a single CPU.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
T80="${HERE}/../tasks/080-stack.sh"; T00="${HERE}/../tasks/000-preflight.sh"
code80="$(grep -vE '^[[:space:]]*#' "$T80")"

printf '%s' "$code80" | grep -q 'OPENMRS_BOOT_TIMEOUT_S:-3600' && ok_ "080 budget defaults to 3600 s and is overridable" || bad "080 has no OPENMRS_BOOT_TIMEOUT_S:-3600 default"
printf '%s' "$code80" | grep -qE 'wait_for_http_or_restart "\$url" "?\$\{?boot_s' && ok_ "080 passes the budget to the wait" || bad "080 does not pass the budget to wait_for_http_or_restart"
printf '%s' "$code80" | grep -qE 'wait_for_http_or_restart "\$url" 1500' && bad "080 still hard-codes 1500 s" || ok_ "080 no longer hard-codes 1500 s"
printf '%s' "$code80" | grep -q 'within 25 min' && bad "080 FAIL line still says 25 min" || ok_ "080 FAIL line is not a fixed 25 min"
printf '%s' "$code80" | grep -q 'still starting' && ok_ "080 tells a slow boot (302) from a dead one" || bad "080 does not name the still-starting case"

# the CPU block runs in isolation against lib.sh; PREFLIGHT_CPUS stands in for the host
blk="$(sed -n '/# cpu-budget:begin/,/# cpu-budget:end/p' "$T00")"
[ -n "$blk" ] || bad "000 has no cpu-budget block"
run(){ env -i PATH="$PATH" PREFLIGHT_CPUS="$1" PLATFORM=linux bash -c ". '${HERE}/../lib.sh'; ${blk}" 2>&1; }
out="$(run 1)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "one CPU is a warning, not a refusal" || bad "one CPU exits $rc"
printf '%s' "$out" | grep -q 'WARN' && printf '%s' "$out" | grep -q 'OPENMRS_BOOT_TIMEOUT_S' && ok_ "one CPU warns and names the budget knob" || bad "one CPU: no WARN naming OPENMRS_BOOT_TIMEOUT_S: $out"
out="$(run 4)"
printf '%s' "$out" | grep -q 'WARN' && bad "four CPUs warn" || ok_ "four CPUs pass quietly"
exit "$fails"
