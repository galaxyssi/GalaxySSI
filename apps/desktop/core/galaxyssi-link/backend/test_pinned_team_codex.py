import os
from dataclasses import replace
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import codex_app_server as native
import mqtt_bridge as bridge
from agent_execution_harness import (
    COLLABORATION_WORKSPACE_RESULT, PINNED_TEAM_CODEX_CAPABILITY, execution_policy_for,
    requested_team_codex_model,
)
from agent_request_snapshot import build_request_snapshot, restore_request_options
from test_mqtt_codex_recovery import _RecoveredCodexServer, _RecoveredTaskManager
from test_mqtt_codex_steering import _SteeringCodexServer, _SteeringTaskManager


MODEL = "gpt-6-astra"
MEMBER = {"team_id": "team-1", "agent_instance_id": "member-1",
          "result_contract": COLLABORATION_WORKSPACE_RESULT, "agent_invocation": {"model_id": MODEL}}


class TeamPinTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.enterContext(patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(self.root),
                                                   "GALAXYSSI_STATE_DIR": str(self.root / "state")}))
        self.enterContext(patch.object(native, "CONVERSATION_THREADS_PATH", self.root / "threads.json"))
        self.policy = replace(execution_policy_for("Hello"), pinned_codex_model=MODEL)

    def test_only_explicit_member_restores_as_pinned(self):
        for agent, changes, expected in (
            ("codex", {}, MODEL), ("claude", {}, ""), ("codex", {"team_id": " "}, ""),
            ("codex", {"agent_instance_id": ""}, ""), ("codex", {"result_contract": "other"}, ""),
            ("codex", {"agent_invocation": {"reasoning_effort": "high"}}, ""),
        ):
            with self.subTest(agent=agent, changes=changes):
                request = {**MEMBER, **changes}
                pin = requested_team_codex_model(agent, request)
                self.assertEqual(expected, pin)
                snapshot = build_request_snapshot(request, model_id=MODEL, reasoning_effort="high",
                    policy=replace(self.policy, pinned_codex_model=pin).public())
                self.assertEqual(expected, requested_team_codex_model(agent, restore_request_options(snapshot)))

    def test_native_start_disables_fallback_and_requires_ack_only_for_pin(self):
        server = native.CodexAppServer("unused", {}, Mock())
        server._request = Mock(return_value={"thread": {"id": "t"}, "model": "other"})
        with self.assertRaisesRegex(RuntimeError, MODEL):
            server._start_thread(str(self.root), MODEL, "client:test", exact_model=True)
        self.assertIs(False, server._request.call_args.args[1]["allowProviderModelFallback"])
        self.assertFalse(server._request.call_args.args[1]["config"]["features.multi_agent"])
        self.assertEqual("t", server._start_thread(str(self.root), MODEL, "client:test"))
        self.assertNotIn("allowProviderModelFallback", server._request.call_args.args[1])
        self.assertNotIn("features.multi_agent", server._request.call_args.args[1]["config"])
        server._request.return_value["model"] = MODEL
        self.assertEqual("t", server._start_thread(str(self.root), MODEL, "client:member", exact_model=True))

    def test_resume_cannot_complete_before_confirming_model(self):
        server = native.CodexAppServer("unused", {}, Mock())
        server._ensure_started = Mock()
        def resume(method, params, timeout):
            self.assertEqual("thread/resume", method)
            self.assertEqual(MODEL, params["model"])
            server._handle_event({"method": "turn/completed", "params": {"threadId": "t", "turn": {"id": "u"}}})
            return {"thread": {"id": "t"}, "model": "substitute"}
        server._request = resume
        with self.assertRaisesRegex(RuntimeError, MODEL):
            server.recover_task("task", "t", "u", "Hello", model=MODEL, execution_policy=self.policy)
        self.assertFalse(any(c.args[1].get("status") == "completed" for c in server.on_event.call_args_list))

    def test_provider_reroute_fails_only_owned_pinned_turn(self):
        server = native.CodexAppServer("unused", {}, Mock())
        server._capture_provider_usage = Mock()
        server._request = Mock()
        for pin, turn in (("", "u"), (MODEL, "u"), (MODEL, "")):
            run = native.CodexRun("task", thread_id="t", turn_id=turn,
                                  execution_policy=replace(self.policy, pinned_codex_model=pin))
            server._runs["task"] = run
            if turn:
                server._turn_tasks[turn] = "task"
            for thread in ("other", "t"):
                server._handle_event({"method": "model/rerouted", "params": {
                    "threadId": thread, "turnId": "u", "fromModel": MODEL, "toModel": "other"}})
                self.assertEqual(bool(pin and thread == "t"), run.finished)
        self.assertEqual("failed", server.on_event.call_args.args[1]["status"])

    def test_capability_only_on_codex_in_both_presence_formats(self):
        self.enterContext(patch.object(bridge, "connector_diagnostics", return_value={"agents": [
            {"id": agent, "adapter": {"capabilities": ["conversation"]}} for agent in ("codex", "claude")]}))
        self.enterContext(patch.object(bridge, "get_signal_bundle", return_value={}))
        self.enterContext(patch("agent_reputation_ledger.agent_reputation_ledger", return_value=None))
        for detailed in (False, True):
            codex, claude = bridge.mobile_connector_agents(detailed=detailed)
            self.assertIn(PINNED_TEAM_CODEX_CAPABILITY, codex["capabilities"])
            self.assertNotIn(PINNED_TEAM_CODEX_CAPABILITY, claude.get("capabilities", []))

    def dispatch(self, **changes):
        value = {**MEMBER, "type": "text", "content": "Hello", "contact_id": "codex", "agent_id": "codex",
                 "client_message_id": "message-follow-up", "client_route_id": "client-1",
                 "task_id": "task-follow-up", "conversation_id": "conversation-1",
                 "turn_id": "phone-turn-follow-up", **changes}
        bridge._start_remote_agent_task(None, {"scheme": "signal", "_client_route_id": "client-1"},
                                        value, [], value["content"], "text")

    def fake_runtime(self, manager, server):
        self.enterContext(patch.object(bridge, "agent_task_manager", manager))
        self.enterContext(patch.object(bridge, "_codex_server", return_value=server))
        self.enterContext(patch.object(bridge, "get_client", return_value=None))
        self.enterContext(patch.object(bridge, "has_full_executor", return_value=True))
        self.enterContext(patch.object(bridge, "_publish_or_queue_task_result"))
        self.enterContext(patch("agent_gateway._agent_env", return_value={}))
        self.enterContext(patch("agent_latency_hooks.trace_stage"))
        self.enterContext(patch("agent_conversation_sessions.agent_conversation_sessions"))
        self.enterContext(patch("task_workspace.task_workspace", return_value=self.root))
        self.worker = self.enterContext(patch("agent_worker_app_admission.dispatch_app_request", return_value=None))
        self.enqueue = self.enterContext(patch.object(bridge, "_enqueue_task_event"))
        for task in ("task-follow-up", "task-recovered", "ordinary"):
            self.addCleanup(bridge.codex_task_callbacks.pop, task, None)

    def test_unavailable_pin_fails_visibly_ordinary_route_can_substitute(self):
        manager, server = _SteeringTaskManager(), _SteeringCodexServer()
        self.fake_runtime(manager, server)
        for model in ("gpt-5.4", "not-advertised"):
            manager.current = None
            self.dispatch(agent_invocation={"model_id": model})
            self.assertEqual("failed", manager.current.status)
            self.assertIn(model, self.enqueue.call_args.args[2]["error"])
        self.assertFalse(server.started)
        self.worker.assert_not_called()
        manager.current = None
        self.dispatch(agent_id="claude")
        self.assertIn("conflicting", manager.current.error)
        self.dispatch(task_id="ordinary", team_id="", agent_invocation={"model_id": "gpt-5.4"})
        self.assertEqual("gpt-5.6-sol", server.start_calls[-1][1]["model"])
        self.worker.assert_called_once()

    def test_model_requested_handoff_is_terminal_for_pin(self):
        manager, server = _SteeringTaskManager(), _SteeringCodexServer()
        self.fake_runtime(manager, server)
        self.dispatch()
        self.worker.assert_not_called()
        self.assertEqual(MODEL, server.start_calls[0][1]["execution_policy"].pinned_codex_model)
        with patch.object(bridge, "deliver_agent_sync") as handoff:
            bridge._dispatch_codex_event("task-follow-up", {"status": "completed", "result":
                '[GALAXYSSI_RECOVERY_ACTION_V1]\n{"version":1,"action":"switch_agent","target_agent_id":"claude"}'
                '\n[/GALAXYSSI_RECOVERY_ACTION_V1]'})
            handoff.assert_not_called()
        self.assertEqual("failed", manager.current.status)
        self.assertIn("handoff refused", manager.current.error)

    def test_recovery_with_lost_pin_fails_before_provider_dispatch(self):
        manager, server = _RecoveredTaskManager(), _RecoveredCodexServer()
        self.fake_runtime(manager, server)
        manager.task.execution_policy = self.policy.public()
        self.dispatch(task_id="task-recovered", client_message_id="message-1", turn_id="phone-turn-recovered",
                      _recovered_task=True, team_id="")
        self.assertEqual("failed", manager.task.status)
        self.assertIn(MODEL, manager.task.error)
        self.assertFalse(server.recoveries)

    def test_recovery_dispatches_to_the_exact_model_again(self):
        manager, server = _RecoveredTaskManager(), _RecoveredCodexServer()
        self.fake_runtime(manager, server)
        manager.task.execution_policy = self.policy.public()
        snapshot = build_request_snapshot(MEMBER, model_id=MODEL, reasoning_effort="high", policy=self.policy.public())
        manager.recovery_request = Mock(return_value=snapshot)
        bridge._resume_recovered_remote_task(None, vars(manager.task))
        self.assertEqual(1, len(server.recoveries))
        self.assertEqual(MODEL, server.recoveries[0]["model"])
        self.assertEqual(MODEL, server.recoveries[0]["execution_policy"].pinned_codex_model)
        self.worker.assert_not_called()
