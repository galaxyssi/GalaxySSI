from __future__ import annotations

import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

from evolution_v2.local_action_contract import action_schema
from evolution_v2.local_implementation import implement_locally, implementation_observer
from evolution_v2.local_tool_observations import WorkspaceToolError
from evolution_v2.local_workspace_tools import WorkspaceTools


class LocalTextEditTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.path = self.root / "source.txt"
        self.original = b"\xef\xbb\xbfHeader\r\nOriginal line\r\nFooter"
        self.path.write_bytes(self.original)
        self.tools = WorkspaceTools(self.root, ["source.txt"])

    def read(self):
        return self.tools.execute({"operation": "read", "path": "source.txt"})["read_revision"]

    def action(self, operation, **fields):
        return {"operation": operation, "path": "source.txt", "expected_revision": self.read(), **fields}

    def test_append_preserves_bom_crlf_and_missing_trailing_newline_byte_for_byte(self):
        self.tools.execute(self.action("append", text="\r\nNew section\n"))
        self.assertEqual(self.original + b"\r\nNew section\n", self.path.read_bytes())

    def test_exact_edit_only_changes_requested_bytes(self):
        self.tools.execute(self.action("edit", old_text="Original line", new_text="Updated line"))
        self.assertEqual(self.original.replace(b"Original line", b"Updated line"), self.path.read_bytes())

    def test_deletion_and_multibyte_text_are_supported(self):
        self.tools.execute(self.action("edit", old_text="Original line", new_text="\u4f60\u597d"))
        self.tools.execute(self.action("edit", old_text="\u4f60\u597d", new_text=""))
        self.assertEqual(self.original.replace(b"Original line", b""), self.path.read_bytes())

    def test_missing_ambiguous_and_invalid_edits_do_not_modify_file(self):
        self.path.write_bytes(b"duplicate duplicate")
        for old, new, code in (("duplicate", "x", "edit_match_ambiguous"), ("missing", "x", "edit_match_missing"),
                               ("", "x", "invalid_edit_text"), ("duplicate", "duplicate", "invalid_edit_text")):
            with self.subTest(code=code), self.assertRaises(WorkspaceToolError) as caught:
                self.tools.execute(self.action("edit", old_text=old, new_text=new))
            self.assertEqual(code, caught.exception.code)
            self.assertEqual(b"duplicate duplicate", self.path.read_bytes())

    def test_stale_receipt_cannot_duplicate_an_append(self):
        action = self.action("append", text="Once")
        self.tools.execute(action)
        with self.assertRaises(WorkspaceToolError):
            self.tools.execute(action)
        self.assertEqual(self.original + b"Once", self.path.read_bytes())

    def test_overlapping_matches_are_ambiguous_too(self):
        self.path.write_bytes(b"aaa")
        with self.assertRaises(WorkspaceToolError) as caught:
            self.tools.execute(self.action("edit", old_text="aa", new_text="b"))
        self.assertEqual("edit_match_ambiguous", caught.exception.code)
        self.assertEqual(b"aaa", self.path.read_bytes())

    def test_append_requires_existing_read_file_and_scope(self):
        for action in ({"operation": "append", "path": "new.txt", "expected_revision": None, "text": "new"},
                       {"operation": "append", "path": "source.txt", "expected_revision": None, "text": "new"}):
            with self.assertRaises(WorkspaceToolError):
                self.tools.execute(action)
        self.assertFalse((self.root / "new.txt").exists())
        self.assertEqual(self.original, self.path.read_bytes())

    def test_changed_file_during_preparation_is_not_overwritten(self):
        from evolution_v2.local_text_edits import edited_bytes
        action = self.action("append", text="append")
        def concurrent_change(original, requested):
            self.path.write_bytes(b"External change")
            return edited_bytes(original, requested)
        with patch("evolution_v2.local_workspace_tools.edited_bytes", side_effect=concurrent_change):
            with self.assertRaises(WorkspaceToolError) as caught:
                self.tools.execute(action)
        self.assertEqual("source_revision_mismatch", caught.exception.code)
        self.assertEqual(b"External change", self.path.read_bytes())
        self.assertEqual(["source.txt"], [path.name for path in self.root.iterdir()])

    def test_combined_size_is_checked_before_replacing_file(self):
        self.path.write_bytes(b"x" * 1_048_576)
        with self.assertRaises(WorkspaceToolError) as caught:
            self.tools.execute(self.action("append", text="overflow"))
        self.assertEqual("invalid_write_text", caught.exception.code)
        self.assertEqual(1_048_576, self.path.stat().st_size)

    def test_model_can_recover_from_edit_error_and_observe_real_append(self):
        events = []
        count = 0
        def infer(messages):
            nonlocal count
            count += 1
            if count == 1:
                return json.dumps({"operation": "read", "path": "source.txt"})
            observation = json.loads(messages[-1]["content"])["observation"]
            if count == 2:
                self.revision = observation["result"]["read_revision"]
                return json.dumps({"operation": "edit", "path": "source.txt", "expected_revision": self.revision,
                                   "old_text": "Absent", "new_text": "Replacement"})
            if count == 3:
                self.assertEqual("edit_match_missing", observation["error_code"])
                return json.dumps({"operation": "append", "path": "source.txt", "expected_revision": self.revision,
                                   "text": "\nModel selected append"})
            self.assertEqual("applied", observation["effect"])
            return json.dumps({"operation": "finish", "summary": "Host acceptance pending"})
        with implementation_observer(threading.Event(), lambda event, **data: events.append(data)):
            implement_locally("Append a section", self.root, scope=["source.txt"], infer=infer)
        self.assertEqual(["read", "edit", "append"], [row["operation"] for row in events])
        self.assertEqual(self.original + b"\nModel selected append", self.path.read_bytes())
        self.assertNotIn("Model selected append", json.dumps(events))

    def test_schema_requires_real_revision_and_explicit_edit_arguments(self):
        variants = {item["properties"]["operation"]["const"]: item for item in action_schema()["oneOf"]}
        self.assertEqual("string", variants["append"]["properties"]["expected_revision"]["type"])
        self.assertIn("old_text", variants["edit"]["required"])
        self.assertIn("new_text", variants["edit"]["required"])


if __name__ == "__main__":
    unittest.main()
