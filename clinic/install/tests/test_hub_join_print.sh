#!/usr/bin/env bash
# Task 110 prints the join for the hub this node was seeded from: HUB_SSH taken
# from the seed's manifest, the seed manifest to pass, this node's row, the
# sinks the hub registers for it, and the status command that tells a joined
# node from one joined to another hub or never joined. It never tells the
# operator to register every connector on a hub.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
mkdir -p "$T/seed" "$T/clinic"; printf 'SEED_TAKEN_AT=x\nHUB_SSH=bhamni@hub.example\n' > "$T/seed/manifest.env"
run(){ env -i PATH="$PATH" HOME="$HOME" DRY=0 INSTALL_DIR="${HERE}/.." CLINIC_DIR="$T/clinic" REPO_DIR="$T" SEED_DIR="$1" \
  CLINIC_SLUG=ghated LOCAL_CLUSTER_ALIAS=ghated MYSQL_SERVER_NAME=bahmni-ghated REMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.example:9092 \
  bash "${HERE}/../tasks/110-hub-join.sh" 2>&1; }
out="$(run "$T/seed")"
printf '%s' "$out" | grep -q 'HUB_SSH=bhamni@hub.example ' && ok_ "the hub is the one the seed's manifest names" || bad "no HUB_SSH from the manifest: $out"
printf '%s' "$out" | grep -q 'install-clinic.sh join ghated' && printf '%s' "$out" | grep -q 'SEED_MANIFEST=<the seed folder>/manifest.env' && ok_ "the join command names the seed manifest and the node" || bad "join command incomplete: $out"
printf '%s' "$out" | grep -q 'install-clinic.sh status ghated' && printf '%s' "$out" | grep -q 'sinks registered and RUNNING' && ok_ "it ends with the status command and what a joined node shows" || bad "no status command: $out"
printf '%s' "$out" | grep -q 'ghated:mysql-sink-ghated-:ghated:bahmni-ghated' && ok_ "the hub's clinics row for this node is printed" || bad "no row: $out"
printf '%s' "$out" | grep -q 'register-all' && bad "it tells the operator to register every connector on the hub" || ok_ "it never says to register every connector on the hub"
out="$(run "$T/none")"
printf '%s' "$out" | grep -q 'HUB_SSH=<operator>@<hub> ' && ok_ "with no seed manifest the hub is a placeholder to fill in" || bad "no placeholder without a manifest: $out"
exit $((fails > 0))
