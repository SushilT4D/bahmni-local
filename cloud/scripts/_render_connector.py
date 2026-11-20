#!/usr/bin/env python3
"""Render a connector JSON for upload: fill ${NAME} values from the environment,
check that no password and no [down] table list is left unfilled, and print the
config object. Unknown placeholders (Kafka Connect's own, like ${topic}) are kept."""
import json, os, re, sys

d = json.load(open(sys.argv[1]))
cfg = d.get('config', d)

def sub(v):
    if not isinstance(v, str):
        return v
    return re.sub(r'\$\{(\w+)\}',
                  lambda m: os.environ[m.group(1)] if m.group(1) in os.environ else m.group(0),
                  v)

# Fill every ${NAME} that is set in the environment.
cfg = {k: sub(v) for k, v in cfg.items()}

# A password left as a placeholder, or an unfilled [down] list, stops the upload.
unresolved = [k for k, v in cfg.items()
              if 'password' in k.lower() and isinstance(v, str) and v.startswith('${')]
if unresolved:
    sys.exit('  unset env for: ' + ','.join(unresolved))

down_left = [k for k, v in cfg.items() if isinstance(v, str) and '${HUB_DOWN_' in v]
if down_left:
    sys.exit('  the down list was not rendered into: ' + ','.join(down_left))

# A source reading a down publication must capture exactly the [down] tables.
DOWN_PUBLICATIONS = {'dbz_odoo_owned': 'HUB_DOWN_ODOO_TABLES', 'dbz_clinlims_owned': 'HUB_DOWN_CLINLIMS_TABLES'}
if cfg.get('publication.name') in DOWN_PUBLICATIONS:
    var = DOWN_PUBLICATIONS[cfg['publication.name']]
    want = set(t for t in os.environ.get(var, '').split(',') if t)
    if not want:
        sys.exit('  %s reads %s but no down list was given (%s)' % (d.get('name', sys.argv[1]), cfg['publication.name'], var))
    inc = set(t.split('.', 1)[-1] for t in cfg.get('table.include.list', '').split(',') if t) - {'dbz_heartbeat'}
    m = re.search(r'\(([^()]*)\)\$?$', cfg.get('transforms.agg.regex', ''))
    agg = set(m.group(1).split('|')) if m else set()
    for what, got in (('table.include.list', inc), ('transforms.agg.regex', agg)):
        if got != want:
            extra, missing = sorted(got - want), sorted(want - got)
            sys.exit('  %s: %s differs from the down list (not down tables: %s; down tables missing: %s)'
                     % (d.get('name', sys.argv[1]), what, ','.join(extra) or 'none', ','.join(missing) or 'none'))

print(json.dumps(cfg))
