from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

from evolution_v2 import legacy
from evolution_v2.manager import EvolutionManager
from evolution_v2.recovery import resume_recovered_tasks
from process_recovery_journal import record_job


class ProcessRecoveryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        source = self.root / "source"
        source.mkdir()
        subprocess.run(["git", "init", "-b", "main"], cwd=source, check=True, capture_output=True, timeout=20)
        self.manager = EvolutionManager(source_root=source, store=legacy.EvolutionStore(self.root / "state"))
        self.task = legacy.EvolutionTask("interrupted", "Resume", [], ["docs"], ["Pass"], "low", 3,
                                         status="running")
        self.manager.store.save(self.task)
        self.journal = self.manager._process_journal(self.task.task_id)

    def evidence(self):
        return record_job(self.journal, "Global\\GalaxySSI-owned-" + uuid.uuid4().hex)

    def test_pending_process_does_not_clean_worktree_or_change_running_status(self):
        self.task.attempts = [legacy.EvolutionAttempt(number=1, status="running", branch="candidate",
                                                      worktree=str(self.root / "candidate"))]
        self.manager.store.save(self.task)
        record = self.evidence()
        with patch("windows_process_job.active_processes", return_value=1), \
                patch.object(self.manager, "_remove_worktree") as cleanup:
            self.assertEqual([], self.manager.recover_interrupted(resume=False))
        cleanup.assert_not_called()
        current = self.manager.require(self.task.task_id)
        self.assertEqual("running", current.status)
        self.assertEqual("process_termination_pending", current.last_error_code)
        self.assertTrue(record.exists())
        self.assertEqual(set(), self.manager._recovering_tasks)
        self.assertFalse(self.manager.task_owners.locally_owned(self.task.task_id))
        with patch("windows_process_job.active_processes", return_value=0), \
                patch.object(self.manager, "_remove_worktree") as cleanup:
            self.assertEqual([self.task.task_id], self.manager.recover_interrupted(resume=False))
        cleanup.assert_called_once_with(self.task.attempts[-1], delete_branch=True)

    def test_manual_start_publish_discard_are_fenced_and_release_ownership(self):
        self.evidence()
        for operation in (lambda: self.manager.start(self.task.task_id),
                          lambda: self.manager.run_sync(self.task.task_id),
                          lambda: self.manager.publish(self.task.task_id, "hash"),
                          lambda: self.manager.discard(self.task.task_id)):
            with self.subTest(operation=operation), patch("windows_process_job.active_processes", return_value=1):
                with self.assertRaises(legacy.EvolutionError) as failure:
                    operation()
                self.assertEqual("process_termination_pending", failure.exception.code)
                self.assertFalse(self.manager.task_owners.locally_owned(self.task.task_id))

    def test_scheduler_rechecks_deferred_recovery_and_honors_disabled(self):
        self.evidence()
        with patch("windows_process_job.active_processes", side_effect=OSError("access denied")):
            self.assertEqual([], self.manager.recover_interrupted(resume=False))
        with patch("windows_process_job.active_processes", return_value=0) as query:
            self.assertEqual([], resume_recovered_tasks(self.manager, {"enabled": False}))
            query.assert_not_called()
            with patch.object(self.manager, "start") as start:
                result = resume_recovered_tasks(self.manager, {"enabled": True, "auto_start_tasks": True})
            self.assertEqual([self.task.task_id], result)
            start.assert_called_once_with(self.task.task_id)
        self.assertEqual("proposed", self.manager.require(self.task.task_id).status)

    def test_background_and_sync_commands_have_task_scoped_journal(self):
        import owned_process
        seen = []
        def run(*_):
            seen.append(owned_process._journal.get())
        with patch.object(self.manager, "_run_task", side_effect=run):
            self.manager.run_sync(self.task.task_id)
            self.manager.start(self.task.task_id)
            thread = self.manager._threads.get(self.task.task_id)
            if thread is not None:
                thread.join(10)
                self.assertFalse(thread.is_alive())
        self.assertEqual([self.journal, self.journal], seen)

    @unittest.skipUnless(os.name == "nt", "Real Windows process-death recovery")
    def test_live_orphan_prevents_real_git_worktree_cleanup(self):
        from owned_process import owned_process_scope, popen
        source = self.manager.source_root
        for argv in (["git", "-c", "user.name=Recovery Test", "-c", "user.email=test@example.invalid",
                      "commit", "--allow-empty", "-m", "Seed isolated recovery test"],):
            subprocess.run(argv, cwd=source, check=True, capture_output=True, timeout=20)
        worktree = self.manager.store.worktrees_root / self.task.task_id / "attempt-1"
        branch = "evolution/interrupted-a1"
        subprocess.run(["git", "worktree", "add", "-b", branch, str(worktree)],
                       cwd=source, check=True, capture_output=True, timeout=20)
        self.task.attempts = [legacy.EvolutionAttempt(number=1, status="running", branch=branch,
                                                      worktree=str(worktree))]
        self.manager.store.save(self.task)
        with owned_process_scope(self.journal):
            process = popen([getattr(sys, "_base_executable", sys.executable), "-c",
                             "import time; time.sleep(120)"], cwd=worktree,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            self.assertEqual([], self.manager.recover_interrupted(resume=False))
            self.assertTrue(worktree.exists())
            self.assertEqual("process_termination_pending", self.manager.require(self.task.task_id).last_error_code)
        finally:
            process.close()
        deadline = time.monotonic() + 10
        recovered = []
        while not recovered and time.monotonic() < deadline:
            recovered = self.manager.recover_interrupted(resume=False)
            if not recovered:
                time.sleep(0.02)
        self.assertEqual([self.task.task_id], recovered)
        self.assertEqual("proposed", self.manager.require(self.task.task_id).status)
        self.assertFalse(worktree.exists())
        result = subprocess.run(["git", "show-ref", "--verify", "--quiet", "refs/heads/" + branch],
                                cwd=source, capture_output=True, timeout=20)
        self.assertEqual(1, result.returncode)

    @unittest.skipUnless(os.name == "nt", "Real Windows process-death recovery")
    def test_real_owner_crash_then_new_manager_recovers_only_after_job_exit(self):
        checkpoint = self.root / "child-ready"
        host_code = """
import os, subprocess, sys, time
from pathlib import Path
from evolution_v2.task_owner import TaskOwners
from owned_process import owned_process_scope, popen
owners = TaskOwners(Path(sys.argv[1]) / 'task-owners')
assert owners.claim('interrupted')
with owned_process_scope(Path(sys.argv[2])):
    process = popen([sys.executable, '-c', "from pathlib import Path; import sys,time; Path(sys.argv[1]).touch(); time.sleep(120)", sys.argv[3]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
sys.stdin.buffer.read(1)
os._exit(23)
"""
        host = subprocess.Popen([getattr(sys, "_base_executable", sys.executable), "-c", host_code,
                                 str(self.manager.store.root), str(self.journal), str(checkpoint)],
                                cwd=Path(__file__).resolve().parents[1], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 20
            while not checkpoint.exists() and host.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(checkpoint.exists(), "Owned child did not start")
            new_manager = EvolutionManager(source_root=self.manager.source_root, store=self.manager.store)
            self.assertEqual([], new_manager.recover_interrupted(resume=False))
            self.assertTrue(list(self.journal.glob("*.json")))
            _, stderr = host.communicate(b"x", timeout=20)
            self.assertEqual(23, host.returncode, stderr.decode(errors="replace"))
            deadline = time.monotonic() + 10
            recovered = []
            while not recovered and time.monotonic() < deadline:
                recovered = new_manager.recover_interrupted(resume=False)
                if not recovered:
                    time.sleep(0.02)
            self.assertEqual([self.task.task_id], recovered)
            self.assertEqual("proposed", new_manager.require(self.task.task_id).status)
            self.assertEqual([], list(self.journal.iterdir()))
        finally:
            if host.poll() is None:
                host.communicate(b"x", timeout=20)


if __name__ == "__main__":
    unittest.main()
