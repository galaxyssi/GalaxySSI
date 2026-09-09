"""Bounded poll/renew/execute/report loop; never activated by an incoming peer."""
from concurrent.futures import CancelledError
from copy import deepcopy
import hashlib
import threading
import time
import uuid

from agent_work_pool import AgentWorkPool, ExecutionKey
from agent_worker_client_store import WorkerClientStore
from agent_worker_leases import _canonical
from agent_worker_local import WorkerExecutionFenced, WorkerExecutionJournal, WorkerLeaseGuard
from agent_worker_registry import _binding, _integer
from agent_worker_rpc import WorkerRpcError


class WorkerController:
    def __init__(self, rpc, get_peer, route, ledger, executor, *, max_parallel=10, clock=time.monotonic, rpc_timeout=2):
        _integer(max_parallel, 1, 10)
        if type(rpc_timeout) not in (int, float) or not 0.01 <= rpc_timeout <= 2:
            raise ValueError("Invalid worker RPC timeout")
        self.rpc, self.get_peer, self.route = rpc, get_peer, route
        self.binding = _binding(get_peer(route))
        self.owner = uuid.uuid4().hex
        self.store, self.journal = WorkerClientStore(ledger), WorkerExecutionJournal(ledger)
        self.executor, self.capacity, self.clock = executor, max_parallel, clock
        self.rpc_timeout = rpc_timeout
        self._control = AgentWorkPool(max_workers=4, max_pending=32)
        self._lock, self._stop = threading.RLock(), threading.Event()
        self._thread = None
        self._ops, self._jobs = {}, {}
        self._heartbeat_due = self._poll_due = self._pair_check_due = 0.0
        self._idle_poll_delay = 0.25
        self._jitter = (int(self.owner[:8], 16) % 1000) / 4000
        self._live_heartbeat = None
        self._error, self._state = "", "connecting"
        self.checkpoint = dict(phase="status", poll_sequence=1, heartbeat_sequence=1, session_epoch=0,
                               completed=0, failed=0, uncertain=0)
        self.store.open(self.owner, route, self.binding, self.checkpoint)

    def start(self):
        with self._lock:
            if self._thread is not None:
                raise WorkerExecutionFenced("worker_client_already_started")
            self._thread = threading.Thread(target=self._run, name="galaxyssi-worker-controller", daemon=True)
            try:
                self._thread.start()
            except BaseException:
                self.store.close(self.owner, clean=True, checkpoint=self.checkpoint)
                self._control.close(cancel_pending=True)
                self.executor.close()
                raise

    def _session(self):
        return dict(incarnation=self.owner, session_epoch=self.checkpoint["session_epoch"])

    def _queue(self, slot, operation, fields):
        if slot in self._ops:
            return
        request_id = self.store.intent(self.owner, slot, operation, fields)
        self._ops[slot] = dict(operation=operation, fields=deepcopy(fields), request_id=request_id,
                               future=None, retry_at=0.0, attempts=0)

    def _uncertain(self, identifier, code):
        job = self._jobs[identifier]
        if job["phase"] == "uncertain":
            return
        if job["guard"] is not None:
            job["guard"].invalidate()
        report = self._ops.get("report:" + identifier)
        if report is not None:
            fields = report["fields"]
            job["receipt_fields"] = dict(incarnation=self.owner, lease=deepcopy(fields["lease"]), sequence=1,
                report_digest=hashlib.sha256(_canonical(fields["report"]).encode()).hexdigest())
            job["receipt_due"] = self.clock()
        job["phase"] = "uncertain"
        job["job"] = None
        self.journal.mark_uncertain(identifier, self.owner)
        self.checkpoint["uncertain"] += 1
        self._error = code

    def _confirm_report(self, identifier, receipt):
        self.journal.confirm(identifier, self.owner, receipt)
        entry = self._jobs.pop(identifier)
        self.checkpoint["completed" if entry.get("report_status") == "completed" else "failed"] += 1
        self._heartbeat_due = self.clock()

    def _apply(self, slot, result):
        payload = result.payload
        if payload.get("ok") is not True:
            if payload.get("error") in {"worker_not_authorized", "worker_session_stale", "worker_source_mismatch",
                    "worker_pairing_unavailable", "worker_pairing_incomplete", "worker_protocol_unsupported"}:
                raise WorkerExecutionFenced("worker_coordinator_authorization_lost")
            if slot.startswith("receipt:"):
                identifier = slot.split(":", 1)[1]
                if identifier in self._jobs:
                    self._jobs[identifier]["receipt_fields"] = None
                self._error = "worker_receipt_reconciliation_rejected"
                return
            if slot.startswith(("renew:", "report:")):
                identifier = slot.split(":", 1)[1]
                if identifier in self._jobs:
                    # A report may commit before an already in-flight renewal.
                    if not (slot.startswith("renew:") and self._jobs[identifier]["phase"] == "reporting"
                            and payload.get("error") == "worker_execution_conflict"):
                        self._uncertain(identifier, "worker_job_rejected")
                return
            raise WorkerExecutionFenced("worker_coordinator_rejected")
        if slot == "status":
            worker = payload["worker"]
            self.checkpoint.update(phase="connect", expected_epoch=_integer(worker["session_epoch"], 0, 2**53 - 2))
        elif slot == "connect":
            worker = payload["worker"]
            epoch = self.checkpoint["expected_epoch"] + 1
            if worker.get("incarnation") != self.owner or worker.get("session_epoch") != epoch:
                raise WorkerExecutionFenced("worker_connect_response_mismatch")
            self.capacity = min(self.capacity, _integer(worker["max_parallel"], 1, 128))
            self.checkpoint.update(phase="running", session_epoch=epoch)
            self._state = "running"
        elif slot == "heartbeat":
            if (payload["worker"].get("incarnation") != self.owner
                    or payload["worker"].get("session_epoch") != self.checkpoint["session_epoch"]):
                raise WorkerExecutionFenced("worker_heartbeat_response_mismatch")
            self.checkpoint["heartbeat_sequence"] += 1
            if payload["worker"].get("connected") is True:
                self._live_heartbeat = self.clock()
                self._heartbeat_due = self.clock() + (5 if self._jobs else 10) + self._jitter
            else:
                self._heartbeat_due = self.clock()
        elif slot == "poll":
            self.checkpoint["poll_sequence"] += 1
            value = payload.get("job")
            self._idle_poll_delay = min(5, self._idle_poll_delay * 2) if value is None else 0.25
            self._poll_due = self.clock() + (self._idle_poll_delay + self._jitter if value is None else 0)
            if value is not None:
                identifier = self.journal.admit(self.binding, self.owner, value)
                if identifier not in self._jobs:
                    entry = dict(job=deepcopy(value), guard=None, phase="running", future=None, renew_due=self.clock() + 5)
                    self._jobs[identifier] = entry
                    try:
                        guard = entry["guard"] = WorkerLeaseGuard(result, clock=self.clock)
                    except WorkerExecutionFenced:
                        self._uncertain(identifier, "worker_received_expired_grant")
                        return
                    if self._stop.is_set():
                        self._uncertain(identifier, "worker_stopped_during_poll")
                    else:
                        try:
                            entry["future"] = self.executor.submit(self.binding, self.owner, value, guard)
                        except Exception:
                            self._uncertain(identifier, "worker_dispatch_failed")
        elif slot.startswith("renew:"):
            identifier = slot.split(":", 1)[1]
            if identifier in self._jobs and self._jobs[identifier]["phase"] != "uncertain":
                try:
                    self._jobs[identifier]["guard"].renew(result)
                    self._jobs[identifier]["renew_due"] = self.clock() + 5
                except WorkerExecutionFenced:
                    self._uncertain(identifier, "worker_renewal_fenced")
        elif slot.startswith("receipt:"):
            identifier = slot.split(":", 1)[1]
            if identifier in self._jobs:
                if payload.get("receipt") is not None:
                    self._confirm_report(identifier, payload["receipt"])
                else:
                    self._jobs[identifier]["receipt_due"] = self.clock() + 5 + self._jitter
        elif slot.startswith("report:"):
            identifier = slot.split(":", 1)[1]
            if identifier in self._jobs:
                receipt = {key: payload[key] for key in ("sequence", "status_sequence", "replayed")}
                self._confirm_report(identifier, receipt)

    def _responses(self):
        for slot, operation in list(self._ops.items()):
            future = operation["future"]
            if future is None or not future.done():
                continue
            try:
                result = future.result()
            except WorkerRpcError as error:
                if str(error) not in {"worker_rpc_timeout", "worker_rpc_publish_failed", "worker_rpc_busy"}:
                    raise WorkerExecutionFenced("worker_rpc_fenced") from error
                operation["future"] = None
                operation["retry_at"] = self.clock() + min(4, 0.25 * 2 ** min(operation["attempts"], 4)) + self._jitter
                if slot == "poll":
                    operation["ambiguous"] = True
                self._error = "worker_transport_retry"
                continue
            except CancelledError:
                continue
            self.store.received(self.owner, slot, result.payload)
            if (result.payload.get("error") == "worker_heartbeat_expired"
                    and (slot == "poll" or slot.startswith(("report:", "renew:")))):
                self._live_heartbeat = None
                self._heartbeat_due = self.clock()
                operation["future"] = None
                operation["retry_at"] = self.clock() + 1
                if slot == "poll":
                    operation["known_ungranted"] = not operation.get("ambiguous", False)
                continue
            self._apply(slot, result)
            self.store.consume(self.owner, slot, self.checkpoint)
            self._ops.pop(slot)

    def tick(self):
        with self._lock:
            now = self.clock()
            if now >= self._pair_check_due:
                if _binding(self.get_peer(self.route)) != self.binding:
                    raise WorkerExecutionFenced("worker_coordinator_pairing_changed")
                self._pair_check_due = now + 1
            self._responses()
            for slot, operation in list(self._ops.items()):
                if (slot.startswith(("renew:", "report:", "receipt:")) and slot.split(":", 1)[1] not in self._jobs
                        and (operation["future"] is None or operation["future"].cancel())):
                    self.store.consume(self.owner, slot, self.checkpoint)
                    self._ops.pop(slot)
            for identifier, job in list(self._jobs.items()):
                if job["phase"] == "uncertain":
                    if job["future"] is not None and job["future"].done():
                        job["future"] = None
                    if not self._stop.is_set() and job.get("receipt_fields") and now >= job["receipt_due"]:
                        self._queue("receipt:" + identifier, "receipt", job["receipt_fields"])
                    continue
                try:
                    job["guard"].require_live()
                except WorkerExecutionFenced:
                    self._uncertain(identifier, "worker_lease_expired")
                    continue
                future = job["future"]
                if job["phase"] == "running" and future is not None and future.done():
                    try:
                        report = future.result()
                    except Exception:
                        self._uncertain(identifier, "worker_execution_failed")
                        continue
                    job["phase"] = "reporting"
                    job["report_status"] = report["status"]
                    self._queue("report:" + identifier, "report", dict(self._session(), sequence=1,
                        lease=job["guard"].capability(), report=report))
                if not self._stop.is_set() and now >= job["renew_due"]:
                    self._queue("renew:" + identifier, "renew", dict(self._session(), lease=job["guard"].capability()))
            if not self._stop.is_set():
                phase = self.checkpoint["phase"]
                if phase == "status":
                    self._queue("status", "status", {})
                elif phase == "connect":
                    self._queue("connect", "connect", dict(incarnation=self.owner,
                        expected_session_epoch=self.checkpoint["expected_epoch"], providers=["codex"]))
                else:
                    if now >= self._heartbeat_due:
                        poll = self._ops.get("poll")
                        reservation = int(poll is not None and not poll.get("known_ungranted", False))
                        slots = max(0, self.capacity - len(self._jobs) - reservation)
                        self._queue("heartbeat", "heartbeat", dict(self._session(),
                            sequence=self.checkpoint["heartbeat_sequence"], available_slots=slots))
                    if (self._live_heartbeat is not None and now - self._live_heartbeat < 10
                            and len(self._jobs) < self.capacity and now >= self._poll_due):
                        self._queue("poll", "poll", dict(self._session(), sequence=self.checkpoint["poll_sequence"]))
                for slot, operation in self._ops.items():
                    if slot.startswith(("renew:", "report:")):
                        entry = self._jobs.get(slot.split(":", 1)[1])
                        if entry is None or entry["phase"] == "uncertain":
                            continue
                    if operation["future"] is None and now >= operation["retry_at"]:
                        key = ExecutionKey("worker-control", slot, self.owner, uuid.uuid4().hex, 1)
                        operation["attempts"] += 1
                        if slot == "poll":
                            operation["known_ungranted"] = False
                        operation["future"] = self._control.submit(key, lambda op=operation: self.rpc.request(
                            self.route, op["operation"], op["fields"], request_id=op["request_id"], timeout=self.rpc_timeout))

    def _run(self):
        try:
            while not self._stop.wait(0.05):
                self.tick()
            # Drain already transmitted responses without pulling new work.
            deadline = self.clock() + 3
            while self.clock() < deadline:
                self.tick()
                with self._lock:
                    waiting = any(op["future"] is not None and not op["future"].done() for op in self._ops.values())
                if not waiting:
                    break
                time.sleep(0.05)
        except Exception:
            self._error = "worker_controller_fenced"
            self._stop.set()
        finally:
            with self._lock:
                for job in self._jobs.values():
                    if job["guard"] is not None:
                        job["guard"].invalidate()
            control_stopped = self._control.close(cancel_pending=True, timeout=5)
            processes_stopped = self.executor.close(timeout=10)
            with self._lock:
                clean = control_stopped and processes_stopped and not self._jobs and "poll" not in self._ops
                self._state = "stopped" if clean else "recovery_required"
                try:
                    self.store.close(self.owner, clean=clean, checkpoint=self.checkpoint)
                except Exception:
                    self._state = "recovery_required"
                    self._error = "worker_client_storage_failed"

    def stop(self, *, wait=True, timeout=20):
        thread = self._thread
        if thread is not None and not thread.is_alive():
            return True
        self._stop.set()
        with self._lock:
            self._state = "stopping"
            for job in self._jobs.values():
                if job["guard"] is not None:
                    job["guard"].invalidate()
        if thread is None:
            self._control.close(cancel_pending=True)
            self.executor.close()
            self.store.close(self.owner, clean=True, checkpoint=self.checkpoint)
            self._state = "stopped"
            return True
        if wait and thread is not None and thread is not threading.current_thread():
            thread.join(timeout)
        return thread is None or not thread.is_alive()

    def is_alive(self):
        return self._thread is not None and self._thread.is_alive()

    def snapshot(self):
        with self._lock:
            return dict(state=self._state, max_parallel=self.capacity,
                active_tasks=sum(job["phase"] == "running" for job in self._jobs.values()),
                awaiting_reports=sum(job["phase"] == "reporting" for job in self._jobs.values()),
                uncertain_tasks=sum(job["phase"] == "uncertain" for job in self._jobs.values()),
                completed_tasks=self.checkpoint["completed"], failed_tasks=self.checkpoint["failed"],
                pending_rpcs=len(self._ops), last_error=self._error)
