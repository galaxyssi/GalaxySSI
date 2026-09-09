"""Local operator activation of this Desktop as a worker for one paired coordinator."""
from pathlib import Path
import threading
from typing import Literal

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, StrictInt

from agent_worker_client_store import WorkerClientStore
from agent_worker_controller import WorkerController
from agent_worker_execution import WorkerProcessExecutor
from agent_worker_local import WorkerExecutionFenced, WorkerExecutionJournal
from agent_worker_ownership import WorkerClientOwnership
from agent_worker_mqtt import worker_rpc_client
from agent_worker_registry import WorkerAccessError
from agent_worker_rpc import WorkerRpcError

router = APIRouter(prefix="/api/agent/worker-client", tags=["agent-worker-client"])
_LOCK = threading.RLock()


class WorkerActivation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    max_parallel: StrictInt = Field(default=10, ge=1, le=10)
    sandbox: Literal["read-only", "workspace-write"] = "read-only"


def _context(request):
    from main import require_desktop_api_token
    require_desktop_api_token(request)
    import mqtt_bridge
    return mqtt_bridge


def activate_worker(bridge, route, settings):
    with _LOCK:
        current = getattr(bridge, "_worker_client_controller", None)
        if current is not None and current.is_alive():
            if current.route == route and current.local_settings == (settings.max_parallel, settings.sandbox):
                return current.snapshot()
            raise WorkerExecutionFenced("worker_client_already_active")
        if bridge.get_client(route) is None:
            raise WorkerExecutionFenced("worker_pairing_unavailable")
        ledger = bridge.agent_task_manager._run_events.ledger
        rpc = worker_rpc_client(bridge)
        from agent_worker_recovery import recover_worker_reports
        ownership = WorkerClientOwnership(ledger).acquire()
        executor = None
        root = Path(ledger.path).parent / "worker-executions"
        try:
            if not recover_worker_reports(ledger, rpc, bridge.get_client, route, ownership=ownership, execution_root=root):
                raise WorkerExecutionFenced("worker_client_recovery_required")
            executor = WorkerProcessExecutor(WorkerExecutionJournal(ledger), root,
                sandbox=settings.sandbox, max_workers=settings.max_parallel,
                work_pool=bridge.agent_task_manager.model_work_pool)
            controller = WorkerController(rpc, bridge.get_client, route, ledger, executor,
                max_parallel=settings.max_parallel, ownership=ownership)
            controller.local_settings = (settings.max_parallel, settings.sandbox)
            controller.start()
        except BaseException:
            if executor is not None:
                executor.close()
            ownership.release()
            raise
        bridge._worker_client_controller = controller
        return controller.snapshot()


def stop_worker_controller(bridge, *, wait=True):
    with _LOCK:
        current = getattr(bridge, "_worker_client_controller", None)
    return current is None or current.stop(wait=wait)


@router.put("/{route}")
def enable_worker_client(route: str, settings: WorkerActivation, request: Request):
    bridge = _context(request)
    try:
        return activate_worker(bridge, route, settings)
    except (WorkerExecutionFenced, WorkerAccessError, WorkerRpcError, ValueError) as error:
        raise HTTPException(status_code=409, detail=str(error)) from None


@router.get("/{route}")
def worker_client_status(route: str, request: Request):
    bridge = _context(request)
    with _LOCK:
        current = getattr(bridge, "_worker_client_controller", None)
        if current is not None and current.route == route:
            return current.snapshot()
        stored = WorkerClientStore(bridge.agent_task_manager._run_events.ledger).read()
        if stored and stored["route"] == route:
            return {"state": "disabled" if stored["state"] == "closed" else "recovery_required",
                    "pending_rpcs": stored["pending"]}
        return {"state": "disabled", "pending_rpcs": 0}


@router.delete("/{route}")
def disable_worker_client(route: str, request: Request):
    bridge = _context(request)
    with _LOCK:
        current = getattr(bridge, "_worker_client_controller", None)
        if current is None or current.route != route:
            return {"state": "disabled"}
        current.stop(wait=False)
        return current.snapshot()
