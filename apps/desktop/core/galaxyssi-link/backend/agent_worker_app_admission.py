"""Admit eligible original App requests before any local provider starts."""
import base64
import hashlib
import json

from agent_request_snapshot import snapshot_copy
from agent_worker_registry import WorkerAccessError
from agent_worker_routing import routing_for


def portable_snapshot(record):
    from agent_worker_execution_child import policy_for_job
    from input_attachment_transfer import resolved_attachment_path
    snapshot = snapshot_copy(record.get("request_snapshot"))
    if not snapshot or len(record["prompt"].encode("utf-8")) > 256 * 1024:
        return None
    options = snapshot["options"]
    for item in options.get("attachments", []):
        if item.get("mime_type") not in {"image/png", "image/jpeg", "image/webp", "image/gif"}:
            return None
        if item.get("transfer_id"):
            path = resolved_attachment_path(item, client_route_id=record["client_route_id"],
                conversation_id=record["client_conversation_id"], task_id=record["task_id"], turn_id=record["client_turn_id"])
            if path is None or path.stat().st_size > 256 * 1024:
                return None
            with path.open("rb") as stream:
                raw = stream.read(256 * 1024 + 1)
            if hashlib.sha256(raw).hexdigest() != item.get("sha256"):
                return None
            item["data_b64"] = base64.b64encode(raw).decode("ascii")
        try:
            raw = base64.b64decode(item.get("data_b64", ""), validate=True)
        except (ValueError, TypeError):
            return None
        if not raw or len(raw) > 256 * 1024 or hashlib.sha256(raw).hexdigest() != item.get("sha256"):
            return None
    job = dict(prompt=record["prompt"], options=options)
    try:
        policy_for_job(job)
        # Reserve room for the private lease and JSON envelope at poll time.
        if len(json.dumps(job, ensure_ascii=False).encode()) > 500 * 1024:
            return None
    except (ValueError, TypeError):
        return None
    return snapshot


def dispatch_app_request(bridge, *, task_id, app, conversation, backend_conversation, turn,
        source_message, contact, prompt, snapshot, policy, trace, trace_id):
    from agent_task_manager import AgentTask
    routing = routing_for(bridge)
    if routing is None or not routing.enabled(app):
        return None
    task = AgentTask(task_id=task_id, agent_id="codex", contact_id=contact,
        source_message_id=source_message, prompt=prompt, goal_id=task_id, run_id="task:" + task_id,
        conversation_id=backend_conversation, client_conversation_id=conversation, client_route_id=app,
        client_turn_id=turn, status="queued", status_seq=1, execution_generation=1,
        execution_checkpoint={"dispatch_started": False}, execution_policy=policy,
        request_snapshot=snapshot_copy(snapshot), delivery_trace=trace, trace_id=trace_id)
    task.attachments = [item.get("name", "image") for item in snapshot.get("options", {}).get("attachments", [])]
    record = task.record()
    portable = portable_snapshot(record)
    if portable is None:
        return None
    record["request_snapshot"] = portable
    try:
        admitted = routing.admit(record)
    except WorkerAccessError:
        # No task was admitted: preserve the already authorized local path.
        return None
    if not admitted:
        return None
    bridge._ensure_outbound_retry_thread()
    return bridge.agent_task_manager.get(task_id)
