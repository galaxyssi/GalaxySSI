"""Loopback-only disclosure policy; pairing or MQTT cannot configure routing."""
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, ConfigDict
from agent_worker_registry import WorkerAccessError
from agent_worker_routing import routing_for

router = APIRouter(prefix="/api/agent/worker-routes", tags=["agent-workers"])


class RoutingSettings(BaseModel):
    model_config = ConfigDict(extra="forbid")
    worker_routes: list[str]


def context(request):
    from main import require_desktop_api_token
    require_desktop_api_token(request)
    import mqtt_bridge
    return routing_for(mqtt_bridge, create=True)


@router.put("/{app_route}")
def configure(app_route: str, settings: RoutingSettings, request: Request):
    routing = context(request)
    try:
        return routing.configure(app_route, settings.worker_routes)
    except WorkerAccessError as error:
        raise HTTPException(status_code=409, detail=str(error)) from None


@router.get("/{app_route}")
def status(app_route: str, request: Request):
    return context(request).status(app_route)


@router.delete("/{app_route}")
def disable(app_route: str, request: Request):
    return context(request).disable(app_route)
