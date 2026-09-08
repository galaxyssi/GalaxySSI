"""Coordinator-local durable leases for authenticated remote execution adapters.

This module is not a network endpoint. The caller authenticates a worker before
binding its identity/incarnation, and must never expose lease tokens in UI events.
"""
from __future__ import annotations

from dataclasses import dataclass, field, replace
import hashlib
import hmac
import json
import secrets
import time

from agent_run_kernel import AgentRunEventLedger
from agent_task_run_events import AgentTaskRunEventSink
from agent_task_store import AgentTaskStore, AgentTaskWriteConflict
from agent_work_pool import ExecutionKey


class WorkerLeaseConflict(RuntimeError):
    pass


def _clock_ms() -> int:
    return time.time_ns() // 1_000_000


def _identifier(value: str) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > 512:
        raise ValueError("A bounded nonempty worker/execution identifier is required")
    return value


def _key(key: ExecutionKey) -> list:
    if not isinstance(key, ExecutionKey) or type(key.generation) is not int or key.generation < 1:
        raise ValueError("A complete execution key is required")
    return [_identifier(key.app), _identifier(key.conversation), _identifier(key.turn),
            _identifier(key.task), key.generation]


def _canonical(value) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


@dataclass(frozen=True)
class WorkerLease:
    key: ExecutionKey
    worker_id: str
    incarnation: str
    epoch: int
    expires_at_ms: int
    token: str = field(repr=False)


class AgentWorkerLeaseLedger:
    """Serialize grants, receipts and task/Run writes on the existing Run database."""

    def __init__(self, ledger: AgentRunEventLedger):
        self.ledger = ledger
        self.tasks = AgentTaskStore(ledger.path)
        self.events = AgentTaskRunEventSink(ledger.path, ledger=ledger)
        with ledger.transaction() as connection:
            connection.execute("""CREATE TABLE IF NOT EXISTS agent_worker_leases (
                task_id TEXT PRIMARY KEY NOT NULL,
                scope_json TEXT NOT NULL,
                worker_id TEXT NOT NULL,
                incarnation TEXT NOT NULL,
                epoch INTEGER NOT NULL,
                token TEXT NOT NULL,
                expires_at_ms INTEGER NOT NULL,
                state TEXT NOT NULL,
                claim_id TEXT NOT NULL,
                claim_ttl_ms INTEGER NOT NULL,
                last_sequence INTEGER NOT NULL DEFAULT 0,
                last_digest TEXT NOT NULL DEFAULT ''
            )""")

    @staticmethod
    def _ttl(ttl_ms: int) -> int:
        if type(ttl_ms) is not int or not 1000 <= ttl_ms <= 300_000:
            raise ValueError("Worker lease TTL must be between 1 and 300 seconds")
        return ttl_ms

    @staticmethod
    def _row(connection, task_id):
        row = connection.execute("""SELECT scope_json, worker_id, incarnation, epoch,
            token, expires_at_ms, state, claim_id, claim_ttl_ms, last_sequence, last_digest
            FROM agent_worker_leases WHERE task_id=?""", (task_id,)).fetchone()
        if row is None:
            return None
        return dict(zip(("scope", "worker", "incarnation", "epoch", "token", "expires",
                         "state", "claim_id", "ttl", "sequence", "digest"), row))

    @staticmethod
    def _grant(row) -> WorkerLease:
        return WorkerLease(ExecutionKey(*json.loads(row["scope"])), row["worker"],
                           row["incarnation"], row["epoch"], row["expires"], row["token"])

    def claim(self, key: ExecutionKey, worker_id: str, incarnation: str, *,
              expected_epoch: int, claim_id: str, ttl_ms: int = 30_000) -> WorkerLease:
        scope = _key(key)
        for value in (worker_id, incarnation, claim_id):
            _identifier(value)
        self._ttl(ttl_ms)
        if type(expected_epoch) is not int or expected_epoch < 0:
            raise ValueError("An observed nonnegative lease epoch is required")
        with self.ledger.transaction() as connection:
            row = self._row(connection, key.task)
            now = _clock_ms()
            task_row = connection.execute("SELECT payload FROM agent_tasks WHERE task_id=?",
                                          (key.task,)).fetchone()
            if task_row is not None:
                task = json.loads(task_row[0])
                task_scope = [task.get("client_route_id"),
                    task.get("client_conversation_id") or task.get("conversation_id"),
                    task.get("client_turn_id"), task.get("task_id")]
                if task_scope != scope[:4] or task.get("execution_generation", 1) > key.generation:
                    raise WorkerLeaseConflict("Existing task belongs to a different execution")
                if task.get("status") in {"completed", "failed", "cancelled", "timed_out"}:
                    raise WorkerLeaseConflict("A terminal task cannot be leased again")
                if row is None and (task.get("status") not in {"accepted", "queued"}
                        or task.get("execution_checkpoint", {}).get("dispatch_started")):
                    raise WorkerLeaseConflict("An already dispatched local task cannot be leased")
            if row is not None:
                if row["claim_id"] == claim_id:
                    if (row["scope"] != _canonical(scope) or row["worker"] != worker_id
                            or row["incarnation"] != incarnation or row["ttl"] != ttl_ms
                            or row["epoch"] != expected_epoch + 1):
                        raise WorkerLeaseConflict("Claim ID was reused with different parameters")
                    # A lost claim response is replayed, never used to extend its deadline.
                    return self._grant(row)
                previous_scope = json.loads(row["scope"])
                if previous_scope[:4] != scope[:4]:
                    raise WorkerLeaseConflict("Task lease belongs to another App/conversation/turn")
                if row["epoch"] != expected_epoch:
                    raise WorkerLeaseConflict("Lease epoch changed")
                if row["state"] == "active" and row["expires"] > now:
                    raise WorkerLeaseConflict("Execution is still leased")
                if key.generation <= previous_scope[4]:
                    raise WorkerLeaseConflict("Reassignment requires a newer execution generation")
            elif expected_epoch != 0:
                raise WorkerLeaseConflict("Initial lease epoch must be zero")
            grant = WorkerLease(key, worker_id, incarnation, expected_epoch + 1,
                                now + ttl_ms, secrets.token_hex(32))
            connection.execute("""INSERT INTO agent_worker_leases VALUES (?, ?, ?, ?, ?, ?, ?,
                'active', ?, ?, 0, '') ON CONFLICT(task_id) DO UPDATE SET
                scope_json=excluded.scope_json, worker_id=excluded.worker_id,
                incarnation=excluded.incarnation, epoch=excluded.epoch, token=excluded.token,
                expires_at_ms=excluded.expires_at_ms, state='active', claim_id=excluded.claim_id,
                claim_ttl_ms=excluded.claim_ttl_ms, last_sequence=0, last_digest=''""",
                (key.task, _canonical(scope), worker_id, incarnation, grant.epoch, grant.token,
                 grant.expires_at_ms, claim_id, ttl_ms))
            return grant

    def _require(self, connection, grant: WorkerLease):
        if not isinstance(grant, WorkerLease):
            raise ValueError("A worker lease capability is required")
        scope = _canonical(_key(grant.key))
        row = self._row(connection, grant.key.task)
        if (row is None or row["scope"] != scope or row["worker"] != grant.worker_id
                or row["incarnation"] != grant.incarnation or row["epoch"] != grant.epoch
                or not isinstance(grant.token, str)
                or not hmac.compare_digest(row["token"], grant.token)
                or row["state"] != "active" or row["expires"] <= _clock_ms()):
            raise WorkerLeaseConflict("Worker lease is expired, revoked or no longer owned")
        return row

    def renew(self, grant: WorkerLease, *, ttl_ms: int = 30_000) -> WorkerLease:
        self._ttl(ttl_ms)
        with self.ledger.transaction() as connection:
            row = self._require(connection, grant)
            expires = max(row["expires"], _clock_ms() + ttl_ms)
            connection.execute("UPDATE agent_worker_leases SET expires_at_ms=? WHERE task_id=?",
                               (expires, grant.key.task))
            return replace(grant, expires_at_ms=expires)

    def revoke(self, key: ExecutionKey, *, expected_epoch: int) -> None:
        """Trusted coordinator action, not an operation granted to an arbitrary worker."""
        with self.ledger.transaction() as connection:
            row = self._row(connection, key.task)
            if row is None or row["scope"] != _canonical(_key(key)) or row["epoch"] != expected_epoch:
                raise WorkerLeaseConflict("Cannot revoke a different execution lease")
            connection.execute("UPDATE agent_worker_leases SET state='revoked' WHERE task_id=?", (key.task,))

    def apply_task(self, grant: WorkerLease, sequence: int, record: dict) -> bool:
        """Atomically accept one ordered task snapshot, its Run event and its receipt.

        The adapter supplies a coordinator-built record, not arbitrary remote SQL
        or an unvalidated remote task object. The last receipt can be retried.
        """
        if type(sequence) is not int or sequence < 1:
            raise ValueError("A positive worker receipt sequence is required")
        encoded = _canonical(record)
        snapshot = json.loads(encoded)
        key = ExecutionKey(str(snapshot.get("client_route_id") or ""),
            str(snapshot.get("client_conversation_id") or snapshot.get("conversation_id") or ""),
            str(snapshot.get("client_turn_id") or ""), str(snapshot.get("task_id") or ""),
            snapshot.get("execution_generation", 1))
        if key != grant.key:
            raise WorkerLeaseConflict("Worker result belongs to another execution")
        digest = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
        with self.ledger.transaction() as connection:
            row = self._require(connection, grant)
            if sequence == row["sequence"] and digest == row["digest"]:
                return False
            if sequence != row["sequence"] + 1:
                raise WorkerLeaseConflict("Worker receipt is reordered or reused")
            self.events.append_snapshot(snapshot, connection=connection)
            self.tasks.upsert(snapshot, connection=connection, worker_lease=grant)
            connection.execute("""UPDATE agent_worker_leases SET last_sequence=?, last_digest=?
                WHERE task_id=?""", (sequence, digest, key.task))
            return True


def require_task_writer(connection, record: dict, grant: WorkerLease | None) -> None:
    """Prevent ordinary task writes from bypassing a persisted worker grant."""
    exists = connection.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                                ("agent_worker_leases",)).fetchone()
    if not exists:
        if grant is not None:
            raise AgentTaskWriteConflict("Worker lease storage is missing")
        return
    row = AgentWorkerLeaseLedger._row(connection, str(record.get("task_id") or ""))
    if row is None:
        if grant is not None:
            raise AgentTaskWriteConflict("Worker lease is missing")
        return
    if grant is None:
        raise AgentTaskWriteConflict("Task is owned by the worker lease coordinator")
    key = ExecutionKey(str(record.get("client_route_id") or ""),
        str(record.get("client_conversation_id") or record.get("conversation_id") or ""),
        str(record.get("client_turn_id") or ""), str(record.get("task_id") or ""),
        record.get("execution_generation", 1))
    if (not isinstance(grant, WorkerLease) or grant.key != key
            or row["scope"] != _canonical(_key(key)) or row["worker"] != grant.worker_id
            or row["incarnation"] != grant.incarnation or row["epoch"] != grant.epoch
            or not isinstance(grant.token, str) or not hmac.compare_digest(row["token"], grant.token)
            or row["state"] != "active" or row["expires"] <= _clock_ms()):
        raise AgentTaskWriteConflict("Task writer has no current worker lease")
