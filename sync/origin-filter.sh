# The origin filter: a Debezium source publishes a change to a table that
# carries an id floor only when the change is to a row this node wrote.
#
# Below a table's floor every row is the hub's own, written before the fleet
# was strided; it is copied to every clinic by the seed, and its residue says
# nothing about who wrote it. At or above the floor a row's id is on the
# residue of the node that wrote it (MySQL issues ids 10 apart, offset by the
# residue). A clinic that edits its copy of a hub row, or of another node's
# row, keeps the edit to itself: publishing it would make two writers of one
# row on the hub, and the hub's upsert would take whichever came last.
#
# So for each such table the source carries one io.debezium.transforms.Filter
# step, applied only to that table's topic (a TopicNameMatches predicate), that
# keeps a record iff
#     record key >= floor  AND  record key % 10 == residue
# The condition reads the record KEY, never the value, and runs on tombstones
# too (null.handling.mode=evaluate): a delete is published only for a row this
# node may write, and the tombstone that follows it the same. Other topics
# pass untouched.
#
# The filter fails closed. Its class and the Groovy engine it names live in
# jars the Connect worker must carry in the MySQL plugin directory
# (clinic/docker-compose.yml mounts them): without the class Connect refuses
# the configuration, and without the engine the connector fails at start. No
# configuration is ever rendered without the filter for a table that needs one.
#
# The functions take the residue as a parameter (0 to 9), so the hub can use
# the same step with its own residue.
#
# bash 3.2 compatible (macOS).

ORIGIN_FILTER_TYPE="io.debezium.transforms.Filter"
ORIGIN_FILTER_LANGUAGE="jsr223.groovy"
ORIGIN_FILTER_PREDICATE_TYPE="org.apache.kafka.connect.transforms.predicates.TopicNameMatches"

# origin_filter_condition PK FLOOR RESIDUE : the Groovy condition, on one line.
# key.get(<column>) reads a field of the record key (a Connect Struct).
origin_filter_condition(){
  local pk="$1" fl="$2" r="$3"
  printf '%s' "$pk" | grep -qE '^[a-z_][a-z0-9_]*$' || { printf 'origin filter: key column %s is not one plain column name\n' "${pk:-(empty)}" >&2; return 1; }
  case "$fl" in ''|*[!0-9]*) printf 'origin filter: floor %s is not a number\n' "${fl:-(empty)}" >&2; return 1 ;; esac
  case "$r" in [0-9]) ;; *) printf 'origin filter: residue %s is not 0 to 9\n' "${r:-(empty)}" >&2; return 1 ;; esac
  printf "key != null && key.get('%s') instanceof Number && key.get('%s').longValue() >= %sL && key.get('%s').longValue() %% 10 == %s" "$pk" "$pk" "$fl" "$pk" "$r"
}

# origin_filter_topic_pattern PREFIX DB TABLE : the regex for exactly one
# topic, every character that is not a letter, digit, _ or - escaped.
origin_filter_topic_pattern(){
  printf '%s.%s.%s' "$1" "$2" "$3" | sed 's/[^A-Za-z0-9_-]/\\&/g'
}

# origin_filter_lines PREFIX DB RESIDUE : reads "table pk floor" lines on stdin
# and prints the connector configuration keys of the filter, one per line, as
# "<key><TAB><value>". Prints nothing for no lines. Returns 1, with the reason
# on stderr, for a line it cannot render: a table with no floor is never
# rendered without its filter.
origin_filter_lines(){
  local prefix="$1" db="$2" r="$3" t pk fl cond aliases="" preds="" out=""
  while read -r t pk fl; do
    [ -n "$t" ] || continue
    [ -n "$fl" ] || { printf 'origin filter: %s has no floor, so no filter can be rendered for it\n' "$t" >&2; return 1; }
    cond="$(origin_filter_condition "$pk" "$fl" "$r")" || return 1
    aliases="${aliases:+${aliases},}origin_${t}"
    preds="${preds:+${preds},}topic_${t}"
    out="${out}transforms.origin_${t}.type	${ORIGIN_FILTER_TYPE}
transforms.origin_${t}.language	${ORIGIN_FILTER_LANGUAGE}
transforms.origin_${t}.condition	${cond}
transforms.origin_${t}.null.handling.mode	evaluate
transforms.origin_${t}.predicate	topic_${t}
predicates.topic_${t}.type	${ORIGIN_FILTER_PREDICATE_TYPE}
predicates.topic_${t}.pattern	$(origin_filter_topic_pattern "$prefix" "$db" "$t")
"
  done
  [ -n "$aliases" ] || return 0
  printf 'transforms\t%s\npredicates\t%s\n%s' "$aliases" "$preds" "$out"
}

# origin_filter_merge CONNECTOR_JSON LINES_FILE : adds the keys to the
# connector's "config" in place. A "transforms" or "predicates" list the
# connector already has is kept, the filter's appended to it.
origin_filter_merge(){
  python3 - "$1" "$2" <<'PY'
import json, sys
path, lines = sys.argv[1], sys.argv[2]
doc = json.load(open(path))
cfg = doc["config"] if "config" in doc else doc
for line in open(lines):
    line = line.rstrip("\n")
    if not line:
        continue
    k, v = line.split("\t", 1)
    if k in ("transforms", "predicates") and cfg.get(k):
        v = cfg[k] + "," + v
    cfg[k] = v
with open(path, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
}

# origin_filter_read CONFIG_JSON TABLE : from a connector config (the object
# Connect's GET /connectors/<name>/config returns, or a file holding
# {"name", "config"}), prints "<pk> <floor> <residue>" read back out of TABLE's
# filter step, or returns 1 with what is missing or not as rendered here.
origin_filter_read(){
  python3 - "$1" "$2" "$ORIGIN_FILTER_TYPE" "$ORIGIN_FILTER_LANGUAGE" "$ORIGIN_FILTER_PREDICATE_TYPE" <<'PY'
import json, re, sys
src, table, ftype, lang, ptype = sys.argv[1:6]
try:
    doc = json.load(open(src))
except Exception as e:
    print("the connector configuration cannot be read as JSON (%s)" % e); sys.exit(1)
cfg = doc.get("config", doc)
a, p = "origin_" + table, "topic_" + table
def fail(msg):
    print(msg); sys.exit(1)
if a not in [x.strip() for x in cfg.get("transforms", "").split(",")]:
    fail("the source connector has no filter step for %s: every change to %s would be published, including edits to rows this clinic does not own" % (table, table))
t = "transforms." + a + "."
if cfg.get(t + "type") != ftype or cfg.get(t + "language") != lang:
    fail("the %s filter step is not %s in %s (type %s, language %s)" % (table, ftype, lang, cfg.get(t + "type"), cfg.get(t + "language")))
if cfg.get(t + "null.handling.mode") != "evaluate":
    fail("the %s filter step does not judge deletes' tombstones (null.handling.mode is %s, not evaluate)" % (table, cfg.get(t + "null.handling.mode")))
if cfg.get(t + "predicate") != p or p not in [x.strip() for x in cfg.get("predicates", "").split(",")]:
    fail("the %s filter step is not limited to the %s topic (predicate %s)" % (table, table, cfg.get(t + "predicate")))
if cfg.get("predicates." + p + ".type") != ptype or not re.search(r"\\\.%s$" % re.escape(table), cfg.get("predicates." + p + ".pattern", "")):
    fail("the %s filter step's topic test does not name the %s topic (pattern %s)" % (table, table, cfg.get("predicates." + p + ".pattern")))
m = re.fullmatch(r"key != null && key\.get\('([a-z_][a-z0-9_]*)'\) instanceof Number && key\.get\('\1'\)\.longValue\(\) >= ([0-9]+)L && key\.get\('\1'\)\.longValue\(\) % 10 == ([0-9])", cfg.get(t + "condition", ""))
if not m:
    fail("the %s filter condition is not the floor-and-residue test this installer writes: %s" % (table, cfg.get(t + "condition")))
print(m.group(1), m.group(2), m.group(3))
PY
}

# origin_filter_verdict CONFIG_JSON TABLES_CONF FLOORS OFFSET : the registered
# source's filter, read back, against what this node is. For every table the
# list takes its floor from the seed or from another table: the step exists,
# its residue is OFFSET mod 10 (MySQL's @@auto_increment_offset, read from the
# server), and its floor is the one FLOORS (a manifest.env, or the floors the
# seed gate recorded from it) gives for that table. Prints one "ok ..." line
# per table, or the first refusal and returns 1. A list that cannot be read is
# a refusal, never a pass.
origin_filter_verdict(){
  local cfg="$1" conf="$2" floors="$3" off="$4" recs t pk kind arg got rpk rfl rr want r out="" n=0
  case "$off" in ''|*[!0-9]*) printf 'could not read MySQL'"'"'s auto_increment_offset (got '"'"'%s'"'"'), so the capture filter'"'"'s residue cannot be checked. Wait a minute and run the same command again; if it persists, call the operator.\n' "$off"; return 1 ;; esac
  r=$(( off % 10 ))
  type up_tables_read >/dev/null 2>&1 || { printf 'origin_filter_verdict needs sync/local/tables-conf.sh sourced first\n'; return 1; }
  recs="$(up_tables_read "$conf" 2>&1)" || { printf 'the clinic table list cannot be read, so the capture filter was not checked: %s\n' "$recs"; return 1; }
  while read -r t pk kind arg; do
    case "$kind" in seed|floor) ;; *) continue ;; esac
    n=$((n+1))
    got="$(origin_filter_read "$cfg" "$t")" || { printf '%s\n' "$got"; return 1; }
    read -r rpk rfl rr <<EOF
$got
EOF
    [ "$rpk" = "$pk" ] || { printf 'the %s capture filter tests column %s, but the table'"'"'s key is %s\n' "$t" "$rpk" "$pk"; return 1; }
    if [ "$rr" != "$r" ]; then
      printf 'the %s capture filter keeps residue %s, but this MySQL issues ids on residue %s (auto_increment_offset %s): every change this clinic makes to %s would be dropped. Regenerate and register the source connector (scripts/generate-connectors.sh, then scripts/register-source-connector.sh) or call the operator.\n' "$t" "$rr" "$r" "$off" "$t"
      return 1
    fi
    want="$(up_floor_of "$conf" "$t" "$floors" 2>&1)" || { printf 'the %s floor this clinic was seeded with cannot be read, so its capture filter was not checked: %s\n' "$t" "$want"; return 1; }
    if [ "$rfl" != "$want" ]; then
      printf 'the %s capture filter starts at %s, but the floor this clinic was seeded with is %s. Regenerate and register the source connector (scripts/generate-connectors.sh, then scripts/register-source-connector.sh) or call the operator.\n' "$t" "$rfl" "$want"
      return 1
    fi
    out="${out}ok ${t} capture filter: key ${pk} at or above ${rfl}, residue ${rr}
"
  done <<EOF
$recs
EOF
  [ "$n" -gt 0 ] || { printf 'ok no table in the clinic table list needs a capture filter\n'; return 0; }
  printf '%s' "$out"
}
