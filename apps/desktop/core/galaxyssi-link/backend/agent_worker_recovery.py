"""Reconcile committed reports after a stopped controller, never restart a model."""
import hashlib
import os
from pathlib import Path
import re
import time

from agent_worker_client_store import WorkerClientStore
from agent_worker_leases import _canonical
from agent_worker_local import WorkerExecutionFenced, WorkerExecutionJournal
from agent_worker_ownership import WorkerClientOwnership
from agent_worker_registry import _binding
from agent_worker_rpc import WorkerRpcError


def recover_worker_reports(ledger, rpc, get_peer, route, *, ownership=None, execution_root=None):
    store, journal = WorkerClientStore(ledger), WorkerExecutionJournal(ledger)
    stored = store.read()
    if stored is None or stored["state"] == "closed":
        return True
    if ownership is None:
        held = WorkerClientOwnership(ledger).acquire()
        try:
            return recover_worker_reports(ledger, rpc, get_peer, route, ownership=held, execution_root=execution_root)
        finally:
            held.release()
    ownership.require(ledger)
    binding = _binding(get_peer(route))
    owner = stored["owner"]
    if stored["route"] != route or stored["binding"] != binding:
        raise WorkerExecutionFenced("worker_client_recovery_required")
    if stored["state"] not in {"open", "recovery_required"}:
        raise WorkerExecutionFenced("worker_client_recovery_required")
    checkpoint = stored["checkpoint"]
    if stored["state"] == "open" or checkpoint.get("process_ownership_version") == 1:
        root = Path(execution_root or (Path(ledger.path).parent / "worker-executions")).resolve()
        if (checkpoint.get("process_ownership_version") != 1 or not checkpoint.get("execution_root")
                or os.path.normcase(str(Path(checkpoint["execution_root"]).resolve())) != os.path.normcase(str(root))):
            raise WorkerExecutionFenced("worker_client_recovery_required")
        from process_recovery_journal import assert_quiescent, task_journal, ProcessTerminationPending
        for identifier in store.pending_executions(owner):
            if not re.fullmatch(r"[0-9a-f]{64}", identifier):
                raise WorkerExecutionFenced("worker_client_recovery_record_mismatch")
            try:
                assert_quiescent(task_journal(root, identifier))
            except ProcessTerminationPending as error:
                raise WorkerExecutionFenced("worker_client_previous_processes_unverified") from error
        if stored["state"] == "open":
            store.mark_process_recovered(owner, route, binding)
    deadline = time.monotonic() + 10
    for slot, request_id, fields in store.recovery_intents(owner, route, binding):
        if time.monotonic() >= deadline:
            break
        if _binding(get_peer(route)) != binding:
            raise WorkerExecutionFenced("worker_coordinator_pairing_changed")
        identifier = slot.split(":", 1)[-1]
        local = journal.get(identifier)
        lease = fields.get("lease", {})
        expected = hashlib.sha256(_canonical([binding, lease.get("key"), lease.get("epoch")]).encode()).hexdigest()
        if (not slot.startswith(("report:", "receipt:")) or identifier != expected or fields.get("incarnation") != owner
                or fields.get("sequence") != 1 or local is None or local["owner"] != owner
                or local["state"] not in {"reporting", "confirmed"}):
            raise WorkerExecutionFenced("worker_client_recovery_record_mismatch")
        digest = hashlib.sha256(_canonical(local["report"]).encode()).hexdigest()
        if ((slot.startswith("report:") and local["report"] != fields.get("report"))
                or (slot.startswith("receipt:") and digest != fields.get("report_digest"))):
            raise WorkerExecutionFenced("worker_client_recovery_record_mismatch")
        query = dict(incarnation=owner, lease=lease, sequence=1,
            report_digest=digest)
        # Derived from the persisted report intent, stable across recovery retries.
        query_id = hashlib.sha256((request_id + ":receipt").encode()).hexdigest()
        try:
            result = rpc.request(route, "receipt", query, request_id=query_id,
                timeout=max(0.01, min(1, deadline - time.monotonic())))
        except WorkerRpcError:
            continue
        if _binding(get_peer(route)) != binding:
            raise WorkerExecutionFenced("worker_coordinator_pairing_changed")
        if result.payload.get("ok") is not True or result.payload.get("receipt") is None:
            continue
        journal.confirm(identifier, owner, result.payload["receipt"])
        store.settle_recovered_report(owner, route, binding, slot, local["report"])
    return store.finish_report_recovery(owner, route, binding)
