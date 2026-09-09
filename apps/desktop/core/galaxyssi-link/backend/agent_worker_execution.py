"""Owned child execution of a deduplicated worker grant; no automatic enrollment."""
from copy import deepcopy
from concurrent.futures import wait
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

from agent_worker_local import WorkerExecutionFenced
from agent_work_pool import AgentQueueFull, AgentWorkPool, ExecutionKey


class WorkerProcessExecutor:
    """One child tree per active job, called from the bounded Agent work pool.

    The caller maintains the guard with authenticated renewals. This adapter does
    not poll a coordinator, grant permissions or restart ambiguous executions.
    """

    def __init__(self, journal, root, *, sandbox="read-only", max_workers=10, work_pool=None):
        if sandbox not in {"read-only", "workspace-write"}:
            raise ValueError("Worker execution requires a bounded local sandbox policy")
        self.journal, self.root, self.sandbox = journal, Path(root).resolve(), sandbox
        if type(max_workers) is not int or not 1 <= max_workers <= 128:
            raise ValueError("Worker limit is outside supported bounds")
        self._owns_pool = work_pool is None
        self._pool = work_pool if work_pool is not None else AgentWorkPool(max_workers=max_workers, max_pending=max_workers)
        self._max_outstanding = max_workers * 2 if self._owns_pool else max_workers
        self._lock, self._guards, self._closed = threading.RLock(), {}, False
        self._request_bytes, self._max_request_bytes = 0, 8 * 1024 * 1024

    def submit(self, coordinator_binding, owner, job, guard):
        import hashlib
        from agent_worker_execution_child import policy_for_job
        guard.require_live()
        job = deepcopy(job)
        request_bytes = len(json.dumps(job, ensure_ascii=False, allow_nan=False).encode("utf-8"))
        if job.get("provider") != "codex":
            raise WorkerExecutionFenced("worker_provider_not_implemented")
        policy = policy_for_job(job)
        capability = guard.capability()
        if any(job.get("lease", {}).get(key) != capability[key] for key in ("key", "epoch", "token")):
            raise WorkerExecutionFenced("worker_guard_job_mismatch")
        execution_id = self.journal.admit(coordinator_binding, owner, job)
        if self.journal.get(execution_id)["owner"] != owner:
            raise WorkerExecutionFenced("worker_previous_process_requires_reconciliation")
        scope = capability["key"]
        app = hashlib.sha256(json.dumps([coordinator_binding, scope[0]]).encode()).hexdigest()
        key = ExecutionKey(app, scope[1], scope[2], execution_id, scope[4])
        with self._lock:
            if self._closed:
                raise WorkerExecutionFenced("worker_executor_closed")
            existing = self._guards.get(execution_id)
            if existing:
                return existing[1]
            if len(self._guards) >= self._max_outstanding:
                raise AgentQueueFull("Worker outstanding job budget is full")
            if self._request_bytes + request_bytes > self._max_request_bytes:
                raise AgentQueueFull("Worker request byte budget is full")
            future = self._pool.submit(key, lambda: self._execute(execution_id, owner, job, guard, policy.task_budget.max_elapsed_seconds))
            self._guards[execution_id] = (guard, future, key)
            self._request_bytes += request_bytes
            def released(completed):
                with self._lock:
                    self._guards.pop(execution_id, None)
                    self._request_bytes -= request_bytes
                if completed.cancelled():
                    self.journal.mark_uncertain(execution_id, owner)
            future.add_done_callback(released)
            return future

    def snapshot(self):
        with self._lock:
            return self._pool.snapshot() | {"request_bytes": self._request_bytes, "max_request_bytes": self._max_request_bytes}

    def close(self, *, timeout=10):
        with self._lock:
            self._closed = True
            owned = list(self._guards.values())
            for guard, _, _ in owned:
                guard.invalidate()
        if self._owns_pool:
            return self._pool.close(cancel_pending=True, timeout=timeout)
        # A worker client borrows the Desktop pool; never shut down other sessions.
        for _, _, key in owned:
            self._pool.cancel(key)
        futures = [future for _, future, _ in owned if not future.done()]
        if futures:
            wait(futures, timeout=max(0.0, timeout))
        return all(future.done() for future in futures)

    def _execute(self, execution_id, owner, job, guard, time_budget):
        from owned_process import owned_process_scope, popen
        from process_recovery_journal import task_journal, assert_quiescent
        if os.name != "nt":
            raise WorkerExecutionFenced("worker_owned_process_platform_unsupported")
        if job["provider"] != "codex":
            raise WorkerExecutionFenced("worker_provider_not_implemented")
        existing = self.journal.get(execution_id)
        guard.require_live()
        if existing["owner"] != owner:
            raise WorkerExecutionFenced("worker_previous_process_requires_reconciliation")
        if existing["state"] in {"reporting", "confirmed"}:
            return existing["report"]
        if not self.journal.begin(execution_id, owner):
            raise WorkerExecutionFenced("worker_execution_already_dispatched")
        process = None
        started = time.monotonic()
        try:
            guard.require_live()
            directory = self.root / execution_id
            directory.mkdir(parents=True, exist_ok=False)
            ownership = task_journal(self.root, execution_id)
            assert_quiescent(ownership)
            request = {"execution_id": execution_id, "provider": job["provider"], "prompt": job["prompt"],
                       "options": job["options"], "workspace": str(directory), "sandbox": self.sandbox}
            request_path = directory / "worker-request.json"
            with request_path.open("x", encoding="utf-8") as stream:
                json.dump(request, stream, ensure_ascii=False, allow_nan=False)
                stream.flush()
                os.fsync(stream.fileno())
            guard.require_live()
            environment = dict(os.environ, GALAXYSSI_STATE_DIR=str(directory / "state"), PYTHONIOENCODING="utf-8")
            child = Path(__file__).with_name("agent_worker_execution_child.py")
            with tempfile.TemporaryFile() as output, owned_process_scope(ownership):
                process = popen([sys.executable, str(child), str(request_path)], cwd=str(directory),
                    stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.DEVNULL, env=environment,
                    creationflags=subprocess.CREATE_NO_WINDOW)
                while True:
                    remaining = guard.require_live()
                    if time_budget > 0:
                        remaining = min(remaining, time_budget - (time.monotonic() - started))
                        if remaining <= 0:
                            raise WorkerExecutionFenced("worker_task_time_budget")
                    try:
                        process.wait(timeout=min(0.1, remaining))
                        break
                    except subprocess.TimeoutExpired:
                        pass
                guard.require_live()
                returncode = process.returncode
                process.close()
                process = None
                assert_quiescent(ownership)
                if returncode != 0:
                    raise WorkerExecutionFenced("worker_child_exit_failed")
                output.seek(0)
                raw = output.read(16 * 1024 + 1)
                if len(raw) > 16 * 1024:
                    raise WorkerExecutionFenced("worker_child_output_too_large")
                report = json.loads(raw)
                guard.require_live()
                self.journal.stage_report(execution_id, owner, report)
                return report
        except BaseException:
            try:
                if process is not None:
                    process.close()
            finally:
                self.journal.mark_uncertain(execution_id, owner)
            raise
