#!/usr/bin/env bash
# The openmrs restore: stock MySQL settings (128 MB buffer pool, 100 MB redo
# log) make a multi-gigabyte load take hours on a small cloud disk, a silent
# restore cannot be told from a hung one, and "the person table exists" is
# also true of an interrupted restore -- a rerun must not carry on with half a
# database.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
eq(){ [ "$2" = "$3" ] && ok_ "$1" || bad "$1: got '$2', want '$3'"; }
T50="${HERE}/../tasks/050-databases.sh"
blk="$(sed -n '/# restore-rules:begin/,/# restore-rules:end/p' "$T50")"
[ -n "$blk" ] || { bad "050 has no restore-rules block"; exit 1; }
call(){ env -i PATH="$PATH" bash -c ". '${HERE}/../lib.sh'; ${blk}
\"\$@\"" _ "$@" 2>&1; }

# buffer pool for the restore: a quarter of what the database server can see, 128 MB steps, 128..4096
eq "pool: 13924 MB host -> 3456" "$(call restore_pool_mb 13924)" 3456
eq "pool: 64 GB host is capped at 4096" "$(call restore_pool_mb 65536)" 4096
eq "pool: a 400 MB machine gets the 512 floor" "$(call restore_pool_mb 400)" 512
eq "pool: junk input gets the 512 floor" "$(call restore_pool_mb '')" 512

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
outside="$(sed '/# drop-dbs:begin/,/# drop-dbs:end/d' "$T50" | grep -vE '^[[:space:]]*#')"
printf '%s' "$outside" | grep -qE 'DROP DATABASE' && bad "050 drops a database outside its one checked drop routine" || ok_ "050 drops databases only in its checked drop routine"

# which dumps each sitting restores: install the baseline, seed the seed folder
dd(){ env -i PATH="$PATH" PHASE="$1" CLINIC_DIR=/c REPO_DIR=/tmp SEED_DIR=/s bash -c ". '${HERE}/../lib.sh'; ${blk}
dump_dir" 2>&1; }
eq "install restores the baseline" "$(dd install)" /c/extracted/baseline
eq "seed restores the seed folder" "$(dd seed)" /s
# the drop that precedes a seed (or a changed baseline) is checked, never replicated
drop="$(sed -n '/# drop-dbs:begin/,/# drop-dbs:end/p' "$T50")"
[ -n "$drop" ] && ok_ "050 has one drop routine" || bad "050 has no drop-dbs block"
printf '%s' "$drop" | grep -q 'sql_log_bin=0' && ok_ "the MySQL drop is kept out of the binlog" || bad "the MySQL drop would be replicated"
printf '%s' "$drop" | grep -q 'ON_ERROR_STOP=1' && ok_ "a failed Postgres drop stops the task" || bad "a failed Postgres drop passes silently"
printf '%s' "$drop" | grep -q 'still there after the drop' && ok_ "each drop is read back" || bad "the drop is not read back"
grep -q 'BASELINE_SHA' "$T50" && ok_ "a changed baseline is dropped and restored" || bad "a changed baseline is never loaded"
exit "$fails"
