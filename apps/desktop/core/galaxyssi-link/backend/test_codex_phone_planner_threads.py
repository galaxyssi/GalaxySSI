import os
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

import codex_app_server
from agent_execution_harness import AgentExecutionMode, execution_policy_for


class PhonePlannerThreadTests(unittest.TestCase):
    def setUp(self):
        self.directory = self.enterContext(tempfile.TemporaryDirectory())
        self.enterContext(patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": self.directory,
            "GALAXYSSI_STATE_DIR": str(Path(self.directory) / "state")}))
        self.enterContext(patch.object(codex_app_server, "CONVERSATION_THREADS_PATH", Path(self.directory) / "threads.json"))
        self.enterContext(patch.object(codex_app_server.CodexAppServer, "_begin_host_config_guard"))
        self.enterContext(patch.object(codex_app_server.CodexAppServer, "_watch_run"))
        self.server = codex_app_server.CodexAppServer("codex", {}, lambda *_: None)
        self.server._ensure_started = lambda: None
        self.calls = []
        self.fail_turn = False
        self.server._request = self.request
        self.image = Path(self.directory) / "picture.png"
        self.image.write_bytes(b"public image fixture")
        self.prefix = "Stable phone goal and tool inventory.\n" * 120

    def request(self, method, params, timeout):
        self.calls.append((method, params))
        if method == "thread/start":
            return {"thread": {"id": f"thread-{len(self.calls)}"}}
        if method == "turn/start" and self.fail_turn:
            self.fail_turn = False
            raise RuntimeError("thread not found")
        return {"turn": {"id": f"turn-{len(self.calls)}"}}

    def start(self, number, scope="phone-planner-v1:goal", images=True):
        return self.server.start_task(f"task-{number}", self.prefix + f"Current observation: {number}\n",
            self.directory, conversation_id=scope, image_paths=[str(self.image)] if images else [])

    def turns(self):
        return [params for method, params in self.calls if method == "turn/start"]

    def test_same_goal_reuses_thread_and_submits_only_new_evidence(self):
        first = self.start(1)
        first.finished = True
        second = self.start(2)
        self.assertEqual(first.thread_id, second.thread_id)
        self.assertEqual(1, sum(method == "thread/start" for method, _ in self.calls))
        before, after = self.turns()
        self.assertGreater(len(before["input"][0]["text"]) - len(after["input"][0]["text"]), len(self.prefix) // 2)
        self.assertIn("Current observation: 2", after["input"][0]["text"])
        self.assertTrue(any(item["type"] == "localImage" for item in before["input"]))
        self.assertFalse(any(item["type"] == "localImage" for item in after["input"]))

    def test_missing_provider_thread_replays_full_prompt_and_images(self):
        self.start(1).finished = True
        self.fail_turn = True
        self.start(2)
        fallback = self.turns()[-1]["input"]
        self.assertIn(self.prefix, fallback[0]["text"])
        self.assertTrue(any(item["type"] == "localImage" for item in fallback))

    def test_compaction_and_different_goal_do_not_reuse_input_receipts(self):
        first = self.start(1)
        first.finished = True
        self.server._handle_event({"method": "thread/compacted", "params": {"threadId": first.thread_id}})
        second = self.start(2)
        second.finished = True
        third = self.start(3, scope="phone-planner-v1:different-goal")
        self.assertNotEqual(second.thread_id, third.thread_id)
        for turn in self.turns()[1:]:
            self.assertIn(self.prefix, turn["input"][0]["text"])
            self.assertTrue(any(item["type"] == "localImage" for item in turn["input"]))

    def test_ordinary_chat_keeps_existing_submission_behavior(self):
        self.start(1, scope="ordinary-chat").finished = True
        self.start(2, scope="ordinary-chat")
        self.assertIn(self.prefix, self.turns()[1]["input"][0]["text"])
        self.assertTrue(any(item["type"] == "localImage" for item in self.turns()[1]["input"]))

    def test_phone_plan_only_keeps_phone_contract_without_host_snapshot(self):
        policy = replace(execution_policy_for("Research public images"), execution_mode=AgentExecutionMode.PLAN_ONLY)
        with patch.object(self.server, "_with_execution_contract", wraps=self.server._with_execution_contract) as contract:
            run = self.server.start_task("phone-only", self.prefix, self.directory,
                conversation_id="phone-planner-v1:research", execution_policy=policy)
        contract.assert_not_called()
        self.server._begin_host_config_guard.assert_not_called()
        self.assertIsNone(run.host_config_guard)
        self.assertIn(self.prefix.strip(), self.turns()[0]["input"][0]["text"])

    def test_phone_scope_does_not_skip_contract_for_desktop_execution(self):
        with patch.object(self.server, "_with_execution_contract", wraps=self.server._with_execution_contract) as contract:
            self.server.start_task("host-work", self.prefix, self.directory,
                conversation_id="phone-planner-v1:host-work", execution_policy=execution_policy_for("Build a project"))
        contract.assert_called()
        self.server._begin_host_config_guard.assert_called_once()


if __name__ == "__main__":
    unittest.main()
