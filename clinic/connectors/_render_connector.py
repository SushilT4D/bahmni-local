#!/usr/bin/env python3
"""Render a connector JSON for registration: substitute credentials from the
environment and emit the bare config object.

Substitutes ONLY names that actually exist in the environment. Kafka Connect has its
own ${topic} placeholder which it expands at runtime in table.name.format, and an
unconditional substitution silently turned it into an empty string -- the sink then
tried to write to a table named `public.` and every task died with
`Invalid identifier: public.` while the CONNECTOR still reported RUNNING. Only the
task state showed it. Unknown placeholders are therefore passed through untouched.
"""
import json, os, re, sys

d = json.load(open(sys.argv[1]))
cfg = d.get('config', d)


def sub(v):
    if not isinstance(v, str):
        return v
    return re.sub(r'\$\{(\w+)\}',
                  lambda m: os.environ[m.group(1)] if m.group(1) in os.environ else m.group(0),
                  v)


cfg = {k: sub(v) for k, v in cfg.items()}

# Kafka Connect expands these itself at runtime, so they MUST survive rendering.
# ${source.table} and friends contain a dot, which \w+ above never matches, so they
# pass through without needing to be listed here.
RUNTIME_PLACEHOLDERS = {'topic'}

# Fail on ANY placeholder we did not resolve, not just credentials. A guard
# over `password` keys alone would be enough only while the only variables
# were secrets. Node identity is parameterised too --
# topic.prefix, database.server.name, the transform regexes and replacements all
# carry ${MYSQL_SERVER_NAME} -- and an unset variable there does NOT fail loudly:
# it registers a connector whose topic prefix is the literal "${MYSQL_SERVER_NAME}",
# publishing to a topic no consumer subscribes to, while the connector reports
# RUNNING. A clinic would look healthy and sync nothing.
unresolved = sorted(
    k for k, v in cfg.items()
    if isinstance(v, str)
    for m in re.finditer(r'\$\{(\w+)\}', v)
    if m.group(1) not in RUNTIME_PLACEHOLDERS
)
if unresolved:
    sys.exit('  unset env for: ' + ','.join(unresolved))

print(json.dumps(cfg))
