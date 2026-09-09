"""Real OS ownership, hard parent exit and scoped worker recovery fences."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import unittest
from unittest.mock import Mock, patch

from agent_worker_client_store import WorkerClientStore
from agent_worker_local import WorkerExecutionFenced
from agent_worker_ownership import WorkerClientOwnership
from agent_worker_recovery import recover_worker_reports
from agent_worker_rpc import WorkerRpcResult
from process_recovery_journal import task_journal
from test_agent_worker_local import LocalWorkerFixture


class WorkerOwnershipTest(LocalWorkerFixture):
    def setUp(self):
        super().setUp()
        self.root = self.ledger.path.parent / "worker-executions"
        self.store = WorkerClientStore(self.ledger)
        self.checkpoint = dict(process_ownership_version=1, execution_root=str(self.root.resolve()), completed=0, failed=0)
        self.rpc = Mock()
        def query(route, operation, fields, **_):
            self.assertEqual("receipt", operation)
            start = time.monotonic()
            payload = self.protocol.receipt(self.peer, self.source, fields)
            return WorkerRpcResult(dict(ok=True, **payload), start, time.monotonic())
        self.rpc.request.side_effect = query

    def recover(self):
        return recover_worker_reports(self.ledger, self.rpc, lambda route: self.peer, "route-a", execution_root=self.root)

    def test_live_os_owner_cannot_be_recovered_even_with_an_old_open_marker(self):
        owner = WorkerClientOwnership(self.ledger).acquire()
        self.addCleanup(owner.release)
        self.store.open(self.owner, "route-a", self.binding, self.checkpoint)
        with self.assertRaisesRegex(WorkerExecutionFenced, "owner_unavailable"):
            self.recover()
        self.rpc.request.assert_not_called()
        self.assertEqual("open", self.store.read()["state"])

    def test_empty_authenticated_poll_can_be_retired_after_exclusive_ownership(self):
        self.store.open(self.owner, "route-a", self.binding, self.checkpoint)
        self.store.intent(self.owner, "poll", "poll", dict(sequence=1))
        self.store.received(self.owner, "poll", dict(ok=True, job=None))
        self.assertTrue(self.recover())
        self.assertEqual("closed", self.store.read()["state"])
        self.rpc.request.assert_not_called()

    def test_ambiguous_poll_is_not_cleared_by_reacquiring_the_os_lock(self):
        self.store.open(self.owner, "route-a", self.binding, self.checkpoint)
        self.store.intent(self.owner, "poll", "poll", dict(sequence=1))
        self.assertFalse(self.recover())
        self.assertEqual(1, self.store.read()["pending"])
        self.assertEqual("recovery_required", self.store.read()["state"])

    def test_legacy_or_wrong_root_marker_never_proves_owner_termination(self):
        self.store.open(self.owner, "route-a", self.binding, dict(self.checkpoint, execution_root=str(self.root / "other")))
        with self.assertRaises(WorkerExecutionFenced):
            self.recover()
        self.assertEqual("open", self.store.read()["state"])

    def test_recovery_marker_still_requires_process_termination_proof(self):
        from process_recovery_journal import ProcessTerminationPending
        self.store.open(self.owner, "route-a", self.binding, self.checkpoint)
        job, _ = self.grant()
        identifier = self.journal.admit(self.binding, self.owner, job)
        self.journal.begin(identifier, self.owner)
        self.store.close(self.owner, clean=False, checkpoint=self.checkpoint)
        with patch("process_recovery_journal.assert_quiescent", side_effect=ProcessTerminationPending("still running")) as check:
            with self.assertRaisesRegex(WorkerExecutionFenced, "processes_unverified"):
                self.recover()
        check.assert_called_once_with(task_journal(self.root, identifier).resolve())
        self.assertEqual("dispatched", self.journal.get(identifier)["state"])
        self.rpc.request.assert_not_called()

    def test_ownership_directory_failure_is_a_bounded_fence(self):
        owner = WorkerClientOwnership(self.ledger)
        with patch.object(Path, "mkdir", side_effect=PermissionError("private path")):
            with self.assertRaisesRegex(WorkerExecutionFenced, "^worker_client_owner_unavailable$"):
                owner.acquire()
        with self.assertRaises(WorkerExecutionFenced):
            owner.require(self.ledger)

    def test_torn_process_journal_blocks_recovery_without_discarding_evidence(self):
        self.store.open(self.owner, "route-a", self.binding, self.checkpoint)
        job, _ = self.grant()
        identifier = self.journal.admit(self.binding, self.owner, job)
        self.journal.begin(identifier, self.owner)
        directory = task_journal(self.root, identifier)
        directory.mkdir(parents=True)
        record = directory / ("a" * 32 + ".json")
        record.write_text('{"version":', encoding="ascii")
        with self.assertRaisesRegex(WorkerExecutionFenced, "processes_unverified"):
            self.recover()
        self.assertTrue(record.exists())
        self.assertEqual("open", self.store.read()["state"])
        self.assertEqual("dispatched", self.journal.get(identifier)["state"])
        self.rpc.request.assert_not_called()

    def test_released_handle_permits_new_owner_without_removing_lock_file(self):
        first = WorkerClientOwnership(self.ledger).acquire()
        path = first.path
        first.require(self.ledger)
        first.release()
        with self.assertRaises(WorkerExecutionFenced):
            first.require(self.ledger)
        self.assertTrue(path.exists())
        second = WorkerClientOwnership(self.ledger).acquire()
        self.addCleanup(second.release)
        second.require(self.ledger)


HOST = r'''
import json, os, sys, time
from pathlib import Path
from unittest.mock import patch
from agent_run_kernel import AgentRunEventLedger
from agent_worker_client_store import WorkerClientStore
from agent_worker_local import WorkerExecutionJournal, WorkerLeaseGuard
from agent_worker_ownership import WorkerClientOwnership
from agent_worker_execution import WorkerProcessExecutor
from agent_worker_rpc import WorkerRpcResult
import owned_process

value = json.loads(sys.argv[1])
ledger = AgentRunEventLedger(Path(value["ledger"]))
owner = WorkerClientOwnership(ledger).acquire()
root = Path(value["root"])
store = WorkerClientStore(ledger)
store.open("boot-a", "route-a", value["binding"], dict(process_ownership_version=1,
    execution_root=str(root.resolve()), completed=0, failed=0))
journal = WorkerExecutionJournal(ledger)
job = value["job"]
identifier = journal.admit(value["binding"], "boot-a", job)
if value["mode"] == "report":
    journal.begin(identifier, "boot-a")
    journal.stage_report(identifier, "boot-a", value["fields"]["report"])
    store.intent("boot-a", "report:" + identifier, "report", value["fields"])
    pending = Path(value["ready"] + ".tmp")
    pending.write_text(identifier, encoding="ascii")
    os.replace(pending, value["ready"])
    sys.stdin.buffer.read(1)
    os._exit(23)
else:
    executor = WorkerProcessExecutor(journal, root, max_workers=1)
    start = time.monotonic()
    guard = WorkerLeaseGuard(WorkerRpcResult(dict(ok=True, job=job,
        server_time_ms=job["lease"]["expires_at_ms"]-30000), start, start))
    original = owned_process.popen
    code = "import os,subprocess,sys,time; from pathlib import Path; subprocess.Popen([sys.executable,'-c','import time; time.sleep(120)']); pending=Path(sys.argv[1]+'.tmp'); pending.write_text('started',encoding='ascii'); os.replace(pending,sys.argv[1]); time.sleep(120)"
    def popen(argv, **kwargs):
        return original([sys.executable, "-c", code, value["ready"]], **kwargs)
    with patch.object(owned_process, "popen", side_effect=popen):
        executor.submit(value["binding"], "boot-a", job, guard)
        sys.stdin.buffer.read(1)
        os._exit(23)
'''


@unittest.skipUnless(os.name == "nt", "Windows owned child-tree recovery")
class WorkerHardExitTest(LocalWorkerFixture):
    def host(self, mode, job, fields=None):
        from owned_process import owned_process_scope, popen
        self.root = self.ledger.path.parent / "worker-executions"
        self.ready = self.ledger.path.parent / "ready"
        value = dict(mode=mode, ledger=str(self.ledger.path), root=str(self.root), ready=str(self.ready),
            binding=self.binding, job=job, fields=fields)
        with owned_process_scope():
            host = popen([sys.executable, "-c", HOST, json.dumps(value)], cwd=str(Path(__file__).parent),
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                creationflags=subprocess.CREATE_NO_WINDOW)
        self.addCleanup(host.close)
        deadline = time.monotonic() + 15
        while not self.ready.exists() and host.poll() is None and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(self.ready.exists(), "Owned fixture did not reach its durable checkpoint")
        return host

    def test_hard_exit_releases_os_lock_and_recovers_committed_receipt(self):
        job, _ = self.grant()
        report = dict(status="completed", text="already committed", error="", current_step="")
        fields = dict(self.session, lease=job["lease"], sequence=1, report=report)
        self.protocol.report(self.peer, self.source, fields)
        host = self.host("report", job, fields)
        with self.assertRaises(WorkerExecutionFenced):
            WorkerClientOwnership(self.ledger).acquire()
        _, error = host.communicate(input=b"x", timeout=15)
        self.assertEqual(23, host.returncode, error.decode(errors="replace"))
        rpc = Mock()
        def query(route, operation, payload, **_):
            self.assertEqual("receipt", operation)
            start = time.monotonic()
            return WorkerRpcResult(dict(ok=True, **self.protocol.receipt(self.peer, self.source, payload)), start, time.monotonic())
        rpc.request.side_effect = query
        self.assertTrue(recover_worker_reports(self.ledger, rpc, lambda route: self.peer, "route-a", execution_root=self.root))
        self.assertEqual("closed", WorkerClientStore(self.ledger).read()["state"])
        self.assertEqual("confirmed", self.journal.get(self.ready.read_text())["state"])

    def test_hard_exit_stops_owned_children_but_does_not_replay_unknown_execution(self):
        from windows_process_job import active_processes
        job, _ = self.grant()
        host = self.host("running", job)
        identifier = self.journal.admit(self.binding, self.owner, job)
        directory = task_journal(self.root, identifier)
        names = [json.loads(path.read_text())["job"] for path in directory.glob("*.json")]
        self.assertTrue(names)
        self.assertTrue(any(active_processes(name) > 0 for name in names))
        _, error = host.communicate(input=b"x", timeout=15)
        self.assertEqual(23, host.returncode, error.decode(errors="replace"))
        deadline = time.monotonic() + 10
        while any(active_processes(name) > 0 for name in names) and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(all(active_processes(name) == 0 for name in names))
        rpc = Mock()
        self.assertFalse(recover_worker_reports(self.ledger, rpc, lambda route: self.peer, "route-a", execution_root=self.root))
        self.assertEqual("uncertain", self.journal.get(identifier)["state"])
        self.assertFalse(self.journal.begin(identifier, "new-owner"))
        self.assertEqual("started", self.ready.read_text())
        rpc.request.assert_not_called()
