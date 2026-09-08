"""High-level lifecycle integration for fair, bounded execution admission."""
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

from agent_task_manager import AgentTaskManager
from agent_work_pool import AgentWorkPool


class TaskSchedulingTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / "tasks.db"
        self.pool = AgentWorkPool(max_workers=1, max_pending=10)
        self.addCleanup(self.pool.close)
        self.manager = AgentTaskManager(state_path=self.path, work_pool=self.pool)
        self.addCleanup(self.manager._control_work_pool.close)

    def external(self, name):
        return self.manager.create_external(
            "codex", "codex", f"message-{name}", "Test", lambda _: None,
            task_id=name, client_route_id="phone", client_conversation_id="session",
            client_turn_id=f"turn-{name}",
        )

    def test_async_starter_retains_worker_until_terminal_callback(self):
        task = self.external("async")
        started = threading.Event()
        self.addCleanup(self.manager.cancel, task.task_id)
        self.manager.schedule_external(task.task_id, started.set, lambda _: None)
        self.assertTrue(started.wait(2))
        later = Mock(return_value="later")
        self.create("later", later)
        self.assertEqual((1, 1), (self.pool.snapshot()["active"], self.pool.snapshot()["pending"]))
        later.assert_not_called()
        self.manager.update(task.task_id, "completed", result="async reply")
        self.assertTrue(self.pool.wait_idle(3))
        later.assert_called_once()

    def test_async_queue_cancel_never_calls_provider(self):
        _, release = self.occupy()
        task = self.external("async-queued")
        starter = Mock()
        self.manager.schedule_external(task.task_id, starter, lambda _: None)
        self.manager.cancel(task.task_id)
        release.set()
        self.assertTrue(self.pool.wait_idle(3))
        starter.assert_not_called()

    def test_control_instruction_can_run_while_regular_slots_are_full(self):
        _, release = self.occupy()
        task = self.external("control")
        started = threading.Event()
        self.addCleanup(self.manager.cancel, task.task_id)
        self.manager.schedule_external(task.task_id, started.set, lambda _: None, interactive=True)
        self.assertTrue(started.wait(2))
        self.assertEqual(1, self.manager.scheduling_status()["control"]["active"])
        self.manager.update(task.task_id, "completed")
        self.assertTrue(self.manager._control_work_pool.wait_idle(3))
        release.set()

    def test_async_start_failure_is_persisted_and_releases_slot(self):
        task = self.external("async-failed")
        self.manager.schedule_external(task.task_id, Mock(side_effect=ValueError("cannot start")), lambda _: None)
        self.assertTrue(self.pool.wait_idle(3))
        self.assertEqual(("failed", "cannot start"), (task.status, task.error))

    def test_pausing_async_execution_releases_slot_without_completing_it(self):
        task = self.external("async-paused")
        started = threading.Event()
        self.manager.schedule_external(task.task_id, started.set, lambda _: None)
        self.assertTrue(started.wait(2))
        self.manager.pause(task.task_id)
        self.assertTrue(self.pool.wait_idle(3))
        self.assertEqual("paused", task.status)

    def create(self, task, runner=lambda _: "done", app="phone", conversation="session"):
        return self.manager.create(
            "codex", "codex", f"message-{task}", "Test", runner, lambda _: None,
            task_id=task, client_route_id=app, client_conversation_id=conversation,
            client_turn_id=f"turn-{task}", conversation_id=f"{app}:{conversation}",
        )

    def occupy(self):
        started, release = threading.Event(), threading.Event()
        self.addCleanup(release.set)
        def run(_):
            started.set()
            if not release.wait(10):
                raise TimeoutError("Test did not release worker")
            return "blocker done"
        task = self.create("blocker", run)
        self.assertTrue(started.wait(2))
        return task, release

    def test_cancelled_queued_task_never_runs(self):
        _, release = self.occupy()
        called = Mock(return_value="wrong")
        task = self.create("queued", called)
        self.assertEqual("queued", task.status)
        self.manager.cancel(task.task_id)
        self.assertEqual(0, self.pool.snapshot()["pending"])
        release.set()
        self.assertTrue(self.pool.wait_idle(3))
        called.assert_not_called()
        self.assertEqual("cancelled", self.manager._store.get(task.task_id)["status"])

    def test_pause_continue_replaces_queued_generation_and_runs_once(self):
        _, release = self.occupy()
        old = Mock(return_value="old")
        new = Mock(return_value="new")
        task = self.create("paused", old)
        self.manager.pause(task.task_id)
        self.assertEqual(0, self.pool.snapshot()["pending"])
        self.manager.continue_task(task.task_id, new, lambda _: None)
        self.assertEqual(2, task.execution_generation)
        release.set()
        self.assertTrue(self.pool.wait_idle(3))
        old.assert_not_called()
        new.assert_called_once()
        self.assertEqual(("completed", "new"), (task.status, task.result))

    def test_capacity_failure_is_durable_and_does_not_start_a_thread(self):
        _, release = self.occupy()
        self.pool.max_pending = 1
        self.create("queued")
        called = Mock(return_value="wrong")
        rejected = self.create("rejected", called)
        self.assertEqual("failed", rejected.status)
        self.assertIn("queue is full", rejected.error)
        self.assertEqual("failed", self.manager._store.get(rejected.task_id)["status"])
        self.assertEqual(1, self.pool.snapshot()["workers"])
        called.assert_not_called()
        release.set()

    def test_apps_with_colliding_conversation_names_keep_distinct_results(self):
        _, release = self.occupy()
        seen = []
        tasks = [self.create(f"{app}-{i}", lambda t: seen.append(t.task_id) or t.client_route_id,
                             app=app, conversation="same") for app in "abc" for i in range(2)]
        release.set()
        self.assertTrue(self.pool.wait_idle(5))
        self.assertEqual([f"{app}-{i}" for i in range(2) for app in "abc"], seen)
        for task in tasks:
            self.assertEqual(task.client_route_id, task.result)

    def test_restarted_queue_is_durable_and_fences_old_execution(self):
        _, release = self.occupy()
        pending = self.create("restore")
        self.pool.cancel(self.manager._execution_key(pending, 1))
        release.set()
        self.assertTrue(self.pool.wait_idle(3))
        restored_pool = AgentWorkPool(max_workers=1)
        self.addCleanup(restored_pool.close)
        restored = AgentTaskManager(state_path=self.path, work_pool=restored_pool)
        task = restored.get(pending.task_id)
        self.assertEqual(("recovering", 2), (task.status, task.execution_generation))
        self.assertFalse(restored._finish(task, "completed", None, result="stale", generation=1))
        restored.resume(task.task_id, lambda _: "recovered", lambda _: None)
        self.assertTrue(restored_pool.wait_idle(3))
        self.assertEqual("recovered", task.result)
        self.assertEqual(2, restored._store.get(task.task_id)["execution_generation"])

    def test_old_monitors_and_running_transition_cannot_change_new_generation(self):
        task = self.manager.create_external("codex", "codex", "message", "Test", lambda _: None)
        task.execution_generation = 2
        task.status = "running"
        original = task.status_seq
        stop = Mock()
        stop.wait.side_effect = [False, True]
        callback = Mock()
        self.manager._heartbeat(task, callback, stop, 1)
        stop.wait.side_effect = [False, True]
        self.manager._progress_watchdog(task, callback, callback, stop, 1)
        self.assertFalse(self.manager._set_status(task, "running", callback, generation=1))
        self.assertEqual(original, task.status_seq)
        callback.assert_not_called()

    def test_never_dispatched_queue_survives_repeated_restarts_without_retry_exhaustion(self):
        task = self.external("waiting-restarts")
        for generation in range(2, 7):
            restored = AgentTaskManager(state_path=self.path)
            self.addCleanup(restored._work_pool.close)
            self.addCleanup(restored._control_work_pool.close)
            task = restored.get(task.task_id)
            self.assertEqual(("recovering", 1, generation),
                             (task.status, task.attempt, task.execution_generation))
            self.assertFalse(task.execution_checkpoint["dispatch_started"])
            self.assertEqual("queued", task.recovery_state)
        restored.resume_external(task.task_id, lambda _: None)
        starts = []
        def start():
            persisted = restored._store.get(task.task_id)
            self.assertTrue(persisted["execution_checkpoint"]["dispatch_started"])
            starts.append(persisted["execution_checkpoint"]["dispatch_generation"])
            restored.update(task.task_id, "completed", result="once")
        restored.schedule_external(task.task_id, start, lambda _: None)
        self.assertTrue(restored._work_pool.wait_idle(3))
        self.assertEqual([6], starts)

    def test_ambiguous_dispatch_still_consumes_recovery_budget(self):
        task = self.external("ambiguous")
        with self.manager._lock:
            self.manager._mark_dispatch_locked(task, 1)
        restored = AgentTaskManager(state_path=self.path)
        self.addCleanup(restored._work_pool.close)
        self.addCleanup(restored._control_work_pool.close)
        self.assertEqual(2, restored.get(task.task_id).attempt)
        exhausted = AgentTaskManager(state_path=self.path)
        self.addCleanup(exhausted._work_pool.close)
        self.addCleanup(exhausted._control_work_pool.close)
        self.assertEqual("failed", exhausted.get(task.task_id).status)

    def test_dispatch_commit_failure_never_invokes_external_provider(self):
        task = self.external("dispatch-write-failure")
        starter = Mock()
        upsert = self.manager._store.upsert
        def fail_dispatch(record, **kwargs):
            if record["execution_checkpoint"].get("dispatch_started") and record["status"] == "queued":
                raise OSError("durable dispatch unavailable")
            return upsert(record, **kwargs)
        with patch.object(self.manager._store, "upsert", side_effect=fail_dispatch):
            self.manager.schedule_external(task.task_id, starter, lambda _: None)
            self.assertTrue(self.pool.wait_idle(3))
        starter.assert_not_called()
        persisted = self.manager._store.get(task.task_id)
        self.assertEqual("failed", persisted["status"])
        self.assertIn("durable dispatch unavailable", persisted["error"])
        self.assertFalse(persisted["execution_checkpoint"]["dispatch_started"])

    def test_pause_keeps_dispatch_boundary_for_recovery(self):
        task = self.external("paused-boundary")
        with self.manager._lock:
            self.manager._mark_dispatch_locked(task, 1)
        self.manager.pause(task.task_id)
        checkpoint = self.manager._store.get(task.task_id)["execution_checkpoint"]
        self.assertTrue(checkpoint["dispatch_started"])
        self.assertEqual(1, checkpoint["dispatch_generation"])
