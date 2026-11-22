#!/usr/bin/env bash
# Turns FileVault off and automatic login on, so the Mac comes back by itself after a power cut.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "05 · FileVault off, automatic login on"

u="$(id -un)"
[ "$u" != root ] || fail "run the installer as the clinic's Mac user, not root"
fv="$(fdesetup status 2>/dev/null || true)"
fv_on=1; case "$fv" in *"FileVault is Off"*|*"Decryption in progress"*) fv_on=0 ;; esac
al="$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true)"
al_on=0; [ "$al" = "$u" ] && al_on=1

[ "$fv_on" = 1 ] || ok "FileVault: $(printf '%s' "$fv" | head -1)"
[ "$al_on" = 0 ] || ok "automatic login is on for ${u}"
[ "$fv_on" = 1 ] || [ "$al_on" = 0 ] || exit 0
if [ "${DRY}" = 1 ]; then
  [ "$fv_on" = 0 ] || info "would: ask ${u}'s password, then fdesetup disable"
  [ "$al_on" = 1 ] || info "would: ask ${u}'s password, then sysadminctl -autologin set -userName ${u}"
  exit 0
fi

[ -r /dev/tty ] || fail "this step asks for ${u}'s password: run the installer from a terminal"
sudo -v || fail "sudo refused"
pw=""
for try in 1 2 3; do
  printf '  password of Mac user %s: ' "$u" > /dev/tty
  IFS= read -rs pw < /dev/tty; printf '\n' > /dev/tty
  dscl . -authonly "$u" "$pw" >/dev/null 2>&1 && break
  pw=""; warn "wrong password for ${u} (try ${try} of 3)"
done
[ -n "$pw" ] || fail "no correct password for ${u}: FileVault and automatic login left as they were"

if [ "$fv_on" = 1 ]; then
  xml_pw="$(printf '%s' "$pw" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Username</key><string>%s</string><key>Password</key><string>%s</string></dict></plist>\n' "$u" "$xml_pw" \
    | sudo fdesetup disable -inputplist >/dev/null || fail "fdesetup disable failed: turn FileVault off in System Settings > Privacy & Security, then resume --from 005"
  ok "FileVault turning off: $(fdesetup status | head -1). Decryption runs in the background; automatic login applies once it ends"
fi

if [ "$al_on" = 0 ]; then
  sudo sysadminctl -autologin set -userName "$u" -password "$pw" >/dev/null 2>&1 || true
  pw=""
  got="$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true)"
  if [ "$got" != "$u" ]; then
    case "$(fdesetup status 2>/dev/null || true)" in
      *"FileVault is Off"*) fail "macOS did not turn on automatic login for ${u} (autoLoginUser is '${got}'): System Settings > Users & Groups, then resume --from 005" ;;
      *) fail "automatic login waits for FileVault to finish turning off ($(fdesetup status | head -1)): resume with --from 005 once fdesetup status says Off" ;;
    esac
  fi
  ok "automatic login is on for ${u}"
fi
pw=""
