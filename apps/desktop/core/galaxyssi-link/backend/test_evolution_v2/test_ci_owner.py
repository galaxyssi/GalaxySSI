from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from unittest.mock import patch

from agent_run_kernel import AgentRunEventLedger
from evolution_v2.ci_owner import OwnerLockUnavailable
from evolution_v2.ci_store import CiLeaseLost, CiWatchStore
from test_evolution_v2.test_ci_snapshot import URL


class CiOwnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / "runs.sqlite3"
        self.store = CiWatchStore(AgentRunEventLedger(self.path))
        self.store.register("parent", URL)
        self.owner = "ci-lock-v1-" + uuid.uuid4().hex
        self.next_owner = "ci-lock-v1-" + uuid.uuid4().hex

    def test_live_owner_is_not_stolen_even_after_lease_expiry(self):
        with self.store.owner_locks.hold(self.owner, create=True) as acquired:
            self.assertTrue(acquired)
            self.store.claim_due(100, self.owner, lease_millis=1)
            self.assertEqual([], self.store.claim_due(9999999, self.next_owner))

    def test_released_owner_recovers_without_waiting_for_lease_or_poll(self):
        with self.store.owner_locks.hold(self.owner, create=True):
            data = self.store.claim_due(100, self.owner)[0]
            data["repair"] = {"task_id": "stable-child"}
            self.store.save(data, self.owner, 101, next_poll=1000000, release=False)
        recovered = self.store.claim_due(102, self.next_owner)
        self.assertEqual("stable-child", recovered[0]["repair"]["task_id"])
        with self.assertRaises(CiLeaseLost):
            self.store.save(data, self.owner, 103, next_poll=0)

    def test_missing_owner_file_is_unknown_not_dead(self):
        self.store.claim_due(100, self.owner)
        self.assertEqual([], self.store.claim_due(9999999, self.next_owner))

    def test_inaccessible_lock_does_not_authorize_takeover(self):
        with self.store.owner_locks.hold(self.owner, create=True):
            self.store.claim_due(100, self.owner)
        with patch.object(self.store.owner_locks, "hold", side_effect=OwnerLockUnavailable("denied")):
            self.assertEqual([], self.store.claim_due(9999999, self.next_owner))

    def test_lock_files_are_retained_and_cannot_escape_directory(self):
        with self.store.owner_locks.hold(self.owner, create=True):
            pass
        self.assertTrue((self.store.owner_locks.root / (self.owner + ".lock")).is_file())
        for owner in ("../other", "ci-lock-v1-../other", "", "ci-lock-v1-" + "z" * 32):
            with self.assertRaises(ValueError):
                with self.store.owner_locks.hold(owner, create=True):
                    pass

    def test_guard_remains_held_during_sql_reassignment(self):
        with self.store.owner_locks.hold(self.owner, create=True):
            self.store.claim_due(100, self.owner)
        original = self.store.owner_locks.hold
        from contextlib import contextmanager
        @contextmanager
        def probe(owner):
            with original(owner) as available:
                self.assertTrue(available)
                with original(owner) as raced:
                    self.assertFalse(raced)
                yield available
        with patch.object(self.store.owner_locks, "hold", side_effect=probe):
            self.assertEqual(1, len(self.store.claim_due(101, self.next_owner)))

    def _spawn_owner(self, *, immediate_exit=False):
        ready = self.root / "ready"
        code = """
import os, sys, time
from pathlib import Path
from agent_run_kernel import AgentRunEventLedger
from evolution_v2.ci_store import CiWatchStore
s=CiWatchStore(AgentRunEventLedger(Path(sys.argv[1])))
with s.owner_locks.hold(sys.argv[2], create=True) as held:
    assert held
    d=s.claim_due(100,sys.argv[2],lease_millis=2)[0]
    d['repair']={'task_id':'survives-process-death'}
    s.save(d,sys.argv[2],101,next_poll=1000000,release=False)
    Path(sys.argv[3]).write_text('ready', encoding='ascii')
    if sys.argv[4]=='exit': os._exit(23)
    time.sleep(60)
"""
        process = subprocess.Popen([sys.executable, "-c", code, str(self.path), self.owner, str(ready),
                                    "exit" if immediate_exit else "hold"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        def cleanup():
            if process.poll() is None:
                process.terminate()
            process.communicate(timeout=10)
        self.addCleanup(cleanup)
        deadline = time.monotonic() + 10
        while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(ready.exists(), "Child did not establish its OS-held observation")
        return process

    def test_actual_process_death_recovery_under_five_seconds(self):
        process = self._spawn_owner(immediate_exit=True)
        self.assertEqual(23, process.wait(timeout=10))
        started = time.perf_counter_ns()
        recovered = self.store.claim_due(102, self.next_owner)
        elapsed = (time.perf_counter_ns() - started) / 1_000_000_000
        self.assertEqual("survives-process-death", recovered[0]["repair"]["task_id"])
        self.assertLess(elapsed, 5.0)
        print(f"CI owner process-death local recovery: {elapsed * 1000:.3f} ms", flush=True)

    def test_actual_live_process_is_not_stolen_then_recovers_after_termination(self):
        process = self._spawn_owner()
        self.assertIsNone(process.poll())
        self.assertEqual([], self.store.claim_due(9999999, self.next_owner))
        process.terminate()
        process.wait(timeout=10)
        self.assertEqual(1, len(self.store.claim_due(102, self.next_owner)))

    def test_blocked_owner_does_not_starve_other_due_watches(self):
        self.store.register("second", URL)
        with self.store.owner_locks.hold(self.owner, create=True):
            self.store.claim_due(100, self.owner, limit=1)
            self.assertEqual(["second"], [d["task_id"] for d in self.store.claim_due(101, self.next_owner)])
