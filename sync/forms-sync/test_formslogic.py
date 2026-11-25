import os
import tempfile
import unittest
from unittest import mock

import formslogic as fl

DIR = "/home/bahmni/clinical_forms"


def form(fid, uuid, published, retired=0):
    return {"form_id": fid, "uuid": uuid, "published": published, "retired": retired}


def res(fid, ref, datatype=fl.FS_DATATYPE):
    return {"form_id": fid, "value_reference": ref, "datatype": datatype}


def envelope(table):
    return ('{"schema":{},"payload":{"op":"u","source":{"table":"%s"}}}' % table).encode()


class PublishedFilesTest(unittest.TestCase):
    def test_published_only(self):
        forms = [form(1, "u1", 1), form(2, "u2", 0), form(3, "u3", 1, retired=1)]
        resources = [res(1, DIR + "/a.json"), res(2, DIR + "/b.json"), res(3, DIR + "/c.json")]
        self.assertEqual(
            fl.published_files(forms, resources, DIR),
            {"a.json", "translations/a.json", "translations/u1.json",
             "c.json", "translations/c.json", "translations/u3.json"})

    def test_published_flag_as_bytes_or_text(self):
        for flag in (b"\x01", "1", True):
            self.assertIn("a.json", fl.published_files([form(1, "u1", flag)], [res(1, DIR + "/a.json")], DIR))
        for flag in (b"\x00", "0", None):
            self.assertEqual(fl.published_files([form(1, "u1", flag)], [res(1, DIR + "/a.json")], DIR), set())

    def test_pointer_outside_folder_ignored(self):
        self.assertEqual(fl.published_files([form(1, "u1", 1)], [res(1, "/tmp/x.json")], DIR), set())
        self.assertEqual(fl.published_files([form(1, "u1", 1)], [res(1, DIR + "/../x.json")], DIR), set())

    def test_name_translation_rows_ignored(self):
        other = "org.bahmni.customdatatype.datatype.FormNameTranslationDatatype"
        self.assertEqual(fl.published_files([form(1, "u1", 1)], [res(1, DIR + "/a.json", other)], DIR), set())


class CodecTest(unittest.TestCase):
    def test_round_trip(self):
        content = (b'{"name":"Adult Case Sheet","controls":[' + b'{"id":1},' * 60000 + b"{}]}")
        self.assertGreater(len(content), 500000)
        self.assertEqual(fl.decode(fl.encode(content)), content)
        self.assertLess(len(fl.encode(content)), fl.MAX_VALUE_BYTES)

    def test_decode_rejects(self):
        for bad in (None, b"not gzip", b""):
            with self.assertRaises(ValueError):
                fl.decode(bad)


class SafeTargetTest(unittest.TestCase):
    def test_safe_target_rejects(self):
        with tempfile.TemporaryDirectory() as root:
            for bad in ("", "../a.json", "/etc/a.json", "translations/../../a.json", "a/b/c.json", "a.txt", None):
                with self.assertRaises(ValueError, msg=repr(bad)):
                    fl.safe_target(root, bad)
            real = os.path.realpath(root)
            self.assertEqual(fl.safe_target(root, "a.json"), os.path.join(real, "a.json"))
            self.assertEqual(fl.safe_target(root, "translations/a.json"), os.path.join(real, "translations", "a.json"))


class ChangeTest(unittest.TestCase):
    def test_is_form_change(self):
        self.assertTrue(fl.is_form_change(envelope("form")))
        self.assertTrue(fl.is_form_change(envelope("form_resource")))
        self.assertTrue(fl.is_form_change(b'{"op":"c","source":{"table":"form"}}'))
        self.assertFalse(fl.is_form_change(envelope("obs")))
        self.assertFalse(fl.is_form_change(None))
        self.assertFalse(fl.is_form_change(b"x"))
        self.assertFalse(fl.is_form_change(b'{"payload":null}'))
        self.assertFalse(fl.is_form_change(b"[1,2]"))


class SendTest(unittest.TestCase):
    def test_to_send_skips_sent_and_reports_missing(self):
        with tempfile.TemporaryDirectory() as root:
            with open(os.path.join(root, "a.json"), "wb") as f:
                f.write(b'{"a":1}')
            wanted = {"a.json", "translations/a.json", "b.json", "translations/b.json"}
            sent = {}
            messages, missing, too_big = fl.to_send(root, wanted, sent)
            self.assertEqual([k for k, _, _ in messages], ["a.json"])
            self.assertEqual(fl.decode(messages[0][1]), b'{"a":1}')
            self.assertEqual(missing, ["b.json"])
            self.assertEqual(too_big, [])
            self.assertEqual(sent, {}, "to_send must not record a send that has not happened")
            sent["a.json"] = messages[0][2]
            self.assertEqual(fl.to_send(root, wanted, sent)[0], [])
            with open(os.path.join(root, "a.json"), "wb") as f:
                f.write(b'{"a":2}')
            self.assertEqual([k for k, _, _ in fl.to_send(root, wanted, sent)[0]], ["a.json"])

    def test_to_send_never_sends_an_empty_file(self):
        with tempfile.TemporaryDirectory() as root:
            open(os.path.join(root, "a.json"), "wb").close()
            messages, missing, _ = fl.to_send(root, {"a.json"}, {})
            self.assertEqual(messages, [])
            self.assertEqual(missing, ["a.json"])

    def test_to_send_too_big(self):
        with tempfile.TemporaryDirectory() as root:
            with open(os.path.join(root, "a.json"), "wb") as f:
                f.write(os.urandom(200))
            with mock.patch.object(fl, "MAX_VALUE_BYTES", 10):
                messages, missing, too_big = fl.to_send(root, {"a.json"}, {})
            self.assertEqual((messages, missing, too_big), ([], [], ["a.json"]))


class ApplyTest(unittest.TestCase):
    def test_apply_message_writes_then_same(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(fl.apply_message(root, "translations/a.json", fl.encode(b"one")), "written")
            path = os.path.join(root, "translations", "a.json")
            with open(path, "rb") as f:
                self.assertEqual(f.read(), b"one")
            self.assertEqual(fl.apply_message(root, "translations/a.json", fl.encode(b"one")), "same")
            self.assertEqual(fl.apply_message(root, "translations/a.json", fl.encode(b"two")), "written")
            with open(path, "rb") as f:
                self.assertEqual(f.read(), b"two")
            self.assertEqual(os.listdir(os.path.join(root, "translations")), ["a.json"])

    def test_apply_message_bad_key_writes_nothing(self):
        with tempfile.TemporaryDirectory() as outer:
            root = os.path.join(outer, "forms")
            os.mkdir(root)
            with self.assertRaises(ValueError):
                fl.apply_message(root, "../a.json", fl.encode(b"x"))
            with self.assertRaises(ValueError):
                fl.apply_message(root, "a.json", b"not gzip")
            self.assertEqual(os.listdir(outer), ["forms"])
            self.assertEqual(os.listdir(root), [])

    def test_missing_definitions(self):
        with tempfile.TemporaryDirectory() as root:
            open(os.path.join(root, "a.json"), "w").write("{}")
            wanted = {"a.json", "b.json", "translations/a.json", "translations/b.json"}
            self.assertEqual(fl.missing_definitions(root, wanted), ["b.json"])


if __name__ == "__main__":
    unittest.main()
