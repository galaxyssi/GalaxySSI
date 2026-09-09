"""Persistent dispatch ownership, capacity and App/conversation fairness."""
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
import json
from pathlib import Path
import subprocess
import sys
import threading
import time
from unittest.mock import patch

from agent_run_kernel import AgentRunEventLedger, AgentRunIdentityConflict
from agent_task_store import AgentTaskWriteConflict
from agent_work_pool import ExecutionKey
from agent_worker_leases import WorkerLeaseConflict
from agent_worker_queue import AgentWorkerQueue
from agent_worker_registry import AgentWorkerRegistry, WorkerAccessError
from test_agent_worker_registry import WorkerFixture, peer


def record(task="task-1", app="app-a", conversation="chat-a", **changes):
    now = time.time_ns() // 1_000_000
    snapshot = dict(task_id=task, client_route_id=app, client_conversation_id=conversation,
        conversation_id=conversation, client_turn_id="turn-" + task, source_message_id="message-" + task,
        execution_generation=1, status="queued", status_seq=0, created_at=now, updated_at=now,
        result="", prompt="Private fixture " + task, agent_id="codex", contact_id="contact-a",
        execution_checkpoint={"dispatch_started": False})
    snapshot.update(changes)
    return snapshot


def poll_process(path, paired, payload):
    script = """
import json, sys
from pathlib import Path
from agent_run_kernel import AgentRunEventLedger
from agent_worker_registry import AgentWorkerRegistry
from agent_worker_queue import AgentWorkerQueue
queue = AgentWorkerQueue(AgentWorkerRegistry(AgentRunEventLedger(Path(sys.argv[1]))))
peer = json.loads(sys.argv[2])
job = queue.poll(peer, peer['signal_name'], json.loads(sys.argv[3]))
print(json.dumps([job.lease.key.task, job.lease.epoch, job.record['_storage_revision']] if job else None))
"""
    result = subprocess.run([sys.executable, "-c", script, str(path), json.dumps(paired), json.dumps(payload)],
        capture_output=True, text=True, timeout=30, check=True)
    return json.loads(result.stdout.strip())


class WorkerQueueTest(WorkerFixture):
    def setUp(self):
        super().setUp()
        self.enroll()
        self.connect()
        self.heartbeat(available_slots=10)
        self.queue = AgentWorkerQueue(self.registry)

    def enqueue(self, snapshot=None, **changes):
        return self.queue.enqueue(snapshot or record(), provider="codex", allowed_workers=["worker-a"], **changes)

    def poll(self, sequence=1, **changes):
        payload = dict(sequence=sequence, request_id="poll-" + str(sequence), incarnation="boot-a", session_epoch=1)
        payload.update(changes)
        return self.queue.poll(self.peer, self.source, payload)

    def complete(self, dispatch):
        snapshot = {**dispatch.record, "status": "completed", "status_seq": dispatch.record["status_seq"] + 1,
                    "result": "Completed " + dispatch.lease.key.task}
        self.assertTrue(self.queue.apply_task(dispatch.lease, 1, snapshot))
        return snapshot

    def test_admission_is_idempotent_and_reserves_before_a_worker_claims(self):
        snapshot = record()
        self.assertTrue(self.enqueue(snapshot))
        self.assertFalse(self.enqueue(snapshot))
        self.assertEqual({"task-1"}, self.queue.tasks.worker_owned_ids(["task-1"]))
        with self.ledger.transaction(write=False) as connection:
            self.assertEqual(0, connection.execute("SELECT count(*) FROM agent_worker_leases").fetchone()[0])
        with self.assertRaises(AgentTaskWriteConflict):
            self.queue.tasks.upsert(self.queue.tasks.get("task-1"))
        with self.assertRaises(WorkerLeaseConflict):
            self.enqueue({**snapshot, "client_turn_id": "other-turn"})
        self.assertEqual(snapshot["prompt"], self.queue.tasks.get("task-1")["prompt"])

    def test_new_task_only_and_targets_need_explicit_provider_authorization(self):
        for changes in ({"status": "running"}, {"execution_checkpoint": {"dispatch_started": True}},
                        {"_storage_revision": 1}):
            with self.subTest(changes=changes), self.assertRaises(WorkerLeaseConflict):
                self.enqueue(record(**changes))
        for targets in ([], ["stranger"], ["worker-a", "stranger"]):
            with self.subTest(targets=targets), self.assertRaises(WorkerAccessError):
                self.queue.enqueue(record(), provider="codex", allowed_workers=targets)
        with self.assertRaises(WorkerAccessError):
            self.queue.enqueue(record(), provider="unapproved", allowed_workers=["worker-a"])
        self.queue.tasks.upsert(record())
        with self.assertRaises(WorkerLeaseConflict):
            self.enqueue()

    def test_capacity_bound_is_atomic_and_does_not_count_waiting_tasks_as_workers(self):
        self.queue = AgentWorkerQueue(self.registry, max_pending=2)
        one = record("one")
        self.enqueue(one)
        self.enqueue(record("two"))
        self.assertFalse(self.enqueue(one))
        with self.assertRaisesRegex(WorkerAccessError, "queue_full"):
            self.enqueue(record("three"))
        self.assertIsNotNone(self.poll())
        self.assertTrue(self.enqueue(record("three")))

    def test_poll_replay_after_coordinator_restart_preserves_every_identity_dimension(self):
        snapshot = record()
        self.enqueue(snapshot)
        first = self.poll()
        self.queue = AgentWorkerQueue(AgentWorkerRegistry(AgentRunEventLedger(self.ledger.path)))
        replay = self.poll()
        self.assertEqual(first, replay)
        self.assertEqual(("app-a", "chat-a", "turn-task-1", "task-1", 1),
                         tuple(getattr(first.lease.key, field) for field in ("app", "conversation", "turn", "task", "generation")))
        self.assertEqual(snapshot["source_message_id"], first.record["source_message_id"])
        self.assertEqual(2, first.record["_storage_revision"])
        self.assertTrue(first.record["execution_checkpoint"]["dispatch_started"])
        self.assertGreaterEqual(first.record["updated_at"], snapshot["updated_at"])
        self.assertNotIn(first.lease.token, json.dumps(first.record))
        self.assertNotIn(snapshot["prompt"], repr(first))
        with self.assertRaises(WorkerAccessError):
            self.poll(request_id="changed")
        with self.assertRaises(WorkerAccessError):
            self.poll(sequence=3)

    def test_empty_poll_is_idempotent_but_new_sequence_can_receive_new_work(self):
        self.assertIsNone(self.poll())
        self.enqueue()
        self.assertIsNone(self.poll())
        self.assertEqual("task-1", self.poll(2).lease.key.task)

    def test_one_advertised_slot_cannot_be_consumed_twice_before_next_heartbeat(self):
        self.heartbeat(sequence=2, available_slots=1)
        self.enqueue(record("one"))
        self.enqueue(record("two"))
        self.assertIsNotNone(self.poll())
        self.assertIsNone(self.poll(2))
        self.heartbeat(sequence=3, available_slots=1)
        self.assertEqual("two", self.poll(3).lease.key.task)

    def test_durable_capacity_wins_over_worker_overreporting_free_slots(self):
        self.registry.enroll(self.peer, "worker-a", max_parallel=1, providers=["codex"])
        self.connect(request_id="new-connect", expected_session_epoch=2)
        self.heartbeat(session_epoch=3, available_slots=1)
        self.enqueue(record("one"))
        self.enqueue(record("two"))
        self.assertIsNotNone(self.poll(session_epoch=3))
        self.heartbeat(session_epoch=3, sequence=2, available_slots=1)
        self.assertIsNone(self.poll(2, session_epoch=3))

    def test_expired_lease_does_not_silently_release_unconfirmed_execution_capacity(self):
        self.registry.enroll(self.peer, "worker-a", max_parallel=1, providers=["codex"])
        self.connect(request_id="new-connect", expected_session_epoch=2)
        self.heartbeat(session_epoch=3, available_slots=1)
        self.enqueue(record("one"))
        self.enqueue(record("two"))
        first = self.poll(session_epoch=3)
        with patch("agent_worker_leases._clock_ms", return_value=first.lease.expires_at_ms + 1):
            with self.assertRaises(WorkerLeaseConflict):
                self.poll(session_epoch=3)
            self.heartbeat(session_epoch=3, sequence=2, available_slots=1)
            self.assertIsNone(self.poll(2, session_epoch=3))

    def test_capacity_includes_worker_leases_created_outside_queue(self):
        self.registry.enroll(self.peer, "worker-a", max_parallel=1, providers=["codex"])
        self.connect(request_id="new-connect", expected_session_epoch=2)
        self.heartbeat(session_epoch=3, available_slots=1)
        self.queue.leases.claim(ExecutionKey("other-app", "other-chat", "other-turn", "other-task", 1),
            "worker-a", "boot-a", expected_epoch=0, claim_id="external")
        self.enqueue()
        self.assertIsNone(self.poll(session_epoch=3))

    def test_completion_releases_the_only_slot_for_next_task(self):
        self.registry.enroll(self.peer, "worker-a", max_parallel=1, providers=["codex"])
        self.connect(request_id="new-connect", expected_session_epoch=2)
        self.heartbeat(session_epoch=3, available_slots=1)
        self.enqueue(record("one"))
        self.enqueue(record("two"))
        first = self.poll(session_epoch=3)
        self.assertIsNone(self.poll(2, session_epoch=3))
        self.complete(first)
        self.assertEqual("two", self.poll(3, session_epoch=3).lease.key.task)

    def test_fairness_round_robins_apps_then_conversations_then_fifo_across_restart(self):
        for task, app, chat in (("a1", "a", "a-chat-1"), ("a2", "a", "a-chat-1"),
                                ("a3", "a", "a-chat-2"), ("b1", "b", "b-chat"), ("b2", "b", "b-chat")):
            self.enqueue(record(task, app, chat))
        actual = []
        for sequence in range(1, 6):
            self.queue = AgentWorkerQueue(AgentWorkerRegistry(AgentRunEventLedger(self.ledger.path)))
            dispatch = self.poll(sequence)
            actual.append(dispatch.lease.key.task)
            self.complete(dispatch)
        self.assertEqual(["a1", "b1", "a3", "b2", "a2"], actual)

    def test_workers_only_receive_targeted_tasks_with_offered_providers(self):
        other = peer("route-b")
        self.registry.enroll(other, "worker-b", max_parallel=1, providers=["codex"])
        self.registry.connect(other, other["signal_name"], dict(incarnation="boot-b", request_id="b-connect",
            expected_session_epoch=0, providers=["codex"]))
        self.registry.heartbeat(other, other["signal_name"], dict(incarnation="boot-b", session_epoch=1,
            sequence=1, available_slots=1))
        self.queue.enqueue(record("private-b"), provider="codex", allowed_workers=["worker-b"])
        self.queue.enqueue(record("deepseek"), provider="deepseek", allowed_workers=["worker-a"])
        self.assertIsNone(self.poll())
        granted = self.queue.poll(other, other["signal_name"], dict(sequence=1, request_id="b-poll",
            incarnation="boot-b", session_epoch=1))
        self.assertEqual("private-b", granted.lease.key.task)

    def test_revoked_stale_forged_and_silent_workers_get_no_task(self):
        self.enqueue()
        with self.assertRaises(WorkerAccessError):
            self.queue.poll(self.peer, "forged", dict(sequence=1, request_id="poll", incarnation="boot-a", session_epoch=1))
        with self.assertRaises(WorkerAccessError):
            self.poll(incarnation="other")
        with patch("agent_worker_registry.time.time_ns", return_value=time.time_ns() + 31_000_000_000):
            with self.assertRaises(WorkerAccessError):
                self.poll()
        self.registry.revoke(self.peer["client_route_id"])
        with self.assertRaises(WorkerAccessError):
            self.poll()
        self.assertEqual("queued", self.queue.tasks.get("task-1")["status"])

    def test_dispatch_failure_rolls_back_lease_checkpoint_fairness_and_receipt(self):
        self.enqueue()
        events = self.ledger.event_count()
        with patch.object(self.queue.tasks, "upsert", side_effect=RuntimeError("disk failure")):
            with self.assertRaisesRegex(RuntimeError, "disk failure"):
                self.poll()
        self.assertEqual(events, self.ledger.event_count())
        self.assertEqual("queued", self.queue.tasks.get("task-1")["status"])
        with self.ledger.transaction(write=False) as connection:
            for table in ("agent_worker_leases", "agent_worker_queue_polls", "agent_worker_queue_fair"):
                self.assertEqual(0, connection.execute("SELECT count(*) FROM " + table).fetchone()[0])
        self.assertIsNotNone(self.poll())

    def test_terminal_result_and_capacity_release_are_atomic_and_replayable(self):
        self.enqueue()
        dispatch = self.poll()
        snapshot = {**dispatch.record, "status": "completed", "status_seq": 2, "result": "x" * 20000}
        with patch.object(self.queue.leases.tasks, "upsert", side_effect=RuntimeError("disk full")):
            with self.assertRaises(RuntimeError):
                self.queue.apply_task(dispatch.lease, 1, snapshot)
        self.assertEqual("running", self.queue.tasks.get("task-1")["status"])
        self.assertTrue(self.queue.apply_task(dispatch.lease, 1, snapshot))
        self.assertFalse(self.queue.apply_task(dispatch.lease, 1, snapshot))
        self.assertEqual(snapshot["result"], self.queue.tasks.get("task-1")["result"])
        with self.assertRaises(WorkerLeaseConflict):
            self.queue.apply_task(dispatch.lease, 2, {**snapshot, "status": "running", "_storage_revision": 3})
        with self.assertRaises(WorkerLeaseConflict):
            self.poll()

    def test_result_rejects_every_cross_task_identity_and_old_execution_capability(self):
        self.enqueue()
        dispatch = self.poll()
        for name, value in (("client_route_id", "app-b"), ("client_conversation_id", "chat-b"),
                            ("client_turn_id", "turn-b"), ("task_id", "task-b"), ("execution_generation", 2)):
            with self.subTest(name=name), self.assertRaises(WorkerLeaseConflict):
                self.queue.apply_task(dispatch.lease, 1, {**dispatch.record, name: value})
        with self.assertRaises((AgentTaskWriteConflict, AgentRunIdentityConflict)):
            self.queue.apply_task(dispatch.lease, 1, {**dispatch.record, "source_message_id": "other-source"})
        for name in ("contact_id", "agent_id", "prompt", "request_snapshot", "attachments", "execution_policy"):
            with self.subTest(name=name), self.assertRaises(AgentTaskWriteConflict):
                self.queue.apply_task(dispatch.lease, 1, {**dispatch.record, name: "other-request"})
        with self.assertRaises(WorkerLeaseConflict):
            self.queue.apply_task(replace(dispatch.lease, token="0" * 64), 1, dispatch.record)
        self.assertEqual("running", self.queue.tasks.get("task-1")["status"])

    def test_queue_reservation_survives_task_deletion_and_does_not_allow_id_reuse(self):
        self.enqueue()
        self.queue.tasks.delete_conversation("chat-a")
        self.assertIsNone(self.poll())
        self.assertEqual({"task-1"}, self.queue.tasks.worker_owned_ids(["task-1"]))
        with self.assertRaises(AgentTaskWriteConflict):
            self.queue.tasks.upsert(record())

    def test_ten_thousand_waiting_tasks_use_no_per_task_threads_and_enforce_bound(self):
        threads = {thread.ident for thread in threading.enumerate()}
        for start in range(0, 10000, 100):
            with self.ledger.transaction() as connection:
                for index in range(start, start + 100):
                    self.enqueue(record("load-" + str(index), "app-" + str(index % 100),
                                        "chat-" + str(index % 500)), connection=connection)
        self.assertEqual(10000, self.queue.tasks.count())
        self.assertEqual(threads, {thread.ident for thread in threading.enumerate()})
        with self.assertRaisesRegex(WorkerAccessError, "queue_full"):
            self.enqueue(record("overflow"))
        self.heartbeat(sequence=2, available_slots=10)
        self.assertEqual("load-0", self.poll().lease.key.task)
        self.assertEqual("load-1", self.poll(2).lease.key.task)

    def test_shared_transaction_rejects_other_database_and_rolls_back_entire_admission(self):
        other = AgentRunEventLedger(self.ledger.path.parent / "other.db")
        with other.transaction() as connection, self.assertRaises(ValueError):
            self.enqueue(connection=connection)
        with self.assertRaisesRegex(RuntimeError, "abort"):
            with self.ledger.transaction() as connection:
                self.enqueue(connection=connection)
                self.assertIsNotNone(self.queue.tasks.get("task-1", connection=connection))
                raise RuntimeError("abort")
        self.assertEqual(0, self.queue.tasks.count())
        self.assertEqual(set(), self.queue.tasks.worker_owned_ids(["task-1"]))
        self.assertEqual(0, self.ledger.event_count())

    def test_same_conversation_concurrent_turns_commit_independently(self):
        self.enqueue(record("one", conversation="shared-chat"))
        self.enqueue(record("two", conversation="shared-chat"))
        one, two = self.poll(), self.poll(2)
        self.complete(two)
        self.complete(one)
        self.assertEqual("Completed one", self.queue.tasks.get("one")["result"])
        self.assertEqual("Completed two", self.queue.tasks.get("two")["result"])
        self.assertNotEqual(one.lease.key.turn, two.lease.key.turn)

    def test_local_manager_restart_observes_unclaimed_queue_without_executing_it(self):
        from agent_task_manager import AgentTaskManager
        self.enqueue()
        before = self.queue.tasks.get("task-1")
        manager = AgentTaskManager(state_path=self.ledger.path)
        self.addCleanup(manager._work_pool.close)
        self.addCleanup(manager._control_work_pool.close)
        self.assertEqual(before, self.queue.tasks.get("task-1"))
        self.assertTrue(manager.get("task-1").storage_fenced)
        self.assertNotIn("task-1", manager._recovered_task_ids)
        self.assertEqual(0, manager.scheduling_status()["active"])
        dispatch = self.poll()
        self.complete(dispatch)
        self.assertEqual("Completed task-1", manager.get("task-1").result)

    def test_task_get_hydrates_one_revision_when_another_writer_commits_between_queries(self):
        original = record("local", result="a" * 20000)
        self.queue.tasks.upsert(original)
        original = self.queue.tasks.get("local")
        decode = self.queue.tasks._decode
        changed = False
        def write_after_metadata(value):
            nonlocal changed
            decoded = decode(value)
            if not changed:
                changed = True
                self.queue.tasks.upsert({**original, "result": "b" * 30000})
            return decoded
        with patch.object(self.queue.tasks, "_decode", side_effect=write_after_metadata):
            self.assertEqual(original["result"], self.queue.tasks.get("local")["result"])
        self.assertEqual("b" * 30000, self.queue.tasks.get("local")["result"])

    def test_real_coordinator_processes_replay_one_grant_without_double_dispatch(self):
        self.enqueue(record("one"))
        self.enqueue(record("two"))
        def run(_):
            return poll_process(self.ledger.path, self.peer,
                dict(sequence=1, request_id="poll-1", incarnation="boot-a", session_epoch=1))
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(run, range(4)))
        self.assertEqual([["one", 1, 2]] * 4, results)
        self.assertEqual("queued", self.queue.tasks.get("two")["status"])

    def test_two_worker_processes_compete_for_one_task_with_one_winner(self):
        other = peer("route-b")
        self.registry.enroll(other, "worker-b", max_parallel=1, providers=["codex"])
        self.registry.connect(other, other["signal_name"], dict(incarnation="boot-b", request_id="b-connect",
            expected_session_epoch=0, providers=["codex"]))
        self.registry.heartbeat(other, other["signal_name"], dict(incarnation="boot-b", session_epoch=1,
            sequence=1, available_slots=1))
        self.queue.enqueue(record(), provider="codex", allowed_workers=["worker-a", "worker-b"])
        def run(pair):
            paired, incarnation = pair
            return poll_process(self.ledger.path, paired,
                dict(sequence=1, request_id="poll-1", incarnation=incarnation, session_epoch=1))
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(run, [(self.peer, "boot-a"), (other, "boot-b")]))
        self.assertEqual(1, results.count(None))
        self.assertEqual([["task-1", 1, 2]], [item for item in results if item is not None])
