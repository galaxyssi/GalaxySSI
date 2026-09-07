from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

from evolution_v2 import legacy
from evolution_v2.common import atomic_write_json
from evolution_v2.manager import EvolutionManager
from evolution_v2.models import TaskMetadata


def task(key, status="preparing"):
    return legacy.EvolutionTask(key, "Resume a task", [], ["docs"], ["Pass"], "low", 3, status=status)


class RecoveryScanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source = self.root / "source"
        source.mkdir()
        subprocess.run(["git", "init", "-b", "main"], cwd=source, check=True, capture_output=True, timeout=20)
        self.manager = EvolutionManager(source_root=source, store=legacy.EvolutionStore(self.root / "state"))

    def test_recovery_finds_old_tasks_beyond_the_500_item_ui_limit(self):
        with patch("evolution_v2.legacy._now_millis", side_effect=range(1, 1000)):
            self.manager.store.save(task("old-interrupted"))
            for number in range(650):
                self.manager.store.save(task(f"done-{number}", "completed"))
        self.assertNotIn("old-interrupted", [row.task_id for row in self.manager.store.list(500)])
        self.assertEqual(["old-interrupted"], self.manager.recover_interrupted(resume=False))
        self.assertEqual("proposed", self.manager.require("old-interrupted").status)
        self.assertEqual(651, sum(1 for _ in self.manager.store.iter_tasks()))

    def test_stream_skips_corrupt_and_mismatched_records(self):
        self.manager.store.save(task("valid"))
        root = self.manager.store.tasks_root
        for filename, text in (
            ("bad.json", "[1,2,3]"), ("torn.json", "{"),
            ("bad-attempt.json", '{"attempts":[1]}'),
            ("bad-attempts.json", '{"attempts":{"number":1}}'),
        ):
            (root / filename).write_text(text, encoding="utf-8")
        (root / "other.json").write_bytes((root / "valid.json").read_bytes())
        self.assertEqual(["valid"], self.manager.recover_interrupted(resume=False))

    def test_reserved_not_yet_started_worker_is_not_rolled_back(self):
        self.manager.store.save(task("reserved"))
        self.manager._threads["reserved"] = threading.Thread(target=lambda: None)
        self.assertEqual(1, self.manager.active_worker_count())
        self.assertEqual([], self.manager.recover_interrupted(resume=False))
        self.assertEqual("preparing", self.manager.require("reserved").status)

    def test_live_background_worker_is_untouched(self):
        self.manager.store.save(task("live"))
        ready, release = threading.Event(), threading.Event()
        def worker(*_):
            ready.set()
            release.wait(timeout=10)
        with patch.object(self.manager, "_run_task", side_effect=worker):
            self.manager.start("live")
            thread = self.manager._threads["live"]
            try:
                self.assertTrue(ready.wait(timeout=5))
                self.assertEqual([], self.manager.recover_interrupted(resume=False))
                self.assertEqual("preparing", self.manager.require("live").status)
            finally:
                release.set()
                thread.join(timeout=5)
        self.assertFalse(thread.is_alive())

    def test_synchronous_execution_is_registered_during_recovery(self):
        self.manager.store.save(task("sync"))
        def worker(*_):
            self.assertEqual(1, self.manager.active_worker_count())
            self.assertEqual([], self.manager.recover_interrupted(resume=False))
            with self.assertRaises(legacy.EvolutionError):
                self.manager.run_sync("sync")
        with patch.object(self.manager, "_run_task", side_effect=worker):
            self.manager.run_sync("sync")
        self.assertEqual(0, self.manager.active_worker_count())

    def test_live_publication_is_not_reset_and_duplicate_is_rejected(self):
        self.manager.store.save(task("publishing", "publishing"))
        def publish(*args, **kwargs):
            self.assertEqual([], self.manager.recover_interrupted(resume=False))
            with self.assertRaises(legacy.EvolutionError):
                self.manager.publish("publishing", "hash")
            return self.manager.require("publishing")
        with patch.object(self.manager, "_publish_owned", side_effect=publish):
            self.manager.publish("publishing", "hash")
        self.assertEqual(set(), self.manager._active_publications)
        self.assertEqual(["publishing"], self.manager.recover_interrupted(resume=False))
        self.assertEqual("waiting_approval", self.manager.require("publishing").status)

    def test_publication_owner_is_released_on_error(self):
        with patch.object(self.manager, "_publish_owned", side_effect=OSError("offline")):
            with self.assertRaises(OSError):
                self.manager.publish("publication", "hash")
        self.assertEqual(set(), self.manager._active_publications)

    def test_failed_thread_start_does_not_leave_a_permanent_owner(self):
        self.manager.store.save(task("start-failed"))
        with patch("threading.Thread.start", side_effect=RuntimeError("thread could not start")):
            with self.assertRaises(RuntimeError):
                self.manager.start("start-failed")
        self.assertNotIn("start-failed", self.manager._threads)
        self.assertEqual(["start-failed"], self.manager.recover_interrupted(resume=False))

    def test_ready_candidate_cannot_be_reexecuted_synchronously(self):
        self.manager.store.save(task("ready", "waiting_approval"))
        with self.assertRaises(legacy.EvolutionError):
            self.manager.run_sync("ready")
        self.assertEqual("waiting_approval", self.manager.require("ready").status)
        self.assertEqual(0, self.manager.active_worker_count())

    def test_rollback_does_not_remove_an_owned_worktree(self):
        self.manager.store.save(task("owned"))
        for owners in (self.manager._active_publications, self.manager._recovering_tasks):
            with self.subTest(owners=type(owners).__name__):
                owners.add("owned")
                with self.assertRaises(legacy.EvolutionError):
                    self.manager.discard("owned")
                owners.clear()

    def test_one_recovery_error_does_not_hide_other_tasks(self):
        broken = task("broken", "running")
        broken.attempts = [legacy.EvolutionAttempt(number=1, status="running", branch="candidate", worktree="unused")]
        self.manager.store.save(broken)
        self.manager.store.save(task("other"))
        with patch.object(self.manager, "_remove_worktree", side_effect=OSError("worktree unavailable")):
            recovered = self.manager.recover_interrupted(resume=False)
        self.assertEqual(["other"], recovered)
        self.assertEqual("proposed", self.manager.require("other").status)
        self.assertEqual(set(), self.manager._recovering_tasks)

    def test_cancellation_during_cleanup_is_not_overwritten_or_resumed(self):
        interrupted = task("cancel-during-cleanup", "running")
        interrupted.attempts = [legacy.EvolutionAttempt(number=1, status="running", branch="candidate", worktree="unused")]
        self.manager.store.save(interrupted)
        def cleanup(attempt, **kwargs):
            self.manager.cancel(interrupted.task_id)
            return True
        with patch.object(self.manager, "_remove_worktree", side_effect=cleanup), \
                patch.object(self.manager, "start") as start:
            self.manager.recover_interrupted(resume=True)
            start.assert_not_called()
        self.assertEqual("cancelled", self.manager.require(interrupted.task_id).status)

    def test_ci_repair_is_left_for_head_reconciliation_not_blindly_resumed(self):
        self.manager.store.save(task("repair"))
        self.manager.v2_store.save_task_metadata(TaskMetadata(task_id="repair", ci_repair_target={"head_sha": "a" * 40}))
        with patch.object(self.manager, "start") as start:
            self.manager.recover_interrupted(resume=True)
            start.assert_not_called()
        self.assertEqual("proposed", self.manager.require("repair").status)

    def test_recovery_reservation_blocks_new_start_without_holding_global_lock(self):
        interrupted = task("cleanup", "running")
        interrupted.attempts = [legacy.EvolutionAttempt(number=1, status="running", branch="candidate", worktree="unused")]
        self.manager.store.save(interrupted)
        def cleanup(attempt, **kwargs):
            with self.assertRaises(legacy.EvolutionError):
                self.manager.start(interrupted.task_id)
            available = []
            def probe():
                acquired = self.manager._lock.acquire(blocking=False)
                available.append(acquired)
                if acquired:
                    self.manager._lock.release()
            thread = threading.Thread(target=probe)
            thread.start()
            thread.join(timeout=5)
            self.assertEqual([True], available)
            return True
        with patch.object(self.manager, "_remove_worktree", side_effect=cleanup):
            self.manager.recover_interrupted(resume=False)
        self.assertEqual(set(), self.manager._recovering_tasks)

    def test_real_process_exit_keeps_pre_execution_task_recoverable(self):
        code = """
import os, sys
from pathlib import Path
from evolution_v2.legacy import EvolutionStore, EvolutionTask
s = EvolutionStore(Path(sys.argv[1]))
s.save(EvolutionTask('process-exit', 'Resume task', [], ['docs'], ['Pass'], 'low', 3, status='preparing'))
os._exit(23)
"""
        result = subprocess.run([sys.executable, "-c", code, str(self.manager.store.root)],
                                cwd=Path(__file__).resolve().parents[1], capture_output=True, timeout=20)
        self.assertEqual(23, result.returncode, result.stderr.decode(errors="replace"))
        self.assertEqual(["process-exit"], self.manager.recover_interrupted(resume=False))
        self.assertEqual("proposed", self.manager.require("process-exit").status)

    def test_all_651_interrupted_records_recover_but_only_two_are_admitted(self):
        for number in range(651):
            self.manager.store.save(task(f"pending-{number}"))
        config = {"enabled": True, "execution_mode": "parallel", "max_parallel_evolutions": 2}
        atomic_write_json(self.manager.v2_store.paths["scheduler"] / "settings.json", config)
        def reserve(task_id):
            self.manager._threads[task_id] = threading.Thread(target=lambda: None)
        with patch.object(self.manager, "start", side_effect=reserve) as start:
            self.assertEqual(651, len(self.manager.recover_interrupted(resume=True)))
            self.assertEqual(2, start.call_count)
        self.assertEqual(651, sum(row.status == "proposed" for row in self.manager.store.iter_tasks()))
        self.assertEqual(2, self.manager.active_worker_count())

    def test_disabled_recovery_does_not_start_tasks_even_when_resume_is_requested(self):
        self.manager.store.save(task("disabled"))
        with patch.object(self.manager, "start") as start:
            self.manager.recover_interrupted(resume=True)
            start.assert_not_called()
        self.assertEqual("proposed", self.manager.require("disabled").status)

    def test_recovered_queue_survives_manager_restart_and_drains_with_capacity(self):
        for number in range(3):
            self.manager.store.save(task(f"queued-{number}"))
        self.manager.recover_interrupted(resume=False)
        restored = EvolutionManager(source_root=self.manager.source_root, store=self.manager.store)
        def reserve(task_id):
            restored._threads[task_id] = threading.Thread(target=lambda: None)
        with patch.object(restored, "start", side_effect=reserve):
            first = restored.resume_recovered_tasks({"enabled": True})
            self.assertEqual(1, len(first))
            self.assertEqual([], restored.resume_recovered_tasks({"enabled": True}))
            finished = restored.require(first[0])
            finished.status = "completed"
            restored.store.save(finished)
            restored._threads.pop(first[0])
            second = restored.resume_recovered_tasks({"enabled": True})
            self.assertEqual(1, len(second))
            self.assertNotEqual(first, second)

    def test_campaign_and_ci_repair_recovery_remains_with_their_own_schedulers(self):
        for key in ("dag", "repair", "ordinary"):
            self.manager.store.save(task(key))
        self.manager.v2_store.save_task_metadata(TaskMetadata(task_id="dag", campaign_id="paused-campaign"))
        self.manager.v2_store.save_task_metadata(TaskMetadata(task_id="repair", ci_repair_target={"head_sha": "a" * 40}))
        self.manager.recover_interrupted(resume=False)
        with patch.object(self.manager, "start") as start:
            self.assertEqual(["ordinary"], self.manager.resume_recovered_tasks({"enabled": True}))
            start.assert_called_once_with("ordinary")

    def test_immediately_completed_jobs_do_not_create_an_unbounded_admission_burst(self):
        for number in range(5):
            self.manager.store.save(task(f"instant-{number}"))
        self.manager.recover_interrupted(resume=False)
        with patch.object(self.manager, "start") as start:
            self.assertEqual(1, len(self.manager.resume_recovered_tasks({"enabled": True})))
            self.assertEqual(1, start.call_count)

    def test_auto_start_off_preserves_durable_queue(self):
        self.manager.store.save(task("manual"))
        self.manager.recover_interrupted(resume=False)
        with patch.object(self.manager, "start") as start:
            self.assertEqual([], self.manager.resume_recovered_tasks({"enabled": True, "auto_start_tasks": False}))
            start.assert_not_called()

    def test_stale_stream_record_cannot_restart_a_cancelled_task(self):
        self.manager.store.save(task("cancelled"))
        self.manager.recover_interrupted(resume=False)
        stale = self.manager.require("cancelled")
        self.manager.cancel("cancelled")
        with patch.object(self.manager.store, "iter_tasks", return_value=iter([stale])), \
                patch.object(self.manager, "start") as start:
            self.assertEqual([], self.manager.resume_recovered_tasks({"enabled": True}))
            start.assert_not_called()

    def test_unrelated_proposals_are_not_implicitly_started_by_recovery(self):
        self.manager.store.save(task("new-proposal", "proposed"))
        with patch.object(self.manager, "start") as start:
            self.assertEqual([], self.manager.resume_recovered_tasks({"enabled": True}))
            start.assert_not_called()

    def test_failed_cleanup_preserves_concurrent_cancellation(self):
        interrupted = task("cancel-cleanup-error", "running")
        interrupted.attempts = [legacy.EvolutionAttempt(number=1, status="running", branch="candidate", worktree="unused")]
        self.manager.store.save(interrupted)
        def cleanup(*args, **kwargs):
            self.manager.cancel(interrupted.task_id)
            raise legacy.EvolutionError("cleanup_refused", "Worktree still in use")
        with patch.object(self.manager, "_remove_worktree", side_effect=cleanup):
            self.manager.recover_interrupted(resume=False)
        self.assertEqual("cancelled", self.manager.require(interrupted.task_id).status)

    def test_failed_cleanup_is_blocked_and_never_admitted(self):
        interrupted = task("cleanup-blocked", "running")
        interrupted.attempts = [legacy.EvolutionAttempt(number=1, status="running", branch="candidate", worktree="unused")]
        self.manager.store.save(interrupted)
        with patch.object(self.manager, "_remove_worktree", side_effect=legacy.EvolutionError("cleanup_refused", "In use")):
            self.manager.recover_interrupted(resume=False)
        self.assertEqual("blocked", self.manager.require(interrupted.task_id).status)
        self.assertEqual([], self.manager.resume_recovered_tasks({"enabled": True}))

    def test_execution_and_publication_owners_cannot_overlap(self):
        self.manager.store.save(task("owned"))
        self.manager._active_publications.add("owned")
        with self.assertRaises(legacy.EvolutionError):
            self.manager.start("owned")
        with self.assertRaises(legacy.EvolutionError):
            self.manager.run_sync("owned")
        self.manager._active_publications.clear()
        self.manager._threads["owned"] = threading.Thread(target=lambda: None)
        with self.assertRaises(legacy.EvolutionError):
            self.manager.publish("owned", "hash")

    def test_real_workers_resume_in_bounded_waves_after_manager_recreation(self):
        for number in range(3):
            self.manager.store.save(task(f"wave-{number}"))
        self.manager.recover_interrupted(resume=False)
        config = {"enabled": True, "execution_mode": "parallel", "max_parallel_evolutions": 2}
        release = threading.Event()
        def execute(task_id, cancellation):
            release.wait(10)
            current = self.manager.require(task_id)
            current.status = "completed"
            self.manager.store.save(current)
        with patch.object(self.manager, "_run_task", side_effect=execute):
            first = self.manager.resume_recovered_tasks(config)
            threads = list(self.manager._threads.values())
            try:
                self.assertEqual(2, len(first))
                self.assertEqual([], self.manager.resume_recovered_tasks(config))
            finally:
                release.set()
                for thread in threads:
                    thread.join(10)
                    self.assertFalse(thread.is_alive())
        self.manager = EvolutionManager(source_root=self.manager.source_root, store=self.manager.store)
        self.assertEqual(1, sum(row.status == "proposed" for row in self.manager.store.iter_tasks()))
        release.clear()
        with patch.object(self.manager, "_run_task", side_effect=execute):
            second = self.manager.resume_recovered_tasks(config)
            threads = list(self.manager._threads.values())
            try:
                self.assertEqual(1, len(second))
                self.assertFalse(set(first) & set(second))
            finally:
                release.set()
                for thread in threads:
                    thread.join(10)
                    self.assertFalse(thread.is_alive())
        self.assertEqual(3, sum(row.status == "completed" for row in self.manager.store.iter_tasks()))
