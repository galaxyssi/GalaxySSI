"""Worker-side monotonic lease fencing and durable execution deduplication."""
from copy import deepcopy
import hashlib
import hmac
import json
import math
import re
import threading
import time

from agent_work_pool import ExecutionKey
from agent_worker_leases import _canonical, _key
from agent_worker_registry import _identifier, _integer
from agent_worker_rpc import WorkerRpcResult


class WorkerExecutionFenced(RuntimeError):
    pass


def _lease(value):
    if not isinstance(value, dict) or set(value) != {"key", "epoch", "token", "expires_at_ms"}:
        raise WorkerExecutionFenced("worker_local_lease_invalid")
    scope = value["key"]
    try:
        if not isinstance(scope, list) or len(scope) != 5:
            raise ValueError("scope")
        _key(ExecutionKey(*scope))
        _integer(scope[4], 1, 2**53 - 1)
        _integer(value["epoch"], 1, 2**53 - 1)
        _integer(value["expires_at_ms"], 1, 2**53 - 1)
        if not isinstance(value["token"], str) or not 1 <= len(value["token"].encode("utf-8")) <= 128:
            raise ValueError("token")
    except (ValueError, TypeError, RuntimeError) as error:
        raise WorkerExecutionFenced("worker_local_lease_invalid") from error
    return deepcopy(value)


def _observation(result, *, initial):
    if (not isinstance(result, WorkerRpcResult) or not isinstance(result.payload, dict)
            or result.payload.get("ok") is not True):
        raise WorkerExecutionFenced("worker_local_response_invalid")
    payload = result.payload
    value = payload.get("job") if initial else payload
    if not isinstance(value, dict):
        raise WorkerExecutionFenced("worker_local_job_missing")
    grant = _lease(value.get("lease"))
    server_time = payload.get("server_time_ms")
    if type(server_time) is not int or not 1 <= server_time <= 2**53 - 1:
        raise WorkerExecutionFenced("worker_local_server_time_invalid")
    for observed in (result.sent_at, result.received_at):
        if type(observed) not in (int, float) or not math.isfinite(observed) or observed < 0:
            raise WorkerExecutionFenced("worker_local_observation_invalid")
    if result.received_at < result.sent_at:
        raise WorkerExecutionFenced("worker_local_observation_reordered")
    return grant, server_time


class WorkerLeaseGuard:
    """A reply never resets a TTL at receive time; network delay consumes it."""

    def __init__(self, result, *, clock=time.monotonic, safety_seconds=0.5):
        if type(safety_seconds) not in (int, float) or not 0 <= safety_seconds <= 5:
            raise ValueError("Invalid lease safety margin")
        self._lock = threading.RLock()
        self._clock, self._margin = clock, safety_seconds
        self._lease, self._server_time = _observation(result, initial=True)
        self._observed = result.received_at
        self._deadline = self._budget(result, self._lease, self._server_time)
        self._fenced = ""
        self.require_live()

    def _budget(self, result, grant, server_time):
        return result.sent_at + min(30.0, (grant["expires_at_ms"] - server_time) / 1000) - self._margin

    def require_live(self):
        with self._lock:
            now = self._clock()
            if now < self._observed:
                self._fenced = "worker_local_clock_regressed"
            elif now >= self._deadline:
                self._fenced = "worker_local_lease_expired"
            if self._fenced:
                raise WorkerExecutionFenced(self._fenced)
            return self._deadline - now

    def renew(self, result):
        grant, server_time = _observation(result, initial=False)
        with self._lock:
            self.require_live()
            if (grant["key"] != self._lease["key"] or grant["epoch"] != self._lease["epoch"]
                    or not hmac.compare_digest(grant["token"].encode(), self._lease["token"].encode())
                    or grant["expires_at_ms"] < self._lease["expires_at_ms"]
                    or result.sent_at < self._observed):
                raise WorkerExecutionFenced("worker_local_renewal_mismatch")
            if server_time < self._server_time:
                self._fenced = "worker_local_server_clock_regressed"
                raise WorkerExecutionFenced(self._fenced)
            deadline = self._budget(result, grant, server_time)
            if self._clock() < result.received_at or self._clock() >= deadline:
                raise WorkerExecutionFenced("worker_local_renewal_expired")
            # An unchanged server observation cannot extend the local budget.
            if server_time > self._server_time:
                self._deadline = max(self._deadline, deadline)
            self._lease, self._server_time, self._observed = grant, server_time, result.received_at

    def invalidate(self):
        with self._lock:
            self._fenced = "worker_local_execution_cancelled"

    def capability(self):
        with self._lock:
            self.require_live()
            return deepcopy(self._lease)


class WorkerExecutionJournal:
    """No automatic re-execution after a recorded dispatch or process loss."""

    def __init__(self, ledger, *, max_records=10000):
        if type(max_records) is not int or not 1 <= max_records <= 10000:
            raise ValueError("Invalid worker journal capacity")
        self.ledger, self.max_records = ledger, max_records
        with ledger.transaction() as connection:
            connection.execute("""CREATE TABLE IF NOT EXISTS agent_worker_local_executions (
                execution_id TEXT PRIMARY KEY, request_digest TEXT NOT NULL, owner TEXT NOT NULL,
                state TEXT NOT NULL, report_json TEXT NOT NULL DEFAULT '', receipt_json TEXT NOT NULL DEFAULT '',
                logical_id TEXT NOT NULL, generation INTEGER NOT NULL, epoch INTEGER NOT NULL
            )""")
            connection.execute("""CREATE INDEX IF NOT EXISTS worker_local_logical_execution
                ON agent_worker_local_executions(logical_id, generation, epoch, state)""")

    def admit(self, coordinator_binding, owner, job):
        if not isinstance(coordinator_binding, str) or not re.fullmatch(r"[0-9a-f]{64}", coordinator_binding):
            raise WorkerExecutionFenced("worker_local_coordinator_invalid")
        _identifier(owner)
        if not isinstance(job, dict) or set(job) != {"lease", "provider", "prompt", "options"}:
            raise WorkerExecutionFenced("worker_local_job_invalid")
        grant = _lease(job["lease"])
        _identifier(job["provider"])
        if (not isinstance(job["prompt"], str) or not job["prompt"].strip()
                or len(job["prompt"].encode("utf-8")) > 256 * 1024 or not isinstance(job["options"], dict)):
            raise WorkerExecutionFenced("worker_local_job_invalid")
        identity = _canonical([coordinator_binding, grant["key"], grant["epoch"]])
        execution_id = hashlib.sha256(identity.encode()).hexdigest()
        logical_id = hashlib.sha256(_canonical([coordinator_binding, grant["key"][:4]]).encode()).hexdigest()
        generation, epoch = grant["key"][4], grant["epoch"]
        immutable = deepcopy(job)
        immutable["lease"].pop("expires_at_ms")
        encoded = _canonical(immutable).encode("utf-8")
        if len(encoded) > 512 * 1024:
            raise WorkerExecutionFenced("worker_local_job_too_large")
        digest = hashlib.sha256(encoded).hexdigest()
        with self.ledger.transaction() as connection:
            row = connection.execute("SELECT request_digest FROM agent_worker_local_executions WHERE execution_id=?",
                                     (execution_id,)).fetchone()
            if row:
                if row[0] != digest:
                    raise WorkerExecutionFenced("worker_local_grant_reused")
                return execution_id
            if connection.execute("""SELECT 1 FROM agent_worker_local_executions WHERE logical_id=?
                AND (generation>? OR (generation=? AND epoch>?)) LIMIT 1""",
                (logical_id, generation, generation, epoch)).fetchone():
                raise WorkerExecutionFenced("worker_local_generation_stale")
            if connection.execute("SELECT count(*) FROM agent_worker_local_executions").fetchone()[0] >= self.max_records:
                raise WorkerExecutionFenced("worker_local_journal_full")
            connection.execute("INSERT INTO agent_worker_local_executions VALUES (?, ?, ?, 'admitted', '', '', ?, ?, ?)",
                               (execution_id, digest, owner, logical_id, generation, epoch))
        return execution_id

    def begin(self, execution_id, owner):
        with self.ledger.transaction() as connection:
            row = connection.execute("SELECT logical_id, generation, epoch FROM agent_worker_local_executions WHERE execution_id=?",
                                     (execution_id,)).fetchone()
            if row is None:
                return False
            if connection.execute("""SELECT 1 FROM agent_worker_local_executions WHERE logical_id=? AND execution_id!=?
                AND (state IN ('dispatched', 'uncertain') OR generation>? OR (generation=? AND epoch>?)) LIMIT 1""",
                (row[0], execution_id, row[1], row[1], row[2])).fetchone():
                return False
            changed = connection.execute("""UPDATE agent_worker_local_executions SET state='dispatched'
                WHERE execution_id=? AND owner=? AND state='admitted'""", (execution_id, owner)).rowcount
            return changed == 1

    def stage_report(self, execution_id, owner, report):
        if not isinstance(report, dict) or set(report) != {"status", "text", "error", "current_step"}:
            raise WorkerExecutionFenced("worker_local_report_invalid")
        if report["status"] not in {"completed", "failed", "cancelled", "timed_out"}:
            raise WorkerExecutionFenced("worker_local_report_invalid")
        for key, limit in (("text", 8192), ("error", 2048), ("current_step", 1024)):
            if not isinstance(report[key], str) or len(report[key].encode("utf-8")) > limit:
                raise WorkerExecutionFenced("worker_local_report_invalid")
        if ((report["status"] == "completed" and (not report["text"].strip() or report["error"]))
                or (report["status"] != "completed" and not report["error"].strip())):
            raise WorkerExecutionFenced("worker_local_report_invalid")
        encoded = _canonical(report)
        with self.ledger.transaction() as connection:
            row = connection.execute("SELECT owner, state, report_json FROM agent_worker_local_executions WHERE execution_id=?",
                                     (execution_id,)).fetchone()
            if row is None or row[0] != owner:
                raise WorkerExecutionFenced("worker_local_owner_mismatch")
            if row[1] in {"reporting", "confirmed"} and row[2] == encoded:
                return False
            if row[1] != "dispatched":
                raise WorkerExecutionFenced("worker_local_report_conflict")
            connection.execute("UPDATE agent_worker_local_executions SET state='reporting', report_json=? WHERE execution_id=?",
                               (encoded, execution_id))
            return True

    def confirm(self, execution_id, owner, receipt):
        if (not isinstance(receipt, dict) or set(receipt) != {"sequence", "status_sequence", "replayed"}
                or type(receipt["sequence"]) is not int or receipt["sequence"] != 1
                or type(receipt["status_sequence"]) is not int or receipt["status_sequence"] < 1
                or type(receipt["replayed"]) is not bool):
            raise WorkerExecutionFenced("worker_local_receipt_invalid")
        encoded = _canonical({key: receipt[key] for key in ("sequence", "status_sequence")})
        with self.ledger.transaction() as connection:
            row = connection.execute("SELECT owner, state, receipt_json FROM agent_worker_local_executions WHERE execution_id=?",
                                     (execution_id,)).fetchone()
            if row is None or row[0] != owner or row[1] not in {"reporting", "confirmed"}:
                raise WorkerExecutionFenced("worker_local_receipt_conflict")
            if row[1] == "confirmed" and row[2] != encoded:
                raise WorkerExecutionFenced("worker_local_receipt_conflict")
            connection.execute("UPDATE agent_worker_local_executions SET state='confirmed', receipt_json=? WHERE execution_id=?",
                               (encoded, execution_id))

    def mark_uncertain(self, execution_id, owner):
        with self.ledger.transaction() as connection:
            connection.execute("""UPDATE agent_worker_local_executions SET state='uncertain'
                WHERE execution_id=? AND owner=? AND state IN ('admitted', 'dispatched')""", (execution_id, owner))

    def get(self, execution_id):
        with self.ledger.transaction(write=False) as connection:
            row = connection.execute("SELECT owner, state, report_json, receipt_json FROM agent_worker_local_executions WHERE execution_id=?",
                                     (execution_id,)).fetchone()
        return None if row is None else dict(owner=row[0], state=row[1], report=json.loads(row[2] or '{}'), receipt=json.loads(row[3] or '{}'))
