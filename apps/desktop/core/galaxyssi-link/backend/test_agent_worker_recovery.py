"""Read-only terminal receipts and restart-safe acknowledgement reconciliation."""
from copy import deepcopy
import hashlib
from types import SimpleNamespace
from unittest.mock import patch

from agent_worker_client_store import WorkerClientStore
from agent_worker_leases import WorkerLeaseConflict, _canonical
from agent_worker_local import WorkerExecutionFenced
from agent_worker_recovery import recover_worker_reports
from agent_worker_registry import WorkerAccessError
from agent_worker_rpc import AgentWorkerRpcClient
from test_agent_worker_local import LocalWorkerFixture
import test_agent_worker_protocol as protocol_tests
from agent_worker_protocol import AgentWorkerProtocol
from test_agent_worker_queue import record
from test_agent_worker_registry import WorkerFixture, peer


class ReceiptProtocolTest(WorkerFixture):
    payload = protocol_tests.WorkerProtocolTest.payload
    poll = protocol_tests.WorkerProtocolTest.poll
    report = protocol_tests.WorkerProtocolTest.report

    def setUp(self):
        super().setUp()
        self.enroll()
        self.connect()
        self.heartbeat()
        self.protocol = AgentWorkerProtocol(self.registry)
        self.protocol.queue.enqueue(record(), provider="codex", allowed_workers=["worker-a"])

    def receipt_query(self, lease, report=None):
        report = report or dict(status="completed", text="Final", error="", current_step="step")
        return dict(incarnation="boot-a", lease=lease, sequence=1,
            report_digest=hashlib.sha256(_canonical(report).encode()).hexdigest())

    def test_committed_receipt_survives_expiry_and_new_session_without_writes(self):
        lease = self.poll()["job"]["lease"]
        receipt = self.report(lease, status="completed", text="Final")
        self.connect(request_id="next-session", expected_session_epoch=1, incarnation="boot-b")
        task = self.protocol.queue.tasks.get("task-1")
        events = self.ledger.event_count()
        notifications = self.protocol.notifications()
        with patch("agent_worker_leases._clock_ms", return_value=lease["expires_at_ms"] + 100_000):
            value = self.protocol.receipt(self.peer, self.source, self.receipt_query(lease))
            self.assertEqual(dict(receipt, replayed=True), value["receipt"])
            with self.assertRaises(WorkerAccessError):
                self.report(lease, status="completed", text="Final")
        self.assertEqual(task, self.protocol.queue.tasks.get("task-1"))
        self.assertEqual(events, self.ledger.event_count())
        self.assertEqual(notifications, self.protocol.notifications())
        with self.ledger.transaction(write=False) as connection:
            self.assertEqual("revoked", self.protocol.queue.leases._row(connection, "task-1")["state"])

    def test_missing_receipt_is_not_accepted_or_written_after_expiry(self):
        lease = self.poll()["job"]["lease"]
        with patch("agent_worker_leases._clock_ms", return_value=lease["expires_at_ms"] + 1):
            self.assertEqual({"receipt": None}, self.protocol.receipt(self.peer, self.source, self.receipt_query(lease)))
            with self.assertRaises(WorkerLeaseConflict):
                self.report(lease, status="completed", text="Final")
        self.assertEqual("running", self.protocol.queue.tasks.get("task-1")["status"])

    def test_receipt_requires_original_five_part_identity_epoch_token_and_digest(self):
        lease = self.poll()["job"]["lease"]
        self.report(lease, status="completed", text="Final")
        query = self.receipt_query(lease)
        changed_queries = []
        for index in range(5):
            changed = deepcopy(query)
            changed["lease"]["key"][index] = 2 if index == 4 else "other"
            changed_queries.append(changed)
        for key, value in (("epoch", 2), ("token", "forged")):
            changed = deepcopy(query)
            changed["lease"][key] = value
            changed_queries.append(changed)
        changed_queries.extend([dict(query, incarnation="other"), dict(query, sequence=2), dict(query, report_digest="f" * 64)])
        for changed in changed_queries:
            with self.subTest(changed=changed), self.assertRaises(WorkerLeaseConflict):
                self.protocol.receipt(self.peer, self.source, changed)

    def test_revoked_or_changed_pair_or_other_worker_cannot_query_copied_receipt(self):
        lease = self.poll()["job"]["lease"]
        self.report(lease, status="completed", text="Final")
        query = self.receipt_query(lease)
        other = peer("other-route")
        self.registry.enroll(other, "other-worker", max_parallel=1, providers=["codex"])
        with self.assertRaises(WorkerLeaseConflict):
            self.protocol.receipt(other, other["signal_name"], query)
        with self.assertRaises(WorkerAccessError):
            self.protocol.receipt(dict(self.peer, link_secret="changed"), self.source, query)
        with self.assertRaises(WorkerAccessError):
            self.protocol.receipt(self.peer, "forged-source", query)
        self.registry.revoke(self.peer["client_route_id"])
        with self.assertRaises(WorkerAccessError):
            self.protocol.receipt(self.peer, self.source, query)


class WorkerReportRecoveryTest(LocalWorkerFixture):
    def setUp(self):
        super().setUp()
        self.store = WorkerClientStore(self.ledger)
        self.store.open(self.owner, "route-a", self.binding, dict(completed=0, failed=0))
        self.requests = []
        def send(peer, payload):
            self.requests.append(deepcopy(payload))
            operation = payload["type"].removeprefix("agent_worker_")
            self.assertEqual("receipt", operation, "Recovery must never poll, renew, report or execute")
            from agent_worker_mqtt import route_worker_payload
            bridge = SimpleNamespace(agent_task_manager=SimpleNamespace(_run_events=SimpleNamespace(ledger=self.ledger)),
                get_client=lambda route: self.peer, _worker_enrollment_registry=self.registry,
                _worker_execution_protocol=self.protocol,
                _publish_phone_payload=lambda mqttc, wire, response: self.rpc.receive(peer, self.source, response))
            route_worker_payload(bridge, object(), {}, payload, client_route_id="route-a", source_id=self.source)
            return True
        self.rpc = AgentWorkerRpcClient(lambda route: self.peer, send)
        self.addCleanup(self.rpc.close)

    def stage(self, task="task-1", committed=True):
        job, guard = self.grant(task)
        identifier = self.journal.admit(self.binding, self.owner, job)
        self.journal.begin(identifier, self.owner)
        report = dict(status="completed", text="Done " + task, error="", current_step="")
        self.journal.stage_report(identifier, self.owner, report)
        fields = dict(self.session, lease=job["lease"], sequence=1, report=report)
        self.store.intent(self.owner, "report:" + identifier, "report", fields)
        if committed:
            self.protocol.report(self.peer, self.source, fields)
        guard.invalidate()
        return identifier, job, fields

    def stop_marker(self):
        self.store.close(self.owner, clean=False, checkpoint=dict(completed=0, failed=0))

    def recover(self):
        return recover_worker_reports(self.ledger, self.rpc, lambda route: self.peer, "route-a")

    def test_stopped_owner_recovers_committed_result_after_lease_expiry(self):
        identifier, job, _ = self.stage()
        self.stop_marker()
        with patch("agent_worker_leases._clock_ms", return_value=job["lease"]["expires_at_ms"] + 100_000):
            self.assertTrue(self.recover())
        self.assertEqual("confirmed", self.journal.get(identifier)["state"])
        self.assertEqual("closed", self.store.read()["state"])
        self.assertEqual(1, self.store.read()["checkpoint"]["completed"])
        self.store.open("new-boot", "route-a", self.binding, {})

    def test_missing_remote_receipt_retains_fence_and_never_submits_result(self):
        identifier, _, _ = self.stage(committed=False)
        self.stop_marker()
        self.assertFalse(self.recover())
        self.assertEqual("reporting", self.journal.get(identifier)["state"])
        self.assertEqual("recovery_required", self.store.read()["state"])
        self.assertEqual("running", self.protocol.queue.tasks.get("task-1")["status"])

    def test_crash_between_confirmation_and_intent_cleanup_retries_read_without_double_count(self):
        identifier, _, _ = self.stage()
        self.stop_marker()
        with patch.object(WorkerClientStore, "settle_recovered_report", side_effect=RuntimeError("disk failure")):
            with self.assertRaises(RuntimeError):
                self.recover()
        self.assertEqual("confirmed", self.journal.get(identifier)["state"])
        self.assertTrue(self.recover())
        self.assertEqual(1, self.store.read()["checkpoint"]["completed"])
        self.assertEqual(self.requests[0]["request_id"], self.requests[1]["request_id"])
        self.assertNotEqual(self.requests[0]["attempt_id"], self.requests[1]["attempt_id"])

    def test_unresolved_poll_or_unfinished_job_prevents_clean_restart(self):
        self.stage()
        self.store.intent(self.owner, "poll", "poll", dict(self.session, sequence=2))
        self.stop_marker()
        self.assertFalse(self.recover())
        self.assertEqual("recovery_required", self.store.read()["state"])

    def test_open_owner_or_changed_pair_is_not_automatically_recovered(self):
        self.stage()
        with self.assertRaisesRegex(WorkerExecutionFenced, "recovery_required"):
            self.recover()
        self.stop_marker()
        self.peer["link_secret"] = "changed"
        with self.assertRaisesRegex(WorkerExecutionFenced, "recovery_required"):
            self.recover()
        self.assertEqual([], self.requests)

    def test_unfinished_local_execution_still_blocks_after_other_report_recovers(self):
        identifier, _, _ = self.stage()
        job, guard = self.grant("unfinished")
        unfinished = self.journal.admit(self.binding, self.owner, job)
        self.journal.begin(unfinished, self.owner)
        guard.invalidate()
        self.stop_marker()
        self.assertFalse(self.recover())
        self.assertEqual("confirmed", self.journal.get(identifier)["state"])
        self.assertEqual("dispatched", self.journal.get(unfinished)["state"])

    def test_receipt_query_intent_can_recover_without_original_report_intent(self):
        identifier, _, fields = self.stage()
        query = dict(incarnation=self.owner, lease=fields["lease"], sequence=1,
            report_digest=hashlib.sha256(_canonical(fields["report"]).encode()).hexdigest())
        self.store.intent(self.owner, "receipt:" + identifier, "receipt", query)
        self.store.consume(self.owner, "report:" + identifier, dict(completed=0, failed=0))
        self.stop_marker()
        self.assertTrue(self.recover())
        self.assertEqual("confirmed", self.journal.get(identifier)["state"])

    def test_receipt_transport_timeout_leaves_state_and_retries_read_only(self):
        from agent_worker_rpc import WorkerRpcError
        identifier, _, _ = self.stage()
        self.stop_marker()
        with patch.object(self.rpc, "request", side_effect=WorkerRpcError("worker_rpc_timeout")):
            self.assertFalse(self.recover())
        self.assertEqual("reporting", self.journal.get(identifier)["state"])
        self.assertTrue(self.recover())

    def test_stale_owner_cannot_finish_recovery_or_confirm_other_turn(self):
        identifier, _, _ = self.stage()
        self.stop_marker()
        with self.assertRaises(WorkerExecutionFenced):
            self.store.finish_report_recovery("other-owner", "route-a", self.binding)
        with self.ledger.transaction() as connection:
            connection.execute("UPDATE agent_worker_client_intents SET slot=? WHERE operation='report'", ("report:" + "a" * 64,))
        with self.assertRaisesRegex(WorkerExecutionFenced, "record_mismatch"):
            self.recover()
        self.assertEqual("reporting", self.journal.get(identifier)["state"])
        self.assertEqual([], self.requests)
