"""Durable, explicitly targeted worker queue; no network or provider execution here.

The coordinator admits validated task records. An authenticated worker polls one
grant at a time. Queue ownership, capacity, fairness and the dispatch checkpoint
commit together; waiting tasks never occupy a thread or a provider process.
"""
from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import json
import time

from agent_work_pool import ExecutionKey
from agent_task_store import AgentTaskWriteConflict
from agent_worker_leases import WorkerLease, WorkerLeaseConflict, _canonical, _key
from agent_worker_registry import AgentWorkerRegistry, WorkerAccessError, _identifier, _integer


TERMINAL = frozenset({"completed", "failed", "cancelled", "timed_out"})


@dataclass(frozen=True)
class WorkerDispatch:
    lease: WorkerLease
    provider: str
    record: dict = field(repr=False)


class AgentWorkerQueue:
    def __init__(self, registry: AgentWorkerRegistry, *, max_pending: int = 10000):
        self.registry = registry
        self.leases = registry.leases
        self.tasks = self.leases.tasks
        self.events = self.leases.events
        self.ledger = registry.ledger
        self.max_pending = _integer(max_pending, 1, 10000)
        with self.ledger.transaction() as connection:
            statements = (
                """CREATE TABLE IF NOT EXISTS agent_worker_queue (
                    ordinal INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT UNIQUE NOT NULL,
                    app TEXT NOT NULL, conversation TEXT NOT NULL, turn TEXT NOT NULL,
                    generation INTEGER NOT NULL, provider TEXT NOT NULL, admission_digest TEXT NOT NULL,
                    state TEXT NOT NULL DEFAULT 'queued', worker_id TEXT NOT NULL DEFAULT '',
                    session_epoch INTEGER NOT NULL DEFAULT 0, heartbeat_sequence INTEGER NOT NULL DEFAULT 0
                )""",
                """CREATE INDEX IF NOT EXISTS agent_worker_queue_ready
                    ON agent_worker_queue(state, provider, ordinal)""",
                """CREATE INDEX IF NOT EXISTS agent_worker_queue_capacity
                    ON agent_worker_queue(worker_id, state, session_epoch, heartbeat_sequence)""",
                """CREATE TABLE IF NOT EXISTS agent_worker_queue_targets (
                    task_id TEXT NOT NULL, worker_id TEXT NOT NULL, binding TEXT NOT NULL DEFAULT '',
                    PRIMARY KEY(worker_id, task_id)
                )""",
                """CREATE TABLE IF NOT EXISTS agent_worker_queue_fair (
                    app TEXT NOT NULL, conversation TEXT NOT NULL, tick INTEGER NOT NULL,
                    PRIMARY KEY(app, conversation)
                )""",
                """CREATE TABLE IF NOT EXISTS agent_worker_queue_clock (
                    singleton INTEGER PRIMARY KEY CHECK(singleton=1), tick INTEGER NOT NULL
                )""",
                "INSERT OR IGNORE INTO agent_worker_queue_clock VALUES (1, 0)",
                """CREATE TABLE IF NOT EXISTS agent_worker_queue_polls (
                    worker_id TEXT PRIMARY KEY, session_epoch INTEGER NOT NULL,
                    sequence INTEGER NOT NULL, request_id TEXT NOT NULL, task_id TEXT NOT NULL
                )""",
            )
            for statement in statements:
                connection.execute(statement)
            columns = {row[1] for row in connection.execute("PRAGMA table_info(agent_worker_queue_targets)")}
            if "binding" not in columns:
                # Old target IDs cannot prove which pairing authorized disclosure.
                connection.execute("ALTER TABLE agent_worker_queue_targets ADD COLUMN binding TEXT NOT NULL DEFAULT ''")

    def enqueue(self, record: dict, *, provider: str, allowed_workers: list[str], connection=None) -> bool:
        """Trusted coordinator admission, never an arbitrary remote task object.

        Only new tasks are admitted. Migrating an already dispatched local task
        requires a separate takeover protocol, not a write to this queue.
        """
        snapshot = json.loads(_canonical(record))
        key = ExecutionKey(snapshot.get("client_route_id"),
            snapshot.get("client_conversation_id") or snapshot.get("conversation_id"),
            snapshot.get("client_turn_id"), snapshot.get("task_id"), snapshot.get("execution_generation", 1))
        _key(key)
        if any(value != value.strip() for value in _key(key)[:4]):
            raise ValueError("Execution identifiers must not contain surrounding whitespace")
        provider = _identifier(provider)
        if not isinstance(allowed_workers, list) or not 1 <= len(allowed_workers) <= 128:
            raise WorkerAccessError("worker_targets_required")
        targets = sorted({_identifier(worker) for worker in allowed_workers})
        if (snapshot.get("status") != "queued" or snapshot.get("_storage_revision", 0) != 0
                or snapshot.get("execution_checkpoint", {}).get("dispatch_started")):
            raise WorkerLeaseConflict("Only a new undispatched queued task can be admitted")
        digest = hashlib.sha256(_canonical([snapshot, provider, targets]).encode()).hexdigest()
        with self.leases.transaction(connection) as connection:
            previous = connection.execute("SELECT admission_digest FROM agent_worker_queue WHERE task_id=?",
                                          (key.task,)).fetchone()
            if previous:
                if previous[0] != digest:
                    raise WorkerLeaseConflict("Task admission ID was reused with different data")
                return False
            if self.tasks.get(key.task, connection=connection) is not None:
                raise WorkerLeaseConflict("Task already exists outside the remote queue")
            pending = connection.execute("SELECT count(*) FROM agent_worker_queue WHERE state='queued'").fetchone()[0]
            if pending >= self.max_pending:
                raise WorkerAccessError("worker_queue_full")
            bound_targets = []
            for target in targets:
                row = connection.execute("""SELECT enabled, providers_json, binding FROM agent_worker_enrollments
                    WHERE worker_id=?""", (target,)).fetchone()
                if not row or not row[0] or provider not in json.loads(row[1]):
                    raise WorkerAccessError("worker_target_not_authorized")
                bound_targets.append((key.task, target, row[2]))
            self.events.append_snapshot(snapshot, connection=connection)
            self.tasks.upsert(snapshot, connection=connection)
            connection.execute("""INSERT INTO agent_worker_queue
                (task_id, app, conversation, turn, generation, provider, admission_digest)
                VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (key.task, key.app, key.conversation, key.turn, key.generation, provider, digest))
            connection.executemany("INSERT INTO agent_worker_queue_targets (task_id, worker_id, binding) VALUES (?, ?, ?)",
                                   bound_targets)
            return True

    def _replay(self, connection, worker, task_id):
        if not task_id:
            return None
        row = self.leases._row(connection, task_id)
        if row is None or row["worker"] != worker["worker_id"] or row["incarnation"] != worker["incarnation"]:
            raise WorkerLeaseConflict("Dispatch no longer belongs to this worker session")
        grant = self.leases._grant(row)
        self.leases._require(connection, grant)
        task = self.tasks.get(task_id, connection=connection)
        queued = connection.execute("SELECT provider, state FROM agent_worker_queue WHERE task_id=?",
                                    (task_id,)).fetchone()
        if task is None or not queued or queued[1] != "leased" or task.get("status") in TERMINAL:
            raise WorkerLeaseConflict("Dispatch is no longer executable")
        return WorkerDispatch(grant, queued[0], task)

    def poll(self, peer, source, payload, *, connection=None) -> WorkerDispatch | None:
        """One durable receipt per worker, with strictly ordered poll sequence.

        Retrying the latest poll replays its grant without consuming another slot.
        An empty reply is also final for that sequence; use a new sequence to poll
        again. The worker must deduplicate executions by lease key and epoch.
        """
        sequence = _integer(payload.get("sequence"), 1, 2**53 - 1)
        request_id = _identifier(payload.get("request_id"))
        with self.leases.transaction(connection) as connection:
            worker = self.registry.require_session(connection, peer, source, payload)
            previous = connection.execute("""SELECT session_epoch, sequence, request_id, task_id
                FROM agent_worker_queue_polls WHERE worker_id=?""", (worker["worker_id"],)).fetchone()
            previous = previous if previous and previous[0] == worker["session_epoch"] else None
            if previous and sequence == previous[1] and request_id == previous[2]:
                return self._replay(connection, worker, previous[3])
            if sequence != (previous[1] + 1 if previous else 1) or (previous and request_id == previous[2]):
                raise WorkerAccessError("worker_poll_reordered")
            active = connection.execute("""SELECT count(*) FROM agent_worker_leases lease
                LEFT JOIN agent_tasks task ON task.task_id=lease.task_id WHERE lease.worker_id=?
                AND (task.status IS NULL OR task.status NOT IN ('completed', 'failed', 'cancelled', 'timed_out'))""",
                (worker["worker_id"],)).fetchone()[0]
            since_heartbeat = connection.execute("""SELECT count(*) FROM agent_worker_queue
                WHERE session_epoch=? AND heartbeat_sequence=? AND worker_id=? AND state='leased'""",
                (worker["session_epoch"], worker["heartbeat_sequence"], worker["worker_id"])).fetchone()
            capacity = min(worker["max_parallel"] - active, worker["available_slots"] - since_heartbeat[0])
            offered = json.loads(worker["offered_json"])
            candidate = None
            if capacity > 0 and offered:
                candidate = connection.execute(f"""SELECT q.task_id FROM agent_worker_queue q
                    JOIN agent_worker_queue_targets target ON target.task_id=q.task_id AND target.worker_id=? AND target.binding=?
                    JOIN agent_tasks task ON task.task_id=q.task_id AND task.status='queued'
                    LEFT JOIN agent_worker_queue_fair a ON a.app=q.app AND a.conversation=''
                    LEFT JOIN agent_worker_queue_fair c ON c.app=q.app AND c.conversation=q.conversation
                    WHERE q.state='queued' AND q.provider IN ({','.join('?' for _ in offered)})
                    ORDER BY coalesce(a.tick, 0), coalesce(c.tick, 0), q.ordinal LIMIT 1""",
                    (worker["worker_id"], worker["binding"], *offered)).fetchone()
            task_id = candidate[0] if candidate else ""
            if candidate:
                record = self.tasks.get(task_id, connection=connection)
                key = ExecutionKey(record["client_route_id"],
                    record.get("client_conversation_id") or record["conversation_id"],
                    record["client_turn_id"], task_id, record.get("execution_generation", 1))
                claim_id = hashlib.sha256(_canonical([worker["worker_id"], worker["session_epoch"],
                    sequence, request_id]).encode()).hexdigest()
                grant = self.leases.claim(key, worker["worker_id"], worker["incarnation"],
                    expected_epoch=0, claim_id=claim_id, connection=connection)
                record.update(status="running", updated_at=time.time_ns() // 1_000_000,
                              status_seq=int(record.get("status_seq", 0)) + 1,
                              execution_checkpoint={**record.get("execution_checkpoint", {}), "dispatch_started": True})
                location = {"kind": "desktop", "id": worker["worker_id"], "name": worker["worker_id"]}
                record["worker_execution_location"] = location
                record["execution_view"] = {**record.get("execution_view", {}),
                    "location_kind": location["kind"], "location_id": location["id"],
                    "location_name": location["name"], "status": "running"}
                self.events.append_snapshot(record, connection=connection)
                self.tasks.upsert(record, connection=connection, worker_lease=grant)
                connection.execute("""UPDATE agent_worker_queue SET state='leased', worker_id=?,
                    session_epoch=?, heartbeat_sequence=? WHERE task_id=?""",
                    (worker["worker_id"], worker["session_epoch"], worker["heartbeat_sequence"], task_id))
                connection.execute("UPDATE agent_worker_queue_clock SET tick=tick+1 WHERE singleton=1")
                tick = connection.execute("SELECT tick FROM agent_worker_queue_clock WHERE singleton=1").fetchone()[0]
                connection.executemany("""INSERT INTO agent_worker_queue_fair VALUES (?, ?, ?)
                    ON CONFLICT(app, conversation) DO UPDATE SET tick=excluded.tick""",
                    [(key.app, "", tick), (key.app, key.conversation, tick)])
            connection.execute("""INSERT INTO agent_worker_queue_polls VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(worker_id) DO UPDATE SET session_epoch=excluded.session_epoch,
                sequence=excluded.sequence, request_id=excluded.request_id, task_id=excluded.task_id""",
                (worker["worker_id"], worker["session_epoch"], sequence, request_id, task_id))
            return self._replay(connection, worker, task_id)

    def apply_task(self, grant: WorkerLease, sequence: int, record: dict, *, connection=None) -> bool:
        """Accept a coordinator-built projection and release capacity atomically.

        A network adapter must authenticate the current worker session and build
        the record from allowlisted fields before calling this internal method.
        """
        with self.leases.transaction(connection) as connection:
            row = connection.execute("SELECT state FROM agent_worker_queue WHERE task_id=?",
                                     (grant.key.task,)).fetchone()
            if not row or row[0] not in {"leased", "finished"}:
                raise WorkerLeaseConflict("Task has no worker queue dispatch")
            lease = self.leases._require(connection, grant)
            if row[0] == "finished" and sequence != lease["sequence"]:
                raise WorkerLeaseConflict("A terminal worker dispatch cannot be resumed")
            current = self.tasks.get(grant.key.task, connection=connection)
            if current is None or any(record.get(field) != current.get(field) for field in (
                    "source_message_id", "contact_id", "agent_id", "prompt", "request_snapshot",
                    "attachments", "execution_policy")):
                raise AgentTaskWriteConflict("Worker projection changed the original request context")
            accepted = self.leases.apply_task(grant, sequence, record, connection=connection)
            if record.get("status") in TERMINAL:
                connection.execute("UPDATE agent_worker_queue SET state='finished' WHERE task_id=?", (grant.key.task,))
            return accepted
