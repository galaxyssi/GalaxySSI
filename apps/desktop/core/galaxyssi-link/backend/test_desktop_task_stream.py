import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import main
from agent_task_manager import AgentTaskManager
from evolution_v2.legacy import EvolutionTask


class FakeEvolutionManager:
    def __init__(self, task: EvolutionTask | None = None):
        self.task = task
        self.store = self
        self.audit = self
        self._listeners: dict[str, object] = {}

    def list(self, limit=100):
        return [self.task] if self.task is not None else []

    def get(self, task_id):
        return self.task if self.task is not None and self.task.task_id == task_id else None

    def require(self, task_id):
        task = self.get(task_id)
        if task is None:
            raise KeyError(task_id)
        return task

    def task_metadata(self, _task_id):
        return {"origin": "research"}

    def list_for_tasks(self, _task_ids, limit_per_task=100):
        return {}

    def list_for_task(self, _task_id, limit=100):
        return []

    def subscribe(self, listener):
        subscription_id = f"evolution-{len(self._listeners) + 1}"
        self._listeners[subscription_id] = listener
        return subscription_id

    def unsubscribe(self, subscription_id):
        return self._listeners.pop(subscription_id, None) is not None

    def emit(self, event):
        for listener in list(self._listeners.values()):
            listener(event)


class FakeTaskStream:
    def __init__(
        self,
        manager: AgentTaskManager,
        host: str = "testclient",
        token: str = "stream-test-token",
        on_snapshot=None,
    ):
        self.client = SimpleNamespace(host=host)
        self.headers = {"sec-websocket-protocol": f"galaxyssi-task-stream, {token}"}
        self.manager = manager
        self.accepted = False
        self.accepted_subprotocol = None
        self.close_code = None
        self.messages: list[dict] = []
        self.on_snapshot = on_snapshot

    async def accept(self, subprotocol: str | None = None):
        self.accepted = True
        self.accepted_subprotocol = subprotocol

    async def close(self, code: int):
        self.close_code = code

    async def send_json(self, payload: dict):
        self.messages.append(payload)
        if payload.get("type") == "desktop_tasks_snapshot":
            if self.on_snapshot is not None:
                self.on_snapshot()
            else:
                self.manager.create_external(
                    agent_id="desktop",
                    contact_id="desktop",
                    source_message_id="desktop:live-task",
                    prompt="Stream this Desktop task",
                    on_event=lambda _snapshot: None,
                    task_id="desktop-live-task",
                    conversation_id="desktop-conversation",
                )
        elif payload.get("type") == "desktop_task_update":
            raise main.WebSocketDisconnect()


class DesktopTaskStreamTests(unittest.IsolatedAsyncioTestCase):
    async def test_stream_sends_large_task_preview_instead_of_complete_output(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            manager = AgentTaskManager(state_path=Path(temp_dir) / "tasks.sqlite3")
            task = manager.create_external(
                agent_id="codex",
                contact_id="codex",
                source_message_id="desktop:large-output",
                prompt="Produce a long report",
                on_event=lambda _snapshot: None,
                task_id="desktop-large-output",
                conversation_id="desktop-conversation",
            )
            complete_output = "Long report paragraph.\n\n".join(
                str(index) for index in range(4_000)
            )
            manager.update(task.task_id, "completed", result=complete_output)
            stream = FakeTaskStream(manager)

            with (
                patch.object(main, "agent_task_manager", manager),
                patch.object(main, "_desktop_evolution_manager", return_value=FakeEvolutionManager()),
                patch.dict(os.environ, {"GALAXYSSI_DESKTOP_TASK_STREAM_TOKEN": "stream-test-token"}),
            ):
                await main.desktop_task_stream(stream)
                page = main.api_get_desktop_task_output(
                    task.task_id,
                    SimpleNamespace(client=SimpleNamespace(host="testclient")),
                    offset=0,
                    limit=2,
                )

            preview = stream.messages[0]["tasks"][0]
            self.assertTrue(preview["result_chunked"])
            self.assertLess(len(preview["result"]), len(complete_output))
            self.assertEqual(len(complete_output), preview["result_length"])
            self.assertEqual(2, len(page["chunks"]))
            self.assertFalse(page["done"])

    async def test_stream_filters_mobile_tasks_and_sends_live_desktop_updates(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            manager = AgentTaskManager(state_path=Path(temp_dir) / "tasks.sqlite3")
            manager.create_external(
                agent_id="codex",
                contact_id="codex",
                source_message_id="mobile:private-task",
                prompt="Do not expose this mobile prompt",
                on_event=lambda _snapshot: None,
                task_id="mobile-private-task",
            )
            stream = FakeTaskStream(manager)

            with (
                patch.object(main, "agent_task_manager", manager),
                patch.object(main, "_desktop_evolution_manager", return_value=FakeEvolutionManager()),
                patch.dict(os.environ, {"GALAXYSSI_DESKTOP_TASK_STREAM_TOKEN": "stream-test-token"}),
            ):
                await main.desktop_task_stream(stream)

            self.assertTrue(stream.accepted)
            self.assertEqual(stream.accepted_subprotocol, "galaxyssi-task-stream")
            self.assertEqual("desktop_tasks_snapshot", stream.messages[0]["type"])
            self.assertEqual([], stream.messages[0]["tasks"])
            self.assertIsInstance(stream.messages[0].get("peer_messages"), list)
            self.assertEqual(stream.messages[1]["type"], "desktop_task_update")
            self.assertEqual(stream.messages[1]["task"]["task_id"], "desktop-live-task")
            self.assertEqual(stream.messages[1]["task"]["prompt"], "Stream this Desktop task")
            self.assertEqual(manager._listeners, {})

    async def test_stream_sends_live_self_evolution_updates_in_the_main_timeline(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            manager = AgentTaskManager(state_path=Path(temp_dir) / "tasks.sqlite3")
            evolution_task = EvolutionTask(
                task_id="evolve-stream",
                problem="Show automatic evolution in the main output",
                reproduction_steps=[],
                scope=["apps/desktop"],
                acceptance=["Stream each action"],
                risk_level="medium",
                max_attempts=3,
                status="proposed",
                created_at_millis=1_000,
                updated_at_millis=1_000,
            )
            evolution_manager = FakeEvolutionManager(evolution_task)

            def emit_live_update():
                evolution_task.status = "running"
                evolution_task.updated_at_millis = 2_000
                evolution_manager.emit({
                    "type": "evolution_task_event",
                    "event": "agent_started",
                    "task": evolution_task.public(),
                    "metadata": {"attempt": 1},
                    "timestamp_millis": 2_000,
                })

            stream = FakeTaskStream(manager, on_snapshot=emit_live_update)
            with (
                patch.object(main, "agent_task_manager", manager),
                patch.object(main, "_desktop_evolution_manager", return_value=evolution_manager),
                patch.dict(os.environ, {"GALAXYSSI_DESKTOP_TASK_STREAM_TOKEN": "stream-test-token"}),
            ):
                await main.desktop_task_stream(stream)

            self.assertEqual("desktop_tasks_snapshot", stream.messages[0]["type"])
            self.assertEqual([], stream.messages[0]["tasks"])
            self.assertIsInstance(stream.messages[0].get("peer_messages"), list)
            update = stream.messages[1]
            self.assertEqual("desktop_task_update", update["type"])
            self.assertEqual("self_evolution", update["task"]["task_kind"])
            self.assertEqual("evolve-stream", update["task"]["task_id"])
            self.assertEqual("running", update["task"]["status"])
            self.assertEqual({}, evolution_manager._listeners)

    async def test_stream_rejects_non_loopback_clients(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            manager = AgentTaskManager(state_path=Path(temp_dir) / "tasks.sqlite3")
            stream = FakeTaskStream(manager, host="192.0.2.10")

            with (
                patch.object(main, "agent_task_manager", manager),
                patch.dict(os.environ, {"GALAXYSSI_DESKTOP_TASK_STREAM_TOKEN": "stream-test-token"}),
            ):
                await main.desktop_task_stream(stream)

            self.assertFalse(stream.accepted)
            self.assertEqual(stream.close_code, 1008)
            self.assertEqual(stream.messages, [])

    async def test_stream_rejects_a_loopback_client_without_the_secret(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            manager = AgentTaskManager(state_path=Path(temp_dir) / "tasks.sqlite3")
            stream = FakeTaskStream(manager, token="wrong-token")

            with (
                patch.object(main, "agent_task_manager", manager),
                patch.dict(os.environ, {"GALAXYSSI_DESKTOP_TASK_STREAM_TOKEN": "stream-test-token"}),
            ):
                await main.desktop_task_stream(stream)

            self.assertFalse(stream.accepted)
            self.assertEqual(stream.close_code, 1008)


if __name__ == "__main__":
    unittest.main()
