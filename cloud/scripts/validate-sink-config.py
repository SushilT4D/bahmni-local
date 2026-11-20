#!/usr/bin/env python3
"""Validate one generated OpenMRS up sink (one per clinic, on <mm_prefix>.<server>.openmrs.all):
the ordering and safety rules, and a diff against known-good.json.
Usage:
    validate-sink-config.py <config.json> [--known-good <path>] [--database-name <name>]
Exit status: 0 valid, 1 invalid (reasons on stderr), 2 usage/IO error.
"""
import argparse
import json
import re
import sys

# Keys whose values differ per deployment or per clinic; checked for presence only.
ENVIRONMENT_KEYS = {"connection.url", "connection.username", "connection.password", "topics"}


def load(path):
    try:
        with open(path) as fh:
            doc = json.load(fh)
    except FileNotFoundError:
        print(f"not found: {path}", file=sys.stderr)
        sys.exit(2)
    except json.JSONDecodeError as e:
        print(f"{path}: invalid JSON: {e}", file=sys.stderr)
        sys.exit(2)
    cfg = doc.get("config", doc) if isinstance(doc, dict) else None
    if not isinstance(cfg, dict):
        print(f"{path}: no config object", file=sys.stderr)
        sys.exit(2)
    return {k: v for k, v in cfg.items() if not k.startswith("//")}


# Ordering and safety: one ordered topic, one writer, record_key, errors stop the task.
def rules(cfg, db):
    errs = []
    topics = cfg.get("topics", "")
    if not re.fullmatch(r"[^.,]+\.[^,]+\." + re.escape(db) + r"\.all", topics):
        errs.append(f"topics {topics!r} is not <mm_prefix>.<server_name>.{db}.all")
    if "${source.table}" not in cfg.get("collection.name.format", ""):
        errs.append("collection.name.format does not route by ${source.table}")
    for key, want in (("tasks.max", "1"), ("batch.size", "1"), ("connection.pool.max_size", "1")):
        if cfg.get(key) != want:
            errs.append(f"{key} is {cfg.get(key)!r}, must be {want!r}: more than one writer reorders the clinic's changes")
    if cfg.get("transforms"):
        errs.append(f"transforms {cfg['transforms']!r} must be absent: the sink writes every table the clinic sends")
    if cfg.get("primary.key.mode") != "record_key":
        errs.append("primary.key.mode must be record_key (the strided integer key)")
    if cfg.get("errors.tolerance") == "all":
        errs.append("errors.tolerance=all silently drops records")
    if "sessionVariables=sql_log_bin=0" not in cfg.get("connection.url", ""):
        errs.append("connection.url lacks sessionVariables=sql_log_bin=0: the clinic's rows would reach the hub's binlog and be sent back down")
    if cfg.get("connection.restart.on.errors") != "true":
        errs.append("missing connection.restart.on.errors (a closed idle connection would kill the task for good)")
    for key in ("auto.create", "auto.evolve"):
        if key in cfg:
            errs.append(f"{key} must be absent: the sink never changes the hub's schema")
    return errs


# Every key known-good.json declares must be present; non-environment values must match.
def known_good_diff(cfg, good):
    errs = []
    for key, expected in sorted(good.items()):
        if key.startswith("//"):
            continue
        if key not in cfg:
            errs.append(f"missing key required by known-good.json: {key}")
        elif key in ENVIRONMENT_KEYS:
            if not str(cfg[key]).strip():
                errs.append(f"{key} is empty")
        elif str(cfg[key]) != str(expected):
            errs.append(f"{key} is {cfg[key]!r}, known-good.json has {expected!r}")
    return errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("config")
    ap.add_argument("--known-good")
    ap.add_argument("--database-name", default="openmrs")
    a = ap.parse_args()
    cfg = load(a.config)
    errs = rules(cfg, a.database_name)
    if a.known_good:
        errs += known_good_diff(cfg, load(a.known_good))
    for e in errs:
        print(f"  FAIL {a.config}: {e}", file=sys.stderr)
    if errs:
        sys.exit(1)
    print(f"  ok   {a.config}")


if __name__ == "__main__":
    main()
