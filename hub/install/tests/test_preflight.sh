#!/usr/bin/env bash
set -u; HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fails=0
assert_rc(){ if [ "$2" -eq "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: rc %s want %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
export DRY=1 HUB_DIR="$(mktemp -d)"; . "$HERE/../lib.sh"
binlog_ok ROW FULL 2592000 181 10 10 184060 >/dev/null; assert_rc "good binlog settings" $? 0
binlog_ok STATEMENT FULL 2592000 181 10 10 184060 >/dev/null; assert_rc "STATEMENT rejected" $? 1
binlog_ok ROW FULL 86400 181 10 10 184060 >/dev/null; assert_rc "one-day retention rejected" $? 1
binlog_ok ROW FULL 2592000 184060 10 10 184060 >/dev/null; assert_rc "server_id equal to the connector id rejected (F-059)" $? 1
binlog_ok ROW FULL 2592000 181 10 1 184060 >/dev/null; assert_rc "offset 1 (a clinic's) rejected" $? 1
printf '%s\n' "$fails failure(s)"; exit $((fails>0))
