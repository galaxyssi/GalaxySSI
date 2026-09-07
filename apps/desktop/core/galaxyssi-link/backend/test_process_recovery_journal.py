from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

import owned_process
from process_recovery_journal import (ProcessTerminationPending, assert_quiescent,
                                      record_job, retire_job, task_journal)


BASE_PYTHON = getattr(sys, "_base_executable", sys.executable)


class JournalTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "journal"
        self.name = "Global\\GalaxySSI-owned-" + uuid.uuid4().hex

    def test_scope_inherits_journal_without_affecting_normal_chat(self):
        with owned_process.owned_process_scope(self.root):
            with owned_process.owned_process_scope():
                self.assertEqual(self.root, owned_process._journal.get())
        self.assertIsNone(owned_process._journal.get())

    def test_task_paths_are_isolated_and_do_not_embed_task_text(self):
        first = task_journal(self.root, "../../sensitive task")
        self.assertEqual(self.root / "process-owners", first.parent)
        self.assertEqual(64, len(first.name))
        self.assertNotEqual(first, task_journal(self.root, "different task"))

    def test_missing_journal_does_not_query_the_os(self):
        with patch("windows_process_job.active_processes") as query:
            assert_quiescent(self.root)
        query.assert_not_called()

    def test_record_is_synced_before_return_and_contains_only_identity(self):
        with patch("os.fsync", wraps=os.fsync) as sync:
            path = record_job(self.root, self.name)
        sync.assert_called_once()
        self.assertEqual({"version": 1, "job": self.name}, json.loads(path.read_text()))

    def test_active_and_unknown_jobs_preserve_evidence(self):
        path = record_job(self.root, self.name)
        for result in (1, 3, OSError("query denied")):
            with self.subTest(result=result), patch("windows_process_job.active_processes") as query:
                if isinstance(result, Exception):
                    query.side_effect = result
                else:
                    query.return_value = result
                with self.assertRaises(ProcessTerminationPending):
                    assert_quiescent(self.root)
                self.assertTrue(path.exists())

    def test_invalid_evidence_cannot_authorize_recovery(self):
        path = record_job(self.root, self.name)
        for text in ("{", "[]", '{"version":1,"job":"unrelated"}',
                     json.dumps({"version": 2, "job": self.name}), "x" * 1025):
            with self.subTest(text=text[:40]):
                path.write_text(text)
                with self.assertRaises(ProcessTerminationPending):
                    assert_quiescent(self.root)
                self.assertTrue(path.exists())

    def test_only_verified_zero_retires_evidence(self):
        path = record_job(self.root, self.name)
        with patch("windows_process_job.active_processes", side_effect=OSError("unknown")):
            retire_job(path, self.name)
        self.assertTrue(path.exists())
        with patch("windows_process_job.active_processes", return_value=0):
            assert_quiescent(self.root)
        self.assertFalse(path.exists())


@unittest.skipUnless(os.name == "nt", "Windows Job Object recovery")
class WindowsJournalTests(unittest.TestCase):
    setUp = JournalTests.setUp

    def test_live_job_query_and_exit_observation(self):
        from windows_process_job import active_processes
        with owned_process.owned_process_scope(self.root):
            process = owned_process.popen([BASE_PYTHON, "-c", "import time; time.sleep(120)"],
                                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            self.assertGreater(active_processes(process.job.name), 0)
            self.assertEqual(1, len(list(self.root.glob("*.json"))))
            with self.assertRaises(ProcessTerminationPending):
                assert_quiescent(self.root)
        finally:
            process.close()
        deadline = time.monotonic() + 10
        while active_processes(process.job.name) and time.monotonic() < deadline:
            time.sleep(0.02)
        assert_quiescent(self.root)
        self.assertEqual([], list(self.root.iterdir()))

    def test_journal_failure_prevents_any_command_start(self):
        marker = self.root.parent / "must-not-run"
        code = "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('ran')"
        with patch("process_recovery_journal.record_job", side_effect=OSError("disk full")), \
                owned_process.owned_process_scope(self.root):
            with self.assertRaises(OSError):
                owned_process.popen([BASE_PYTHON, "-c", code, str(marker)])
        self.assertFalse(marker.exists())

    def test_target_observes_durable_record_before_it_runs(self):
        code = "from pathlib import Path; import sys; print(len(list(Path(sys.argv[1]).glob('*.json'))))"
        with owned_process.owned_process_scope(self.root):
            result = owned_process.run([BASE_PYTHON, "-c", code, str(self.root)],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        self.assertEqual(b"1", result.stdout.strip(), result.stderr)

    def test_github_runner_preserves_input_and_is_owned(self):
        from evolution_v2.runner import SafeRunner
        code = "from pathlib import Path; import sys; print(len(list(Path(sys.argv[1]).glob('*.json')))); print(sys.stdin.read())"
        with owned_process.owned_process_scope(self.root):
            result = SafeRunner().run([BASE_PYTHON, "-c", code, str(self.root)], self.root.parent,
                                      input_text="publication body", timeout_seconds=10)
        self.assertTrue(result.ok)
        self.assertEqual("1\npublication body", result.stdout.strip())


if __name__ == "__main__":
    unittest.main()
