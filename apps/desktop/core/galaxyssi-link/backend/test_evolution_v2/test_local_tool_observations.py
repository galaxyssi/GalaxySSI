from __future__ import annotations

import errno
import hashlib
import json
from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from evolution_v2.audit import AuditLedger
from evolution_v2.local_implementation import implement_locally, implementation_observer
from evolution_v2.local_tool_observations import durable_observation, failure_observation, WorkspaceToolError
from evolution_v2.local_workspace_tools import WorkspaceTools
from evolution_v2.manager import EvolutionManager


class LocalToolObservationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "source.txt").write_bytes(b"private original\n")
        self.tools = WorkspaceTools(self.root, ["source.txt"])

    def test_write_failures_are_distinct_and_do_not_modify_source(self):
        common = {"operation": "write", "path": "source.txt", "text": "replacement"}
        cases = [
            (common, "read_digest_required"),
            ({**common, "expected_sha256": "abc"}, "invalid_read_digest"),
            ({**common, "expected_sha256": 123}, "invalid_read_digest"),
            ({**common, "expected_sha256": "0" * 64}, "source_digest_mismatch"),
            ({**common, "expected_sha256": None}, "source_digest_mismatch"),
            ({**common, "path": "outside.txt"}, "write_scope_mismatch"),
            ({**common, "path": "../outside.txt"}, "source_path_forbidden"),
        ]
        for action, code in cases:
            with self.subTest(code=code), self.assertRaises(WorkspaceToolError) as caught:
                self.tools.execute(action)
            observation = failure_observation(caught.exception, "file_tool_execution")
            self.assertEqual(code, observation["error_code"])
            self.assertEqual("not_applied", observation["effect"])
            self.assertEqual(b"private original\n", (self.root / "source.txt").read_bytes())

    def test_uppercase_digest_is_valid_but_stale_digest_is_not(self):
        digest = hashlib.sha256(b"private original\n").hexdigest().upper()
        action = {"operation": "write", "path": "source.txt", "text": "changed", "expected_sha256": digest}
        self.tools.execute(action)
        with self.assertRaises(WorkspaceToolError) as caught:
            self.tools.execute(action)
        self.assertEqual("source_digest_mismatch", caught.exception.code)
        self.assertEqual("changed", (self.root / "source.txt").read_text())

    def test_os_failure_does_not_echo_private_paths(self):
        for number, code in ((errno.ENOENT, "file_not_found"), (errno.EACCES, "file_access_denied"),
                             (errno.ENOSPC, "storage_full"), (errno.EIO, "file_io_failed")):
            with self.subTest(code=code):
                result = failure_observation(OSError(number, "private text", "secret/path"), "file_tool_execution")
                self.assertEqual(code, result["error_code"])
                self.assertEqual("unknown", result["effect"])
                self.assertNotIn("secret", str(result))
                self.assertNotIn("private text", str(result))

    def test_non_utf8_source_is_identified_without_bytes(self):
        (self.root / "source.txt").write_bytes(b"secret\xff")
        with self.assertRaises(UnicodeDecodeError) as caught:
            self.tools.execute({"operation": "read", "path": "source.txt"})
        result = failure_observation(caught.exception, "file_tool_execution")
        self.assertEqual("non_utf8_source", result["error_code"])
        self.assertNotIn("secret", str(result))

    def test_projection_excludes_source_paths_hashes_and_arbitrary_operation(self):
        result = durable_observation({"operation": "secret operation", "path": "secret path", "text": "secret body"},
                                     {"ok": False, "stage": "file_tool_execution", "detail": "secret detail",
                                      "result": {"text": "secret content"}, "error_code": "invalid_action"}, 7)
        self.assertEqual("invalid", result["operation"])
        self.assertEqual(7, result["tool_step"])
        self.assertNotIn("secret", json.dumps(result))
        self.assertEqual({"operation", "tool_step", "ok", "stage", "error_code", "effect"}, set(result))

    def test_model_receives_typed_failures_and_can_recover_without_host_edits(self):
        calls, observed = [], []
        digest = hashlib.sha256(b"private original\n").hexdigest()
        replies = iter(["not JSON", json.dumps({"operation": "write", "path": "source.txt", "text": "new"}),
                        json.dumps({"operation": "read", "path": "source.txt"}),
                        json.dumps({"operation": "write", "path": "source.txt", "text": "new", "expected_sha256": digest}),
                        json.dumps({"operation": "finish", "summary": "Host validation pending"})])
        def infer(messages):
            calls.append(messages)
            return next(replies)
        with implementation_observer(threading.Event(), lambda event, **data: observed.append(data)):
            implement_locally("Change source", self.root, scope=["source.txt"], infer=infer)
        self.assertEqual("invalid_action_json", json.loads(calls[1][-1]["content"])["observation"]["error_code"])
        self.assertEqual("read_digest_required", json.loads(calls[2][-1]["content"])["observation"]["error_code"])
        self.assertEqual([1, 2, 3, 4], [row["tool_step"] for row in observed])
        self.assertEqual(["not_applied", "not_applied", "read_only", "applied"], [row["effect"] for row in observed])
        self.assertNotIn("private original", json.dumps(observed))
        self.assertEqual("new", (self.root / "source.txt").read_text())

    def test_observation_is_durable_before_ui_delivery_and_survives_ui_error(self):
        manager = object.__new__(EvolutionManager)
        manager.audit = AuditLedger(self.root / "events.jsonl")
        task = SimpleNamespace(task_id="task-local")
        metadata = {"operation": "write", "ok": False, "error_code": "source_digest_mismatch",
                    "tool_step": 4, "attempt": 2, "stage": "file_tool_execution", "effect": "not_applied"}
        def broken_ui(*args, **kwargs):
            rows = AuditLedger(manager.audit.path).list(newest_first=False)
            self.assertEqual(metadata, rows[0]["payload"])
            raise RuntimeError("private UI details")
        with patch("evolution_v2.legacy.EvolutionManager._emit", side_effect=broken_ui):
            manager._emit(task, "local_tool_observed", **metadata)
        reopened = AuditLedger(manager.audit.path)
        rows = reopened.list(newest_first=False)
        self.assertEqual(["local_tool_observed", "local_tool_delivery_failed"], [row["event"] for row in rows])
        self.assertEqual({"error_type": "RuntimeError"}, rows[1]["payload"])
        self.assertTrue(reopened.verify()["valid"])
        self.assertNotIn("private UI details", manager.audit.path.read_text())

    def test_failed_durable_write_does_not_deliver_unrecorded_observation(self):
        manager = object.__new__(EvolutionManager)
        manager.audit = AuditLedger(self.root / "events.jsonl")
        with patch.object(manager.audit, "append", side_effect=OSError(errno.ENOSPC, "disk full")), \
                patch("evolution_v2.legacy.EvolutionManager._emit") as ui, self.assertRaises(OSError):
            manager._emit(SimpleNamespace(task_id="t"), "local_tool_observed", ok=False)
        ui.assert_not_called()


if __name__ == "__main__":
    unittest.main()
