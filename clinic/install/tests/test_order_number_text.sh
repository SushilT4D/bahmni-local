#!/usr/bin/env bash
# Nothing in this repo reads an order number as a number or assumes its width.
#
# Each node issues order numbers (ORD-<k>) from its own range of k: a clinic of
# residue r issues r x 10,000,000 + 1 up to (r + 1) x 10,000,000 - 1, and the hub
# issues below 10,000,000. So the numeric part has a different width on the hub
# and on every clinic, and two nodes never issue the same k. Code that turns an
# order number into an integer (to sort it, to compare it, to compute the next
# one), that cuts it at a fixed position, or that declares a column or pattern
# of a fixed width, would mis-sort, truncate or reject another node's numbers.
# The orders table holds it as varchar(50).
#
# This test scans every tracked file, plus the clinic's extracted UI and config
# (clinic/extracted/, when an install has extracted them), for an order-number
# name with a numeric or width operation within 40 characters of it. A
# deliberate reader (a check that reads the numeric part to find its node's
# range, written to accept any width) goes in ALLOWED with the reason beside it.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$(cd "${HERE}/../../.." && pwd)"
SELF="clinic/install/tests/$(basename "${BASH_SOURCE[0]}")"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

# Repo paths allowed to read the numeric part, one per line, each with why.
ALLOWED=""

# order_number_scan LIST : prints FILE:LINE:SNIPPET for every hit in the files
# LIST names, one path per line, relative to the current directory. A hit is
# an order-number name -- order_number / orderNumber as a whole word (so
# the global property order.nextOrderNumberSeed, a number by definition, is
# not one) or the ORD- prefix not inside a longer word -- with, within 40
# characters of it, a conversion to a number, arithmetic, a cut at a position,
# the prefix stripped, a digit pattern or a fixed repetition count, or a
# declared width. One python3 process reads every file: a grep per file with a
# bounded window is minutes on the repo's one-line form JSON.
order_number_scan(){
  python3 - "$1" <<'PY_SCAN'
import re, sys
name = re.compile(r'(?<![a-z0-9_])(?:order_number|ordernumber)(?![a-z0-9_])|(?<![a-z0-9_])ord-', re.I)
ops = re.compile(r'parse(?:int|float|long|double)|number\(|valueof\(|(?<![a-z0-9_.])int\(|cast\(|convert\(|to_number'
                 r'|::(?:int|bigint|numeric)|substr|(?<![a-z0-9_])(?:left|right|mid)\(|length\(|lpad|rpad|replace\('
                 r'|\.split\(|\.slice\(|\\d|\[0-9\]|\{[0-9]+(?:,[0-9]*)?\}|(?<![a-z0-9_])(?:var)?char\('
                 r'|(?:order_number|ordernumber) *[-+*/%]', re.I)
for f in open(sys.argv[1]).read().splitlines():
    if not f:
        continue
    try:
        data = open(f, 'rb').read()
    except (IOError, OSError):
        continue
    if b'\0' in data[:8192]:
        continue
    low = data.lower()
    if b'order_number' not in low and b'ordernumber' not in low and b'ord-' not in low:
        continue
    for no, line in enumerate(data.decode('utf-8', 'replace').splitlines(), 1):
        for m in name.finditer(line):
            w = line[max(0, m.start() - 40):m.end() + 40]
            if ops.search(w):
                print('%s:%d:%s' % (f, no, w.strip()))
PY_SCAN
}

# --- the scan catches what it is for -----------------------------------------
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
scan1(){ (cd "$T" && printf '%s\n' "$1" > list1 && order_number_scan list1); }
hits(){ scan1 "$1" | wc -l | tr -d ' '; }
printf 'var n = parseInt(order.orderNumber.replace("ORD-", ""), 10);\n' > "$T/parse.js"
printf 'SELECT CAST(SUBSTRING(order_number, 5) AS UNSIGNED) FROM orders;\n' > "$T/cast.sql"
printf '  order_number varchar(10) NOT NULL,\n' > "$T/width.sql"
printf 'if (!/^ORD-\\d{6}$/.test(no)) { reject(); }\n' > "$T/regex.js"
printf 'next = order_number + 1\n' > "$T/arith.py"
for f in parse.js cast.sql width.sql regex.js arith.py; do
  [ "$(hits "$f")" -ge 1 ] && ok_ "flags $(cat "$T/$f" | sed 's/^ *//')" || bad "does not flag $f: $(cat "$T/$f")"
done
cat > "$T/benign.txt" <<'TXT'
"pacsImageUrl":"/viewer?accessionNumber={{orderNumber}}",
SELECT order_number, COUNT(*) FROM orders GROUP BY 1 HAVING COUNT(*) > 1;
set order.nextOrderNumberSeed to the start of the range: substr(x, 1)
the prescription shows ORD-30000001 on the dashboard
MYSQL_PASSWORD-file: replace(x)
TXT
[ "$(hits benign.txt)" = 0 ] && ok_ "passes text that carries an order number as a string, and the seed property" || bad "flags benign text: $(scan1 benign.txt)"

# --- the repo, and the extracted UI and config --------------------------------
if git -C "$R" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  files="$(git -C "$R" ls-files)"
else
  files="$(cd "$R" && find . -type f ! -path './.git/*' | sed 's|^\./||')"
fi
if [ -d "$R/clinic/extracted" ]; then
  files="${files}
$(cd "$R" && find clinic/extracted -type f)"
fi
n="$(printf '%s\n' "$files" | grep -c .)"
printf '%s\n' "$files" | grep -v -x -F "$SELF" | while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ -n "$ALLOWED" ] && printf '%s\n' "$ALLOWED" | grep -q -x -F "$f"; then continue; fi
  printf '%s\n' "$f"
done > "$T/list"
found="$(cd "$R" && order_number_scan "$T/list")"
if [ -z "$found" ]; then
  ok_ "no file of ${n} reads an order number as a number or assumes its width"
else
  bad "these lines read an order number as a number or assume its width; another node's numbers have a different width and range:"
  printf '%s\n' "$found" | cut -c1-200 | head -20 | sed 's/^/         /'
fi
exit "$fails"
