"""One-time read-only legacy import, with real crash and corruption cases."""

import hashlib
import json
from pathlib import Path
from contextlib import closing
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from agent_run_kernel import AgentRunEventLedger
from agent_task_manager import AgentTask, AgentTaskManager
from agent_task_run_events import AgentTaskRunEventSink
from agent_task_run_migration import migrate_task_run_data
from agent_task_store import AgentTaskStore


class TaskRunMigrationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.old_path = self.root / "legacy" / "agent_tasks.sqlite3"
        self.old_events_path = self.old_path.with_name("agent-run-events-v1.sqlite3")
        self.old_store = AgentTaskStore(self.old_path)
        self.old_sink = AgentTaskRunEventSink(self.old_events_path)
        self.path = self.root / "new" / "agent-run-events-v1.sqlite3"
        self.store = AgentTaskStore(self.path)
        self.ledger = AgentRunEventLedger(self.path)

    def seed(self, **overrides):
        values = dict(task_id="legacy-task", agent_id="codex", contact_id="codex",
                      source_message_id="message-legacy", prompt="preserve original input",
                      conversation_id="conversation-legacy", client_route_id="phone-s26u",
                      run_id="task:legacy-task", goal_id="legacy-task", status="completed",
                      attachments=["private/attachment.png"], result="long verified output\n" * 15000)
        values.update(overrides)
        task = AgentTask(**values)
        self.old_store.upsert(task.record())
        self.old_sink.append_snapshot(task.record())
        return task

    def migrate(self):
        return migrate_task_run_data(self.ledger, legacy_tasks=self.old_path,
                                     legacy_events=self.old_events_path)

    def assert_empty_target(self):
        self.assertEqual(0, self.store.count())
        self.assertEqual(0, self.ledger.event_count())

    def test_migration_preserves_complete_input_result_events_and_source_files(self):
        task = self.seed()
        before = [hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in (self.old_path, self.old_events_path)]
        self.assertEqual({"tasks": 1, "events": 1, "migrated": True}, self.migrate())
        restored = self.store.get(task.task_id)
        self.assertEqual(task.result, restored["result"])
        self.assertEqual(task.prompt, restored["prompt"])
        self.assertEqual(task.attachments, restored["attachments"])
        self.assertEqual(self.old_sink.events(task.run_id),
                         [event.public() for event in self.ledger.events(task.run_id)])
        self.assertEqual(before, [hashlib.sha256(path.read_bytes()).hexdigest()
                                 for path in (self.old_path, self.old_events_path)])

    def test_migration_is_once_only_and_deleted_tasks_are_not_resurrected(self):
        task = self.seed()
        self.migrate()
        with closing(sqlite3.connect(self.path)) as connection, connection:
            connection.execute("DELETE FROM agent_tasks WHERE task_id = ?", (task.task_id,))
        self.assertEqual({"tasks": 0, "events": 0, "migrated": False}, self.migrate())
        self.assertIsNone(self.store.get(task.task_id))
        self.assertEqual(1, self.ledger.event_count())

    def test_legacy_databases_are_attached_read_only(self):
        self.seed()
        from agent_task_run_migration import _copy_tasks

        def verify_readonly(connection):
            with self.assertRaisesRegex(sqlite3.OperationalError, "readonly"):
                connection.execute("DELETE FROM legacy_tasks.agent_tasks")
            return _copy_tasks(connection)

        with patch("agent_task_run_migration._copy_tasks", side_effect=verify_readonly):
            self.migrate()
        self.assertEqual(1, self.old_store.count())

    def test_manager_migrates_completed_and_recoverable_tasks(self):
        completed = self.seed()
        running = self.seed(task_id="running-task", run_id="task:running-task",
                            goal_id="running-task", status="running", result="")
        manager = AgentTaskManager(state_path=self.path, legacy_state_path=self.old_path)
        self.assertEqual(completed.result, manager.get(completed.task_id).result)
        self.assertEqual("recovering", manager.get(running.task_id).status)
        self.assertEqual("RUN_RECOVERED", manager.run_events(running.task_id)[-1]["type"])
        self.assertEqual(running.prompt, manager.get(running.task_id).prompt)

    def test_explicit_old_task_path_imports_its_sibling_events_without_moving_tasks(self):
        task = self.seed()
        manager = AgentTaskManager(state_path=self.old_path)
        self.assertEqual(self.old_path, manager._store.path)
        self.assertEqual(self.old_path, manager._run_events.ledger.path)
        self.assertEqual(1, len(manager.run_events(task.task_id)))
        self.assertEqual(task.result, manager.get(task.task_id).result)

    def test_missing_legacy_files_do_not_create_them(self):
        missing = self.root / "absent" / "tasks.sqlite3"
        outcome = migrate_task_run_data(self.ledger, legacy_tasks=missing,
                                         legacy_events=missing.with_name("events.sqlite3"))
        self.assertFalse(outcome["migrated"])
        self.assertFalse(missing.parent.exists())

    def test_result_chunk_missing_corrupt_or_reordered_rolls_back_everything(self):
        task = self.seed()
        for corruption in ("missing", "hash", "order", "metadata"):
            with self.subTest(corruption=corruption):
                self.old_store.upsert(task.record())
                with closing(sqlite3.connect(self.old_path)) as connection, connection:
                    if corruption == "missing":
                        connection.execute("DELETE FROM agent_task_output_chunks WHERE chunk_index = 1")
                    elif corruption == "hash":
                        connection.execute("UPDATE agent_task_output_chunks SET chunk_sha256 = 'bad' WHERE chunk_index = 1")
                    elif corruption == "order":
                        connection.execute("UPDATE agent_task_output_chunks SET chunk_index = 9000 WHERE chunk_index = 1")
                    else:
                        connection.execute("UPDATE agent_tasks SET payload = json_set(payload, '$.result_sha256', 'bad')")
                with self.assertRaisesRegex(ValueError, "result"):
                    self.migrate()
                self.assert_empty_target()
        self.old_store.upsert(task.record())
        self.assertTrue(self.migrate()["migrated"])

    def test_invalid_payload_rolls_back_all_tasks(self):
        self.seed()
        with closing(sqlite3.connect(self.old_path)) as connection, connection:
            connection.execute("UPDATE agent_tasks SET payload = 'invalid'")
        with self.assertRaisesRegex(ValueError, "invalid JSON"):
            self.migrate()
        self.assert_empty_target()

    def test_task_identity_conflict_preserves_target(self):
        task = self.seed()
        newer = {**task.record(), "client_route_id": "phone-s20u", "result": "newer"}
        self.store.upsert(newer)
        with self.assertRaisesRegex(ValueError, "task identity"):
            self.migrate()
        self.assertEqual("newer", self.store.get(task.task_id)["result"])
        self.assertEqual(0, self.ledger.event_count())

    def test_event_conflict_rolls_back_tasks_copied_before_events(self):
        task = self.seed(status="running", result="")
        sink = AgentTaskRunEventSink(self.path, ledger=self.ledger)
        sink.append_snapshot({**task.record(), "current_step": "different"})
        with self.assertRaisesRegex(ValueError, "event conflicts"):
            self.migrate()
        self.assertEqual(0, self.store.count())
        self.assertEqual(1, self.ledger.event_count())

    def test_legacy_checkpoint_survives_import(self):
        self.seed()
        self.old_sink.ledger.append({
            "event_id": "checkpoint-event", "idempotency_key": "checkpoint-key",
            "client_route_id": "phone-s26u", "conversation_id": "runtime-conversation",
            "goal_id": "runtime-goal", "task_id": "runtime-task", "run_id": "runtime-run",
            "turn_id": "turn", "action_id": "action", "type": "RUN_STARTED",
            "payload": {"projection_checkpoint": {"kind": "test-runtime", "data": {"prompt": "resume me"}}},
        })
        self.migrate()
        with closing(sqlite3.connect(self.path)) as connection, connection:
            payload = connection.execute(
                "SELECT data_json FROM agent_run_checkpoints WHERE run_id = 'runtime-run'"
            ).fetchone()[0]
        self.assertEqual({"prompt": "resume me"}, json.loads(payload))

    def test_process_exit_mid_migration_is_retryable_without_partial_import(self):
        task = self.seed()
        code = """
import os, sys
from pathlib import Path
from unittest.mock import patch
from agent_run_kernel import AgentRunEventLedger
from agent_task_run_migration import migrate_task_run_data
ledger = AgentRunEventLedger(Path(sys.argv[1]))
with patch('agent_task_run_migration.copy_legacy_run_events', side_effect=lambda _: os._exit(79)):
    migrate_task_run_data(ledger, legacy_tasks=Path(sys.argv[2]), legacy_events=Path(sys.argv[3]))
"""
        result = subprocess.run([sys.executable, "-c", code, str(self.path), str(self.old_path),
                                 str(self.old_events_path)], cwd=Path(__file__).parent,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(79, result.returncode, result.stderr)
        self.assert_empty_target()
        self.assertTrue(self.migrate()["migrated"])
        self.assertEqual(task.result, self.store.get(task.task_id)["result"])
        self.assertEqual(1, self.ledger.event_count())


if __name__ == "__main__":
    unittest.main()
