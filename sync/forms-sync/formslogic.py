"""Which form files travel from the cloud to a clinic, and how a clinic writes one.

A form's rows reach a clinic with the other rows. Its files travel as messages:
key = the file's path under the forms folder, value = the gzipped content.
"""

import gzip
import hashlib
import json
import os
import zlib

FS_DATATYPE = "org.bahmni.customdatatype.datatype.FileSystemStorageDatatype"
TRANSLATIONS = "translations"
MAX_VALUE_BYTES = 1_000_000


def _flag(value):
    if isinstance(value, (bytes, bytearray)):
        return value not in (b"", b"\x00", b"0")
    return str(value) in ("1", "True", "true")


def _text(value):
    return value.decode("utf-8", "replace") if isinstance(value, (bytes, bytearray)) else (value or "")


def _valid_key(key):
    if not isinstance(key, str) or not key.endswith(".json"):
        return False
    parts = key.split("/")
    if len(parts) == 2 and parts[0] != TRANSLATIONS:
        return False
    return len(parts) in (1, 2) and all(p and not p.startswith(".") and "\\" not in p for p in parts)


def published_files(forms, resources, forms_dir):
    """Paths, relative to the forms folder, of every published form's files.

    A retired form stays: saved observations name the version they were entered with.
    """
    published = {str(f["form_id"]): _text(f["uuid"]) for f in forms if _flag(f["published"])}
    prefix = forms_dir.rstrip("/") + "/"
    wanted = set()
    for r in resources:
        ref, fid = _text(r.get("value_reference")), str(r["form_id"])
        if _text(r.get("datatype")) != FS_DATATYPE or fid not in published or not ref.startswith(prefix):
            continue
        name = ref[len(prefix):]
        if "/" in name or not _valid_key(name):
            continue
        wanted.update((name, f"{TRANSLATIONS}/{name}", f"{TRANSLATIONS}/{published[fid]}.json"))
    return wanted


def encode(content):
    return gzip.compress(content, mtime=0)


def decode(value):
    if not value:
        raise ValueError("no content")
    try:
        return gzip.decompress(value)
    except (OSError, EOFError, zlib.error) as e:
        raise ValueError(f"not gzip: {e}") from None


def safe_target(root, key):
    """The absolute path for key under root; ValueError for anything that would leave it."""
    if not _valid_key(key):
        raise ValueError(f"not a form file name: {key!r}")
    base = os.path.realpath(root)
    target = os.path.realpath(os.path.join(base, key))
    if os.path.commonpath([base, target]) != base:
        raise ValueError(f"outside the forms folder: {key!r}")
    return target


def is_form_change(value):
    """True for a change message about the form or form_resource table."""
    try:
        doc = json.loads(value)
        doc = doc.get("payload", doc)
        return doc["source"]["table"] in ("form", "form_resource")
    except (TypeError, ValueError, KeyError, AttributeError):
        return False


def _is_definition(key):
    return "/" not in key


def to_send(root, wanted, sent):
    """(messages, missing, too_big) for the wanted files.

    messages: (key, value, digest) for each file whose content is not the one recorded
    in sent; the caller records the digest once the message is delivered. A missing or
    empty definition file is reported; a form need not have a translation file.
    """
    messages, missing, too_big = [], [], []
    for key in sorted(wanted):
        try:
            with open(safe_target(root, key), "rb") as f:
                content = f.read()
        except (OSError, ValueError):
            content = b""
        if not content:
            if _is_definition(key):
                missing.append(key)
            continue
        digest = hashlib.sha256(content).hexdigest()
        if sent.get(key) == digest:
            continue
        value = encode(content)
        if len(value) > MAX_VALUE_BYTES:
            too_big.append(key)
            continue
        messages.append((key, value, digest))
    return messages, missing, too_big


def apply_message(root, key, value):
    """Write the file a message carries. Returns "written" or "same"."""
    target = safe_target(root, key)
    content = decode(value)
    try:
        with open(target, "rb") as f:
            if f.read() == content:
                return "same"
    except OSError:
        pass
    os.makedirs(os.path.dirname(target), exist_ok=True)
    tmp = target + ".tmp"
    with open(tmp, "wb") as f:
        f.write(content)
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o644)
    os.replace(tmp, target)
    return "written"


def missing_definitions(root, wanted):
    """Published forms' definition files that are not in the folder."""
    out = []
    for key in sorted(k for k in wanted if _is_definition(k)):
        try:
            if os.path.getsize(safe_target(root, key)) > 0:
                continue
        except (OSError, ValueError):
            pass
        out.append(key)
    return out
