from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from evolution_v2 import legacy
from evolution_v2.manager import EvolutionManager
from evolution_v2.os_owner import OwnerLockUnavailable
from evolution_v2.task_owner import TaskOwners


class TaskOwnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source = self.root / "source"
        source.mkdir()
        subprocess.run(["git", "init", "-b", "main"], cwd=source, check=True, capture_output=True, timeout=20)
        self.manager = EvolutionManager(source_root=source, store=legacy.EvolutionStore(self.root / "state"))
        self.other = EvolutionManager(source_root=source, store=legacy.EvolutionStore(self.root / "state"))
        self.manager.store.save(legacy.EvolutionTask("shared", "Resume", [], ["docs"], ["Pass"], "low", 3))

    def test_independent_owners_exclude_same_task_but_allow_other_tasks(self):
        first = self.manager.task_owners
        second = self.other.task_owners
        with first.hold("shared") as held:
            self.assertTrue(held)
            with second.hold("shared") as duplicate:
                self.assertFalse(duplicate)
            with second.hold("other") as unrelated:
                self.assertTrue(unrelated)
        with second.hold("shared") as recovered:
            self.assertTrue(recovered)
        self.assertEqual(2, len(list(first.locks.root.glob("*.lock"))))

    def test_live_background_owner_blocks_other_manager_operations(self):
        ready, release = threading.Event(), threading.Event()
        def run(*args):
            ready.set()
            release.wait(15)
        with patch.object(self.manager, "_run_task", side_effect=run):
            self.manager.start("shared")
            thread = self.manager._threads["shared"]
            try:
                self.assertTrue(ready.wait(10))
                self.assertEqual([], self.other.recover_interrupted(resume=False))
                for operation in (
                    lambda: self.other.start("shared"), lambda: self.other.run_sync("shared"),
                    lambda: self.other.discard("shared"), lambda: self.other.publish("shared", "hash"),
                    lambda: self.other.cancel("shared"),
                ):
                    with self.assertRaises(legacy.EvolutionError) as error:
                        operation()
                    self.assertEqual("task_owned_elsewhere", error.exception.code)
                self.assertEqual("preparing", self.other.require("shared").status)
            finally:
                release.set()
                thread.join(10)
        self.assertFalse(thread.is_alive())
        self.assertEqual(["shared"], self.other.recover_interrupted(resume=False))

    def test_sync_owner_is_held_until_execution_returns(self):
        def run(*args):
            self.assertEqual([], self.other.recover_interrupted(resume=False))
            with self.assertRaises(legacy.EvolutionError):
                self.other.run_sync("shared")
        with patch.object(self.manager, "_run_task", side_effect=run):
            self.manager.run_sync("shared")
        with self.other.task_owners.hold("shared") as held:
            self.assertTrue(held)

    def test_publication_owner_rejects_remote_recovery_and_releases_on_error(self):
        current = self.manager.require("shared")
        current.status = "publishing"
        self.manager.store.save(current)
        def publish(*args, **kwargs):
            self.assertEqual([], self.other.recover_interrupted(resume=False))
            with self.assertRaises(legacy.EvolutionError):
                self.other.publish("shared", "hash")
            raise RuntimeError("GitHub unavailable")
        with patch.object(self.manager, "_publish_owned", side_effect=publish):
            with self.assertRaises(RuntimeError):
                self.manager.publish("shared", "hash")
        self.assertEqual(["shared"], self.other.recover_interrupted(resume=False))

    def test_failed_thread_start_releases_os_owner(self):
        with patch("threading.Thread.start", side_effect=RuntimeError("startup failed")):
            with self.assertRaises(RuntimeError):
                self.manager.start("shared")
        with self.other.task_owners.hold("shared") as held:
            self.assertTrue(held)

    def test_unknown_lock_failure_never_authorizes_recovery_or_execution(self):
        current = self.manager.require("shared")
        current.status = "running"
        self.manager.store.save(current)
        with patch.object(self.manager.task_owners.locks, "hold", side_effect=OwnerLockUnavailable("denied")):
            self.assertEqual([], self.manager.recover_interrupted(resume=False))
            with self.assertRaises(OwnerLockUnavailable):
                self.manager.start("shared")
        self.assertEqual("running", self.manager.require("shared").status)

    def test_recovery_holds_owner_through_cleanup_and_status_write(self):
        current = self.manager.require("shared")
        current.status = "running"
        current.attempts = [legacy.EvolutionAttempt(number=1, status="running", branch="candidate", worktree="unused")]
        self.manager.store.save(current)
        def cleanup(*args, **kwargs):
            self.assertEqual([], self.other.recover_interrupted(resume=False))
            with self.assertRaises(legacy.EvolutionError):
                self.other.start("shared")
        original_save = self.manager.store.save
        def save(current):
            with self.other.task_owners.hold("shared") as held:
                self.assertFalse(held)
            return original_save(current)
        with patch.object(self.manager, "_remove_worktree", side_effect=cleanup), \
                patch.object(self.manager.store, "save", side_effect=save):
            self.assertEqual(["shared"], self.manager.recover_interrupted(resume=False))

    def test_task_ids_are_hashed_and_cannot_escape_the_owner_directory(self):
        owners = TaskOwners(self.root / "owners")
        with owners.hold("../../outside") as held:
            self.assertTrue(held)
        self.assertEqual(1, len(list(owners.locks.root.glob("task-v1-*.lock"))))
        self.assertFalse((self.root / "outside.lock").exists())

    def test_real_executor_process_death_releases_task_without_lease_timeout(self):
        ready = self.root / "ready"
        code = """
import os, sys
from pathlib import Path
from evolution_v2 import legacy
from evolution_v2.manager import EvolutionManager
m = EvolutionManager(source_root=Path(sys.argv[1]), store=legacy.EvolutionStore(Path(sys.argv[2])))
def run(*args):
    Path(sys.argv[3]).write_text('ready', encoding='ascii')
    sys.stdin.buffer.read(1)
    os._exit(23)
m._run_task = run
m.run_sync('shared')
"""
        child = subprocess.Popen([sys.executable, "-c", code, str(self.manager.source_root),
                                  str(self.manager.store.root), str(ready)],
                                 cwd=Path(__file__).resolve().parents[1], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 20
            while not ready.exists() and child.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(ready.exists(), "Executor never acquired ownership")
            self.assertEqual([], self.manager.recover_interrupted(resume=False))
            with self.assertRaises(legacy.EvolutionError):
                self.manager.start("shared")
            _, stderr = child.communicate(input=b"x", timeout=20)
            self.assertEqual(23, child.returncode, stderr.decode(errors="replace"))
            started = time.perf_counter()
            self.assertEqual(["shared"], self.manager.recover_interrupted(resume=False))
            print(f"Task OS-owner exit recovery: {(time.perf_counter() - started) * 1000:.3f} ms")
            self.assertEqual("proposed", self.manager.require("shared").status)
        finally:
            if child.poll() is None:
                child.communicate(input=b"x", timeout=20)
