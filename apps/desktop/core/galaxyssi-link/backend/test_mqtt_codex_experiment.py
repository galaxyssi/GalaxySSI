from types import SimpleNamespace
from unittest.mock import Mock, patch

import mqtt_bridge
import codex_experiment_registry as experiments
from codex_experiment_boundary import ExperimentBoundaryError
from test_codex_experiment_registry import RegistryFixture
from test_mqtt_codex_steering import _SteeringTaskManager, _SteeringCodexServer, _ImmediateThread
from test_mqtt_codex_recovery import _RecoveredTaskManager, _RecoveredCodexServer


class MqttExperimentTests(RegistryFixture):
    def setUp(self):
        super().setUp()
        self.backend = mqtt_bridge._scoped_agent_conversation_id("client-1", "conversation-1")
        self.row["conversation_ids"] = [self.backend]
        self.row["task_conversations"] = {t: self.backend for t in self.row["task_ids"]}
        self.write([self.row])
        self.enterContext(patch("agent_latency_hooks.trace_stage"))
        self.enterContext(patch.object(mqtt_bridge, "has_full_executor", return_value=True))
        self.enqueue = self.enterContext(patch.object(mqtt_bridge, "_enqueue_task_event"))
        self.enterContext(patch.object(mqtt_bridge, "_publish_or_queue_task_result"))
        self.enterContext(patch.object(mqtt_bridge.threading, "Thread", _ImmediateThread))
        self.enterContext(patch("agent_gateway._find_codex_desktop_cli", return_value="codex"))
        self.sessions = self.enterContext(patch("agent_conversation_sessions.agent_conversation_sessions"))
        self.ordinary = Mock()
        self.enterContext(patch.object(mqtt_bridge, "codex_app_server", self.ordinary))
        self.addCleanup(mqtt_bridge.codex_task_callbacks.clear)

    def payload(self, **changes):
        return dict(type="text", content="Return one synthetic JSON object.", contact_id="codex", agent_id="codex",
            client_message_id="message-follow-up", client_route_id="client-1", task_id="task-follow-up",
            conversation_id="conversation-1", turn_id="phone-turn-follow-up", attachments=[],
            connector_task_mode="phone_supervised_project_plan_v1",
            agent_invocation={"model_id": "gpt-6-astra", "reasoning_effort": "high"}, **changes)

    def dispatch(self, payload=None):
        value = payload or self.payload()
        mqtt_bridge._start_remote_agent_task(SimpleNamespace(),
            {"scheme": "signal", "_client_route_id": "client-1"}, value, [], value["content"], "text")

    def prepare_new(self):
        manager = _SteeringTaskManager()
        original_create = manager.create_external
        def create(**values):
            current = original_create(**values)
            current.request_snapshot = values["request_snapshot"]
            return current
        manager.create_external = create
        self.enterContext(patch.object(mqtt_bridge, "agent_task_manager", manager))
        server = _SteeringCodexServer()
        server.executable = "codex"
        server.close = Mock()
        server.interrupt = Mock()
        self.factory = self.enterContext(patch.object(mqtt_bridge, "CodexAppServer", return_value=server))
        return manager, server

    def test_new_mqtt_task_keeps_selection_identity_and_private_snapshot(self):
        manager, server = self.prepare_new()
        self.dispatch()
        self.assertEqual(1, len(server.start_calls))
        args, kwargs = server.start_calls[0]
        scope = experiments.registry().tasks["task-follow-up"]
        self.assertEqual(scope.marker, manager.current.request_snapshot[experiments.MARKER])
        self.assertEqual(str(scope.workspace("task-follow-up")), args[2])
        self.assertEqual(self.backend, kwargs["conversation_id"])
        self.assertEqual("gpt-6-astra", kwargs["model"])
        self.assertEqual("high", kwargs["execution_policy"].reasoning_effort.value)
        self.assertEqual("read-only", kwargs["sandbox"])
        self.assertIs(scope.boundary, self.factory.call_args.kwargs["experiment_boundary"])
        self.sessions.return_value.get.assert_not_called()
        self.sessions.return_value.put.assert_not_called()
        self.ordinary.start_task.assert_not_called()
        self.assertEqual([], server.steers)

    def test_recovery_selects_scope_from_persisted_admission_not_remote_hint(self):
        manager = _RecoveredTaskManager()
        manager.task.request_snapshot = {experiments.MARKER: experiments.registry().tasks["task-recovered"].marker}
        server = _RecoveredCodexServer()
        server.executable, server.close = "codex", Mock()
        self.enterContext(patch.object(mqtt_bridge, "agent_task_manager", manager))
        factory = self.enterContext(patch.object(mqtt_bridge, "CodexAppServer", return_value=server))
        payload = {**self.payload(), "task_id": "task-recovered", "client_message_id": "message-1",
            "turn_id": "phone-turn-recovered", "_recovered_task": True}
        self.dispatch(payload)
        self.assertEqual(1, len(server.recoveries))
        self.assertEqual("thread-original", server.recoveries[0]["thread_id"])
        self.assertEqual("turn-original", server.recoveries[0]["turn_id"])
        self.assertEqual(self.backend, server.recoveries[0]["conversation_id"])
        self.assertEqual("high", server.recoveries[0]["execution_policy"].reasoning_effort.value)
        self.assertIn("experiment_boundary", factory.call_args.kwargs)
        self.assertFalse(server.started)
        self.ordinary.recover_task.assert_not_called()

    def test_missing_or_tampered_checkpoint_grant_cannot_start_ordinary_runtime(self):
        manager = _RecoveredTaskManager()
        manager.task.request_snapshot = {}
        self.enterContext(patch.object(mqtt_bridge, "agent_task_manager", manager))
        payload = {**self.payload(), "task_id": "task-recovered", "client_message_id": "message-1",
            "turn_id": "phone-turn-recovered", "_recovered_task": True}
        self.dispatch(payload)
        self.assertEqual("failed", manager.task.status)
        self.assertIn("admission_identity", manager.task.error)
        self.ordinary.warm.assert_not_called()

    def test_remote_agent_or_model_change_is_rejected_before_runtime(self):
        manager, _ = self.prepare_new()
        for changes in ({"agent_invocation": {"model_id": "gpt-6-sol", "reasoning_effort": "high"}},
                        {"connector_task_mode": ""}, {"attachments": [{"name": "fixture.png"}]}):
            manager.current = None
            with self.subTest(changes=changes):
                self.dispatch({**self.payload(), **changes})
                self.assertEqual("failed", manager.current.status)
                self.assertTrue(manager.current.error.startswith("experiment_boundary_"))
        self.factory.assert_not_called()

    def test_unavailable_registry_reports_terminal_failure_without_starting_model(self):
        manager, _ = self.prepare_new()
        self.path.unlink()
        self.dispatch()
        self.assertEqual("failed", manager.current.status)
        self.assertIn("registry_unavailable", manager.current.error)
        self.assertEqual("failed", self.enqueue.call_args.args[2]["status"])
        self.assertEqual("task-follow-up", self.enqueue.call_args.args[2]["task_id"])
        self.factory.assert_not_called()

    def test_busy_scope_does_not_start_fresh_thread_or_steer_other_task(self):
        manager, server = self.prepare_new()
        from codex_app_server import CodexConversationBusyError
        server.start_task = Mock(side_effect=CodexConversationBusyError("other"))
        self.dispatch()
        self.assertEqual("failed", manager.current.status)
        self.assertEqual(1, server.start_task.call_count)
        self.assertEqual([], server.steers)

    def test_cancel_targets_owned_server_only(self):
        manager, server = self.prepare_new()
        manager.cancel = Mock()
        self.dispatch()
        mqtt_bridge._interrupt_agent_runtime(manager.current)
        server.interrupt.assert_called_once_with("task-follow-up")
        self.ordinary.interrupt.assert_not_called()
        manager.cancel.assert_called_once()
