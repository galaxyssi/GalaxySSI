"""Private request persistence and real task-manager recovery with fake providers."""
import base64
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from agent_execution_harness import execution_policy_for
from agent_request_snapshot import build_request_snapshot, restore_request_options, snapshot_copy
from agent_task_manager import AgentTaskManager
import mqtt_bridge as bridge


class RequestSnapshotTest(unittest.TestCase):
    def snapshot(self, attachments=None):
        return build_request_snapshot(
            {"response_language": "zh-CN", "attachments": attachments or [],
             "api_key": "secret-not-persisted", "_recovered_task": True,
             "client_route_id": "forged-route", "agent_invocation": {"model_id": "ignored"}},
            model_id="gpt-6-astra", reasoning_effort="high", policy=execution_policy_for("Test").public(),
        )

    def manager(self, path):
        manager = AgentTaskManager(state_path=path)
        self.addCleanup(manager._work_pool.close)
        self.addCleanup(manager._control_work_pool.close)
        return manager

    def create(self, manager, snapshot):
        return manager.create_external(
            "codex", "codex", "message-1", "Read the attached arithmetic.", lambda _: None,
            task_id="test-queued", client_route_id="app-a", conversation_id="app-a:chat",
            client_conversation_id="chat", client_turn_id="turn-1", request_snapshot=snapshot,
        )

    def test_only_allowed_options_and_attachment_fields_are_persisted(self):
        value = self.snapshot([{"name": "test.png", "transfer_id": "a" * 64,
                                "api_key": "secret", "local_path": "do-not-trust"}])
        encoded = json.dumps(value)
        for forbidden in ("api_key", "_recovered_task", "client_route_id", "local_path"):
            self.assertNotIn(forbidden, encoded)
        self.assertEqual("gpt-6-astra", value["options"]["agent_invocation"]["model_id"])

    def test_options_cannot_override_canonical_identity_on_restore(self):
        value = self.snapshot()
        value["options"].update({"client_route_id": "other-app", "task_id": "other-task", "_recovered_task": False})
        options = restore_request_options(value)
        self.assertNotIn("client_route_id", options)
        self.assertNotIn("task_id", options)
        self.assertNotIn("_recovered_task", options)

    def test_snapshot_is_detached_and_bounded(self):
        value = self.snapshot([{"name": "first.png"}])
        copied = snapshot_copy(value)
        value["options"]["attachments"][0]["name"] = "changed.png"
        self.assertEqual("first.png", copied["options"]["attachments"][0]["name"])
        with self.assertRaises(ValueError):
            self.snapshot([{"data_b64": "x" * (512 * 1024)}])
        with self.assertRaises(ValueError):
            self.snapshot([{}] * 13)

    def test_repeated_restarts_preserve_options_without_public_or_ledger_leakage(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "tasks.db"
            original = self.snapshot([{"name": "test.png", "data_b64": "PRIVATE_BYTES_MARKER"}])
            manager = self.manager(path)
            task = self.create(manager, original)
            original["options"]["agent_invocation"]["model_id"] = "modified-after-admission"
            for generation in range(2, 6):
                manager = self.manager(path)
                task = manager.get(task.task_id)
                self.assertEqual(("recovering", 1, generation), (task.status, task.attempt, task.execution_generation))
                restored = manager.recovery_request(task.task_id)
                self.assertEqual("gpt-6-astra", restored["options"]["agent_invocation"]["model_id"])
                self.assertEqual("PRIVATE_BYTES_MARKER", restored["options"]["attachments"][0]["data_b64"])
                public = json.dumps([task.public(include_prompt=True), manager.drain_recovered(), manager.run_events(task.task_id)])
                self.assertNotIn("request_snapshot", public)
                self.assertNotIn("PRIVATE_BYTES_MARKER", public)
                restored["options"].clear()
                self.assertTrue(manager.recovery_request(task.task_id)["options"])

    def test_snapshot_commit_failure_never_exposes_an_accepted_task(self):
        with tempfile.TemporaryDirectory() as temporary:
            manager = self.manager(Path(temporary) / "tasks.db")
            with patch.object(manager._store, "upsert", side_effect=OSError("disk full")):
                with self.assertRaises(OSError):
                    self.create(manager, self.snapshot())
            self.assertIsNone(manager.get("test-queued"))

    def test_restart_adapter_restores_descriptors_and_canonical_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            manager = self.manager(Path(temporary) / "tasks.db")
            self.create(manager, self.snapshot([{"name": "test.png", "transfer_id": "a" * 64}]))
            manager = self.manager(Path(temporary) / "tasks.db")
            with patch.object(bridge, "agent_task_manager", manager), \
                    patch.object(bridge, "_start_remote_agent_task") as start, \
                    patch("task_workspace.task_workspace", return_value=Path(temporary)):
                bridge._resume_recovered_remote_task(object(), manager.drain_recovered()[0])
            payload = start.call_args.args[2]
            self.assertEqual("app-a", payload["client_route_id"])
            self.assertEqual("chat", payload["conversation_id"])
            self.assertEqual("app-a:chat", payload["_backend_conversation_id"])
            self.assertEqual("turn-1", payload["turn_id"])
            self.assertEqual("a" * 64, payload["attachments"][0]["transfer_id"])
            self.assertEqual("gpt-6-astra", payload["agent_invocation"]["model_id"])

    def test_queued_codex_image_starts_once_with_restored_model_and_attachment(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "tasks.db"
            manager = self.manager(path)
            snapshot = self.snapshot([{"name": "test.png", "mime_type": "image/png",
                                       "data_b64": base64.b64encode(b"synthetic-image-bytes").decode()}])
            self.create(manager, snapshot)
            manager = self.manager(path)
            server = Mock()
            server.process = SimpleNamespace(pid=1)

            def start(task_id, prompt, cwd, **kwargs):
                manager.update(task_id, "completed", result="fixture complete")
                return SimpleNamespace(thread_id="new-provider-thread")

            server.start_task.side_effect = start
            sessions = Mock()
            sessions.get.return_value = None
            with patch.object(bridge, "agent_task_manager", manager), \
                    patch.object(bridge, "_codex_server", return_value=server), \
                    patch.object(bridge, "_enqueue_task_event"), \
                    patch.object(bridge, "get_client", return_value=None), \
                    patch("agent_gateway._find_codex_desktop_cli", return_value="codex"), \
                    patch("task_workspace.task_workspace", return_value=root), \
                    patch("agent_conversation_sessions.agent_conversation_sessions", return_value=sessions):
                bridge._resume_recovered_remote_task(SimpleNamespace(), manager.drain_recovered()[0])
                self.assertTrue(manager._work_pool.wait_idle(5))
            self.assertEqual("completed", manager.get("test-queued").status,
                             manager.get("test-queued").error)
            server.recover_task.assert_not_called()
            server.start_task.assert_called_once()
            invocation = server.start_task.call_args.kwargs
            self.assertEqual("gpt-6-astra", invocation["model"])
            self.assertEqual("app-a:chat", invocation["conversation_id"])
            self.assertEqual(1, len(invocation["image_paths"]))
            self.assertEqual(b"synthetic-image-bytes", Path(invocation["image_paths"][0]).read_bytes())
            self.assertEqual(2, manager.get("test-queued").execution_generation)
            with bridge.codex_task_callbacks_lock:
                bridge.codex_task_callbacks.pop("test-queued", None)

    def test_dispatched_codex_reconnects_with_original_model_and_provider_ids(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manager = self.manager(root / "tasks.db")
            task = self.create(manager, self.snapshot())
            with manager._lock:
                task.status = "running"
                task.started_at = task.created_at
                task.thread_id = "original-thread"
                task.turn_id = "original-provider-turn"
                manager._mark_dispatch_locked(task, 1)
            manager = self.manager(root / "tasks.db")
            server = Mock()
            server.process = SimpleNamespace(pid=1)

            def recover(**kwargs):
                manager.update(kwargs["task_id"], "completed", result="reconnected fixture")
                return SimpleNamespace(finished=True)

            server.recover_task.side_effect = recover
            with patch.object(bridge, "agent_task_manager", manager), \
                    patch.object(bridge, "_codex_server", return_value=server), \
                    patch.object(bridge, "_enqueue_task_event"), \
                    patch.object(bridge, "get_client", return_value=None), \
                    patch("agent_gateway._find_codex_desktop_cli", return_value="codex"), \
                    patch("task_workspace.task_workspace", return_value=root):
                bridge._resume_recovered_remote_task(SimpleNamespace(), manager.drain_recovered()[0])
                self.assertTrue(manager._work_pool.wait_idle(5))
            server.start_task.assert_not_called()
            server.recover_task.assert_called_once()
            invocation = server.recover_task.call_args.kwargs
            self.assertEqual("gpt-6-astra", invocation["model"])
            self.assertEqual("original-thread", invocation["thread_id"])
            self.assertEqual("original-provider-turn", invocation["turn_id"])
            with bridge.codex_task_callbacks_lock:
                bridge.codex_task_callbacks.pop("test-queued", None)

    def test_queued_generic_agent_is_readmitted_instead_of_querying_missing_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manager = self.manager(root / "tasks.db")
            snapshot = build_request_snapshot({}, model_id="", reasoning_effort="",
                                              policy=execution_policy_for("Compute 2 + 2").public())
            manager.create_external(
                "hermes", "hermes", "message-1", "Compute 2 + 2", lambda _: None,
                task_id="test-generic", client_route_id="app-a", conversation_id="app-a:chat",
                client_conversation_id="chat", client_turn_id="turn-1", request_snapshot=snapshot,
            )
            manager = self.manager(root / "tasks.db")
            with patch.object(bridge, "agent_task_manager", manager), \
                    patch.object(bridge, "get_client", return_value=None), \
                    patch.object(bridge, "_enqueue_task_event"), \
                    patch("agent_gateway.desktop_agent_provider") as provider, \
                    patch("task_workspace.task_workspace", return_value=root), \
                    patch.object(manager, "resume", return_value=manager.get("test-generic")) as resume:
                bridge._resume_recovered_remote_task(SimpleNamespace(), manager.drain_recovered()[0])
            resume.assert_called_once()
            self.assertEqual("test-generic", resume.call_args.args[0])
            self.assertTrue(callable(resume.call_args.args[1]))
            provider.assert_not_called()


if __name__ == "__main__":
    unittest.main()
