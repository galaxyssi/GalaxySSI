"""Local task managers observe leased work without becoming its executor."""
from dataclasses import replace
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

from agent_run_kernel import AgentRunEventLedger
from agent_task_manager import AgentTaskManager
from agent_task_store import AgentTaskStore
from agent_worker_leases import AgentWorkerLeaseLedger
from agent_work_pool import ExecutionKey


class WorkerLeaseRecoveryTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / "tasks.db"
        self.leases = AgentWorkerLeaseLedger(AgentRunEventLedger(self.path))
        self.key = ExecutionKey("app", "conversation", "turn", "remote", 1)

    def manager(self):
        manager = AgentTaskManager(state_path=self.path)
        self.addCleanup(manager._work_pool.close)
        self.addCleanup(manager._control_work_pool.close)
        return manager

    def seed(self, *, status="running"):
        grant = self.leases.claim(self.key, "node", "process", expected_epoch=0, claim_id="claim")
        self.leases.apply_task(grant, 1, self.record(status=status))
        return grant

    def record(self, **changes):
        record = dict(task_id="remote", agent_id="codex", client_route_id="app",
            conversation_id="conversation", client_conversation_id="conversation",
            client_turn_id="turn", source_message_id="source", execution_generation=1,
            status="running", status_seq=1, result="", created_at=1000, updated_at=1000)
        record.update(changes)
        return record

    def test_restart_preserves_lease_task_and_recovers_local_queue(self):
        self.seed()
        local = self.record(task_id="local", status="queued", client_turn_id="local-turn")
        self.leases.tasks.upsert(local)
        before = self.leases.tasks.get("remote")
        manager = self.manager()
        self.assertEqual(before, self.leases.tasks.get("remote"))
        self.assertEqual({"local"}, manager._recovered_task_ids)
        self.assertEqual(1, manager.get("remote").execution_generation)
        self.assertEqual(2, manager.get("local").execution_generation)
        self.assertTrue(manager.get("remote").storage_fenced)
        self.assertEqual(0, manager.scheduling_status()["active"])

    def test_expired_or_revoked_lease_is_not_automatically_adopted_locally(self):
        for state in ("expired", "revoked"):
            with self.subTest(state=state):
                task_id = "remote-" + state
                key = replace(self.key, task=task_id)
                grant = self.leases.claim(key, "node", "process", expected_epoch=0, claim_id=state)
                self.leases.apply_task(grant, 1, self.record(task_id=task_id))
                if state == "revoked":
                    self.leases.revoke(key, expected_epoch=1)
                else:
                    with self.leases.ledger.transaction() as connection:
                        connection.execute("UPDATE agent_worker_leases SET expires_at_ms=0 WHERE task_id=?", (task_id,))
                before = self.leases.tasks.get(task_id)
                manager = self.manager()
                self.assertEqual(before, self.leases.tasks.get(task_id))
                self.assertNotIn(task_id, manager._recovered_task_ids)

    def test_paused_remote_task_remains_unchanged(self):
        self.seed(status="paused")
        before = self.leases.tasks.get("remote")
        count = self.leases.ledger.event_count()
        manager = self.manager()
        self.assertEqual(before, self.leases.tasks.get("remote"))
        self.assertEqual(count, self.leases.ledger.event_count())
        self.assertEqual("paused", manager.get("remote").status)

    def test_every_public_read_refreshes_committed_remote_progress(self):
        grant = self.seed()
        manager = self.manager()
        old = manager.get("remote")
        updated = self.leases.tasks.get("remote")
        updated.update(status="completed", status_seq=2, result="new result")
        self.leases.apply_task(grant, 2, updated)
        self.assertEqual("new result", manager.get("remote").result)
        self.assertEqual("completed", manager.list()[0]["status"])
        self.assertEqual("completed", manager.public_preview("remote")["status"])
        self.assertTrue(old.storage_fenced)
        self.assertTrue(manager.get(" remote ").storage_fenced)
        self.assertFalse(manager.is_current_execution(self.key))
        public = json.dumps(manager.list())
        self.assertNotIn(grant.token, public)
        self.assertNotIn("storage_fenced", public)

    def test_local_cancellation_does_not_claim_to_cancel_remote_work(self):
        self.seed()
        manager = self.manager()
        before = self.leases.tasks.get("remote")
        callback = Mock()
        self.assertIsNone(manager.cancel("remote", callback))
        self.assertEqual(before, self.leases.tasks.get("remote"))
        callback.assert_not_called()

    def test_local_controls_do_not_resume_or_take_over_a_worker_task(self):
        self.seed(status="paused")
        manager = self.manager()
        before = self.leases.tasks.get("remote")
        callback, runner = Mock(), Mock()
        controls = [lambda: manager.pause("remote", on_event=callback),
                    lambda: manager.begin_takeover("remote", {}, on_event=callback),
                    lambda: manager.release_takeover("remote", on_event=callback),
                    lambda: manager.continue_task("remote", runner, callback),
                    lambda: manager.resume("remote", runner, callback),
                    lambda: manager.resume_external("remote", callback)]
        for index, control in enumerate(controls):
            with self.subTest(control=index):
                self.assertIsNone(control())
        manager.retain_recovered("remote")
        self.assertNotIn("remote", manager._recovered_task_ids)
        self.assertEqual(before, self.leases.tasks.get("remote"))
        callback.assert_not_called()
        runner.assert_not_called()

    def test_claim_during_startup_scan_does_not_crash_or_duplicate_recovery(self):
        self.leases.tasks.upsert(self.record(status="queued"))
        before = self.leases.tasks.get("remote")
        original = AgentTaskStore.worker_owned_ids
        claimed = False

        def scan(store, task_ids):
            nonlocal claimed
            task_ids = list(task_ids)
            if "remote" in task_ids and not claimed:
                claimed = True
                self.leases.claim(self.key, "node", "process", expected_epoch=0, claim_id="race")
                return set()
            return original(store, task_ids)

        count = self.leases.ledger.event_count()
        with patch.object(AgentTaskStore, "worker_owned_ids", scan):
            manager = self.manager()
        self.assertTrue(claimed)
        self.assertEqual(before, self.leases.tasks.get("remote"))
        self.assertEqual(count, self.leases.ledger.event_count())
        self.assertNotIn("remote", manager._recovered_task_ids)

    def test_reconstructed_real_manager_process_only_observes_leased_task(self):
        self.seed()
        before = self.leases.tasks.get("remote")
        script = """
import json, sys
from pathlib import Path
from agent_task_manager import AgentTaskManager
m = AgentTaskManager(state_path=Path(sys.argv[1]))
t = m.get('remote')
print(json.dumps({'generation': t.execution_generation, 'fenced': t.storage_fenced,
                  'recovered': sorted(m._recovered_task_ids), 'active': m.scheduling_status()['active']}))
"""
        result = subprocess.run([sys.executable, "-c", script, str(self.path)],
            cwd=Path(__file__).parent, capture_output=True, text=True, timeout=30)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(dict(generation=1, fenced=True, recovered=[], active=0), json.loads(result.stdout))
        self.assertEqual(before, self.leases.tasks.get("remote"))
