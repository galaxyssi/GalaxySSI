from __future__ import annotations

import concurrent.futures
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from agent_run_kernel import AgentRunEventLedger
from evolution_v2.ci_store import CiLeaseLost, CiWatchStore
from test_evolution_v2.test_ci_snapshot import URL


class CiStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "run.sqlite3"
        self.ledger = AgentRunEventLedger(self.path)
        self.store = CiWatchStore(self.ledger)
        self.store.register("parent", URL)

    def test_registration_idempotence_and_identity(self):
        self.store.register("parent", URL)
        self.assertEqual(1, self.ledger.snapshot("ci-watch:parent")["last_sequence"])
        with self.assertRaises(ValueError):
            self.store.register("parent", URL + "0")

    def test_restart_preserves_reserved_repair(self):
        data = self.store.claim_due(100, "first")[0]
        data["repair"] = {"task_id": "stable-child"}
        self.store.save(data, "first", 101, next_poll=200)
        recreated = CiWatchStore(AgentRunEventLedger(self.path))
        self.assertEqual("stable-child", recreated.claim_due(200, "second")[0]["repair"]["task_id"])

    def test_unchanged_poll_does_not_append_events(self):
        data = self.store.claim_due(100, "first")[0]
        self.store.save(data, "first", 101, next_poll=200)
        self.assertEqual(1, self.ledger.snapshot("ci-watch:parent")["last_sequence"])

    def test_expired_owner_cannot_overwrite_new_owner(self):
        old = self.store.claim_due(100, "old", lease_millis=10)[0]
        new = self.store.claim_due(110, "new")[0]
        with self.assertRaises(CiLeaseLost):
            self.store.save(old, "old", 111, next_poll=0)
        new["status"] = "passed"
        self.store.save(new, "new", 111, next_poll=200)
        self.assertEqual("passed", self.store.get("parent")["status"])

    def test_closed_watch_is_not_claimed(self):
        data = self.store.claim_due(100, "one")[0]
        data["status"] = "closed"
        self.store.save(data, "one", 101, next_poll=-1)
        self.assertEqual([], self.store.claim_due(9999999, "two"))

    def test_concurrent_claim_only_one_owner(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            rows = list(pool.map(lambda n: self.store.claim_due(100, str(n)), range(8)))
        self.assertEqual(1, sum(len(row) for row in rows))

    def test_meaningful_transition_is_in_run_ledger(self):
        data = self.store.claim_due(100, "one")[0]
        data["status"] = "failed"
        self.store.save(data, "one", 101, next_poll=200)
        root = self.ledger.snapshot("ci-watch:parent")
        self.assertEqual(2, root["last_sequence"])
        self.assertEqual("parent", root["task_id"])

    def test_process_death_after_reservation_keeps_checkpoint(self):
        code = """
import os, sys
from pathlib import Path
from agent_run_kernel import AgentRunEventLedger
from evolution_v2.ci_store import CiWatchStore
s=CiWatchStore(AgentRunEventLedger(Path(sys.argv[1])))
d=s.claim_due(100,'dead')[0]
d['repair']={'task_id':'reserved-before-crash'}
s.save(d,'dead',101,next_poll=0,release=False)
os._exit(23)
"""
        result = subprocess.run([sys.executable, "-c", code, str(self.path)], capture_output=True, timeout=20)
        self.assertEqual(23, result.returncode, result.stderr.decode())
        self.assertEqual([], self.store.claim_due(200, "early"))
        self.assertEqual("reserved-before-crash", self.store.claim_due(700000, "restarted")[0]["repair"]["task_id"])

    def test_transaction_rollback_has_no_partial_projection(self):
        from unittest.mock import patch
        with patch.object(self.store, "_event", side_effect=RuntimeError("write interrupted")):
            with self.assertRaises(RuntimeError):
                self.store.register("other", URL)
        self.assertIsNone(self.store.get("other"))

    def test_more_than_500_watches_are_incrementally_recoverable(self):
        for index in range(505):
            self.store.register(f"p{index}", URL)
        found = set()
        while rows := self.store.claim_due(100, "one", limit=19):
            for data in rows:
                found.add(data["task_id"])
                self.store.save(data, "one", 101, next_poll=-1)
        self.assertEqual(506, len(found))
