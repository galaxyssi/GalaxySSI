import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import main
from agent_task_manager import AgentTaskManager


class FakeTaskStream:
    def __init__(self, manager: AgentTaskManager, host: str = "testclient", token: str = "stream-test-token"):
        self.client = SimpleNamespace(host=host)
        self.headers = {"sec-websocket-protocol": f"signalasi-task-stream, {token}"}
        self.manager = manager
        self.accepted = False
        self.accepted_subprotocol = None
        self.close_code = None
        self.messages: list[dict] = []

    async def accept(self, subprotocol: str | None = None):
        self.accepted = True
        self.accepted_subprotocol = subprotocol

    async def close(self, code: int):
        self.close_code = code

    async def send_json(self, payload: dict):
        self.messages.append(payload)
        if payload.get("type") == "desktop_tasks_snapshot":
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
                patch.dict(os.environ, {"SIGNALASI_DESKTOP_TASK_STREAM_TOKEN": "stream-test-token"}),
            ):
                await main.desktop_task_stream(stream)

            self.assertTrue(stream.accepted)
            self.assertEqual(stream.accepted_subprotocol, "signalasi-task-stream")
            self.assertEqual(stream.messages[0], {"type": "desktop_tasks_snapshot", "tasks": []})
            self.assertEqual(stream.messages[1]["type"], "desktop_task_update")
            self.assertEqual(stream.messages[1]["task"]["task_id"], "desktop-live-task")
            self.assertEqual(stream.messages[1]["task"]["prompt"], "Stream this Desktop task")
            self.assertEqual(manager._listeners, {})

    async def test_stream_rejects_non_loopback_clients(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            manager = AgentTaskManager(state_path=Path(temp_dir) / "tasks.sqlite3")
            stream = FakeTaskStream(manager, host="192.0.2.10")

            with (
                patch.object(main, "agent_task_manager", manager),
                patch.dict(os.environ, {"SIGNALASI_DESKTOP_TASK_STREAM_TOKEN": "stream-test-token"}),
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
                patch.dict(os.environ, {"SIGNALASI_DESKTOP_TASK_STREAM_TOKEN": "stream-test-token"}),
            ):
                await main.desktop_task_stream(stream)

            self.assertFalse(stream.accepted)
            self.assertEqual(stream.close_code, 1008)


if __name__ == "__main__":
    unittest.main()
