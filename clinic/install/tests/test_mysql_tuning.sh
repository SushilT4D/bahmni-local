#!/usr/bin/env bash
# MySQL runs on the image's defaults (128 MB buffer pool, 100 MB redo log) unless
# told otherwise; on a 14 GB node that starves every read and turns a restore into
# hours. The installer renders one conf.d file sized from the memory the database
# server can see, and the compose file mounts it.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
eq(){ [ "$2" = "$3" ] && ok_ "$1" || bad "$1: got '$2', want '$3'"; }
LIB="${HERE}/../lib.sh"; T20="${HERE}/../tasks/020-env.sh"; CL="${HERE}/../../docker-compose.yml"; OV="${HERE}/../../docker-compose.override.yml"
call(){ env -i PATH="$PATH" bash -c ". '$LIB'; \"\$@\"" _ "$@" 2>&1; }

eq "pool: 13924 MB -> 3456" "$(call mysql_pool_mb 13924)" 3456
eq "pool: 65536 MB capped at 4096" "$(call mysql_pool_mb 65536)" 4096
eq "pool: 2048 MB -> 512 (floor)" "$(call mysql_pool_mb 2048)" 512
eq "pool: junk -> 512 (floor)" "$(call mysql_pool_mb '')" 512

cnf="$(call mysql_tuning_cnf 3456)"
printf '%s' "$cnf" | grep -q '^\[mysqld\]' && ok_ "cnf: [mysqld] section" || bad "cnf: no [mysqld] section"
printf '%s' "$cnf" | grep -q '^innodb_buffer_pool_size *= *3456M$' && ok_ "cnf: buffer pool 3456M" || bad "cnf: buffer pool line wrong: $cnf"
printf '%s' "$cnf" | grep -q '^innodb_redo_log_capacity *= *512M$' && ok_ "cnf: redo log 512M" || bad "cnf: no redo log line"

# task 020 renders it next to the env, sized from node_mem_mb
code20="$(grep -vE '^[[:space:]]*#' "$T20")"
printf '%s' "$code20" | grep -q 'mysql_tuning_cnf' && ok_ "020 renders the tuning file" || bad "020 does not render the tuning file"
printf '%s' "$code20" | grep -q 'config/mysql/sync-tuning.cnf' && ok_ "020 writes clinic/config/mysql/sync-tuning.cnf" || bad "020 writes it elsewhere"
grep -q 'config/mysql/sync-tuning.cnf:/etc/mysql/conf.d/sync-tuning.cnf:ro' "$CL" "$OV" && ok_ "compose mounts it read-only into conf.d" || bad "compose does not mount it"
REPO="$(cd "${HERE}/../../.." && pwd)"
( cd "$REPO" && git check-ignore -q clinic/config/mysql/sync-tuning.cnf ) && ok_ "the rendered file is gitignored" || bad "the rendered file is not gitignored"

# node_mem_mb: linux reads the host; macos reads the podman machine (the database server runs inside it)
out="$(env -i PATH="$PATH" PLATFORM=linux NODE_MEM_MB= bash -c ". '$LIB'; node_mem_mb" 2>&1)"
case "$out" in ''|*[!0-9]*) bad "node_mem_mb on linux is not a number: $out" ;; *) ok_ "node_mem_mb on linux: $out" ;; esac
out="$(env -i PATH="$PATH" PLATFORM=macos NODE_MEM_MB=6144 bash -c ". '$LIB'; node_mem_mb" 2>&1)"
eq "node_mem_mb honours NODE_MEM_MB (the tests' and operator's override)" "$out" 6144
# task 050 reads the value back from the running server (a mounted file proves nothing by itself)
grep -vE '^[[:space:]]*#' "${HERE}/../tasks/050-databases.sh" | grep -q 'select @@innodb_buffer_pool_size' && ok_ "050 reads innodb_buffer_pool_size back from the server" || bad "050 does not read the buffer pool back"
exit "$fails"
