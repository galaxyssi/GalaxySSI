"""Queued disclosures remain bound to the originally authorized worker identity."""
from copy import deepcopy

from agent_worker_queue import AgentWorkerQueue
from test_agent_worker_queue import record
from test_agent_worker_registry import WorkerFixture, peer


class WorkerTargetBindingTest(WorkerFixture):
    def setUp(self):
        super().setUp()
        self.enroll()
        self.queue = AgentWorkerQueue(self.registry)

    def connect_peer(self, value, epoch=0, incarnation="new-boot"):
        session = self.registry.connect(value, value["signal_name"], dict(request_id=incarnation,
            incarnation=incarnation, expected_session_epoch=epoch, providers=["codex"]))
        fields = dict(incarnation=incarnation, session_epoch=session["session_epoch"])
        self.registry.heartbeat(value, value["signal_name"], dict(fields, request_id="hb", sequence=1, available_slots=1))
        return fields

    def poll_peer(self, value, fields, sequence=1):
        return self.queue.poll(value, value["signal_name"], dict(fields, request_id="poll-" + str(sequence), sequence=sequence))

    def test_repaired_same_worker_id_cannot_read_previously_queued_request(self):
        original = record(prompt="private request for original identity")
        self.queue.enqueue(original, provider="codex", allowed_workers=["worker-a"])
        changed = dict(self.peer, identity_fingerprint="d" * 64)
        updated = self.registry.enroll(changed, "worker-a", max_parallel=10, providers=["codex"])
        session = self.connect_peer(changed, updated["session_epoch"])
        self.assertIsNone(self.poll_peer(changed, session))
        self.assertEqual("queued", self.queue.tasks.get("task-1")["status"])
        self.assertFalse(self.queue.enqueue(original, provider="codex", allowed_workers=["worker-a"]))
        self.assertIsNone(self.poll_peer(changed, session, 2))
        self.queue.enqueue(record("new-task"), provider="codex", allowed_workers=["worker-a"])
        self.assertEqual("new-task", self.poll_peer(changed, session, 3).lease.key.task)

    def test_reconnect_same_pair_keeps_original_queued_authorization(self):
        first = self.connect_peer(self.peer)
        self.queue.enqueue(record(), provider="codex", allowed_workers=["worker-a"])
        second = self.connect_peer(self.peer, first["session_epoch"], "second-boot")
        self.assertEqual("task-1", self.poll_peer(self.peer, second).lease.key.task)

    def test_repaired_one_target_does_not_block_another_original_target(self):
        other = peer("route-b")
        self.registry.enroll(other, "worker-b", max_parallel=10, providers=["codex"])
        self.queue.enqueue(record(), provider="codex", allowed_workers=["worker-a", "worker-b"])
        changed = deepcopy(self.peer)
        changed["link_secret"] = "e" * 64
        enrollment = self.registry.enroll(changed, "worker-a", max_parallel=10, providers=["codex"])
        self.assertIsNone(self.poll_peer(changed, self.connect_peer(changed, enrollment["session_epoch"])))
        result = self.poll_peer(other, self.connect_peer(other))
        self.assertEqual(("app-a", "chat-a", "turn-task-1", "task-1", 1),
            tuple(getattr(result.lease.key, name) for name in ("app", "conversation", "turn", "task", "generation")))

    def test_every_changed_pairing_component_fences_old_queued_work(self):
        value = deepcopy(self.peer)
        for index, (field, replacement) in enumerate((("identity_fingerprint", "d" * 64),
                ("local_identity_fingerprint", "e" * 64), ("link_secret", "f" * 64),
                ("signal_name", "new-signal-name"), ("access_granted_at", 124))):
            with self.subTest(field=field):
                self.queue.enqueue(record("task-" + str(index)), provider="codex", allowed_workers=["worker-a"])
                value[field] = replacement
                enrollment = self.registry.enroll(value, "worker-a", max_parallel=10, providers=["codex"])
                self.assertIsNone(self.poll_peer(value,
                    self.connect_peer(value, enrollment["session_epoch"], "boot-" + str(index))))

    def test_upgrade_does_not_invent_authorization_for_legacy_targets(self):
        self.queue.enqueue(record(), provider="codex", allowed_workers=["worker-a"])
        with self.ledger.transaction() as connection:
            connection.execute("ALTER TABLE agent_worker_queue_targets RENAME TO previous_targets")
            connection.execute("CREATE TABLE agent_worker_queue_targets (task_id TEXT NOT NULL, worker_id TEXT NOT NULL, PRIMARY KEY(worker_id, task_id))")
            connection.execute("INSERT INTO agent_worker_queue_targets SELECT task_id, worker_id FROM previous_targets")
            connection.execute("DROP TABLE previous_targets")
        self.queue = AgentWorkerQueue(self.registry)
        session = self.connect_peer(self.peer)
        self.assertIsNone(self.poll_peer(self.peer, session))
        self.assertEqual("queued", self.queue.tasks.get("task-1")["status"])
        self.queue.enqueue(record("new-task"), provider="codex", allowed_workers=["worker-a"])
        self.assertEqual("new-task", self.poll_peer(self.peer, session, 2).lease.key.task)
