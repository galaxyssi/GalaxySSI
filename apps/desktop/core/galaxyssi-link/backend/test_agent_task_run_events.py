import tempfile
import unittest
from pathlib import Path

from agent_run_kernel import AgentRunIdentityConflict
from agent_task_run_events import AgentTaskRunEventSink
from agent_task_manager import AgentTaskManager, MAX_TASK_EVENTS


class AgentTaskRunEventIntegrationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.state_path = self.root / "agent-tasks.sqlite3"

    def tearDown(self):
        self.temporary.cleanup()

    def manager(self) -> AgentTaskManager:
        return AgentTaskManager(state_path=self.state_path)

    def create_task(self, manager: AgentTaskManager, **overrides):
        values = {
            "agent_id": "codex",
            "contact_id": "codex-agent",
            "source_message_id": "message-1",
            "prompt": "Inspect the repository",
            "on_event": lambda _snapshot: None,
            "task_id": "task-1",
            "goal_id": "goal-1",
            "run_id": "task-run-1",
            "conversation_id": "desktop-conversation-1",
            "client_conversation_id": "conversation-1",
            "client_route_id": "phone-s26u",
            "client_turn_id": "turn-1",
        }
        values.update(overrides)
        return manager.create_external(**values)

    def test_snapshot_replay_keeps_original_type_before_and_after_later_progress(self):
        sink = AgentTaskRunEventSink(self.root / "snapshot-replay.sqlite3")
        snapshot = {"task_id": "task-1", "run_id": "run-1", "agent_id": "codex",
                    "status": "running", "status_seq": 1, "client_route_id": "phone-s26u"}
        original, created = sink.append_snapshot(snapshot)
        replay, replay_created = sink.append_snapshot(snapshot)
        self.assertTrue(created)
        self.assertFalse(replay_created)
        self.assertEqual(original, replay)
        sink.append_snapshot({**snapshot, "status_seq": 2, "current_step": "Read file"})
        replay, replay_created = sink.append_snapshot(snapshot)
        self.assertFalse(replay_created)
        self.assertEqual(original, replay)
        self.assertEqual(2, len(sink.events("run-1")))
        with self.assertRaises(AgentRunIdentityConflict):
            sink.append_snapshot({**snapshot, "client_route_id": "phone-s20u"})

    def test_high_level_task_lifecycle_is_written_to_portable_ledger(self):
        manager = self.manager()
        task = self.create_task(manager)
        manager.update(task.task_id, "running", current_step="Inspecting files")
        manager.add_event(
            task.task_id,
            "tool",
            "Reading repository",
            event_id="tool-read-1",
            status="running",
        )
        manager.add_event(
            task.task_id,
            "tool",
            "Repository read",
            event_id="tool-read-1",
            status="completed",
        )
        manager.update(task.task_id, "completed", result="done")

        events = manager.run_events(task.task_id)

        self.assertEqual(
            [
                "RUN_CREATED",
                "RUN_STARTED",
                "TOOL_STARTED",
                "TOOL_COMPLETED",
                "RUN_COMPLETED",
            ],
            [event["type"] for event in events],
        )
        self.assertEqual(list(range(1, 6)), [event["sequence"] for event in events])
        self.assertTrue(all(event["client_route_id"] == "phone-s26u" for event in events))
        self.assertTrue(all(event["conversation_id"] == "conversation-1" for event in events))
        self.assertTrue(all(event["goal_id"] == "goal-1" for event in events))
        self.assertTrue(all(event["turn_id"] == "turn-1" for event in events))
        self.assertEqual("completed", manager.run_snapshot(task.task_id)["state"])

    def test_restart_replays_history_and_records_recovery(self):
        manager = self.manager()
        task = self.create_task(manager)
        manager.update(task.task_id, "running", current_step="Working")

        restored = self.manager()
        recovered = restored.get(task.task_id)
        events = restored.run_events(task.task_id)

        self.assertIsNotNone(recovered)
        self.assertEqual("recovering", recovered.status)
        self.assertEqual(
            ["RUN_CREATED", "RUN_STARTED", "RUN_RECOVERED"],
            [event["type"] for event in events],
        )
        self.assertEqual("running", restored.run_snapshot(task.task_id)["state"])

    def test_full_ledger_survives_ui_projection_truncation_and_pages(self):
        manager = self.manager()
        task = self.create_task(manager)
        manager.update(task.task_id, "running", current_step="Working")
        event_total = MAX_TASK_EVENTS + 12
        for index in range(event_total):
            manager.add_event(
                task.task_id,
                "tool",
                f"Tool event {index}",
                event_id=f"tool-{index}",
                status="completed",
            )

        self.assertEqual(MAX_TASK_EVENTS, len(manager.get(task.task_id).events))
        self.assertEqual(event_total + 2, len(manager.run_events(task.task_id)))
        tail = manager.run_events(
            task.task_id,
            after_sequence=event_total,
            limit=10,
        )
        self.assertEqual([event_total + 1, event_total + 2], [row["sequence"] for row in tail])

        reopened = self.manager()
        replayed = reopened.run_events(task.task_id)
        self.assertEqual(event_total + 3, len(replayed))
        self.assertEqual("RUN_RECOVERED", replayed[-1]["type"])

    def test_reusing_run_id_across_task_roots_is_rejected_without_phantom_task(self):
        manager = self.manager()
        self.create_task(manager)

        with self.assertRaises(AgentRunIdentityConflict):
            self.create_task(
                manager,
                task_id="task-2",
                goal_id="goal-2",
                client_route_id="phone-s20u",
                run_id="task-run-1",
            )

        self.assertIsNone(manager.get("task-2"))
        self.assertEqual(1, len(manager.run_events("task-1")))


if __name__ == "__main__":
    unittest.main()
