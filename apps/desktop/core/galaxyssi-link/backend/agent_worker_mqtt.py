"""Reserved worker controls routed only after Signal envelope authentication."""
import json
import threading

from agent_worker_registry import AgentWorkerRegistry, WorkerAccessError

_LOCK = threading.Lock()
PROTOCOL = "galaxyssi.worker-control.v1"


def worker_registry(bridge):
    with _LOCK:
        current = getattr(bridge, "_worker_enrollment_registry", None)
        ledger = bridge.agent_task_manager._run_events.ledger
        if current is None or current.ledger.path.resolve() != ledger.path.resolve():
            current = AgentWorkerRegistry(ledger)
            bridge._worker_enrollment_registry = current
        return current


def route_worker_payload(bridge, mqttc, wire_payload, payload, *, client_route_id, source_id):
    kind = str(payload.get("type") or "").lower()
    if not kind.startswith("agent_worker_"):
        return False
    if kind == "agent_worker_response":
        return True
    response = {"type": "agent_worker_response", "protocol": PROTOCOL, "ok": False}
    try:
        if len(json.dumps(payload, ensure_ascii=False).encode("utf-8")) > 16 * 1024:
            raise WorkerAccessError("worker_request_too_large")
        if payload.get("protocol") != PROTOCOL:
            raise WorkerAccessError("worker_protocol_unsupported")
        request_id = payload.get("request_id")
        if not isinstance(request_id, str) or not 1 <= len(request_id) <= 128:
            raise WorkerAccessError("worker_request_id_invalid")
        response["request_id"] = request_id
        peer = bridge.get_client(client_route_id)
        if not peer or peer.get("client_route_id") != client_route_id:
            raise WorkerAccessError("worker_pairing_unavailable")
        registry = worker_registry(bridge)
        if kind == "agent_worker_status":
            result = registry.status(peer, source_id)
        elif kind == "agent_worker_connect":
            result = registry.connect(peer, source_id, payload)
        elif kind == "agent_worker_heartbeat":
            result = registry.heartbeat(peer, source_id, payload)
        else:
            raise WorkerAccessError("worker_operation_unsupported")
        response.update(ok=True, worker=result)
    except WorkerAccessError as error:
        response["error"] = str(error)
    bridge._publish_phone_payload(mqttc, wire_payload, response)
    return True
