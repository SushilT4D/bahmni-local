#!/usr/bin/env python3
"""Carries the files of published forms from the cloud to a clinic through Kafka.

    forms_sync.py send      on the cloud: forms folder -> the forms topic
    forms_sync.py receive   at a clinic:  the forms topic -> forms folder
"""

import os
import sys
import time

import formslogic as fl

POLL_MS = 5000
PASS_SPACING_SECONDS = 5
MISSING_RETRY_SECONDS = 60
CHECK_AFTER_WRITE_SECONDS = 60
CHECK_REPEAT_SECONDS = 600


def say(line):
    print(line, flush=True)


def scrub(text):
    secret = os.environ.get("FORMS_DB_PASSWORD")
    return text.replace(secret, "***") if secret else text


def setting(name, default=None):
    value = os.environ.get(name) or default
    if not value:
        sys.exit(f"forms-sync: {name} is not set")
    return value


def until_ready(fn, wait=10, log=say, what="Kafka and the database"):
    """Call fn until it stops raising; one log line per try that did not succeed."""
    while True:
        try:
            return fn()
        except Exception as e:
            log(scrub(f"waiting for {what}: {type(e).__name__}: {e}"))
            time.sleep(wait)


def wanted():
    """Paths of every published form's files, asked of the database now."""
    import pymysql

    conn = pymysql.connect(
        host=setting("FORMS_DB_HOST"), user=setting("FORMS_DB_USER"), password=setting("FORMS_DB_PASSWORD"),
        database=setting("FORMS_DB_NAME"), connect_timeout=10, read_timeout=60,
        cursorclass=pymysql.cursors.DictCursor)
    try:
        with conn.cursor() as c:
            c.execute("select form_id, uuid, published from form")
            forms = c.fetchall()
            c.execute("select form_id, value_reference, datatype from form_resource")
            resources = c.fetchall()
    finally:
        conn.close()
    return fl.published_files(forms, resources, setting("OPENMRS_FORMS_DIR", "/home/bahmni/clinical_forms"))


def partitions(consumer, topics):
    """Every partition of the named topics (one name, or several separated by commas)."""
    from kafka import TopicPartition

    out = []
    for topic in (t.strip() for t in topics.split(",") if t.strip()):
        found = consumer.partitions_for_topic(topic)
        if not found:
            raise RuntimeError(f"topic {topic} does not exist yet")
        out.extend(TopicPartition(topic, p) for p in sorted(found))
    return out


def ensure_topic(bootstrap, topic):
    """The forms topic must keep the latest file for every name; a broker would create it with a time limit."""
    from kafka.admin import KafkaAdminClient, NewTopic
    from kafka.errors import TopicAlreadyExistsError

    admin = KafkaAdminClient(bootstrap_servers=bootstrap)
    try:
        admin.create_topics([NewTopic(name=topic, num_partitions=1, replication_factor=1,
                                      topic_configs={"cleanup.policy": "compact"})])
        say(f"created topic {topic} (keeps the latest message for every file)")
    except TopicAlreadyExistsError:
        pass
    finally:
        admin.close()


def send_pass(producer, topic, root, sent):
    """Send every published form file not yet sent with its current content. Returns the missing ones."""
    messages, missing, too_big = fl.to_send(root, wanted(), sent)
    for key, value, digest in messages:
        producer.send(topic, key=key.encode("utf-8"), value=value).get(timeout=60)
        sent[key] = digest
        say(f"sent {key} ({len(value)} bytes)")
    for key in missing:
        say(f"ERROR a published form's file is not in the forms folder: {key}")
    for key in too_big:
        say(f"ERROR too large to send after compression (limit {fl.MAX_VALUE_BYTES} bytes), skipped: {key}")
    return missing


def missing_deadline(now, missing):
    """Until when a file that was not in the folder is looked for again."""
    return now + MISSING_RETRY_SECONDS if missing else 0


def pass_due(now, last, dirty, failed, missing, deadline):
    """Whether to read the database and send now. The change stream carries every table, so passes are spaced."""
    if now - last < PASS_SPACING_SECONDS:
        return False
    return bool(dirty or failed or (missing and now < deadline))


def send():
    from kafka import KafkaConsumer, KafkaProducer

    bootstrap, topic, root = setting("KAFKA_BOOTSTRAP", "kafka:29092"), setting("FORMS_TOPIC"), setting("FORMS_ROOT", "/forms")
    change_topic = setting("CHANGE_TOPIC")
    for name in ("FORMS_DB_HOST", "FORMS_DB_NAME", "FORMS_DB_USER", "FORMS_DB_PASSWORD"):
        setting(name)

    until_ready(lambda: ensure_topic(bootstrap, topic))
    consumer = until_ready(lambda: KafkaConsumer(bootstrap_servers=bootstrap, group_id=None, enable_auto_commit=False))
    # Take the change stream's end before the first pass, so a form published during it is not lost.
    tps = until_ready(lambda: partitions(consumer, change_topic))
    consumer.assign(tps)
    consumer.seek_to_end()
    for tp in tps:
        consumer.position(tp)
    producer = until_ready(lambda: KafkaProducer(bootstrap_servers=bootstrap, acks="all"))

    sent = {}
    missing = until_ready(lambda: send_pass(producer, topic, root, sent))
    say(f"start-up pass: {len(sent)} files sent, {len(missing)} missing")

    last = time.monotonic()
    deadline, dirty, failed = missing_deadline(last, missing), False, False
    while True:
        records = consumer.poll(timeout_ms=POLL_MS)
        now = time.monotonic()
        if any(fl.is_form_change(r.value) for batch in records.values() for r in batch):
            dirty, deadline = True, now + MISSING_RETRY_SECONDS
        if not pass_due(now, last, dirty, failed, missing, deadline):
            continue
        last, dirty = now, False
        try:
            missing, failed = send_pass(producer, topic, root, sent), False
        except Exception as e:
            failed = True
            say(scrub(f"ERROR could not send, trying again: {type(e).__name__}: {e}"))


def handle(root, key, value, log=say):
    """Write the file one message carries. Returns "written", "same" or "error"; never raises."""
    try:
        name = key.decode("utf-8")
        result = fl.apply_message(root, name, value)
    except (ValueError, AttributeError, OSError) as e:
        log(f"ERROR message not written (key {key!r}): {type(e).__name__}: {e}")
        return "error"
    if result == "written":
        log(f"wrote {name}")
    return result


def self_check(root):
    """Log every published form whose file is not here. Returns how many."""
    missing = fl.missing_definitions(root, wanted())
    for key in missing:
        say(f"ERROR a published form has no file at this clinic: {key}")
    if not missing:
        say("check: every published form has its file")
    return len(missing)


def receive():
    from kafka import KafkaConsumer

    bootstrap, topic, root = setting("KAFKA_BOOTSTRAP", "kafka:29092"), setting("FORMS_TOPIC"), setting("FORMS_ROOT", "/forms")
    for name in ("FORMS_DB_HOST", "FORMS_DB_NAME", "FORMS_DB_USER", "FORMS_DB_PASSWORD"):
        setting(name)
    if not os.path.isdir(root):
        sys.exit(f"forms-sync: no forms folder at {root}")

    consumer = until_ready(lambda: KafkaConsumer(bootstrap_servers=bootstrap, group_id=None, enable_auto_commit=False))
    # Said before the wait: if the topic never comes, the log still names the forms that cannot open.
    try:
        self_check(root)
    except Exception as e:
        say(scrub(f"ERROR could not check the forms folder: {type(e).__name__}: {e}"))
    tps = until_ready(lambda: partitions(consumer, topic), what=f"topic {topic}")
    consumer.assign(tps)
    # Every start reads the whole topic again, so a restart is a full check of the folder.
    consumer.seek_to_beginning()

    caught_up, check_at, written = False, None, 0
    while True:
        records = consumer.poll(timeout_ms=POLL_MS)
        now = time.monotonic()
        for batch in records.values():
            for r in batch:
                if handle(root, r.key, r.value) == "written":
                    written += 1
                    check_at = now + CHECK_AFTER_WRITE_SECONDS
        if not caught_up:
            ends = consumer.end_offsets(tps)
            if all(consumer.position(tp) >= ends[tp] for tp in tps):
                caught_up, check_at = True, now
                say(f"start-up read: {written} files written")
        if caught_up and check_at is not None and now >= check_at:
            try:
                check_at = now + CHECK_REPEAT_SECONDS if self_check(root) else None
            except Exception as e:
                check_at = now + CHECK_AFTER_WRITE_SECONDS
                say(scrub(f"ERROR could not check the forms folder, trying again: {type(e).__name__}: {e}"))


def main(argv):
    modes = {"send": send, "receive": receive}
    if len(argv) != 2 or argv[1] not in modes:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    modes[argv[1]]()


if __name__ == "__main__":
    main(sys.argv)
