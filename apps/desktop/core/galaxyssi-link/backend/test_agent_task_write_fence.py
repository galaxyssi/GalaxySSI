"""Durable write fencing across independent stores and real processes."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from copy import deepcopy
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock

from agent_task_manager import AgentTaskManager
from agent_task_store import AgentTaskStore, AgentTaskWriteConflict
from agent_work_pool import AgentWorkPool


def record():
    return dict(task_id="task", client_route_id="app", client_conversation_id="conversation",
                client_turn_id="turn", source_message_id="message", conversation_id="backend",
                status="running", execution_generation=1, status_seq=1, result="original")


class TaskWriteFenceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / "tasks.db"
        self.store = AgentTaskStore(self.path)

    def seed(self):
        self.assertEqual(1, self.store.upsert(record()))
        return self.store.get("task")

    def manager(self):
        pool = AgentWorkPool(max_workers=1)
        self.addCleanup(pool.close)
        manager = AgentTaskManager(state_path=self.path, work_pool=pool)
        self.addCleanup(manager._control_work_pool.close)
        return manager

    def test_two_independent_connections_cannot_commit_the_same_revision(self):
        first = self.seed()
        second = deepcopy(first)
        first["result"], second["result"] = "first", "second"
        first["status_seq"] = second["status_seq"] = 2
        barrier = threading.Barrier(2)

        def write(value):
            store = AgentTaskStore(self.path)
            barrier.wait(5)
            try:
                store.upsert(value)
                return value["result"]
            except AgentTaskWriteConflict:
                return None

        with ThreadPoolExecutor(max_workers=2) as executor:
            outcomes = list(executor.map(write, (first, second)))
        winners = [value for value in outcomes if value is not None]
        self.assertEqual(1, len(winners))
        self.assertEqual(winners[0], self.store.get("task")["result"])
        self.assertEqual(2, self.store.get("task")["_storage_revision"])

    def test_real_process_writers_have_exactly_one_winner(self):
        snapshot = self.seed()
        script = """
import json, sys
from pathlib import Path
from agent_task_store import AgentTaskStore, AgentTaskWriteConflict
record = json.loads(sys.argv[2])
record['result'] = sys.argv[3]
record['status_seq'] += 1
try:
    revision = AgentTaskStore(Path(sys.argv[1])).upsert(record)
    print(json.dumps({'winner': sys.argv[3], 'revision': revision}))
except AgentTaskWriteConflict:
    print(json.dumps({'winner': None}))
"""

        def write(name):
            result = subprocess.run(
                [sys.executable, "-c", script, str(self.path), json.dumps(snapshot), name],
                cwd=Path(__file__).parent, text=True, capture_output=True, timeout=30,
            )
            self.assertEqual(0, result.returncode, result.stderr)
            return json.loads(result.stdout)

        with ThreadPoolExecutor(max_workers=2) as executor:
            outcomes = list(executor.map(write, ("node-a", "node-b")))
        winners = [value for value in outcomes if value["winner"]]
        self.assertEqual(1, len(winners))
        self.assertEqual(2, winners[0]["revision"])
        self.assertEqual(winners[0]["winner"], self.store.get("task")["result"])

    def test_identity_generation_and_sequence_regressions_are_rejected(self):
        self.seed()
        for field, value in (
            ("client_route_id", "other"), ("client_conversation_id", "other"),
            ("client_turn_id", "other"), ("source_message_id", "other"), ("status_seq", 0),
        ):
            with self.subTest(field=field):
                snapshot = self.store.get("task")
                snapshot[field] = value
                with self.assertRaises(AgentTaskWriteConflict):
                    self.store.upsert(snapshot)
        newer = self.store.get("task")
        newer["execution_generation"] = 2
        newer["status_seq"] = 0
        self.store.upsert(newer)
        stale = self.store.get("task")
        stale["execution_generation"] = 1
        with self.assertRaisesRegex(AgentTaskWriteConflict, "generation"):
            self.store.upsert(stale)

    def test_stale_large_result_cannot_replace_current_chunks(self):
        stale = self.seed()
        current = deepcopy(stale)
        current["result"] = "current result\n" * 4000
        self.store.upsert(current)
        stale["result"] = "stale result\n" * 8000
        with self.assertRaises(AgentTaskWriteConflict):
            self.store.upsert(stale)
        self.assertEqual(current["result"], self.store.get("task")["result"])

    def test_legacy_payload_without_revision_can_be_updated_once(self):
        self.seed()
        with closing(sqlite3.connect(self.path)) as connection, connection:
            connection.execute("UPDATE agent_tasks SET payload=json_remove(payload, '$._storage_revision')")
        legacy = self.store.get("task")
        self.assertNotIn("_storage_revision", legacy)
        self.assertEqual(1, self.store.upsert(legacy))
        with self.assertRaises(AgentTaskWriteConflict):
            self.store.upsert(legacy)

    def test_transaction_rollback_does_not_consume_the_revision(self):
        snapshot = self.seed()
        with closing(sqlite3.connect(self.path)) as connection, connection:
            connection.execute("BEGIN IMMEDIATE")
            self.assertEqual(2, self.store.upsert(snapshot, connection=connection))
            connection.rollback()
        self.assertEqual(1, self.store.get("task")["_storage_revision"])
        self.assertEqual(2, self.store.upsert(snapshot))

    def test_stale_manager_is_fenced_and_cannot_adopt_the_new_owner_revision(self):
        manager = self.manager()
        task = manager.create_external(
            "codex", "codex", "message", "Test", lambda _: None, task_id="task",
            client_route_id="app", client_conversation_id="conversation", client_turn_id="turn",
        )
        old_key = manager._execution_key(task, task.execution_generation)
        started = threading.Event()
        manager.schedule_external("task", started.set, lambda _: None)
        self.assertTrue(started.wait(3))
        newer = self.store.get("task")
        newer["current_step"] = "another owner"
        self.store.upsert(newer)
        event_count = manager._run_events.ledger.event_count()
        callback = Mock()
        with self.assertRaises(AgentTaskWriteConflict):
            manager.update("task", "completed", result="stale", on_event=callback, expected_execution=old_key)
        self.assertTrue(task.storage_fenced)
        self.assertTrue(manager._work_pool.wait_idle(3))
        self.assertFalse(manager.is_current_execution(old_key))
        self.assertIsNone(manager.update("task", "completed", result="stale again", expected_execution=old_key))
        self.assertEqual("another owner", self.store.get("task")["current_step"])
        self.assertEqual(event_count, manager._run_events.ledger.event_count())
        callback.assert_not_called()

    def test_storage_revision_is_not_exposed_in_public_events(self):
        manager = self.manager()
        snapshots = []
        task = manager.create_external("codex", "codex", "message", "Test", snapshots.append)
        self.assertEqual(1, task.storage_revision)
        self.assertEqual(1, manager._store.get(task.task_id)["_storage_revision"])
        for snapshot in [task.public(), *snapshots]:
            self.assertNotIn("_storage_revision", snapshot)
            self.assertNotIn("storage_revision", snapshot)
            self.assertNotIn("storage_fenced", snapshot)

    def test_runner_result_loses_ownership_without_failed_callback_or_retry(self):
        manager = self.manager()
        task = manager.create_external("codex", "codex", "message", "Test", None)
        manager._heartbeat_interval_seconds = 60
        event, result = Mock(), Mock()

        def runner(current):
            winner = self.store.get(current.task_id)
            winner["current_step"] = "new owner"
            self.store.upsert(winner)
            event.reset_mock()
            return "old result"

        manager._run(task, runner, event, result, task.execution_generation)
        self.assertTrue(task.storage_fenced)
        self.assertEqual("new owner", self.store.get(task.task_id)["current_step"])
        self.assertFalse(manager._finish(task, "failed", event, error="retry"))
        self.assertFalse(manager._set_status(task, "running", event))
        event.assert_not_called()
        result.assert_not_called()

    def test_stale_dispatch_does_not_start_runner(self):
        manager = self.manager()
        task = manager.create_external("codex", "codex", "message", "Test", None)
        self.store.upsert(self.store.get(task.task_id))
        runner, callback = Mock(), Mock()
        manager._run(task, runner, callback, callback, task.execution_generation)
        self.assertTrue(task.storage_fenced)
        runner.assert_not_called()
        callback.assert_not_called()

    def test_monitors_exit_on_first_durable_conflict(self):
        for monitor in ("heartbeat", "watchdog", "external_heartbeat", "external_watchdog"):
            with self.subTest(monitor=monitor):
                manager = self.manager()
                task = manager.create_external("codex", "codex", monitor, "Test", None)
                manager._set_status(task, "running", None)
                task.last_progress_at = 1
                task.execution_policy["max_replans"] = 1
                callback = Mock()
                recovery = Mock()
                manager._external_task_ids.add(task.task_id)
                manager._external_recovery_handlers[task.task_id] = (recovery, callback, callback)
                self.store.upsert(self.store.get(task.task_id))
                stop = Mock()
                stop.wait.side_effect = [False, True]
                if monitor == "heartbeat":
                    manager._heartbeat(task, callback, stop)
                elif monitor == "watchdog":
                    manager._progress_watchdog(task, callback, callback, stop)
                elif monitor == "external_heartbeat":
                    manager._external_heartbeat(task.task_id, callback, stop)
                else:
                    manager._external_progress_watchdog(task.task_id, stop)
                self.assertTrue(task.storage_fenced)
                callback.assert_not_called()
                recovery.assert_not_called()

    def test_live_old_manager_process_cannot_overwrite_recovered_execution(self):
        script = """
import json, sys
from pathlib import Path
from agent_task_manager import AgentTaskManager
from agent_task_store import AgentTaskWriteConflict
manager = AgentTaskManager(state_path=Path(sys.argv[1]))
task = manager.create_external('codex', 'codex', 'message', 'Test', lambda _: None,
    task_id='task', client_route_id='app', client_conversation_id='conversation', client_turn_id='turn')
key = manager._execution_key(task, task.execution_generation)
print('READY', flush=True)
input()
try:
    manager.update('task', 'completed', result='old-process-result', expected_execution=key)
    print(json.dumps({'blocked': False}), flush=True)
except AgentTaskWriteConflict:
    retry = manager.update('task', 'completed', result='retry-from-old-process', expected_execution=key)
    print(json.dumps({'blocked': task.storage_fenced, 'retry_rejected': retry is None,
                     'current': manager.is_current_execution(key)}), flush=True)
"""
        process = subprocess.Popen(
            [sys.executable, "-c", script, str(self.path)], cwd=Path(__file__).parent,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        try:
            deadline = time.monotonic() + 20
            while self.store.get("task") is None:
                if process.poll() is not None or time.monotonic() >= deadline:
                    self.fail("The old manager did not persist its initial task")
                time.sleep(0.01)
            recovered = self.manager()
            task = recovered.get("task")
            self.assertEqual(2, task.execution_generation)
            before = self.store.get("task")
            count = recovered._run_events.ledger.event_count()
            output, error = process.communicate("finish\n", timeout=20)
            self.assertEqual(0, process.returncode, error)
            lines = output.splitlines()
            self.assertEqual("READY", lines[0])
            self.assertEqual({"blocked": True, "retry_rejected": True, "current": False}, json.loads(lines[-1]))
            self.assertEqual(before, self.store.get("task"))
            self.assertEqual(count, recovered._run_events.ledger.event_count())
        finally:
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=5)
            for pipe in (process.stdin, process.stdout, process.stderr):
                if pipe is not None:
                    pipe.close()
