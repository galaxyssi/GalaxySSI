"""Provider callbacks must not mutate a different logical execution."""
from dataclasses import replace
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

from agent_execution_mutations import AgentExecutionMutations
from agent_task_manager import AgentTaskManager
from agent_work_pool import AgentWorkPool


class ExecutionMutationTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        pool = AgentWorkPool(max_workers=1)
        self.addCleanup(pool.close)
        self.manager = AgentTaskManager(state_path=Path(temporary.name) / "tasks.db", work_pool=pool)
        self.addCleanup(self.manager._control_work_pool.close)
        self.task = self.manager.create_external(
            "codex", "codex", "message", "Test", lambda _: None,
            task_id="task", client_route_id="app", client_conversation_id="conversation",
            client_turn_id="turn",
        )
        self.key = self.manager._execution_key(self.task, self.task.execution_generation)

    def test_every_identity_dimension_is_checked_by_every_mutation(self):
        mutations = [
            lambda key: self.manager.update("task", "completed", result="wrong", expected_execution=key),
            lambda key: self.manager.add_event("task", "step", "wrong", expected_execution=key),
            lambda key: self.manager.record_partial_result("task", "wrong", expected_execution=key),
            lambda key: self.manager.record_partial_result("task", "", expected_execution=key),
            lambda key: self.manager.append_trace("task", "wrong", expected_execution=key),
            lambda key: self.manager.merge_trace("task", [{"stage": "wrong", "at": 1}], expected_execution=key),
        ]
        before = self.task.record()
        persisted = self.manager._store.get("task")
        listener = Mock()
        with patch.object(self.manager, "_emit_snapshot", listener):
            for field in ("app", "conversation", "turn", "task", "generation"):
                key = replace(self.key, **{field: 99 if field == "generation" else "other"})
                for index, mutate in enumerate(mutations):
                    with self.subTest(field=field, mutation=index):
                        self.assertIsNone(mutate(key))
                        self.assertEqual(before, self.task.record())
                        self.assertEqual(persisted, self.manager._store.get("task"))
        listener.assert_not_called()

    def test_bound_callback_uses_original_generation_after_task_changes(self):
        bound = AgentExecutionMutations(self.manager, self.key)
        with self.manager._lock:
            self.task.execution_generation += 1
            self.manager._save_locked(self.task)
        self.assertIsNone(bound.update("task", "completed", result="stale"))
        self.assertIsNone(bound.add_event("task", "step", "stale"))
        self.assertIsNone(bound.record_partial_result("task", "stale"))
        self.assertEqual("", self.task.result)
        self.assertEqual("", self.task.partial_result_text)

    def test_bound_callback_cannot_target_another_task(self):
        manager = Mock()
        bound = AgentExecutionMutations(manager, self.key)
        self.assertIsNone(bound.update("other-task", "completed"))
        manager.update.assert_not_called()

    def test_current_execution_still_persists_and_emits(self):
        bound = AgentExecutionMutations(self.manager, self.key)
        callback = Mock()
        bound.record_partial_result("task", "current output", on_event=callback)
        self.assertEqual("current output", self.manager._store.get("task")["partial_result"]["text"])
        self.assertEqual(self.key.generation, callback.call_args.args[0]["execution_generation"])
        bound.update("task", "completed", result="done")
        self.assertEqual("done", self.manager._store.get("task")["result"])

    def test_delayed_writer_cannot_emit_new_generation(self):
        entered, release = threading.Event(), threading.Event()
        self.addCleanup(release.set)
        callback = Mock()
        failures = []

        def delay(*args, **kwargs):
            entered.set()
            if not release.wait(5):
                raise TimeoutError("Writer not released")

        def write():
            try:
                self.manager.record_partial_result(
                    "task", "old output", on_event=callback, expected_execution=self.key,
                )
            except Exception as exc:
                failures.append(exc)

        with patch.object(self.manager, "_record_latency", side_effect=delay):
            worker = threading.Thread(target=write)
            worker.start()
            self.assertTrue(entered.wait(3))
            with self.manager._lock:
                self.task.execution_generation += 1
                self.task.partial_result_text = "new output"
                self.manager._save_locked(self.task)
            release.set()
            worker.join(3)
        self.assertFalse(worker.is_alive())
        self.assertEqual([], failures)
        callback.assert_not_called()
        self.assertEqual("new output", self.manager._store.get("task")["partial_result"]["text"])

    def test_old_terminal_notification_does_not_remove_new_listener(self):
        self.task.status = "completed"
        snapshot = self.task.public()
        new_listener = Mock()

        def advance(_):
            with self.manager._lock:
                self.task.execution_generation += 1
                self.manager._task_event_callbacks["task"] = new_listener

        self.manager._emit_snapshot(snapshot, advance)
        self.assertIs(new_listener, self.manager._task_event_callbacks["task"])

    def test_snapshot_is_detached_from_mutable_task(self):
        snapshots = []
        self.task.events = [{"metadata": {"marker": "original"}}]
        self.manager._emit(self.task, snapshots.append, expected_execution=self.key)
        self.task.events[0]["metadata"]["marker"] = "changed"
        self.assertEqual("original", snapshots[0]["events"][0]["metadata"]["marker"])

    def test_event_metadata_cannot_replace_execution_identity(self):
        for metadata in ({"client_route_id": "other", "execution_generation": 100},
                         {"too_large": "x" * 17000}, {"invalid": object()}):
            with self.subTest(metadata_type=next(iter(metadata))):
                self.manager.add_event("task", "step", "Current", metadata=metadata, expected_execution=self.key)
                event = self.task.events[-1]["metadata"]
                self.assertEqual("app", event["client_route_id"])
                self.assertEqual(self.key.generation, event["execution_generation"])

    def test_paused_execution_rejects_partial_output(self):
        self.manager.pause("task")
        before = self.task.record()
        self.manager.record_partial_result("task", "late", expected_execution=self.key)
        self.assertEqual(before, self.task.record())

    def test_bound_snapshot_is_detached_and_never_rebinds_to_new_execution(self):
        bound = AgentExecutionMutations(self.manager, self.key)
        snapshot = bound.snapshot()
        self.assertTrue(bound.accepts(snapshot))
        snapshot["pending_approval"]["injected"] = True
        self.assertEqual({}, self.task.pending_approval)
        self.task.execution_generation += 1
        self.assertIsNone(bound.snapshot())
        self.assertFalse(bound.current())
        self.assertFalse(bound.accepts(snapshot))
        self.assertFalse(bound.accepts(self.task.public()))

    def test_publication_rejects_mismatched_snapshot_identity(self):
        bound = AgentExecutionMutations(self.manager, self.key)
        for field in ("client_route_id", "client_conversation_id", "client_turn_id", "task_id", "execution_generation"):
            with self.subTest(field=field):
                snapshot = bound.snapshot()
                snapshot[field] = 99 if field == "execution_generation" else "other"
                self.assertFalse(bound.accepts(snapshot))

    def test_stale_event_snapshot_is_not_sent_to_current_listener(self):
        old = self.task.public()
        self.task.execution_generation += 1
        callback = Mock()
        self.manager._task_event_callbacks["task"] = callback
        self.manager._emit_snapshot(old, None)
        callback.assert_not_called()

    def test_finish_does_not_emit_after_a_new_generation_replaces_it(self):
        callback = Mock()

        def advance(*args, **kwargs):
            self.task.execution_generation += 1
            self.task.status = "running"
            self.task.result = "new"

        with patch.object(self.manager, "_record_latency", side_effect=advance):
            self.assertTrue(self.manager._finish(
                self.task, "completed", callback, result="old", generation=self.key.generation,
            ))
        callback.assert_not_called()
        self.assertEqual("new", self.task.result)
