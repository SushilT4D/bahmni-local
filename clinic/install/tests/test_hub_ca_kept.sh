#!/usr/bin/env bash
# The hub's certificate a TLS install was given is the one every later sitting
# trusts: lib.sh picks HUB_CA from the environment first, then the copy kept at
# clinic/certs/hub-ca.pem, then the fleet's sync/hub-ca.pem; task 020 keeps the copy.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/sync" "$TMP/repo/clinic/certs"
echo fleet > "$TMP/repo/sync/hub-ca.pem"
pick(){ ( unset HUB_CA; [ -n "${1:-}" ] && export HUB_CA="$1"; CLINIC_DIR="$TMP/repo/clinic" REPO_DIR="$TMP/repo" bash -c '. "'"${HERE}"'/../lib.sh" >/dev/null 2>&1; printf "%s" "$HUB_CA"' ); }
[ "$(pick)" = "$TMP/repo/sync/hub-ca.pem" ] && ok_ "no copy kept: the fleet's sync/hub-ca.pem" || bad "default without a kept copy: $(pick)"
echo kept > "$TMP/repo/clinic/certs/hub-ca.pem"
[ "$(pick)" = "$TMP/repo/clinic/certs/hub-ca.pem" ] && ok_ "a kept copy wins over the fleet's file" || bad "kept copy not preferred: $(pick)"
[ "$(pick /given/ca.pem)" = "/given/ca.pem" ] && ok_ "HUB_CA in the environment wins over both" || bad "environment not preferred: $(pick /given/ca.pem)"
blk="$(sed -n '/keep the certificate this install was given/,/^fi$/p' "${HERE}/../tasks/020-env.sh")"
printf '%s' "$blk" | grep -q 'cp "${HUB_CA}" "${HUB_CA_KEPT}.new"' && printf '%s' "$blk" | grep -q 'proto" = SASL_SSL' && printf '%s' "$blk" | grep -q 'DRY}" != 1' \
  && ok_ "task 020 keeps the certificate on a real TLS install only" || bad "020 keep block: $blk"
exit "$fails"
