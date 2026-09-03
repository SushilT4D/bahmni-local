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

unresolved = [k for k, v in cfg.items()
              if 'password' in k.lower() and isinstance(v, str) and v.startswith('${')]
if unresolved:
    sys.exit('  unset env for: ' + ','.join(unresolved))

print(json.dumps(cfg))
