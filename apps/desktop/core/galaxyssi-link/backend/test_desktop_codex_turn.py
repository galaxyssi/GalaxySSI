import threading
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from desktop_codex_turn import managed_chat_scope, native_chat_model, run_chat_turn
from pairing_access import grant_for_executor


class DesktopCodexTurnTest(unittest.TestCase):
    def setUp(self):
        self.callbacks = {}
        self.removed = []
        self.events = []
        self.server = Mock()
        self.policy = object()

    def run_turn(self, **overrides):
        def unregister(key, callback):
            self.removed.append(callback)
            self.callbacks.pop(key, None)
        args = dict(server=self.server, register=self.callbacks.__setitem__, unregister=unregister,
                    prompt="current", fresh_prompt="history and current", conversation_id="session-a",
                    cwd="workspace", model="selected-model", policy=self.policy,
                    on_event=self.events.append, cancelled=lambda: False, timeout=1)
        args.update(overrides)
        return run_chat_turn(**args)

    def test_returns_on_validated_turn_completion_without_closing_shared_server(self):
        def start(key, *args, **kwargs):
            self.callbacks[key](key, {"status": "running", "output_delta": {"text": "partial"}})
            self.callbacks[key](key, {"status": "completed", "result": "answer"})
        self.server.start_task.side_effect = start
        self.assertEqual("answer", self.run_turn())
        self.server.close.assert_not_called()
        self.assertEqual({}, self.callbacks)
        kwargs = self.server.start_task.call_args.kwargs
        self.assertEqual("selected-model", kwargs["model"])
        self.assertIs(self.policy, kwargs["execution_policy"])
        self.assertEqual("desktop-chat-v1:session-a", kwargs["conversation_id"])

    def test_wrong_identity_and_late_events_cannot_complete_another_attempt(self):
        def start(key, *args, **kwargs):
            self.callbacks[key]("wrong", {"status": "completed", "result": "wrong"})
            self.callbacks[key](key, {"status": "completed", "result": "right"})
        self.server.start_task.side_effect = start
        self.assertEqual("right", self.run_turn())
        count = len(self.events)
        self.removed[0](self.server.start_task.call_args.args[0], {"status": "running"})
        self.assertEqual(count, len(self.events))

    def test_two_conversations_are_isolated_on_one_runtime(self):
        barrier = threading.Barrier(2)
        replies = {}
        def start(key, *args, **kwargs):
            barrier.wait(timeout=2)
            self.callbacks[key](key, {"status": "completed", "result": kwargs["conversation_id"]})
        self.server.start_task.side_effect = start
        threads = [threading.Thread(target=lambda name=name: replies.update({name: self.run_turn(conversation_id=name)}))
                   for name in ("a", "b")]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(3)
        self.assertEqual({"a": "desktop-chat-v1:a", "b": "desktop-chat-v1:b"}, replies)
        self.assertEqual({}, self.callbacks)

    def test_cancel_interrupts_only_owned_turn(self):
        calls = []
        def cancelled():
            calls.append(True)
            return len(calls) > 1
        with self.assertRaisesRegex(RuntimeError, "cancelled"):
            self.run_turn(cancelled=cancelled)
        self.server.interrupt.assert_called_once_with(self.server.start_task.call_args.args[0])
        self.server.close.assert_not_called()
        self.assertEqual({}, self.callbacks)

    def test_timeout_interrupts_and_unregisters(self):
        with self.assertRaises(TimeoutError):
            self.run_turn(timeout=0.01)
        self.server.interrupt.assert_called_once()
        self.assertEqual({}, self.callbacks)

    def test_start_failure_is_not_reexecuted_through_cli(self):
        self.server.start_task.side_effect = RuntimeError("uncertain delivery")
        with self.assertRaisesRegex(RuntimeError, "uncertain delivery"):
            self.run_turn()
        self.server.start_task.assert_called_once()
        self.assertEqual({}, self.callbacks)

    def test_failed_and_empty_turns_are_not_success(self):
        for event in ({"status": "failed", "error": "validation failed"},
                      {"status": "completed", "result": ""}):
            self.server.start_task.side_effect = lambda key, *a, **kw: self.callbacks[key](key, event)
            with self.assertRaises(RuntimeError):
                self.run_turn()

    def test_custom_command_semantics_are_not_silently_changed(self):
        command = ["codex", "exec", "--skip-git-repo-check", "--ephemeral", "--model", "selected",
                   "-c", 'model_reasoning_effort="high"', "-"]
        self.assertEqual("selected", native_chat_model(command))
        for extra in ("--sandbox", "--config", "--profile", "--output-schema"):
            self.assertEqual("", native_chat_model(command + [extra, "custom"]))
        self.assertEqual("", native_chat_model(["python", "wrapper.py"]))


class SelectionSnapshotTest(unittest.TestCase):
    def test_does_not_probe_network_or_scan_run_history(self):
        import agent_gateway as gateway
        specs = {key: gateway.BASE_AGENTS[key] for key in ("codex", "local-llm")}
        with patch.object(gateway, "visible_agent_specs", return_value=specs), \
                patch.object(gateway, "_agent_runtime_snapshot", return_value={}), \
                patch.object(gateway, "_quick_agent_available", return_value=(True, "ready")) as quick, \
                patch.object(gateway, "local_model_config", return_value={"url": "local", "model": "model"}), \
                patch.object(gateway, "_local_model_available", side_effect=AssertionError("network")), \
                patch.object(gateway, "desktop_agent_provider", side_effect=AssertionError("history")):
            self.assertEqual({"agents": [{"id": "codex", "status": "ready"},
                                        {"id": "local-llm", "status": "degraded"}]}, gateway.agent_selection_snapshot())
            quick.assert_called_once_with(specs["codex"])

    def test_unavailable_backoff_is_preserved(self):
        import agent_gateway as gateway
        with patch.object(gateway, "visible_agent_specs", return_value={"codex": gateway.BASE_AGENTS["codex"]}), \
                patch.object(gateway, "_quick_agent_available", return_value=(True, "ready")), \
                patch.object(gateway, "_agent_runtime_snapshot", return_value={"status": "unavailable", "unavailable_until": 10**15}):
            self.assertEqual("unavailable", gateway.agent_selection_snapshot()["agents"][0]["status"])


class GatewayManagedChatTest(unittest.TestCase):
    def setUp(self):
        import agent_gateway as gateway
        from agent_execution_harness import execution_policy_for
        self.gateway = gateway
        self.command = ["codex", "exec", "--model", "configured-model", "-"]
        self.task = SimpleNamespace(source_message_id="desktop:test",
            execution_policy=execution_policy_for("Explain a rhetorical question").public())

    def test_selected_model_and_effort_reach_managed_runtime(self):
        gateway = self.gateway
        with patch("agent_task_manager.agent_task_manager.get", return_value=self.task), \
                patch.object(gateway, "cli_agent_runtime_config", return_value={"enabled": True, "mode": "managed-app-server"}), \
                patch.object(gateway, "_apply_selected_agent_model", return_value=self.command), \
                patch.object(gateway, "_run_managed_codex_chat", return_value="answer") as managed:
            result = gateway._ask_cli_agent_locked(gateway.BASE_AGENTS["codex"], self.command, "question",
                task_id="child", conversation_id="conversation", progress_task_id="root",
                agent_reasoning_effort="high")
            self.assertEqual("answer", result)
            self.assertEqual("configured-model", managed.call_args.kwargs["model"])
            self.assertEqual("high", managed.call_args.kwargs["reasoning_effort"])
            self.assertEqual("root", managed.call_args.kwargs["progress_task_id"])

    def test_images_restricted_plan_structured_and_custom_profiles_keep_cli_path(self):
        gateway = self.gateway
        for extra in ({"image_paths": ["image.png"]}, {"restricted_workspace": True},
                      {"plan_only": True}, {"stream_user_output": False},
                      {"codex_video_permissions": "enabled"}):
            with self.subTest(extra=extra), \
                    patch("agent_conversation_sessions.agent_conversation_sessions") as sessions, \
                    patch.object(gateway, "_run_managed_codex_chat", side_effect=AssertionError("wrong transport")), \
                    patch.object(gateway, "_apply_selected_agent_model", return_value=self.command), \
                    patch.object(gateway, "_video_codex_command", return_value=self.command), \
                    patch.object(gateway, "_native_session_command", return_value=self.command), \
                    patch.object(gateway, "_plan_only_command", return_value=self.command), \
                    patch.object(gateway, "_run_cli_agent_process", return_value="legacy"):
                sessions.return_value.get.return_value.session_id = ""
                self.assertEqual("legacy", gateway._ask_cli_agent_locked(gateway.BASE_AGENTS["codex"],
                    self.command, "question", task_id="child", conversation_id="", progress_task_id="root", **extra))

    def test_phone_desktop_handoff_reuses_managed_runtime_with_selected_model(self):
        self.task.source_message_id = "phone-message"
        self.task.agent_id = "desktop"
        self.task.client_route_id = "phone-a"
        self.task.client_conversation_id = "session"
        self.task.client_turn_id = "turn"
        self.task.conversation_id = "client:phone-a:session"
        gateway = self.gateway
        with patch("agent_task_manager.agent_task_manager.get", return_value=self.task), \
                patch("pairing_state.get_client", return_value={"access": grant_for_executor(True)}), \
                patch.object(gateway, "cli_agent_runtime_config", return_value={"enabled": True, "mode": "managed-app-server"}), \
                patch.object(gateway, "_apply_selected_agent_model", return_value=self.command), \
                patch.object(gateway, "_run_managed_codex_chat", return_value="answer") as managed, \
                patch.object(gateway, "_run_cli_agent_process", side_effect=AssertionError("process per turn")):
            self.assertEqual("answer", gateway._ask_cli_agent_locked(gateway.BASE_AGENTS["codex"],
                self.command, "question", task_id="child", progress_task_id="root",
                conversation_id=self.task.conversation_id, agent_reasoning_effort="high"))
            self.assertEqual(self.task.conversation_id, managed.call_args.kwargs["conversation_id"])
            self.assertEqual("configured-model", managed.call_args.kwargs["model"])
            self.assertEqual("high", managed.call_args.kwargs["reasoning_effort"])

    def test_native_phone_or_incomplete_or_cross_conversation_scope_is_not_migrated(self):
        fields = dict(agent_id="desktop", source_message_id="phone-message", client_route_id="phone-a",
                      client_conversation_id="session", client_turn_id="turn", conversation_id="scoped-a")
        with patch("pairing_state.get_client", return_value={"access": grant_for_executor(True)}):
            self.assertTrue(managed_chat_scope(SimpleNamespace(**fields), "scoped-a"))
        for client in (None, {"access": grant_for_executor(False)}):
            with patch("pairing_state.get_client", return_value=client):
                self.assertFalse(managed_chat_scope(SimpleNamespace(**fields), "scoped-a"))
        for changes in ({"agent_id": "codex"}, {"client_turn_id": ""}, {"source_message_id": ""},
                        {"client_conversation_id": ""}, {"conversation_id": "scoped-b"}):
            with self.subTest(changes=changes):
                self.assertFalse(managed_chat_scope(SimpleNamespace(**{**fields, **changes}), "scoped-a"))
        self.assertFalse(managed_chat_scope(None, "scoped-a"))


if __name__ == "__main__":
    unittest.main()
