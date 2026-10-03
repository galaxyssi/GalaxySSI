"""On-demand, authenticated, task-bound read-only recall from the originating phone."""
from __future__ import annotations

import json
import hashlib
import threading
import time
import uuid
from dataclasses import dataclass, field

from agent_task_recovery_query import IDENTITY_FIELDS, TASK_FIELDS

TOOL = "collaboration_recall"
REQUEST = "collaboration_recall_request"
RESPONSE = "collaboration_recall_result"
CONTRACT = "galaxyssi.collaboration-recall/2"
ACTIVE = frozenset({"starting", "running", "recovering"})


def tool_spec():
    return {"type": "function", "name": TOOL, "description": (
        "Read already saved collaboration goal/context, workspace versions or original evidence. "
        "The host binds this to your current member assignment; never supply group/member/task IDs. "
        "Use mode=goal_contract and cursor='' to recover omitted dependency receipts; follow next_cursor. "
        "Use mode=workspace to browse exact revisions, then object_id/revision/offset to read them. "
        "Use mode=evidence to browse originals, then evidence_id/sha256/offset; follow next_offset. "
        "Use mode=archive with record_id/offset to read complete dependency handoffs; follow next_offset. "
        "Read-only, no web search, phone UI access or task execution."),
        "inputSchema": {"type": "object", "properties": {
            "mode": {"type": "string", "enum": ["goal_contract", "workspace", "evidence", "archive"]},
            "record_id": {"type": "string", "maxLength": 64},
            "cursor": {"type": "string", "maxLength": 512},
            "object_id": {"type": "string", "maxLength": 64},
            "revision": {"type": "integer", "minimum": 1},
            "evidence_id": {"type": "string", "maxLength": 64},
            "sha256": {"type": "string", "maxLength": 64},
            "offset": {"type": "integer", "minimum": 0}},
            "required": ["mode"], "additionalProperties": False}}


def validate_arguments(arguments):
    properties = tool_spec()["inputSchema"]["properties"]
    if not isinstance(arguments, dict) or set(arguments) - properties.keys():
        raise ValueError("Recall accepts only scoped record selectors")
    if arguments.get("mode") not in {"goal_contract", "workspace", "evidence", "archive"}:
        raise ValueError("Invalid recall mode")
    for key, value in arguments.items():
        spec = properties[key]
        if spec["type"] == "string":
            if not isinstance(value, str) or len(value) > spec.get("maxLength", 32):
                raise ValueError("Invalid recall selector")
        elif type(value) is not int or not spec["minimum"] <= value <= 2**31 - 1:
            raise ValueError("Invalid recall offset/revision")
    if arguments["mode"] == "goal_contract" and set(arguments) - {"mode", "cursor"}:
        raise ValueError("Goal recall accepts only mode and cursor")
    if arguments["mode"] == "archive":
        record_id = arguments.get("record_id", "")
        if (set(arguments) - {"mode", "record_id", "offset"}
                or len(record_id) != 64 or any(c not in "0123456789abcdef" for c in record_id)):
            raise ValueError("Archive recall requires an exact record_id and optional offset")
    if arguments["mode"] == "evidence" and arguments.get("evidence_id"):
        if any(len(arguments.get(key, "")) != 64 or any(c not in "0123456789abcdef" for c in arguments[key])
               for key in ("evidence_id", "sha256")):
            raise ValueError("Original evidence recall requires exact evidence_id and sha256 from browse")
    return dict(arguments)


def task_scope(task):
    if not isinstance(task, dict) or task.get("status") not in ACTIVE or task.get("agent_id") != "codex":
        raise ValueError("Collaboration task is not active")
    if task.get("cancel_requested") or task.get("pause_requested"):
        raise ValueError("Collaboration task is paused or stopped")
    result = {key: str(task.get(source) or "") for key, source in zip(IDENTITY_FIELDS, TASK_FIELDS)}
    generation = task.get("execution_generation", 1)
    if any(not 1 <= len(value) <= 200 for value in result.values()) or type(generation) is not int or not 1 <= generation <= 2**53 - 1:
        raise ValueError("Recall requires the originating phone task identity")
    return {**result, "execution_generation": generation}


@dataclass
class Pending:
    request: dict
    event: threading.Event = field(default_factory=threading.Event)
    response: dict | None = None


class RecallBroker:
    def __init__(self):
        self._lock = threading.Lock()
        self._pending: dict[str, Pending] = {}

    def query(self, snapshot, arguments, publish, *, active=lambda: True, timeout=20.0):
        arguments = validate_arguments(arguments)
        scope = task_scope(snapshot())
        result = self._exchange(scope, snapshot, arguments, publish, active, timeout, "read")
        if result.get("success") is not True or arguments["mode"] != "evidence" or not arguments.get("evidence_id"):
            return result
        delivery = result.get("delivery")
        content = result.get("content")
        if (not isinstance(delivery, dict) or set(delivery) != {"receipt_id", "content_sha256"}
                or not isinstance(delivery.get("receipt_id"), str) or not 1 <= len(delivery["receipt_id"]) <= 128
                or not isinstance(content, str)
                or hashlib.sha256(content.encode("utf-8")).hexdigest() != delivery.get("content_sha256")):
            raise ValueError("Original evidence delivery was not authenticated; retry the read")
        confirmed = self._exchange(scope, snapshot, arguments, publish, active, timeout, "confirm", delivery)
        if (confirmed.get("success") is not True or confirmed.get("status") != "confirmed"
                or confirmed.get("delivery") != delivery or not isinstance(confirmed.get("host_read_coverage"), dict)):
            raise ValueError("Phone did not confirm original evidence delivery; retry the read")
        result.pop("delivery", None)
        result["host_read_coverage"] = confirmed["host_read_coverage"]
        result["delivery_status"] = "desktop_received_phone_confirmed_not_comprehension"
        return result

    def _exchange(self, scope, snapshot, arguments, publish, active, timeout, phase, delivery=None):
        nonce = str(uuid.uuid4())
        request = {**scope, "type": REQUEST, "contract": CONTRACT, "request_id": nonce,
                   "expires_at": int(time.time() * 1000 + timeout * 1000), "arguments": arguments, "phase": phase}
        if delivery is not None:
            request["delivery"] = delivery
        pending = Pending(request)
        with self._lock:
            if len(self._pending) >= 128 or sum(p.request["task_id"] == scope["task_id"] for p in self._pending.values()) >= 4:
                raise ValueError("Recall capacity busy; retry after current reads finish")
            self._pending[nonce] = pending
        try:
            if not active() or task_scope(snapshot()) != scope:
                raise ValueError("Recall assignment changed")
            if not publish(request):
                raise ConnectionError(
                    "Recall transport rejected the request; phone connectivity is unconfirmed. "
                    "The read was not delivered. Retry this same read after transport recovery; "
                    "do not restart completed work or infer that the phone is powered off."
                )
            deadline = time.monotonic() + timeout
            while not pending.event.wait(min(.25, max(0, deadline - time.monotonic()))):
                if not active() or task_scope(snapshot()) != scope:
                    raise ValueError("Recall assignment changed")
                if time.monotonic() >= deadline:
                    raise TimeoutError("Phone recall timed out; saved evidence remains available for a read retry")
            if not active() or task_scope(snapshot()) != scope:
                raise ValueError("Recall assignment changed")
            return pending.response["result"]
        finally:
            with self._lock:
                self._pending.pop(nonce, None)

    def receive(self, payload, authenticated_route):
        if not isinstance(payload, dict) or not isinstance(payload.get("request_id"), str):
            return False
        with self._lock:
            pending = self._pending.get(payload.get("request_id"))
            if pending is None or pending.response is not None:
                return False
            request = pending.request
            if (authenticated_route != request["client_route_id"] or payload.get("type") != RESPONSE
                    or payload.get("contract") != CONTRACT
                    or payload.get("phase") != request["phase"]
                    or any(payload.get(key) != request[key] for key in (*IDENTITY_FIELDS, "execution_generation"))
                    or not isinstance(payload.get("result"), dict)
                    or type(payload["result"].get("success")) is not bool):
                return False
            try:
                encoded = json.dumps(payload, ensure_ascii=False, allow_nan=False)
            except (TypeError, ValueError):
                return False
            if len(encoded.encode()) > 256 * 1024:
                return False
            pending.response = json.loads(encoded)
            pending.event.set()
            return True


broker = RecallBroker()
