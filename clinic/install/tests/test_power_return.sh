#!/usr/bin/env bash
# The macOS host layer sets power-on after a power failure and checks the two
# things only a person can set; the README names the manual steps.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
I="$(cd "${HERE}/.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
has(){ grep -qF -- "$2" "$I/$1" && ok_ "$1: $3" || bad "$1: $3 (no '$2')"; }
has host-macos.sh 'pmset -a autorestart 1' "powers on after a power failure"
has host-macos.sh 'autoLoginUser' "checks automatic login"
has host-macos.sh 'fdesetup status' "checks FileVault"
has README.md '## After a power cut' "has the section"
has README.md 'automatic login' "names the Mac step"
has README.md 'AC power' "names the PC firmware step"
has README.md 'up -d' "says existing nodes recreate their containers once"
exit $((fails > 0))
