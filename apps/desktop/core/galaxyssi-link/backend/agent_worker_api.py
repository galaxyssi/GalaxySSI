"""Explicit loopback operator authorization for paired worker nodes."""
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, ConfigDict, StrictInt

from agent_worker_mqtt import worker_registry
from agent_worker_registry import WorkerAccessError

router = APIRouter(prefix="/api/agent/workers", tags=["agent-workers"])


class WorkerEnrollment(BaseModel):
    model_config = ConfigDict(extra="forbid")
    worker_id: str
    max_parallel: StrictInt
    providers: list[str]


def _context(request, route, *, require_peer=True):
    from main import require_desktop_api_token
    require_desktop_api_token(request)
    import mqtt_bridge
    peer = mqtt_bridge.get_client(route)
    if peer is None and require_peer:
        raise HTTPException(status_code=404, detail="worker_pairing_unavailable")
    return worker_registry(mqtt_bridge), peer


@router.put("/{route}")
def enroll_worker(route: str, req: WorkerEnrollment, request: Request):
    registry, peer = _context(request, route)
    try:
        return registry.enroll(peer, req.worker_id, max_parallel=req.max_parallel, providers=req.providers)
    except WorkerAccessError as error:
        raise HTTPException(status_code=409, detail=str(error)) from None


@router.get("/{route}")
def worker_status(route: str, request: Request):
    registry, peer = _context(request, route)
    try:
        return registry.status(peer, peer["signal_name"])
    except WorkerAccessError as error:
        raise HTTPException(status_code=403, detail=str(error)) from None


@router.delete("/{route}")
def revoke_worker(route: str, request: Request):
    registry, _peer = _context(request, route, require_peer=False)
    try:
        return registry.revoke(route)
    except WorkerAccessError as error:
        raise HTTPException(status_code=404, detail=str(error)) from None
