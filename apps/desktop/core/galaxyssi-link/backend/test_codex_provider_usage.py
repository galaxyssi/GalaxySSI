import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from codex_provider_usage import MAX_COUNTER, capture, normalize


def payload(value=100):
    counts = dict(inputTokens=value, cachedInputTokens=20, outputTokens=30,
                  reasoningOutputTokens=10, totalTokens=value + 30)
    return dict(threadId="provider-thread", turnId="provider-turn",
                tokenUsage=dict(total=counts, last=dict(counts), modelContextWindow=400000))


def observation(value=100):
    return normalize(payload(value), model="fixture-model", effort="high")


class CodexProviderUsageTest(unittest.TestCase):
    def test_preserves_counters_without_inventing_requests_cost_or_actual_model(self):
        result = observation()
        self.assertEqual(100, result["total"]["input_tokens"])
        self.assertEqual(130, result["last"]["total_tokens"])
        self.assertEqual([], result["issues"])
        for field in ("request_count", "billed_cost", "actual_model"):
            self.assertIsNone(result[field])
        self.assertIsNone(result["last"]["cache_write_input_tokens"])
        self.assertEqual("provider_thread_cumulative_not_task_total", result["total_scope"])

    def test_zero_is_not_missing(self):
        params = payload()
        params["tokenUsage"]["last"]["cacheWriteInputTokens"] = 0
        self.assertEqual(0, normalize(params, model="m", effort="high")["last"]["cache_write_input_tokens"])
        params["tokenUsage"]["last"]["inputTokens"] = None
        result = normalize(params, model="m", effort="high")
        self.assertIsNone(result["last"]["input_tokens"])
        self.assertIn("last.inputTokens:invalid_or_missing_counter", result["issues"])

    def test_invalid_counters_are_redacted_and_diagnosed(self):
        for invalid in (True, -1, 1.5, "100", float("nan"), MAX_COUNTER + 1, {}, []):
            with self.subTest(value=invalid):
                params = payload()
                params["tokenUsage"]["total"]["inputTokens"] = invalid
                result = normalize(params, model="m", effort="high")
                self.assertIsNone(result["total"]["input_tokens"])
                self.assertIn("total.inputTokens:invalid_or_missing_counter", result["issues"])

    def test_inconsistent_subcounts_preserved_with_warning_not_silently_fixed(self):
        params = payload()
        params["tokenUsage"]["total"]["cachedInputTokens"] = 101
        params["tokenUsage"]["last"]["reasoningOutputTokens"] = 31
        result = normalize(params, model="m", effort="high")
        self.assertEqual(101, result["total"]["cached_input_tokens"])
        self.assertIn("total.cached_input_tokens:exceeds_parent_counter", result["issues"])
        self.assertIn("last.reasoning_output_tokens:exceeds_parent_counter", result["issues"])

    def test_missing_usage_is_not_zero_and_unknown_content_is_not_retained(self):
        params = dict(threadId="t", turnId="u", tokenUsage="secret-raw-payload", prompt="secret-prompt")
        result = normalize(params, model="m", effort="high")
        self.assertNotIn("secret", str(result))
        self.assertIn("tokenUsage:invalid_or_missing_object", result["issues"])
        self.assertTrue(all(value is None for value in result["total"].values()))

    def test_identity_and_lifecycle_are_strict(self):
        for field in ("threadId", "turnId"):
            for invalid in (None, "", 1, "x" * 201):
                params = {**payload(), field: invalid}
                self.assertIsNone(normalize(params, model="m", effort="high"))
        self.assertIsNone(normalize(payload(), model="m", effort="high", kind={}))
        marker = normalize(payload(), model="m", effort="high", kind="turn_terminal", status="completed")
        self.assertEqual("completed", marker["provider_status"])
        self.assertNotIn("total", marker)

    def test_capture_is_failure_isolated_and_never_retries_the_task(self):
        manager = Mock()
        manager.provider_usage.record.side_effect = OSError("private error")
        mutations = SimpleNamespace(manager=manager, snapshot=lambda: {"task_id": "task"})
        with self.assertLogs("codex_provider_usage", level="WARNING") as logs:
            self.assertIsNone(capture(mutations, {"provider_usage": observation()}))
        self.assertNotIn("private error", str(logs.output))
        self.assertEqual(1, len(manager.mock_calls))
        manager.provider_usage.record.assert_called_once()


class CodexProviderUsageRoutingTest(unittest.TestCase):
    def setUp(self):
        from codex_app_server import CodexAppServer, CodexRun
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        env = patch.dict(os.environ, GALAXYSSI_WORKSPACE_ROOT=temporary.name,
                         GALAXYSSI_STATE_DIR=str(Path(temporary.name) / "state"))
        env.start()
        self.addCleanup(env.stop)
        self.events = []
        self.server = CodexAppServer("codex", {}, lambda task, event: self.events.append((task, event)))
        self.run = CodexRun(task_id="task", thread_id="provider-thread", turn_id="provider-turn",
                            model="fixture-model", reasoning_effort="high")
        self.server._runs["task"] = self.run
        self.server._turn_tasks[self.run.turn_id] = self.run.task_id

    def send(self, params=None):
        self.server._handle_event(dict(method="thread/tokenUsage/updated", params=payload() if params is None else params))

    def test_usage_does_not_refresh_progress_watchdog_or_checkpoint(self):
        before = vars(self.run).copy()
        with patch.object(self.server, "_checkpoint_progress") as checkpoint:
            self.send()
            checkpoint.assert_not_called()
        self.assertEqual(before, vars(self.run))
        self.assertEqual("task", self.events[0][0])
        self.assertTrue(self.events[0][1]["provider_usage_only"])
        self.assertNotIn("status", self.events[0][1])

    def test_wrong_thread_turn_and_malformed_ids_are_ignored(self):
        for params in ({**payload(), "threadId": "other"}, {**payload(), "turnId": "other"},
                       {**payload(), "turnId": {}}, {"threadId": "provider-thread"}, []):
            self.send(params)
        self.assertEqual([], self.events)

    def test_late_notification_keeps_finished_execution_without_resurrecting_it(self):
        self.run.finished = True
        self.server._turn_tasks.clear()
        self.send()
        self.assertTrue(self.run.finished)
        self.assertEqual("task", self.events[0][0])
        self.assertEqual({}, self.server._turn_tasks)

    def test_ambiguous_late_turn_is_not_guessed(self):
        from codex_app_server import CodexRun
        self.server._turn_tasks.clear()
        self.server._runs["other"] = CodexRun(task_id="other", thread_id=self.run.thread_id, turn_id=self.run.turn_id)
        self.send()
        self.assertEqual([], self.events)

    def test_failure_of_usage_consumer_does_not_fail_execution(self):
        self.server.on_event = Mock(side_effect=RuntimeError("private"))
        with self.assertLogs("galaxyssi.codex", level="WARNING"):
            self.send()
        self.assertFalse(self.run.finished)

    def test_lifecycle_is_separate_from_public_events_and_precedes_terminal_delivery(self):
        self.server._handle_event(dict(method="turn/started", params=dict(
            threadId=self.run.thread_id, turn=dict(id=self.run.turn_id))))
        self.assertEqual("turn_started", self.events[0][1]["provider_usage"]["kind"])
        self.assertEqual("running", self.events[1][1]["status"])
        self.events.clear()
        self.run.final_text = "Fixture complete."
        with patch.object(self.server, "_apply_web_citation_gate", return_value=False), \
                patch.object(self.server, "_finish_host_config_guard", return_value=None):
            self.server._handle_event(dict(method="turn/completed", params=dict(
                threadId=self.run.thread_id, turn=dict(id=self.run.turn_id, status="completed"))))
        self.assertEqual("turn_terminal", self.events[0][1]["provider_usage"]["kind"])
        self.assertEqual("completed", self.events[-1][1]["status"])

    def test_citation_repair_keeps_first_turn_terminal_observation(self):
        self.run.final_text = "Fixture requiring repair."
        with patch.object(self.server, "_apply_web_citation_gate", return_value=True):
            self.server._handle_event(dict(method="turn/completed", params=dict(
                threadId=self.run.thread_id, turn=dict(id=self.run.turn_id, status="completed"))))
        self.assertEqual("turn_terminal", self.events[0][1]["provider_usage"]["kind"])
        self.assertFalse(self.run.finished)


if __name__ == "__main__":
    unittest.main()
