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
