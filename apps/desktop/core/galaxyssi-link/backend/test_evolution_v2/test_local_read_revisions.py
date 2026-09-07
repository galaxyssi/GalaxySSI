from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evolution_v2.local_action_contract import action_schema
from evolution_v2.local_implementation import implement_locally
from evolution_v2.local_tool_observations import WorkspaceToolError
from evolution_v2.local_workspace_tools import WorkspaceTools


class LocalReadRevisionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "a.txt").write_bytes(b"original\n")
        (self.root / "b.txt").write_bytes(b"original\n")
        self.tools = WorkspaceTools(self.root, ["."])

    def read(self, path="a.txt", **extra):
        return self.tools.execute({"operation": "read", "path": path, **extra})

    def write(self, revision, path="a.txt", **extra):
        return self.tools.execute({"operation": "write", "path": path, "expected_revision": revision, "text": "changed", **extra})

    def test_read_receipt_write_then_stale_receipt_is_rejected(self):
        receipt = self.read()["read_revision"]
        self.assertLess(len(receipt), 24)
        self.write(receipt)
        self.assertEqual("changed", (self.root / "a.txt").read_text())
        with self.assertRaises(WorkspaceToolError) as caught:
            self.write(receipt, text="must not apply")
        self.assertEqual("source_revision_mismatch", caught.exception.code)
        self.assertEqual("changed", (self.root / "a.txt").read_text())
        current = self.read()["read_revision"]
        self.assertNotEqual(receipt, current)
        self.write(current, text="next revision")

    def test_external_change_requires_reread(self):
        receipt = self.read()["read_revision"]
        (self.root / "a.txt").write_text("external change")
        with self.assertRaisesRegex(WorkspaceToolError, "no longer matches"):
            self.write(receipt)
        self.assertEqual("external change", (self.root / "a.txt").read_text())

    def test_receipt_is_bound_to_path_even_when_bytes_are_identical(self):
        receipt = self.read()["read_revision"]
        with self.assertRaises(WorkspaceToolError) as caught:
            self.write(receipt, path="b.txt")
        self.assertEqual("read_revision_path_mismatch", caught.exception.code)
        self.assertEqual(b"original\n", (self.root / "b.txt").read_bytes())

    def test_invented_malformed_and_foreign_receipts_cannot_write(self):
        other = WorkspaceTools(self.root, ["."])
        foreign = other.execute({"operation": "read", "path": "a.txt"})["read_revision"]
        self.read()
        for receipt in (foreign, "invented", "", 4, {"value": "r1"}):
            with self.subTest(receipt=receipt), self.assertRaises(WorkspaceToolError) as caught:
                self.write(receipt)
            self.assertEqual("read_revision_unknown", caught.exception.code)
        self.assertEqual(b"original\n", (self.root / "a.txt").read_bytes())

    def test_null_only_creates_new_file_and_does_not_overwrite_existing(self):
        self.write(None, path="new/nested.txt")
        self.assertEqual("changed", (self.root / "new/nested.txt").read_text())
        with self.assertRaises(WorkspaceToolError) as caught:
            self.write(None)
        self.assertEqual("source_revision_mismatch", caught.exception.code)
        self.assertEqual(b"original\n", (self.root / "a.txt").read_bytes())

    def test_paged_reads_share_receipt_for_same_content(self):
        (self.root / "a.txt").write_text("a" * 40_000)
        first = self.read()
        second = self.read(offset=first["next_offset"])
        self.assertEqual(first["read_revision"], second["read_revision"])
        self.assertEqual(16_384, first["next_offset"])

    def test_receipt_cache_is_bounded_and_eviction_requires_reread_not_task_stop(self):
        old = self.read()["read_revision"]
        for index in range(140):
            path = self.root / f"file-{index}.txt"
            path.write_text(str(index))
            self.read(path.name)
        self.assertEqual(128, len(self.tools.revisions._values))
        with self.assertRaises(WorkspaceToolError) as caught:
            self.write(old)
        self.assertEqual("read_revision_unknown", caught.exception.code)
        self.write(self.read()["read_revision"])
        self.assertEqual("changed", (self.root / "a.txt").read_text())

    def test_ambiguous_digest_and_receipt_is_rejected(self):
        result = self.read()
        with self.assertRaises(WorkspaceToolError) as caught:
            self.write(result["read_revision"], expected_sha256=result["sha256"])
        self.assertEqual("ambiguous_read_revision", caught.exception.code)

    def test_default_inference_receives_schema_and_uses_real_read_receipt(self):
        seen = []
        def infer(messages, *, response_schema):
            self.assertEqual(action_schema(), response_schema)
            seen.append(messages)
            if len(seen) == 1:
                return json.dumps({"operation": "read", "path": "a.txt"})
            if len(seen) == 2:
                result = json.loads(messages[-1]["content"])["observation"]["result"]
                self.assertNotIn("sha256", result)
                return json.dumps({"operation": "write", "path": "a.txt", "expected_revision": result["read_revision"], "text": "model edit"})
            return json.dumps({"operation": "finish", "summary": "Host checks pending"})
        with patch("evolution_v2.local_implementation.infer_local_plan", side_effect=infer):
            self.assertEqual("Host checks pending", implement_locally("Modify file", self.root, scope=["a.txt"]))
        self.assertEqual("model edit", (self.root / "a.txt").read_text())


if __name__ == "__main__":
    unittest.main()
