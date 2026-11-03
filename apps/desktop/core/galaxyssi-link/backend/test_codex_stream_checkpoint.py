"""A stream heartbeat must not make terminal delivery wait for token-level I/O."""
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from agent_execution_harness import AgentExecutionHarness, AgentTaskBudgetExceeded, execution_policy_for
from codex_app_server import CodexAppServer, CodexRun


class StreamCheckpointTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        env = patch.dict(os.environ, {"GALAXYSSI_STATE_DIR": self.directory.name,
                                     "GALAXYSSI_WORKSPACE_ROOT": self.directory.name})
        env.start()
        self.addCleanup(env.stop)

    def harness(self, **kwargs):
        return AgentExecutionHarness("stream-test", "codex", "answer", **kwargs)

    def test_fragments_update_memory_without_rewriting_each_checkpoint(self):
        harness = self.harness()
        with patch("agent_execution_harness.time.monotonic", return_value=100.0), \
                patch.object(harness, "_save", wraps=harness._save) as save:
            for index in range(1024):
                harness.stream_progress("act", event_index=index)
            self.assertEqual(1, save.call_count)
            self.assertEqual(1023, harness.checkpoint.verification["event_index"])
            harness.progress("observe", completed_item="result")
            self.assertEqual(2, save.call_count)
        for path in harness._checkpoint_paths():
            saved = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(1023, saved["verification"]["event_index"])
            self.assertEqual("observe", saved["phase"])

    def test_stream_flushes_periodically_and_phase_changes_are_immediate(self):
        harness = self.harness()
        with patch("agent_execution_harness.time.monotonic", return_value=100.0) as clock, \
                patch.object(harness, "_save", wraps=harness._save) as save:
            harness.stream_progress("act")
            clock.return_value = 100.9
            harness.stream_progress("act")
            self.assertEqual(1, save.call_count)
            clock.return_value = 101.0
            harness.stream_progress("act")
            self.assertEqual(2, save.call_count)
            harness.stream_progress("observe")
            harness.progress("observe", tool_receipt="complete")
            harness.progress("finalize")
            self.assertEqual(5, save.call_count)
        restored = self.harness()
        self.assertEqual("finalize", restored.checkpoint.phase)
        self.assertEqual("complete", restored.checkpoint.verification["tool_receipt"])

    def test_monotonic_reset_and_separate_runs_do_not_suppress_saves(self):
        left = self.harness()
        right = AgentExecutionHarness("other-task", "codex", "answer")
        with patch("agent_execution_harness.time.monotonic", return_value=100.0) as clock, \
                patch.object(left, "_save", wraps=left._save) as saves_left, \
                patch.object(right, "_save", wraps=right._save) as saves_right:
            left.stream_progress("act")
            right.stream_progress("act")
            self.assertEqual(1, saves_right.call_count)
            clock.return_value = 1.0
            left.stream_progress("act")
            self.assertEqual(2, saves_left.call_count)

    def test_stream_budget_failure_is_checked_and_persisted_without_waiting(self):
        policy = execution_policy_for("answer", requested_task_budget={
            "profile": "custom", "max_elapsed_seconds": 1})
        harness = self.harness(policy=policy)
        with patch("agent_execution_harness.time.monotonic", return_value=100.0), \
                patch("agent_execution_harness.time.time", return_value=1000.0) as wall:
            harness.stream_progress("act")
            wall.return_value = 1002.0
            with self.assertRaises(AgentTaskBudgetExceeded):
                harness.stream_progress("act")
        self.assertEqual("failed", self.harness(policy=policy).checkpoint.phase)

    def test_interleaved_notifications_preserve_exact_text_and_terminal_order(self):
        events = []
        server = CodexAppServer("codex", {}, lambda task, event: events.append((task, event)))
        harness = self.harness()
        run = CodexRun(task_id="stream-test", thread_id="thread", turn_id="turn", execution_harness=harness)
        server._runs[run.task_id] = run
        server._turn_tasks[run.turn_id] = run.task_id
        with patch("agent_execution_harness.time.monotonic", return_value=100.0), \
                patch.object(harness, "_save", wraps=harness._save) as save:
            for _ in range(1024):
                server._handle_event({"method": "item/agentMessage/delta", "params": {
                    "threadId": "thread", "turnId": "turn", "itemId": "answer", "delta": "x"}})
                # An interleaved notification prevents adjacent-delta batching.
                server._handle_event({"method": "thread/status/changed", "params": {
                    "threadId": "thread", "turnId": "turn", "status": {"type": "active"}}})
            self.assertEqual(1, save.call_count)
            server._handle_event({"method": "item/completed", "params": {
                "threadId": "thread", "turnId": "turn", "item": {
                    "id": "answer", "type": "agentMessage", "phase": "final_answer", "text": "x" * 1024}}})
            self.assertEqual(2, save.call_count)
            server._handle_event({"method": "turn/completed", "params": {
                "threadId": "thread", "turn": {"id": "turn", "status": "completed"}}})
            # Stream, item completion, turn receipt, quality check, finalization,
            # and usage accounting all retain their required durable boundaries.
            self.assertEqual(6, save.call_count)
        self.assertTrue(run.finished)
        terminal = [(task, event) for task, event in events if event.get("status") == "completed"]
        self.assertEqual(1, len(terminal))
        self.assertEqual("x" * 1024, terminal[0][1]["result"])
        self.assertEqual("finalize", self.harness().checkpoint.phase)


if __name__ == "__main__":
    unittest.main()
