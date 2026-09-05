"""Crash boundaries for the shared high-level task and Run transaction."""

from pathlib import Path
from contextlib import closing
from concurrent.futures import ThreadPoolExecutor
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from agent_run_kernel import AgentRunEventLedger, AgentRunIdentityConflict
from agent_run_storage import RUN_KERNEL_DATABASE_NAME, desktop_state_root, run_kernel_database_path
from agent_task_manager import AgentTask, AgentTaskManager
from agent_task_run_events import AgentTaskRunEventSink


class AtomicTaskRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.path = self.root / RUN_KERNEL_DATABASE_NAME
        self.manager = AgentTaskManager(state_path=self.path)

    def task(self, **overrides):
        values = dict(task_id="task-atomic", agent_id="codex", contact_id="codex",
                      source_message_id="message-1", prompt="Inspect the project",
                      conversation_id="conversation-1", client_route_id="phone-s26u")
        values.update(overrides)
        return self.manager.create_external(**values, on_event=lambda _: None)

    def test_task_and_events_share_storage(self):
        task = self.task()
        self.assertEqual(self.manager._store.path, self.manager._run_events.ledger.path)
        with closing(sqlite3.connect(self.path)) as connection, connection:
            self.assertEqual(1, connection.execute("SELECT count(*) FROM agent_tasks").fetchone()[0])
            self.assertEqual(1, connection.execute("SELECT count(*) FROM agent_run_events").fetchone()[0])
        self.assertEqual(task.prompt, self.manager._store.get(task.task_id)["prompt"])

    def test_new_task_failure_leaves_no_phantom_or_event(self):
        with patch.object(self.manager._store, "upsert", side_effect=OSError("disk full")):
            with self.assertRaisesRegex(OSError, "disk full"):
                self.task()
        self.assertIsNone(self.manager.get("task-atomic"))
        self.assertEqual(0, self.manager._run_events.ledger.event_count())

    def test_existing_task_failure_rolls_back_event_row_and_live_reference(self):
        task = self.task()
        original = self.manager._store.get(task.task_id)
        original_upsert = self.manager._store.upsert

        def fail_after_row(record, **kwargs):
            original_upsert(record, **kwargs)
            raise OSError("write interrupted")

        with patch.object(self.manager._store, "upsert", side_effect=fail_after_row):
            with self.assertRaisesRegex(OSError, "write interrupted"):
                self.manager.update(task.task_id, "completed", result="large output " * 5000)
        self.assertEqual(original, self.manager._store.get(task.task_id))
        self.assertEqual("accepted", task.status)
        self.assertEqual("", task.result)
        self.assertEqual(1, self.manager._run_events.ledger.event_count())
        with closing(sqlite3.connect(self.path)) as connection, connection:
            self.assertEqual(0, connection.execute("SELECT count(*) FROM agent_task_output_chunks").fetchone()[0])
        self.manager.update(task.task_id, "completed", result="retried")
        self.assertEqual("retried", self.manager.get(task.task_id).result)

    def test_event_identity_failure_does_not_overwrite_input(self):
        task = self.task()
        task.client_route_id = "another-phone"
        with self.assertRaises(AgentRunIdentityConflict):
            self.manager._save_locked(task)
        self.assertEqual("phone-s26u", task.client_route_id)
        self.assertEqual(1, self.manager._run_events.ledger.event_count())

    def test_shared_connection_requires_transaction_and_same_database(self):
        record = self.task().record()
        with closing(sqlite3.connect(self.path)) as connection, connection:
            with self.assertRaisesRegex(ValueError, "active"):
                self.manager._store.upsert(record, connection=connection)
            with self.assertRaisesRegex(ValueError, "active"):
                self.manager._run_events.append_snapshot(record, connection=connection)
        other = AgentRunEventLedger(self.root / "other.sqlite3")
        with other.transaction() as connection:
            with self.assertRaisesRegex(ValueError, "another database"):
                self.manager._store.upsert(record, connection=connection)
            with self.assertRaisesRegex(ValueError, "another database"):
                self.manager._run_events.append_snapshot(record, connection=connection)

    def test_cross_database_sink_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "share one database"):
            AgentTaskManager(state_path=self.path,
                             run_event_sink=AgentTaskRunEventSink(self.root / "other.sqlite3"))

    def test_commit_is_invisible_to_other_readers_until_transaction_finishes(self):
        task = AgentTask("uncommitted", "codex", "codex", "msg", "input")
        with self.manager._run_events.ledger.transaction() as connection:
            self.manager._run_events.append_snapshot(task.record(), connection=connection)
            self.manager._store.upsert(task.record(), connection=connection)
            self.assertIsNone(self.manager._store.get(task.task_id))
            self.assertEqual(0, self.manager._run_events.ledger.event_count())
        self.assertIsNotNone(self.manager._store.get(task.task_id))
        self.assertEqual(1, self.manager._run_events.ledger.event_count())

    def test_real_process_exit_before_and_after_commit(self):
        for boundary in ("after_event", "after_task", "committed"):
            with self.subTest(boundary=boundary):
                path = self.root / boundary / RUN_KERNEL_DATABASE_NAME
                code = """
import os, sys
from pathlib import Path
from agent_task_manager import AgentTask, AgentTaskManager
manager = AgentTaskManager(state_path=Path(sys.argv[1]))
task = AgentTask('crash-task', 'codex', 'codex', 'msg', 'original input',
                 status='completed', result='verified result ' * 10000)
with manager._run_events.ledger.transaction() as connection:
    manager._run_events.append_snapshot(task.record(), connection=connection)
    if sys.argv[2] == 'after_event': os._exit(71)
    manager._store.upsert(task.record(), connection=connection)
    if sys.argv[2] == 'after_task': os._exit(72)
os._exit(73)
"""
                result = subprocess.run([sys.executable, "-c", code, str(path), boundary],
                                        cwd=Path(__file__).parent, capture_output=True, text=True, timeout=30)
                self.assertEqual({"after_event": 71, "after_task": 72, "committed": 73}[boundary],
                                 result.returncode, result.stderr)
                restored = AgentTaskManager(state_path=path)
                record = restored._store.get("crash-task")
                self.assertEqual(int(boundary == "committed"), restored._run_events.ledger.event_count())
                if boundary == "committed":
                    self.assertEqual("original input", record["prompt"])
                    self.assertEqual("verified result " * 10000, record["result"])
                    self.assertEqual("completed", restored.get("crash-task").status)
                else:
                    self.assertIsNone(record)

    def test_gateway_runtime_and_task_default_resolve_same_state_root(self):
        from agent_gateway import _agent_runtime_server_state_path
        from desktop_agent_runtime_server import DesktopAgentRuntimeStore
        with patch.dict(os.environ, {"GALAXYSSI_STATE_DIR": str(self.root / "configured")}):
            path = run_kernel_database_path()
            self.assertEqual(desktop_state_root(), _agent_runtime_server_state_path().parent)
            runtime = DesktopAgentRuntimeStore(_agent_runtime_server_state_path())
            manager = AgentTaskManager(state_path=path, legacy_state_path=self.root / "absent.sqlite3")
            self.assertEqual(path, manager._run_events.ledger.path)
            self.assertEqual(path, runtime._event_ledger.path)

    def test_task_and_runtime_interleaved_writes_recover_without_identity_collision(self):
        from desktop_agent_adapters import AgentAdapterRequest
        from desktop_agent_runtime_server import DesktopAgentRuntimeStore
        task = self.task()
        runtime_path = self.root / "runtime.json"
        runtime = DesktopAgentRuntimeStore(runtime_path)
        request = AgentAdapterRequest(
            agent_id="codex", prompt=task.prompt, run_id=task.task_id,
            idempotency_key=task.task_id, conversation_id="desktop-scoped-conversation",
            checkpoint={"task_id": task.task_id, "client_route_id": task.client_route_id,
                        "turn_id": "turn-1"},
        ).normalized()
        runtime.claim(request)
        self.manager.update(task.task_id, "running")

        def write_runtime():
            for index in range(20):
                runtime._event_ledger.append({
                    **runtime.kernel_events(task.task_id)[0], "event_id": f"progress-{index}",
                    "idempotency_key": f"progress-{index}", "sequence": 0,
                    "type": "TOOL_PROGRESS", "payload": {"progress": index},
                })

        def write_task():
            for index in range(20):
                self.manager.add_event(task.task_id, "tool", f"Read {index}",
                                       event_id=f"read-{index}", status="completed")

        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(write_runtime), pool.submit(write_task)]
            for future in futures:
                future.result(timeout=30)
        self.assertEqual(22, len(self.manager.run_events(task.task_id)))
        self.assertEqual(21, len(runtime.kernel_events(task.task_id)))
        self.assertNotEqual(task.run_id, task.task_id)
        restored_task = AgentTaskManager(state_path=self.path).get(task.task_id)
        restored_runtime = DesktopAgentRuntimeStore(runtime_path).status(task.task_id)
        self.assertEqual(task.prompt, restored_task.prompt)
        self.assertEqual("recovering", restored_task.status)
        self.assertEqual("interrupted", restored_runtime["state"])


if __name__ == "__main__":
    unittest.main()
