#!/usr/bin/env python3
"""Render a connector config, substituting only available environment values."""
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

# Reject unresolved placeholders, including connector identity fields.
unresolved = sorted(
    k for k, v in cfg.items()
    if isinstance(v, str)
    for m in re.finditer(r'\$\{(\w+)\}', v)
    if m.group(1) not in RUNTIME_PLACEHOLDERS
)
if unresolved:
    sys.exit('  unset env for: ' + ','.join(unresolved))

print(json.dumps(cfg))
