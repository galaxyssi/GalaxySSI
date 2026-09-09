"""Reserved worker controls routed only after Signal envelope authentication."""
import json
import sqlite3
import threading

from agent_worker_registry import AgentWorkerRegistry, WorkerAccessError
from agent_worker_rpc import AgentWorkerRpcClient, PROTOCOL, WorkerRpcError, request_digest
from agent_worker_protocol import AgentWorkerProtocol
from agent_worker_leases import WorkerLeaseConflict
from agent_task_store import AgentTaskWriteConflict
from agent_run_kernel import AgentRunIdentityConflict

_LOCK = threading.Lock()


def worker_rpc_client(bridge):
    """Explicit local entry point; inbound packets must never create a client."""
    with _LOCK:
        stopped = getattr(bridge, "mqtt_lifecycle_stop_event", None)
        if stopped is not None and stopped.is_set():
            raise WorkerRpcError("worker_rpc_closed")
        current = getattr(bridge, "_worker_rpc_client", None)
        if current is None or current.snapshot()["closed"]:
            def send(peer, payload):
                mqttc = bridge.client
                if mqttc is None or not mqttc.is_connected():
                    return False
                info = bridge._publish_to_registered_client(mqttc, peer, payload, durable=False)
                return info.rc == 0
            current = AgentWorkerRpcClient(bridge.get_client, send)
            bridge._worker_rpc_client = current
        return current


def close_worker_rpc_client(bridge):
    with _LOCK:
        current = getattr(bridge, "_worker_rpc_client", None)
        if current is not None:
            current.close()


def worker_registry(bridge):
    with _LOCK:
        current = getattr(bridge, "_worker_enrollment_registry", None)
        ledger = bridge.agent_task_manager._run_events.ledger
        if current is None or current.ledger.path.resolve() != ledger.path.resolve():
            current = AgentWorkerRegistry(ledger)
            bridge._worker_enrollment_registry = current
        return current


def worker_protocol(bridge):
    registry = worker_registry(bridge)
    with _LOCK:
        current = getattr(bridge, "_worker_execution_protocol", None)
        if current is None or current.registry is not registry:
            current = AgentWorkerProtocol(registry)
            bridge._worker_execution_protocol = current
        return current


def flush_worker_notifications(bridge, mqttc):
    if getattr(bridge, "_worker_execution_protocol", None) is None:
        with bridge.agent_task_manager._run_events.ledger.transaction(write=False) as connection:
            if connection.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                                  ("agent_worker_notifications",)).fetchone() is None:
                return
    protocol = worker_protocol(bridge)
    for task_id, generation, sequence in protocol.notifications():
        protocol.attempted_notification(task_id, generation, sequence)
        task = bridge.agent_task_manager.get(task_id)
        if task is None:
            protocol.acknowledge_notification(task_id, generation, sequence)
            continue
        public = task.public()
        if public.get("execution_generation") != generation or public.get("status_seq") != sequence:
            observed = (public.get("execution_generation", 0), public.get("status_seq", 0))
            if observed > (generation, sequence):
                protocol.acknowledge_notification(task_id, generation, sequence)
            continue
        route = public.get("client_route_id")
        if not route or bridge.get_client(route) is None:
            continue
        wire = {"scheme": "signal", "_client_route_id": route}
        if public.get("status") == "completed":
            payload = bridge._build_republished_task_result(public, route)
            published = bridge._publish_or_queue_task_result(mqttc, wire, payload)
        else:
            published = bridge._publish_or_queue_task_event(mqttc, wire, public, [])
        if published:
            protocol.acknowledge_notification(task_id, generation, sequence)


def route_worker_payload(bridge, mqttc, wire_payload, payload, *, client_route_id, source_id):
    kind = str(payload.get("type") or "").lower()
    if not kind.startswith("agent_worker_"):
        return False
    if kind == "agent_worker_response":
        current = getattr(bridge, "_worker_rpc_client", None)
        if current is not None:
            peer = bridge.get_client(client_route_id)
            current.receive(peer, source_id, payload)
        return True
    execution_operation = kind in {"agent_worker_poll", "agent_worker_renew", "agent_worker_report", "agent_worker_receipt"}
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
        response["request_digest"] = request_digest(payload)
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
        elif execution_operation:
            protocol = worker_protocol(bridge)
            operation = {"agent_worker_poll": protocol.poll, "agent_worker_renew": protocol.renew,
                         "agent_worker_report": protocol.report, "agent_worker_receipt": protocol.receipt}[kind]
            result = operation(peer, source_id, payload)
        else:
            raise WorkerAccessError("worker_operation_unsupported")
        response.update(ok=True, **(result if execution_operation else {"worker": result}))
    except WorkerAccessError as error:
        response["error"] = str(error)
    except (WorkerLeaseConflict, AgentTaskWriteConflict, AgentRunIdentityConflict):
        response["error"] = "worker_execution_conflict"
    except sqlite3.Error:
        response["error"] = "worker_storage_unavailable"
    except (ValueError, TypeError):
        response["error"] = "worker_request_invalid"
    if response["ok"] and execution_operation and kind != "agent_worker_receipt":
        bridge._ensure_outbound_retry_thread()
    bridge._publish_phone_payload(mqttc, wire_payload, response)
    return True
