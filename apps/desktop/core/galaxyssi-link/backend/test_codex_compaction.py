import tempfile
import os
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import codex_app_server as module
from codex_compaction import CompactionPhase


class CompactionTests(unittest.TestCase):
    def setUp(self):
        root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.enterContext(patch.object(module, "CONVERSATION_THREADS_PATH", root / "threads.json"))
        self.enterContext(patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(root), "GALAXYSSI_STATE_DIR": str(root / "state")}))
        self.events = []
        self.server = module.CodexAppServer("codex", {}, lambda *event: self.events.append(event))
        self.run = module.CodexRun("task", conversation_id="phone-planner-v1:task", thread_id="thread", turn_id="turn")
        self.run.last_meaningful_progress_monotonic = 100
        self.server._runs["task"] = self.run
        self.server._turn_tasks["turn"] = "task"
        self.server._finish_host_config_guard = Mock(return_value=None)
        self.server._request = Mock(return_value={"thread": {"id": "thread", "turns": [{"id": "turn", "status": "inProgress", "items": []}]}})
        self.server._checkpoint_progress = Mock()

    def event(self, method, identity="compact", turn="turn"):
        return {"method": method, "params": {"threadId": "thread", "turnId": turn,
            "item": {"id": identity, "type": "contextCompaction"}}}

    def test_duplicate_start_cannot_renew_phase_deadline(self):
        phase = CompactionPhase()
        phase.observe("item/started", self.event("")["params"], 100)
        phase.observe("item/started", self.event("")["params"], 500)
        self.assertFalse(phase.expired(579, 480))
        self.assertTrue(phase.expired(580, 480))
        phase.observe("item/completed", self.event("")["params"], 581)
        phase.observe("item/started", self.event("")["params"], 600)
        self.assertIsNone(phase.started)

    def test_completed_before_started_cannot_reopen_old_phase(self):
        phase = CompactionPhase()
        phase.observe("item/completed", self.event("")["params"], 100)
        phase.observe("item/started", self.event("")["params"], 101)
        self.assertIsNone(phase.started)

    def test_restart_restores_original_compaction_deadline(self):
        self.run.execution_harness = module.AgentExecutionHarness("task", "codex", "research")
        self.server._checkpoint_progress = module.CodexAppServer._checkpoint_progress
        with patch.object(module.time, "time", return_value=1000):
            self.server._observe_compaction(self.run, "item/started", self.event("")["params"], 50)
        recovered = module.CodexAppServer("codex", {}, lambda *_: None)
        recovered._ensure_started = lambda: None
        recovered._request = Mock(return_value={"thread": {"id": "thread", "turns": [{"id": "turn", "status": "inProgress",
            "items": [{"id": "compact", "type": "contextCompaction"}]}]}})
        with patch.object(module.time, "time", return_value=1300), patch.object(module.time, "monotonic", return_value=900), \
                patch.object(module.threading, "Thread"):
            run = recovered.recover_task(task_id="task", thread_id="thread", turn_id="turn", original_prompt="research",
                                         conversation_id=self.run.conversation_id)
        self.assertEqual(600, run.compaction.started)
        self.assertTrue(run.compaction.expired(1080, 480))

    def test_compaction_survives_ordinary_180s_silence_but_not_300s(self):
        self.run.compaction.observe("item/started", self.event("")["params"], 100)
        self.server._probe_compaction = Mock()
        with patch.object(module.time, "sleep") as sleep, patch.object(module.time, "monotonic", side_effect=[280, 399, 400]):
            self.server._watch_run("task")
        self.assertEqual(3, sleep.call_count)
        self.assertEqual("codex_compaction_timeout", self.events[-1][1]["failure_code"])
        self.assertEqual(300, self.events[-1][1]["compaction_timeout_seconds"])

    def test_wrong_turn_cannot_start_or_finish_compaction(self):
        self.server._handle_event(self.event("item/started", turn="old"))
        self.assertIsNone(self.run.compaction.started)
        self.server._handle_event(self.event("item/started"))
        self.server._handle_event(self.event("item/completed", turn="old"))
        self.assertIsNotNone(self.run.compaction.started)
        self.server._handle_event(self.event("item/completed"))
        self.assertIsNone(self.run.compaction.started)

    def test_probe_active_is_not_model_progress(self):
        self.run.compaction.observe("item/started", self.event("")["params"], 100)
        self.server._probe_compaction(self.run)
        self.assertEqual(100, self.run.last_meaningful_progress_monotonic)
        self.assertEqual(100, self.run.compaction.started)
        self.assertEqual("compaction", self.events[-1][1]["progress_event"]["metadata"]["phase"])

    def test_failed_probe_does_not_extend_deadline(self):
        self.run.compaction.started = 100
        self.server._request.side_effect = TimeoutError()
        self.server._probe_compaction(self.run)
        self.assertEqual(100, self.run.compaction.started)

    def test_probe_replays_terminal_answer_when_notification_was_missed(self):
        turn = {"id": "turn", "status": "completed", "items": [{"id": "answer", "type": "agentMessage", "text": "Verified result", "phase": "final_answer"}]}
        self.server._request.return_value = {"thread": {"id": "thread", "turns": [turn]}}
        self.server._probe_compaction(self.run)
        self.assertTrue(self.run.finished)
        self.assertTrue(any(event.get("result") == "Verified result" for _, event in self.events))

    def test_foreign_thread_snapshot_is_ignored(self):
        self.server._request.return_value = {"thread": {"id": "foreign", "turns": [{"id": "turn", "status": "completed"}]}}
        self.server._probe_compaction(self.run)
        self.assertFalse(self.run.finished)
        self.assertEqual([], self.events)

    def test_pressure_uses_last_context_not_cumulative_usage_and_only_steers_once(self):
        self.run.research_observed = True
        params = {"threadId": "thread", "turnId": "turn", "tokenUsage": {"modelContextWindow": 258400,
            "last": {"inputTokens": 180000}, "total": {"inputTokens": 4000000}}}
        with patch.object(module.threading, "Thread") as thread:
            self.server._capture_provider_usage(params)
            self.server._capture_provider_usage(params)
        thread.assert_called_once()
        self.assertEqual(100, self.run.last_meaningful_progress_monotonic)

    def test_recovery_store_is_scoped_and_keeps_source_with_missing_fee(self):
        self.server._save_research(self.run, [{"id": "school", "kind": "finding", "text": "Online doctorate", "url": "https://school.edu"},
            {"id": "fee", "kind": "gap", "text": "Fee unavailable", "status": "open"}])
        retry = module.CodexRun("retry", conversation_id=self.run.conversation_id)
        self.assertEqual(2, len(self.server._research_store().handoff(self.server._research_scope(retry))["entries"]))
        retry.conversation_id = "phone-planner-v1:other"
        self.assertEqual([], self.server._research_store().handoff(self.server._research_scope(retry))["entries"])

    def test_exact_duplicate_web_outputs_do_not_repeat_large_bodies(self):
        output = {"success": True, "contentItems": [{"type": "inputText", "text": "same source evidence " * 500}]}
        responses = []
        self.server._write_server_response = lambda _, response: responses.append(response)
        with patch.object(module, "execute_codex_dynamic_search", return_value=output):
            for number in range(2):
                self.server._execute_dynamic_tool_call("task", {"id": str(number)}, {
                    "tool": module.CODEX_DYNAMIC_SEARCH_TOOL, "arguments": {"query": "source"}}, {})
        self.assertEqual(output, responses[0])
        self.assertLess(len(responses[1]["contentItems"][0]["text"]), 500)
        self.assertIn("same evidence", responses[1]["contentItems"][0]["text"])

    def test_compaction_completion_allows_reopening_evidence_in_new_context(self):
        self.run.research_output_digests.add("old-result")
        self.server._observe_compaction(self.run, "item/started", self.event("")["params"], 100)
        self.server._observe_compaction(self.run, "item/completed", self.event("")["params"], 200)
        self.assertEqual(set(), self.run.research_output_digests)

    def test_actual_reasoning_delta_is_progress_not_a_heartbeat(self):
        with patch.object(module.time, "monotonic", return_value=200):
            self.server._handle_event({"method": "item/reasoning/summaryTextDelta", "params": {
                "threadId": "thread", "turnId": "turn", "itemId": "reason", "delta": "Checking a source"}})
        self.assertEqual(200, self.run.last_meaningful_progress_monotonic)
        self.assertFalse(self.server._is_meaningful_event("item/reasoning/summaryTextDelta", {}, {"delta": ""}))

    def test_connection_retries_cannot_reset_deadline_or_borrow_compaction_budget(self):
        params = {"error": {"message": "request timed out"}, "willRetry": True}
        self.run.provider_recovery.observe(params, 100)
        self.run.provider_recovery.observe(params, 210)
        self.run.compaction.started = 100
        self.server._probe_compaction = Mock()
        with patch.object(module.time, "sleep"), patch.object(module.time, "monotonic", return_value=220):
            self.server._watch_run("task")
        self.assertEqual("codex_provider_unavailable", self.events[-1][1]["failure_code"])
        self.assertEqual("provider_connection", self.events[-1][1]["timeout_stage"])
        self.assertEqual("request timed out", self.events[-1][1]["error"])

    def test_non_retryable_error_ends_without_waiting_180_seconds(self):
        self.server._handle_event({"method": "error", "params": {"threadId": "thread", "turnId": "turn",
            "error": {"message": "Unauthorized"}, "willRetry": False}})
        with patch.object(module.time, "sleep"), patch.object(module.time, "monotonic", return_value=101):
            self.server._watch_run("task")
        self.assertEqual("failed", self.events[-1][1]["status"])
        self.assertEqual("Unauthorized", self.events[-1][1]["error"])

    def test_recovered_model_stream_clears_connection_failure_but_status_does_not(self):
        self.run.provider_recovery.observe({"error": {"message": "disconnected"}, "willRetry": True}, 100)
        self.server._handle_event({"method": "thread/status/changed", "params": {
            "threadId": "thread", "turnId": "turn", "status": "active"}})
        self.assertEqual(100, self.run.provider_recovery.started)
        self.server._handle_event({"method": "item/agentMessage/delta", "params": {
            "threadId": "thread", "turnId": "turn", "itemId": "reply", "delta": "A supported answer"}})
        self.assertIsNone(self.run.provider_recovery.started)

    def test_lost_completion_is_reconciled_before_ordinary_stall(self):
        self.server._request.return_value = {"thread": {"id": "thread", "turns": [
            {"id": "turn", "status": "completed", "items": [
                {"id": "reply", "type": "agentMessage", "text": "Already done", "phase": "final_answer"}]}]}}
        with patch.object(module.time, "sleep"), patch.object(module.time, "monotonic", return_value=280):
            self.server._watch_run("task")
        self.assertEqual("completed", self.events[-1][1]["status"])
        self.assertEqual("Already done", self.events[-1][1]["result"])

    def test_foreign_error_cannot_fail_current_turn(self):
        self.server._handle_event({"method": "error", "params": {"threadId": "thread", "turnId": "old",
            "error": {"message": "Unauthorized"}, "willRetry": False}})
        self.assertIsNone(self.run.provider_recovery.started)

    def test_old_completed_compaction_snapshot_cannot_renew_ordinary_silence(self):
        self.run.compaction.observe("item/started", self.event("")["params"], 50)
        self.run.compaction.observe("item/completed", self.event("")["params"], 60)
        for status in (None, "completed"):
            item = {"id": "compact", "type": "contextCompaction"}
            if status is not None:
                item["status"] = status
            self.server._request.return_value = {"thread": {"id": "thread", "turns": [
                {"id": "turn", "status": "inProgress", "items": [item]}]}}
            self.server._probe_compaction(self.run)
            self.assertIsNone(self.run.compaction.started)
            self.assertEqual(100, self.run.last_meaningful_progress_monotonic)

    def test_model_output_during_failure_probe_prevents_stale_timeout(self):
        self.run.provider_recovery.observe({"error": {"message": "disconnected"}, "willRetry": True}, 100)
        def recover(_run):
            self.run.provider_recovery.recovered()
            self.run.last_meaningful_progress_monotonic = 220
        self.server._probe_compaction = Mock(side_effect=recover)
        def stop_next_tick(_seconds):
            if self.server._probe_compaction.called:
                self.run.finished = True
        with patch.object(module.time, "sleep", side_effect=stop_next_tick), patch.object(module.time, "monotonic", return_value=220):
            self.server._watch_run("task")
        self.server._probe_compaction.assert_called_once()
        self.assertFalse(any(event.get("status") == "timed_out" for _, event in self.events))


if __name__ == "__main__":
    unittest.main()
