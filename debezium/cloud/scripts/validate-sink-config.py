#!/usr/bin/env python3
"""Validate one generated up-direction JDBC sink config.

Two layers of check:

1. The five hand-written rules that were previously inlined in
   generate-sink-connectors.sh. They catch the specific ways this generator has
   produced dead configs before (bash eating a literal $1, a doubled topic
   prefix, BL-005's silent-drop setting, a missing BL-039 restart flag).

2. NEW: a diff against `known-good.json`, the committed record of a sink that
   actually works. `known-good.json` is a FLOOR, not a ceiling: every key it
   declares must be present, and every key whose value is table- and
   environment-independent must match exactly. Extra keys in the generated
   config are fine - that is how later hardening (BL-039 restart/retry, pool
   settings, errors.tolerance) was added without invalidating the shape.

   This is the executable half of an invariant that had only ever been a
   comment. `generate-sink-connectors.sh` said "SHAPE IS AUTHORITATIVE: keep
   this heredoc matching known-good.json" - and on 2026-08-27 the heredoc was
   found to have diverged from it in six ways and been emitting configs that
   could never have worked. A comment cannot prevent that; a diff can.

Lives in a FILE rather than a `python3 -c "..."` string on purpose. The
generator's heredoc is unquoted, so bash expands $ and collapses backslashes
inside it, and that has already caused three separate silent bugs. Source code
that must contain $, backslashes and quotes does not belong in that blast
radius.

Usage:
    validate-sink-config.py <config.json> [--known-good <path>]
                                          [--database-name <name>]
                                          [--skip-generator-rules]

`--skip-generator-rules` runs only the known-good shape diff, for pointing at a
config that did not come from this generator - e.g. a live connector dumped
from `GET /connectors/<name>/config`, which is wrapped differently and has no
obligation to carry the generator's own comment keys.

Exit status: 0 valid, 1 invalid (reasons on stderr), 2 usage/IO error.
"""
import argparse
import json
import os
import re
import sys

# Keys whose value legitimately differs per deployment, so `known-good.json`'s
# value is an example rather than a requirement. Presence is still required.
ENVIRONMENT_KEYS = {
    "connection.url",
    "connection.username",
    "connection.password",
    # embeds MYSQL_SERVER_NAME / database name, which vary per clinic
    "transforms.dropPrefix.regex",
}

_PLACEHOLDER = re.compile(r"\$\{[^}]+\}")


def _config(doc, path):
    """Accept either a full connector document ({"name":..,"config":{..}}) or a
    bare config mapping, which is what the Connect REST API returns."""
    if not isinstance(doc, dict):
        sys.exit(f"{path}: expected a JSON object, got {type(doc).__name__}")
    cfg = doc.get("config", doc)
    if not isinstance(cfg, dict):
        sys.exit(f"{path}: 'config' is not an object")
    # `//`-prefixed keys are this repo's JSON comment convention, never settings.
    return {k: v for k, v in cfg.items() if not k.startswith("//")}


def _load(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except FileNotFoundError:
        sys.exit(f"not found: {path}")
    except json.JSONDecodeError as e:
        sys.exit(f"{path}: invalid JSON: {e}")


def generator_rules(cfg, database_name):
    """The checks that were inlined in generate-sink-connectors.sh. Preserved
    verbatim in meaning, including their original messages."""
    errs = []
    topics = cfg.get("topics", "")
    if database_name and topics.count(database_name) > 1:
        errs.append(f"doubled topic prefix: {topics}")
    if not cfg.get("transforms.dropPrefix.replacement"):
        errs.append("empty RegexRouter replacement (bare $1 was expanded by bash)")
    if cfg.get("errors.tolerance") == "all":
        errs.append("errors.tolerance=all silently drops records (BL-005)")
    if cfg.get("connection.restart.on.errors") != "true":
        errs.append("missing BL-039 connection.restart.on.errors")
    if not cfg.get("primary.key.fields"):
        errs.append("empty primary.key.fields")
    return errs


def known_good_diff(cfg, good):
    """Every key known-good declares must be present; every table- and
    environment-independent value must match. Extra keys are allowed."""
    errs = []
    for key, expected in sorted(good.items()):
        if key not in cfg:
            errs.append(f"missing key required by known-good.json: {key}")
            continue
        actual = cfg[key]
        if key in ENVIRONMENT_KEYS:
            if not str(actual).strip():
                errs.append(f"{key} is empty (deployment-specific, but required)")
            continue
        if _PLACEHOLDER.search(str(expected)):
            # known-good carries ${TABLE} / ${PRIMARY_KEY} here: the generated
            # value is per-table, so only require that something was filled in
            # and that no placeholder survived substitution.
            if not str(actual).strip():
                errs.append(f"{key} is empty (known-good expects a value here)")
            elif _PLACEHOLDER.search(str(actual)):
                errs.append(f"{key} still contains an unsubstituted placeholder: {actual!r}")
            continue
        if actual != expected:
            errs.append(
                f"{key} diverges from known-good.json: "
                f"generated={actual!r} known-good={expected!r}"
            )
    return errs


def main():
    p = argparse.ArgumentParser(add_help=True)
    p.add_argument("config")
    p.add_argument("--known-good")
    p.add_argument("--database-name", default="")
    p.add_argument("--skip-generator-rules", action="store_true")
    args = p.parse_args()

    cfg = _config(_load(args.config), args.config)

    known_good = args.known_good
    if known_good is None:
        default = os.path.join(
            os.path.dirname(os.path.abspath(args.config)), "known-good.json"
        )
        known_good = default if os.path.exists(default) else None

    errs = []
    if not args.skip_generator_rules:
        errs += generator_rules(cfg, args.database_name)

    if known_good:
        errs += known_good_diff(cfg, _config(_load(known_good), known_good))
    else:
        # Never pass silently just because the reference is missing - that is
        # the same "absent check reads as a passing check" trap this file exists
        # to close.
        errs.append(
            "known-good.json not found next to the config and --known-good not "
            "given: the shape diff did NOT run"
        )

    if errs:
        sys.stderr.write(
            f"INVALID CONFIG {args.config}:\n  - " + "\n  - ".join(errs) + "\n"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
