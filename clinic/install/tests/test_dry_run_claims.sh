#!/usr/bin/env bash
# install.sh --dry-run changes nothing and ends saying nothing was installed, not "done".
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/logs"
mkdir -p "$TMP/tasks" "$TMP/ic"
printf '#!/usr/bin/env bash\necho probe\n' > "$TMP/tasks/05-probe.sh"
printf 'CLINIC_SLUG=tst\nRESIDUE=7\nMRN_PREFIX=TST\nSITE_NUMBER=7\nCLINIC_PHONE=+910000000000\nCERT_HOSTNAME=t.test\nREMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.test:9092\nREMOTE_KAFKA_USERNAME=m\nREMOTE_KAFKA_PASSWORD=p\nOPENMRS_ATOMFEED_PASSWORD=a\nOPENELIS_ATOMFEED_PASSWORD=b\nODOO_ATOMFEED_PASSWORD=c\n' > "$TMP/answers.env"
printf 'tst:7\n' > "$TMP/ledger"
out="$(CLINIC_DIR="$TMP/ic" REPO_DIR="$RP" TASKS_DIR="$TMP/tasks" LEDGER="$TMP/ledger" INSTALL_LOG="$TMP/logs/install.log" bash "$RP/clinic/install/install.sh" --answers "$TMP/answers.env" --dry-run </dev/null 2>&1)"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'probe'; then
  case "$out" in *"done: installed"*) bad "install.sh --dry-run says done: installed" ;; *) ok_ "install.sh --dry-run does not say it installed anything" ;; esac
else bad "install dry run did not run its task: rc=$rc $(printf '%s' "$out" | tail -3)"; fi
case "$out" in *"dry run: nothing was installed or changed."*) ok_ "install.sh --dry-run ends saying nothing was installed" ;; *) bad "install dry run end: $(printf '%s' "$out" | tail -2)" ;; esac
exit $((fails > 0))
