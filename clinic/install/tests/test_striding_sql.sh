#!/usr/bin/env bash
# clinic/odoo/apply-odoo-sequence-striding.sql against a REAL PostgreSQL, because
# its first ADR-005 version passed every fixture test and failed on a database:
# pg_get_serial_sequence('t','id') does not return NULL for a table that has no
# `id` column -- it RAISES, which rolled back the whole transaction, so even the
# id tables listed beside a link table stayed unstrided (found 2026-09-21 by
# running it on the dev box's PostgreSQL before any clinic did).
# A host without psql keeps a static guard.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL="${HERE}/../../odoo/apply-odoo-sequence-striding.sql"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
grep -q "attname = 'id'" "$SQL" && ok_ "the SQL asks whether an id column exists before resolving its sequence" || bad "no id-column existence check before pg_get_serial_sequence"
db="${STRIDING_TEST_DB:-bahmni_test}"
if command -v psql >/dev/null 2>&1 && psql -d "$db" -qAt -c 'select 1' >/dev/null 2>&1; then
  p="zz_$$"
  psql -d "$db" -q -v ON_ERROR_STOP=1 >/dev/null <<DDL
CREATE TABLE public.${p}_village (id serial PRIMARY KEY, name text);
INSERT INTO public.${p}_village(name) SELECT 'v'||g FROM generate_series(1,37) g;
CREATE TABLE public.${p}_empty (id serial PRIMARY KEY);
CREATE TABLE public.${p}_link (prod_id int, tax_id int, PRIMARY KEY (prod_id, tax_id));
CREATE TABLE public.${p}_nopk (a int, b int);
CREATE TABLE public.${p}_onecol (code text PRIMARY KEY);
DDL
  out="$(psql -d "$db" -v residue=3 -v tables="${p}_village,${p}_link,${p}_empty" -q -f "$SQL" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q ERROR && ok_ "an id table, a composite link table and an empty id table stride together" || bad "mixed list failed: $out"
  printf '%s' "$out" | grep -q "${p}_link.*composite" && ok_ "the link table is skipped with a NOTICE naming its composite key" || bad "no composite NOTICE for the link table: $out"
  [ "$(psql -d "$db" -qAt -c "select increment_by from pg_sequences where sequencename='${p}_village_id_seq'")" = 10 ] && ok_ "id table: step 10" || bad "village sequence step is not 10"
  [ "$(psql -d "$db" -qAt -c "select nextval('${p}_village_id_seq')")" = 43 ] && ok_ "id table: next id 43 (above max 37, residue 3)" || bad "village next id is not 43"
  [ "$(psql -d "$db" -qAt -c "select nextval('${p}_empty_id_seq')")" = 13 ] && ok_ "empty id table: next id 13 (residue 3)" || bad "empty table next id is not 13"
  out="$(psql -d "$db" -v residue=3 -v tables="${p}_nopk" -q -f "$SQL" 2>&1)"
  printf '%s' "$out" | grep -q "no composite primary key" && ok_ "a table with no key at all is still refused, in the script's own words" || bad "no-pk table: $out"
  out="$(psql -d "$db" -v residue=3 -v tables="${p}_onecol" -q -f "$SQL" 2>&1)"
  printf '%s' "$out" | grep -q "no composite primary key" && ok_ "a single-column non-serial key is still refused" || bad "one-column pk table: $out"
  psql -d "$db" -q -c "DROP TABLE public.${p}_village, public.${p}_empty, public.${p}_link, public.${p}_nopk, public.${p}_onecol" >/dev/null 2>&1
else
  ok_ "live PostgreSQL proof skipped (no psql / no ${db})"
fi
exit "$fails"
