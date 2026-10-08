#!/usr/bin/env bash
# Task 100 reads each application back through the clinic LAN name, by
# content, and the install sitting stops after those pages.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; S="${HERE}/../tasks/100-exit-checks.sh"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
grep -q -- '--resolve' "$S" && ok_ "pages fetched by name, resolved locally" || bad "no --resolve"
grep -q '"authenticated"' "$S" && ok_ "OpenMRS page asserted by content" || bad "OpenMRS not asserted by content"
grep -qi 'openelis' "$S" && grep -q -- '--baseline' "$S" && ok_ "OpenELIS failure names the baseline override" || bad "OpenELIS failure does not name --baseline"
grep -qF 'odoo.${N}' "$S" && ok_ "Odoo checked on its own name" || bad "Odoo not on its own name"
grep -qE '9444|BAHMNI_ODOO_HTTPS_PORT' "$S" && bad "old Odoo port remains" || ok_ "no old Odoo port"
grep -q 'PHASE:-install}" = install' "$S" && ok_ "install sitting stops after the pages" || bad "no install-sitting exit"
# Tomcat's own 404 page names the path ("/openelis/"), so the word alone proves
# nothing: the page must answer 200 and not be a Tomcat error page
sed -n '/^elis_page_ok()/,/^}/p' "${HERE}/../lib.sh" | grep -q 'HTTP Status' && ok_ "a Tomcat error page is not taken for OpenELIS" || bad "a Tomcat 404 would pass as OpenELIS"
sed -n '/^elis_page_ok()/,/^}/p' "${HERE}/../lib.sh" | grep -q '"$1" = 200' && ok_ "OpenELIS must answer 200" || bad "OpenELIS status code not checked"
# OpenELIS starts after OpenMRS answers and can take minutes more on a small
# machine: one early probe would stop a healthy install. The check waits on a
# named budget, and its FAIL says how long it waited.
grep -q 'OPENELIS_BOOT_TIMEOUT_S' "$S" && ok_ "OpenELIS waited for on a named budget" || bad "OpenELIS probed once, no wait"
grep -qE 'does not answer as OpenELIS.*within' "$S" && ok_ "OpenELIS FAIL names the wait" || bad "OpenELIS FAIL does not name the wait"
# The check runs under pipefail. A page piped into `grep -q` lets grep exit at
# the first match while the writer is still writing; the writer dies of SIGPIPE
# and pipefail fails the test of a page that matched. A real login page is
# tens of kilobytes, so judge it with a page that size.
. "${HERE}/../lib.sh"
big="<html><head><title>OpenELIS</title></head><body>$(head -c 200000 /dev/zero | tr '\0' 'x')</body></html>"
( set -euo pipefail; elis_page_ok 200 "$big" ) && ok_ "a 200 KB OpenELIS page passes under pipefail" || bad "a large OpenELIS page fails under pipefail (SIGPIPE)"
( set -euo pipefail; elis_page_ok 200 "<html><h1>HTTP Status 404 - /openelis/</h1></html>" ) && bad "a Tomcat error page passes" || ok_ "a Tomcat error page fails"
( set -euo pipefail; elis_page_ok 302 "$big" ) && bad "a non-200 passes" || ok_ "a non-200 fails"
( set -euo pipefail; elis_page_ok 200 "<html>login</html>" ) && bad "a page that is not OpenELIS passes" || ok_ "a page that is not OpenELIS fails"
grep -q 'elis_page_ok "$elis_code" "$elis_body"' "$S" && ok_ "task 100 judges the page with elis_page_ok" || bad "task 100 does not use elis_page_ok"
# Whether the writer loses that race depends on the OS and the page, so the
# behaviour above cannot always show it: no page body may be piped into grep -q.
F="$(sed -n '/^elis_page_ok()/,/^}/p' "${HERE}/../lib.sh")"
printf '%s\n' "$F" | grep -q 'grep -q' && bad "elis_page_ok pipes the page into grep -q (SIGPIPE under pipefail)" || ok_ "elis_page_ok reads the whole page before judging it"
grep -qE 'printf .%s. "\$elis_body" \| grep -q' "$S" && bad "task 100 still pipes the OpenELIS page into grep -q" || ok_ "task 100 pipes no page into grep -q"
# --- the capture filter, read back from the registered connector ---------------
# The source connector Connect holds is judged, not the generated file: its
# residue must be the offset the running MySQL issues ids on, and its floors
# those the seed's manifest gives. A wrong residue would drop every change the
# clinic makes, silently.
RP="$(cd "${HERE}/../../.." && pwd)"
CF="$(mktemp -d)"; trap 'rm -rf "$CF"' EXIT
mkdir -p "$CF/repo/clinic"; cp -R "$RP/clinic/scripts" "$CF/repo/clinic/"; cp -R "$RP/sync" "$CF/repo/"
printf 'obs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\nvisit:visit_id:625000\n' > "$CF/repo/sync/local/tables.conf"
printf 'MYSQL_SERVER_NAME=bahmni-t\nRESIDUE=3\n' > "$CF/repo/clinic/.env"
mkdir -p "$CF/seed"; printf 'FLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$CF/seed/manifest.env"
SEED_MANIFEST="$CF/seed/manifest.env" bash "$CF/repo/clinic/scripts/generate-connectors.sh" >/dev/null 2>&1 || bad "fixture: the generator did not render the clinical list"
# what GET /connectors/<name>/config answers: the config map, flat, with its name
reg(){ # [PYTHON-EDIT] : the registered config, optionally edited, into $CF/reg.json
  python3 - "$CF/repo/clinic/connectors/mysql-local-source-connector.json" "$CF/reg.json" "${1:-}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); c = dict(d["config"]); c["name"] = d["name"]
exec(sys.argv[3] or "")
json.dump(c, open(sys.argv[2], "w"))
PY
}
. "$CF/repo/sync/local/tables-conf.sh"; . "$CF/repo/sync/origin-filter.sh"
V(){ origin_filter_verdict "$CF/reg.json" "$CF/repo/sync/local/tables.conf" "${2:-$CF/seed/manifest.env}" "$1"; }
reg; out="$(V 3)"; rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^ok .* capture filter')" = 3 ] && ok_ "registered filter, residue 3 on a MySQL at offset 3, floors as the manifest: passes for obs, orders, drug_order" || bad "good filter: rc=$rc $out"
out="$(V 4)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"keeps residue 3, but this MySQL issues ids on residue 4"*) true ;; *) false ;; esac && ok_ "a filter residue other than MySQL's offset is refused" || bad "residue 3 vs offset 4: rc=$rc $out"
out="$(V '')"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"auto_increment_offset"*) true ;; *) false ;; esac && ok_ "an offset that cannot be read is a refusal, not a pass" || bad "no offset: rc=$rc $out"
printf 'FLOOR_OBS=5000010\nFLOOR_ORDERS=300000\n' > "$CF/other.env"
out="$(V 3 "$CF/other.env")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"obs capture filter starts at 5000000, but the floor this clinic was seeded with is 5000010"*) true ;; *) false ;; esac && ok_ "a filter floor other than the manifest's is refused" || bad "floor mismatch: rc=$rc $out"
printf 'FLOOR_OBS=5000000\nFLOOR_ORDERS=300010\n' > "$CF/other.env"
out="$(V 3 "$CF/other.env")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"orders capture filter starts at 300000"*) true ;; *) false ;; esac && ok_ "the orders floor is checked too" || bad "orders floor mismatch: rc=$rc $out"
reg 'c["transforms"] = "origin_orders,origin_drug_order"'; out="$(V 3)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"no filter step for obs"*) true ;; *) false ;; esac && ok_ "a registered source without the obs step is refused" || bad "no obs step: rc=$rc $out"
reg 'c["transforms.origin_drug_order.null.handling.mode"] = "keep"'; out="$(V 3)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"tombstones"*) true ;; *) false ;; esac && ok_ "a step that passes tombstones unjudged is refused" || bad "keep tombstones: rc=$rc $out"
reg 'c["predicates.topic_obs.pattern"] = ".*"'; out="$(V 3)"; rc=$?
[ "$rc" = 1 ] && ok_ "a step not limited to its own topic is refused" || bad "any-topic predicate: rc=$rc $out"
reg 'c["predicates.topic_obs.pattern"] = "bahmni-x\\.openmrs\\.obs"'; out="$(V 3)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"not exactly this connector's obs topic (bahmni-t\\.openmrs\\.obs)"*) true ;; *) false ;; esac && ok_ "a step whose topic test names another prefix's obs topic is refused" || bad "wrong-prefix predicate: rc=$rc $out"
reg 'c["topic.prefix"] = "bahmni-u"'; out="$(V 3)"; rc=$?
[ "$rc" = 1 ] && ok_ "a connector whose topic prefix changed after its filter was rendered is refused" || bad "changed prefix: rc=$rc $out"
reg 'c["transforms.origin_obs.condition"] = "true"'; out="$(V 3)"; rc=$?
[ "$rc" = 1 ] && ok_ "a condition that is not the floor-and-residue test is refused" || bad "condition true: rc=$rc $out"
reg; printf 'obs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id\n' > "$CF/bad.conf"
out="$(origin_filter_verdict "$CF/reg.json" "$CF/bad.conf" "$CF/seed/manifest.env" 3)"; rc=$?
[ "$rc" = 1 ] && ok_ "a table list that cannot be read is a refusal" || bad "unreadable list: rc=$rc $out"
# the installer reads Connect's copy: curl and the MySQL read stand in, the
# generated file says residue 3, Connect holds residue 3, MySQL issues on 4
reg
out="$(
  curl(){ cat "$CF/reg.json"; }
  ct(){ cat >/dev/null; echo 4; }
  REPO_DIR="$CF/repo" SEED_DIR="$CF/seed" COMPOSE_PROJECT_NAME=t capture_filter_check
)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"residue 4"*) true ;; *) false ;; esac && ok_ "capture_filter_check judges what Connect answers against the running MySQL" || bad "capture_filter_check: rc=$rc $out"
out="$(
  curl(){ return 22; }
  ct(){ cat >/dev/null; echo 3; }
  REPO_DIR="$CF/repo" SEED_DIR="$CF/seed" COMPOSE_PROJECT_NAME=t capture_filter_check
)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"could not read the registered"*) true ;; *) false ;; esac && ok_ "a connector Connect does not hold is a refusal (never the generated file instead)" || bad "no registered connector: rc=$rc $out"
F="$(sed -n '/^capture_filter_check()/,/^}/p' "${HERE}/../lib.sh")"
printf '%s\n' "$F" | grep -q '/connectors/mysql-source-connector/config' && ! printf '%s\n' "$F" | grep -qE 'connectors/mysql-(local-)?source-connector\.json' \
  && ok_ "the check reads the registered configuration, never the generated file" || bad "capture_filter_check does not read Connect's registered configuration"
S90="${HERE}/../tasks/090-local-sync.sh"
awk '/register-source-connector.sh/ {r=NR} /capture_filter_check/ && r && !c {c=NR} END {exit !(r && c > r)}' "$S90" && ok_ "task 90 checks the filter after registering the source" || bad "task 90 does not check the filter after registering"
grep -q 'capture_filter_check' "$S" && ok_ "task 100 checks the filter again at exit" || bad "task 100 does not check the filter"
# the operator's check script reports the same verdict, and fails on it
mkdir -p "$CF/bin"; printf 'FLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$CF/repo/clinic/.install-state"
cat > "$CF/bin/curl" <<EOF
#!/bin/sh
for a; do u="\$a"; done
case "\$u" in
  */config) cat "$CF/reg.json" ;;
  */status) echo '{"connector":{"state":"RUNNING"},"tasks":[{"id":0,"state":"RUNNING"}]}' ;;
  */connectors) echo '["mysql-source-connector"]' ;;
esac
EOF
chmod +x "$CF/bin/curl"; reg
out="$(PATH="$CF/bin:$PATH" MYSQL_OFFSET=3 bash "$CF/repo/clinic/scripts/check-source-connectors.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c 'ok .* capture filter')" = 3 ] && ok_ "check-source-connectors.sh: the filter read back and passed" || bad "check-source-connectors.sh, good: rc=$rc $(printf '%s' "$out" | tail -3)"
out="$(PATH="$CF/bin:$PATH" MYSQL_OFFSET=5 bash "$CF/repo/clinic/scripts/check-source-connectors.sh" 2>&1)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"residue 5"*) true ;; *) false ;; esac && ok_ "check-source-connectors.sh: a wrong residue fails the check" || bad "check-source-connectors.sh, offset 5: rc=$rc $(printf '%s' "$out" | tail -3)"
exit $((fails > 0))
