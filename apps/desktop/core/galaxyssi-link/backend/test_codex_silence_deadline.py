import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, Mock

import codex_app_server as module


class SilenceDeadlineTests(unittest.TestCase):
    def setUp(self):
        directory = self.enterContext(tempfile.TemporaryDirectory())
        self.enterContext(patch.object(module, "CONVERSATION_THREADS_PATH", Path(directory) / "threads.json"))
        self.events = []
        self.server = module.CodexAppServer("codex", {}, lambda *event: self.events.append(event))
        self.run = module.CodexRun("task", conversation_id="phone-planner-v1:test", thread_id="hung", turn_id="turn")
        self.run.last_meaningful_progress_monotonic = 100
        self.server._runs[self.run.task_id] = self.run
        self.key = self.server._conversation_key(self.run.conversation_id)
        self.server._conversation_threads[self.key] = "hung"
        self.server._finish_host_config_guard = Mock()
        self.server._request = Mock()
        self.server._attempt_replan = Mock()

    def test_silence_expires_at_180_even_with_long_execution_policy(self):
        with patch.object(module.time, "sleep"), patch.object(module.time, "monotonic", return_value=280), \
                patch.object(module, "CODEX_STALL_TIMEOUT_SECONDS", 900):
            self.server._watch_run("task")
        self.assertTrue(self.run.finished)
        self.assertEqual("timed_out", self.events[-1][1]["status"])
        self.assertEqual(180, self.events[-1][1]["no_progress_timeout_seconds"])
        self.assertNotIn(self.key, self.server._conversation_threads)
        self.server._attempt_replan.assert_not_called()
        self.assertEqual("turn/interrupt", self.server._request.call_args.args[0])

    def test_progress_before_deadline_keeps_run_and_newer_thread_mapping(self):
        times = iter([279, 280])
        self.server._conversation_threads[self.key] = "newer-thread"
        with patch.object(module.time, "sleep") as sleep, \
                patch.object(module.time, "monotonic", side_effect=lambda: next(times)):
            self.server._watch_run("task")
        self.assertEqual(2, sleep.call_count)
        self.assertEqual("newer-thread", self.server._conversation_threads[self.key])

    def test_heartbeat_is_not_meaningful_progress(self):
        self.assertFalse(self.server._is_meaningful_event("thread/status/changed", {}, {"status": "active"}))


if __name__ == "__main__":
    unittest.main()
