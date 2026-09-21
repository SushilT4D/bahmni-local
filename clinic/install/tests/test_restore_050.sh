#!/usr/bin/env bash
# The openmrs restore (manpur rebuild, 2026-09-21): three hours of silence at
# 85% iowait on stock MySQL settings (128 MB buffer pool, 100 MB redo log), and
# a skip rule -- "the person table exists" -- that an interrupted restore also
# satisfies, so a rerun would have carried on with half a database.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
eq(){ [ "$2" = "$3" ] && ok_ "$1" || bad "$1: got '$2', want '$3'"; }
T50="${HERE}/../tasks/050-databases.sh"
blk="$(sed -n '/# restore-rules:begin/,/# restore-rules:end/p' "$T50")"
[ -n "$blk" ] || { bad "050 has no restore-rules block"; exit 1; }
call(){ env -i PATH="$PATH" bash -c "${blk}
\"\$@\"" _ "$@" 2>&1; }

# buffer pool for the restore: a quarter of what the database server can see, 128 MB steps, 128..4096
eq "pool: 13924 MB host -> 3456" "$(call restore_pool_mb 13924)" 3456
eq "pool: 64 GB host is capped at 4096" "$(call restore_pool_mb 65536)" 4096
eq "pool: a 400 MB machine keeps the stock 128" "$(call restore_pool_mb 400)" 128
eq "pool: junk input keeps the stock 128" "$(call restore_pool_mb '')" 128

sql="$(call restore_tune_sql 3456)"
printf '%s' "$sql" | grep -q 'innodb_buffer_pool_size=3623878656' && ok_ "tune: buffer pool in bytes" || bad "tune: no buffer pool bytes: $sql"
printf '%s' "$sql" | grep -q 'innodb_redo_log_capacity=2147483648' && ok_ "tune: 2 GB redo log" || bad "tune: no redo capacity"
printf '%s' "$sql" | grep -q 'innodb_flush_log_at_trx_commit=2' && ok_ "tune: relaxed flush for the restore" || bad "tune: no flush setting"
printf '%s' "$sql" | grep -qi 'PERSIST' && bad "tune: PERSIST would outlive the restore" || ok_ "tune: nothing is persisted"
rev="$(call restore_revert_sql 134217728 104857600 1 1)"
for want in 'innodb_buffer_pool_size=134217728' 'innodb_redo_log_capacity=104857600' 'innodb_flush_log_at_trx_commit=1' 'sync_binlog=1'; do
  printf '%s' "$rev" | grep -q "$want" && ok_ "revert: $want" || bad "revert lacks $want"
done

# what to do, from: person table exists? done-marker exists? tables in the database, tables in the dump
eq "state: empty database -> restore"                          "$(call restore_state 0 0 0 0)"     restore
eq "state: restored and marked -> skip"                        "$(call restore_state 1 1 0 0)"     skip
eq "state: unmarked but every table present -> adopt"          "$(call restore_state 1 0 412 412)" adopt
eq "state: unmarked and tables missing -> interrupted"         "$(call restore_state 1 0 190 412)" interrupted
eq "state: unmarked and the dump could not be counted -> interrupted" "$(call restore_state 1 0 190 0)" interrupted

code="$(grep -vE '^[[:space:]]*#' "$T50")"
printf '%s' "$code" | grep -q 'restore_state ' && ok_ "050 decides through restore_state" || bad "050 does not call restore_state"
printf '%s' "$code" | grep -q 'restore_revert_sql' && printf '%s' "$code" | grep -q 'trap ' && ok_ "050 reverts the settings on any exit" || bad "050 has no revert trap"
printf '%s' "$code" | grep -q 'still restoring' && ok_ "050 reports progress while it restores" || bad "050 restores in silence"
printf '%s' "$code" | grep -qE 'DROP DATABASE' && bad "050 drops a database by itself" || ok_ "050 never drops a database itself"
exit "$fails"
