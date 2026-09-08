"""Durable worker ownership, ordered receipts and actual process contention."""
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from agent_run_kernel import AgentRunEventLedger
from agent_task_store import AgentTaskWriteConflict
from agent_worker_leases import AgentWorkerLeaseLedger, WorkerLeaseConflict
from agent_work_pool import ExecutionKey


class WorkerLeaseTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / "runs.db"
        self.now = 1_000_000
        clock = patch("agent_worker_leases._clock_ms", side_effect=lambda: self.now)
        clock.start()
        self.addCleanup(clock.stop)
        self.ledger = AgentRunEventLedger(self.path)
        self.leases = AgentWorkerLeaseLedger(self.ledger)
        self.key = ExecutionKey("app", "conversation", "turn", "task", 1)

    def claim(self, **changes):
        arguments = dict(key=self.key, worker_id="node-a", incarnation="process-a",
                         expected_epoch=0, claim_id="claim-a", ttl_ms=1000)
        arguments.update(changes)
        return self.leases.claim(**arguments)

    def record(self, **changes):
        snapshot = dict(task_id="task", client_route_id="app", client_conversation_id="conversation",
                        client_turn_id="turn", source_message_id="message", conversation_id="conversation",
                        execution_generation=1, status="running", status_seq=1, created_at=self.now,
                        updated_at=self.now, result="", agent_id="codex")
        snapshot.update(changes)
        return snapshot

    def test_claim_replay_is_idempotent_and_does_not_extend_deadline(self):
        first = self.claim()
        self.now += 700
        self.assertEqual(first, self.claim())
        self.assertNotIn(first.token, repr(first))
        with self.assertRaises(WorkerLeaseConflict):
            self.claim(incarnation="different-process")
        with self.assertRaises(WorkerLeaseConflict):
            self.claim(ttl_ms=2000)

    def test_live_lease_cannot_be_stolen_by_restarted_worker(self):
        self.claim()
        with self.assertRaisesRegex(WorkerLeaseConflict, "still leased"):
            self.claim(key=replace(self.key, generation=2), incarnation="restarted",
                       expected_epoch=1, claim_id="claim-b")

    def test_expiry_requires_new_generation_and_rejects_old_owner(self):
        old = self.claim()
        self.now += 1000
        with self.assertRaises(WorkerLeaseConflict):
            self.leases.renew(old)
        with self.assertRaisesRegex(WorkerLeaseConflict, "newer execution"):
            self.claim(worker_id="node-b", expected_epoch=1, claim_id="claim-b")
        new = self.claim(key=replace(self.key, generation=2), worker_id="node-b",
                         incarnation="process-b", expected_epoch=1, claim_id="claim-b")
        self.assertEqual(2, new.epoch)
        with self.assertRaises(WorkerLeaseConflict):
            self.leases.apply_task(old, 1, self.record())
        with self.assertRaises(WorkerLeaseConflict):
            self.leases.renew(old)
        self.assertTrue(self.leases.apply_task(new, 1, self.record(execution_generation=2)))

    def test_renewal_survives_coordinator_restart(self):
        grant = self.claim()
        self.now += 800
        extended = self.leases.renew(grant, ttl_ms=2000)
        restarted = AgentWorkerLeaseLedger(AgentRunEventLedger(self.path))
        self.now += 500
        self.assertTrue(restarted.apply_task(grant, 1, self.record()))
        self.assertGreater(extended.expires_at_ms, grant.expires_at_ms)

    def test_every_capability_component_is_bound(self):
        grant = self.claim()
        for field, value in (("worker_id", "node-b"), ("incarnation", "other"),
                             ("epoch", 2), ("token", "0" * 64)):
            with self.subTest(field=field), self.assertRaises(WorkerLeaseConflict):
                self.leases.renew(replace(grant, **{field: value}))
        for field in ("app", "conversation", "turn", "task"):
            with self.subTest(field=field), self.assertRaises(WorkerLeaseConflict):
                self.leases.renew(replace(grant, key=replace(self.key, **{field: "other"})))

    def test_revoke_does_not_revoke_a_newer_owner(self):
        old = self.claim()
        self.leases.revoke(self.key, expected_epoch=1)
        with self.assertRaises(WorkerLeaseConflict):
            self.leases.renew(old)
        new = self.claim(key=replace(self.key, generation=2), expected_epoch=1, claim_id="claim-b")
        with self.assertRaises(WorkerLeaseConflict):
            self.leases.revoke(self.key, expected_epoch=1)
        self.leases.renew(new)

    def test_ordered_receipts_and_idempotent_replay(self):
        grant = self.claim()
        record = self.record()
        self.assertTrue(self.leases.apply_task(grant, 1, record))
        count = self.ledger.event_count()
        self.assertFalse(self.leases.apply_task(grant, 1, record))
        with self.assertRaises(WorkerLeaseConflict):
            self.leases.apply_task(grant, 1, self.record(result="changed"))
        with self.assertRaises(WorkerLeaseConflict):
            self.leases.apply_task(grant, 3, self.record())
        self.assertEqual(count, self.ledger.event_count())

    def test_failed_task_write_rolls_back_event_and_receipt(self):
        grant = self.claim()
        self.leases.apply_task(grant, 1, self.record())
        count = self.ledger.event_count()
        bad = self.record(status_seq=2, result="stale revision")
        with self.assertRaises(AgentTaskWriteConflict):
            self.leases.apply_task(grant, 2, bad)
        self.assertEqual(count, self.ledger.event_count())
        good = self.record(status_seq=2, _storage_revision=1, result="current revision")
        self.assertTrue(self.leases.apply_task(grant, 2, good))
        self.assertEqual("current revision", self.leases.tasks.get("task")["result"])

    def test_result_scope_cannot_be_changed(self):
        grant = self.claim()
        for field in ("client_route_id", "client_conversation_id", "client_turn_id", "task_id"):
            with self.subTest(field=field), self.assertRaises(WorkerLeaseConflict):
                self.leases.apply_task(grant, 1, self.record(**{field: "other"}))
        self.assertEqual(0, self.ledger.event_count())

    def test_ordinary_task_writer_cannot_bypass_lease_or_expiry(self):
        grant = self.claim()
        with self.assertRaises(AgentTaskWriteConflict):
            self.leases.tasks.upsert(self.record())
        self.leases.tasks.upsert(self.record(), worker_lease=grant)
        snapshot = self.leases.tasks.get("task")
        self.now += 1000
        with self.assertRaises(AgentTaskWriteConflict):
            self.leases.tasks.upsert(snapshot, worker_lease=grant)

    def test_existing_local_execution_and_terminal_task_are_not_redispatched(self):
        self.leases.tasks.upsert(self.record())
        with self.assertRaisesRegex(WorkerLeaseConflict, "already dispatched"):
            self.claim()
        task = self.leases.tasks.get("task")
        task["status"] = "completed"
        self.leases.tasks.upsert(task)
        with self.assertRaisesRegex(WorkerLeaseConflict, "terminal"):
            self.claim()

    def test_existing_queued_task_is_claimed_without_changing_identity(self):
        self.leases.tasks.upsert(self.record(status="queued"))
        with self.assertRaises(WorkerLeaseConflict):
            self.claim(key=replace(self.key, app="other"))
        grant = self.claim()
        task = self.leases.tasks.get("task")
        task["status"] = "running"
        task["status_seq"] += 1
        self.assertTrue(self.leases.apply_task(grant, 1, task))

    def test_takeover_preserves_task_revision_and_rejects_previous_generation(self):
        old = self.claim()
        self.leases.apply_task(old, 1, self.record())
        self.now += 1000
        new = self.claim(key=replace(self.key, generation=2), worker_id="node-b",
                         expected_epoch=1, claim_id="claim-b")
        task = self.leases.tasks.get("task")
        task["execution_generation"] = 2
        task["status_seq"] = 2
        self.assertTrue(self.leases.apply_task(new, 1, task))
        with self.assertRaises(WorkerLeaseConflict):
            self.leases.apply_task(old, 2, self.record(status_seq=3, _storage_revision=2))
        self.assertEqual(2, self.leases.tasks.get("task")["execution_generation"])
        self.assertEqual(2, self.leases.tasks.get("task")["_storage_revision"])

    def test_tombstone_preserves_scope_and_epoch_after_revoke(self):
        self.claim()
        self.leases.revoke(self.key, expected_epoch=1)
        with self.assertRaises(WorkerLeaseConflict):
            self.claim(key=replace(self.key, app="other", generation=2),
                       claim_id="claim-b", expected_epoch=1)
        with self.assertRaises(WorkerLeaseConflict):
            self.claim(key=replace(self.key, generation=2), claim_id="claim-b", expected_epoch=0)

    def test_real_process_claims_have_one_winner(self):
        script = """
import json, sys
from pathlib import Path
from agent_run_kernel import AgentRunEventLedger
from agent_worker_leases import AgentWorkerLeaseLedger, WorkerLeaseConflict
from agent_work_pool import ExecutionKey
leases = AgentWorkerLeaseLedger(AgentRunEventLedger(Path(sys.argv[1])))
try:
    grant = leases.claim(ExecutionKey('app','conversation','turn','task',1), sys.argv[2],
        'process', expected_epoch=0, claim_id=sys.argv[2], ttl_ms=30000)
    print(json.dumps({'winner': sys.argv[2], 'epoch': grant.epoch}))
except WorkerLeaseConflict:
    print(json.dumps({'winner': None}))
"""

        def claim(worker):
            result = subprocess.run([sys.executable, "-c", script, str(self.path), worker],
                cwd=Path(__file__).parent, capture_output=True, text=True, timeout=30)
            self.assertEqual(0, result.returncode, result.stderr)
            return json.loads(result.stdout)

        with ThreadPoolExecutor(max_workers=4) as pool:
            outcomes = list(pool.map(claim, ("a", "b", "c", "d")))
        self.assertEqual(1, sum(item["winner"] is not None for item in outcomes))


if __name__ == "__main__":
    unittest.main()
