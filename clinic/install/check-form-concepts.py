#!/usr/bin/env python3
"""Check that every concept the published forms refer to exists on this node.

    check-form-concepts.py --repo <forms tree> --known <concepts-file> [--known-forms <forms-file>]

<forms tree> is a copy of the forms repo: MANIFEST.tsv at its root and the
form files it names. The forms checked are the manifest rows that are
published, not retired, and have a file. Each form's concepts are read from
its file: each field's concept, its coded answers, and the members of grouped
concepts.

<concepts-file> lists every concept uuid that exists and is not retired on
this node, one per line; <forms-file> every form uuid published and not
retired here. A form this node does not yet publish is BLOCKED by a missing
concept; one it already publishes under the same uuid is only a WARN (the
node runs it today with the same gaps).

This checker ships with the installer and only reads the forms tree as data:
nothing from the forms repo is executed on a clinic.

Exit 0 when nothing blocks (warnings included), 1 when a form is blocked,
2 when the check could not run.
"""
import argparse
import json
import os
import re
import sys

MANIFEST = "MANIFEST.tsv"
MANIFEST_HEADER = ["form_name", "version", "uuid", "published", "retired", "file", "source", "exported_at"]
UUID_LIKE = re.compile(r"^[A-Za-z0-9-]+$")
# a manifest file entry: a plain relative path, no climbing out of the tree
CONTROL = re.compile(r"[\x00-\x1f\x7f]")
PLAIN_FILE = re.compile(r"^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$")


def die(msg):
    print(f"check-concepts: {msg}")
    sys.exit(2)


def read_manifest(path):
    if not os.path.exists(path):
        die(f"no {MANIFEST} in the forms tree")
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    if not lines:
        return []
    if lines[0].split("\t") != MANIFEST_HEADER:
        die(f"{MANIFEST}: header is not {' '.join(MANIFEST_HEADER)}")
    rows = []
    for n, line in enumerate(lines[1:], start=2):
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != len(MANIFEST_HEADER):
            die(f"{MANIFEST}:{n}: {len(parts)} columns, expected {len(MANIFEST_HEADER)}")
        rows.append(dict(zip(MANIFEST_HEADER, parts)))
    return rows


def printable(text):
    """text with control characters escaped, so a manifest cannot drive the terminal"""
    return CONTROL.sub(lambda m: repr(m.group())[1:-1], text)


def answer_name(answer):
    n = answer.get("name")
    if isinstance(n, dict):
        return n.get("display") or n.get("name") or ""
    return n or answer.get("displayString") or ""


def concept_refs(definition):
    """(uuid, field label) for every concept the definition refers to."""
    refs = []

    def concept(con, field):
        if not isinstance(con, dict):
            return
        if con.get("uuid"):
            refs.append((str(con["uuid"]), field))
        for a in con.get("answers") or []:
            if isinstance(a, dict) and a.get("uuid"):
                refs.append((str(a["uuid"]), f"{field} / answer '{answer_name(a)}'"))
        for m in con.get("setMembers") or []:
            concept(m, f"{field} / member '{m.get('name', '')}'" if isinstance(m, dict) else field)

    def walk(controls):
        for c in controls or []:
            if not isinstance(c, dict):
                continue
            label = (c.get("label") or {}).get("value") if isinstance(c.get("label"), dict) else None
            con = c.get("concept")
            field = label or (con.get("name") if isinstance(con, dict) else None) or c.get("type", "?")
            concept(con, field)
            walk(c.get("controls"))

    walk(definition.get("controls") if isinstance(definition, dict) else None)
    return refs


def read_uuid_list(path, what):
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError as exc:
        die(f"cannot read the {what} file {path} ({exc})")
    out = set()
    for line in lines:
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if not UUID_LIKE.match(line):
            die(f"{path}: not a uuid: {line!r}")
        out.add(line.lower())
    return out


def checked_forms(repo):
    """(name, version, uuid, file, refs) for every published, unretired form
    the manifest lists with a file."""
    root = os.path.realpath(repo)
    out = []
    for r in read_manifest(os.path.join(repo, MANIFEST)):
        if r["published"] != "1" or r["retired"] != "0" or not r["file"]:
            continue
        f = r["file"]
        fpath = os.path.realpath(os.path.join(root, f))
        if not PLAIN_FILE.match(f) or ".." in f.split("/") or not fpath.startswith(root + os.sep):
            print(f"check-concepts: warning: {r['form_name']} v{r['version']}: file {f!r} is not a plain path inside the forms tree; skipped")
            continue
        try:
            with open(fpath, encoding="utf-8") as fh:
                definition = json.load(fh)
        except OSError as exc:
            die(f"cannot read {f} ({exc})")
        except ValueError:
            print(f"check-concepts: warning: {f} ({r['form_name']} v{r['version']}) is not JSON; skipped")
            continue
        out.append((printable(r["form_name"]), printable(r["version"]), r["uuid"], f, concept_refs(definition)))
    return out


def check():
    p = argparse.ArgumentParser(description="check the published forms' concepts against this node")
    p.add_argument("--repo", required=True)
    p.add_argument("--known", required=True)
    p.add_argument("--known-forms")
    try:
        args = p.parse_args()
    except SystemExit:
        sys.exit(2)

    per_form = checked_forms(args.repo)
    for name, version, fuuid, f, refs in per_form:
        for u in [fuuid] + [u for u, _ in refs]:
            if not UUID_LIKE.match(u):
                die(f"refusing odd uuid {u!r} in {f}")
    known = read_uuid_list(args.known, "known concepts")
    if not known:
        die(f"{args.known} lists no concepts; the check cannot run against an empty dictionary")
    on_node = read_uuid_list(args.known_forms, "known forms") if args.known_forms else set()
    distinct_all = {u.lower() for *_, refs in per_form for u, _ in refs}
    print(f"check-concepts: {len(per_form)} published forms, {len(distinct_all)} distinct concepts")

    blocked = warned = 0
    for name, version, fuuid, f, refs in per_form:
        missing, seen = [], set()
        for uuid, field in refs:
            key = uuid.lower()
            if (key, field) in seen:
                continue
            seen.add((key, field))
            if key not in known:
                missing.append((uuid, field))
        distinct = len({u.lower() for u, _ in refs})
        if not missing:
            print(f"OK       {name} v{version} ({f}): {distinct} concepts")
            continue
        what = f"{len({u.lower() for u, _ in missing})} not on the node of {distinct} concepts"
        if fuuid.lower() in on_node:
            warned += 1
            print(f"WARN     {name} v{version} ({f}): {what}; already published on the node (uuid {fuuid}), which runs it today with these gaps")
        else:
            blocked += 1
            print(f"BLOCKED  {name} v{version} ({f}): {what}; new to the node (uuid {fuuid})")
        for uuid, field in missing:
            print(f"           missing  {uuid}  {field}")
    print(f"check-concepts: {len(per_form) - blocked - warned} forms load cleanly, {warned} warned (already on the node), {blocked} blocked")
    sys.exit(1 if blocked else 0)


def main():
    # a form file of an unexpected shape must read as "could not check" (2),
    # never as "a form misses concepts" (1)
    try:
        check()
    except SystemExit:
        raise
    except Exception as exc:
        die(f"could not check the forms ({type(exc).__name__}: {exc})")


if __name__ == "__main__":
    main()
