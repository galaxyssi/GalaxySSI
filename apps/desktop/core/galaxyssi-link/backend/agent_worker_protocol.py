"""Allowlisted worker RPCs and durable original-App notification checkpoints."""
import hashlib
import hmac
import re
import time

from agent_request_snapshot import restore_request_options
from agent_work_pool import ExecutionKey
from agent_worker_leases import WorkerLease, WorkerLeaseConflict, _canonical, _key
from agent_worker_queue import AgentWorkerQueue, TERMINAL
from agent_worker_registry import WorkerAccessError, _integer, _identifier


def _text(value, limit, *, required=False):
    if not isinstance(value, str) or len(value.encode("utf-8")) > limit or (required and not value.strip()):
        raise WorkerAccessError("worker_text_invalid")
    return value


class AgentWorkerProtocol:
    def __init__(self, registry):
        self.registry = registry
        self.queue = AgentWorkerQueue(registry)
        self.ledger = registry.ledger
        with self.ledger.transaction() as connection:
            connection.execute("""CREATE TABLE IF NOT EXISTS agent_worker_report_receipts (
                task_id TEXT PRIMARY KEY, epoch INTEGER NOT NULL, sequence INTEGER NOT NULL,
                digest TEXT NOT NULL, status_sequence INTEGER NOT NULL
            )""")
            connection.execute("""CREATE TABLE IF NOT EXISTS agent_worker_notifications (
                task_id TEXT PRIMARY KEY, generation INTEGER NOT NULL, status_sequence INTEGER NOT NULL,
                attempted_at INTEGER NOT NULL DEFAULT 0
            )""")

    @staticmethod
    def _notify(connection, record):
        connection.execute("""INSERT INTO agent_worker_notifications (task_id, generation, status_sequence) VALUES (?, ?, ?)
            ON CONFLICT(task_id) DO UPDATE SET generation=excluded.generation,
            status_sequence=excluded.status_sequence""",
            (record["task_id"], record.get("execution_generation", 1), record["status_seq"]))

    @staticmethod
    def _capability(grant):
        return {"key": _key(grant.key), "epoch": grant.epoch, "token": grant.token,
                "expires_at_ms": grant.expires_at_ms}

    @staticmethod
    def _parse_grant(worker, payload):
        value = payload.get("lease")
        if not isinstance(value, dict) or set(value) != {"key", "epoch", "token", "expires_at_ms"}:
            raise WorkerAccessError("worker_lease_invalid")
        scope = value["key"]
        if not isinstance(scope, list) or len(scope) != 5:
            raise WorkerAccessError("worker_lease_invalid")
        key = ExecutionKey(*scope)
        _key(key)
        grant = WorkerLease(key, worker["worker_id"], worker["incarnation"],
            _integer(value["epoch"], 1, 2**53 - 1), _integer(value["expires_at_ms"], 1, 2**53 - 1),
            _text(value["token"], 128, required=True))
        return grant

    def _require_grant(self, connection, worker, payload):
        grant = self._parse_grant(worker, payload)
        self.queue.leases._require(connection, grant)
        return grant

    def poll(self, peer, source, payload):
        with self.ledger.transaction() as connection:
            job = self.queue.poll(peer, source, payload, connection=connection)
            if job is None:
                return {"job": None}
            record = job.record
            options = restore_request_options(record.get("request_snapshot"))
            if record.get("attachments") and not options.get("attachments"):
                raise WorkerAccessError("worker_attachment_snapshot_required")
            result = {"job": {"lease": self._capability(job.lease), "provider": job.provider,
                "prompt": _text(record.get("prompt"), 256 * 1024, required=True), "options": options},
                "server_time_ms": time.time_ns() // 1_000_000}
            if len(_canonical(result).encode("utf-8")) > 512 * 1024:
                raise WorkerAccessError("worker_dispatch_too_large")
            # Encoding validation remains inside the grant transaction.
            self._notify(connection, record)
            return result

    def renew(self, peer, source, payload):
        with self.ledger.transaction() as connection:
            worker = self.registry.require_session(connection, peer, source, payload)
            grant = self._require_grant(connection, worker, payload)
            record = self.queue.tasks.get(grant.key.task, connection=connection)
            if record is None or record.get("status") in TERMINAL:
                raise WorkerLeaseConflict("A missing or terminal execution cannot be renewed")
            renewed = self.queue.leases.renew(grant, connection=connection)
            return {"lease": self._capability(renewed), "server_time_ms": time.time_ns() // 1_000_000}

    def receipt(self, peer, source, payload):
        """Read an exact committed terminal receipt without reviving a lease."""
        incarnation = _identifier(payload.get("incarnation"))
        sequence = _integer(payload.get("sequence"), 1, 2**53 - 1)
        digest = payload.get("report_digest")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise WorkerAccessError("worker_report_digest_invalid")
        with self.ledger.transaction(write=False) as connection:
            worker = self.registry._authorized(connection, peer, source)
            grant = self._parse_grant({**worker, "incarnation": incarnation}, payload)
            value = self._capability(grant)
            row = self.queue.leases._row(connection, value["key"][3])
            if (row is None or row["worker"] != worker["worker_id"] or row["incarnation"] != incarnation
                    or row["scope"] != _canonical(value["key"]) or row["epoch"] != value["epoch"]
                    or not hmac.compare_digest(row["token"], value["token"])):
                raise WorkerLeaseConflict("Receipt belongs to another execution")
            receipt = connection.execute("""SELECT epoch, sequence, digest, status_sequence
                FROM agent_worker_report_receipts WHERE task_id=?""", (value["key"][3],)).fetchone()
            if receipt is None:
                return {"receipt": None}
            if receipt[:3] != (value["epoch"], sequence, digest):
                raise WorkerLeaseConflict("Receipt does not match the reported result")
            task = self.queue.tasks.get(value["key"][3], connection=connection)
            if task is None or task.get("status") not in TERMINAL or task.get("status_seq") != receipt[3]:
                return {"receipt": None}
            scope = [task.get("client_route_id"), task.get("client_conversation_id") or task.get("conversation_id"),
                     task.get("client_turn_id"), task.get("task_id"), task.get("execution_generation", 1)]
            if scope != value["key"]:
                raise WorkerLeaseConflict("Receipt snapshot belongs to another execution")
            return {"receipt": {"sequence": sequence, "status_sequence": receipt[3], "replayed": True}}

    def report(self, peer, source, payload):
        report = payload.get("report")
        if not isinstance(report, dict) or set(report) != {"status", "text", "error", "current_step"}:
            raise WorkerAccessError("worker_report_fields_invalid")
        if report["status"] not in {"running", "completed", "failed", "cancelled", "timed_out"}:
            raise WorkerAccessError("worker_report_status_invalid")
        normalized = {"status": report["status"], "text": _text(report["text"], 8192),
                      "error": _text(report["error"], 2048), "current_step": _text(report["current_step"], 1024)}
        if normalized["status"] == "completed" and (not normalized["text"].strip() or normalized["error"]):
            raise WorkerAccessError("worker_completed_result_invalid")
        if normalized["status"] in {"failed", "cancelled", "timed_out"} and not normalized["error"].strip():
            raise WorkerAccessError("worker_failure_reason_required")
        sequence = _integer(payload.get("sequence"), 1, 2**53 - 1)
        digest = hashlib.sha256(_canonical(normalized).encode()).hexdigest()
        with self.ledger.transaction() as connection:
            worker = self.registry.require_session(connection, peer, source, payload)
            grant = self._require_grant(connection, worker, payload)
            receipt = connection.execute("""SELECT epoch, sequence, digest, status_sequence
                FROM agent_worker_report_receipts WHERE task_id=?""", (grant.key.task,)).fetchone()
            if receipt and receipt[0] == grant.epoch and receipt[1] == sequence and receipt[2] == digest:
                return {"sequence": sequence, "status_sequence": receipt[3], "replayed": True}
            previous_sequence = receipt[1] if receipt and receipt[0] == grant.epoch else 0
            if sequence != previous_sequence + 1:
                raise WorkerLeaseConflict("Worker report is reordered or reused")
            current = self.queue.tasks.get(grant.key.task, connection=connection)
            if current is None or current.get("status") in TERMINAL:
                raise WorkerLeaseConflict("A missing or terminal execution cannot accept progress")
            now = time.time_ns() // 1_000_000
            snapshot = {**current, "status": normalized["status"], "result": normalized["text"],
                "error": normalized["error"], "current_step": normalized["current_step"],
                "updated_at": max(now, current.get("updated_at", 0)), "status_seq": current.get("status_seq", 0) + 1}
            if snapshot["status"] in TERMINAL:
                snapshot["completed_at"] = snapshot["updated_at"]
            self.queue.apply_task(grant, sequence, snapshot, connection=connection)
            connection.execute("""INSERT INTO agent_worker_report_receipts VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(task_id) DO UPDATE SET epoch=excluded.epoch, sequence=excluded.sequence,
                digest=excluded.digest, status_sequence=excluded.status_sequence""",
                (grant.key.task, grant.epoch, sequence, digest, snapshot["status_seq"]))
            self._notify(connection, snapshot)
            return {"sequence": sequence, "status_sequence": snapshot["status_seq"], "replayed": False}

    def notifications(self, limit=8):
        with self.ledger.transaction(write=False) as connection:
            return connection.execute("""SELECT task_id, generation, status_sequence
                FROM agent_worker_notifications ORDER BY attempted_at, rowid LIMIT ?""", (limit,)).fetchall()

    def attempted_notification(self, task_id, generation, sequence):
        with self.ledger.transaction() as connection:
            connection.execute("""UPDATE agent_worker_notifications SET attempted_at=?
                WHERE task_id=? AND generation=? AND status_sequence=?""",
                (time.time_ns(), task_id, generation, sequence))

    def acknowledge_notification(self, task_id, generation, sequence):
        with self.ledger.transaction() as connection:
            connection.execute("""DELETE FROM agent_worker_notifications
                WHERE task_id=? AND generation=? AND status_sequence=?""", (task_id, generation, sequence))
