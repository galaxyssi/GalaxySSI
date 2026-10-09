"""On-demand, authenticated, task-bound read-only recall from the originating phone."""
from __future__ import annotations

import json
import hashlib
import logging
import math
import threading
import time
import uuid
from dataclasses import dataclass, field

from agent_task_recovery_query import IDENTITY_FIELDS, TASK_FIELDS
from collaboration_transport_feedback import ExchangeObservations, PublicationRejected, ResponseUnconfirmed

TOOL = "collaboration_recall"
REQUEST = "collaboration_recall_request"
RESPONSE = "collaboration_recall_result"
CONTRACT = "galaxyssi.collaboration-recall/2"
ACTIVE = frozenset({"starting", "running", "recovering"})
RETRY_INITIAL_SECONDS = 2.0
RETRY_MAX_SECONDS = 8.0
log = logging.getLogger(__name__)
RULE_TOPICS = ("catalog", "all", "foundation", "learning", "procedures", "transfer", "innovation",
               "team_invention", "prediction", "tools", "workflows", "retention", "self_research", "coordination")
NUMERIC_CASE_FILTERS = ("failed", "all", "domain_error", "improved", "regressed", "error_reduced",
                        "error_increased", "domain_recovered", "domain_failed")


def tool_spec():
    return {"type": "function", "name": TOOL, "description": (
        "Read already saved collaboration goal/context, workspace versions or original evidence. "
        "The host binds this to your current member assignment; never supply group/member/dispatch IDs. "
        "Use mode=goal_contract with optional section=goal, criteria, source or context:<exact section name> "
        "and cursor='' to recover omitted material directly. Keep section unchanged while following next_cursor until null; "
        "null ends that section, not the full snapshot. Omit section to browse all pinned material. "
        "Use mode=workspace to browse exact revisions, then object_id/revision/offset to read them. "
        "Use mode=evidence to browse originals, then evidence_id/sha256/offset; follow next_offset. "
        "Use mode=archive with record_id/offset to read complete dependency handoffs; follow next_offset. "
        "Use mode=evolution/cursor for scoped learning records. Use evolution_rules with topic=catalog to discover typed contracts, "
        "then topic=<id>/offset to read a chosen schema; keep the same topic while paging. Omitted topic reads all. "
        "Use mode=capabilities with query/cursor to find related saved methods, tools and failure lessons; "
        "follow next_cursor even after an empty page, then read exact workspace originals before reuse. "
        "Use mode=method_history with exact method object_id/revision/sha256 and cursor to inspect prior usage; "
        "read returned record_id/offset for original conditions, errors and delivery. These are not quality measurements. "
        "Use mode=numeric_cases with exact trial object_id/revision/sha256, optional case_filter (default failed) and cursor "
        "to inspect host-computed counterexamples or regressions. Follow next_cursor using the same trial and case_filter; "
        "concatenate content pages before decoding cases. Use mode=workspace for the full model and original trial. "
        "These saved numeric checks are not independent reference truth or proof of generalization. "
        "Use mode=problems/cursor for original failed tool observations; these are symptoms, not diagnosed causes. "
        "Active incremental coordinators can use mode=team_updates/cursor to discover newly published exact versions. "
        "Follow next_cursor to an empty page and reuse that cursor later; read the versions before judging sufficiency. "
        "Alternatively, mode=team_updates with work_id from the inventory (without cursor) reads the complete current work contract before a dependency revision. "
        "Other members cannot use team_updates. Original goal snapshots and independent research isolation are unchanged. "
        "Workers may use mode=peer_updates/cursor during their existing assignment to read interim requests explicitly addressed to them "
        "from peers allowed by the host work contract peer_updates_from. Read the exact versions and observations before accepting, rejecting or deferring a request. "
        "Use next_cursor to caught_up_at_read, then reuse it at useful checkpoints, not a busy polling loop. Empty does not mean peers finished. "
        "all revisions and their observations in that milestone are shared with eligible recipients. No extra model is started. "
        "Read-only, no web search, phone UI access or task execution."),
        "inputSchema": {"type": "object", "properties": {
            "mode": {"type": "string", "enum": ["goal_contract", "workspace", "evidence", "archive", "evolution", "capabilities", "method_history", "evolution_rules", "problems", "numeric_cases", "team_updates", "peer_updates"]},
            "query": {"type": "string", "maxLength": 1000},
            "work_id": {"type": "string", "maxLength": 160},
            "case_filter": {"type": "string", "maxLength": 32, "enum": list(NUMERIC_CASE_FILTERS)},
            "topic": {"type": "string", "maxLength": 32, "enum": list(RULE_TOPICS)},
            "record_id": {"type": "string", "maxLength": 64},
            "cursor": {"type": "string", "maxLength": 512},
            "section": {"type": "string", "maxLength": 512},
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
    if arguments.get("mode") not in properties["mode"]["enum"]:
        raise ValueError("Invalid recall mode")
    for key, value in arguments.items():
        spec = properties[key]
        if spec["type"] == "string":
            if not isinstance(value, str) or len(value) > spec.get("maxLength", 32):
                raise ValueError("Invalid recall selector")
        elif type(value) is not int or not spec["minimum"] <= value <= 2**31 - 1:
            raise ValueError("Invalid recall offset/revision")
    if arguments["mode"] == "goal_contract":
        if set(arguments) - {"mode", "cursor", "section"}:
            raise ValueError("Goal recall accepts only mode, cursor and optional section")
        if "section" in arguments:
            section = arguments["section"]
            if section not in {"goal", "criteria", "source"} and not (
                    section.startswith("context:") and section[len("context:"):].strip()):
                raise ValueError("Use section=goal, criteria, source or context:<exact section name>")
    elif "section" in arguments:
        raise ValueError("Section is only supported for goal/context recall")
    if arguments["mode"] in {"evolution", "problems"} and set(arguments) - {"mode", "cursor"}:
        raise ValueError("Evolution/problem recall accepts only mode and cursor")
    if arguments["mode"] == "team_updates":
        allowed = {"mode", "work_id"} if "work_id" in arguments else {"mode", "cursor"}
        if set(arguments) - allowed or "work_id" in arguments and not arguments["work_id"].strip():
            raise ValueError("Team updates take cursor for publications OR work_id for the complete work contract")
    elif "work_id" in arguments:
        raise ValueError("Work ID is only supported for coordinator updates")
    if arguments["mode"] == "peer_updates" and set(arguments) - {"mode", "cursor"}:
        raise ValueError("Peer updates accept mode and cursor only")
    if arguments["mode"] == "capabilities":
        if set(arguments) - {"mode", "query", "cursor"} or not arguments.get("query", "").strip():
            raise ValueError("Capability search requires query and accepts optional cursor only")
    elif "query" in arguments:
        raise ValueError("Query is only supported for capability search")
    if arguments["mode"] == "evolution_rules":
        if set(arguments) - {"mode", "offset", "topic"}:
            raise ValueError("Evolution rules accept only mode, offset and topic")
        if arguments.get("topic", "all") not in RULE_TOPICS:
            raise ValueError("Unknown evolution topic; use topic=catalog")
    elif "topic" in arguments:
        raise ValueError("Topic is only supported for evolution rules")
    if arguments["mode"] == "archive":
        record_id = arguments.get("record_id", "")
        if (set(arguments) - {"mode", "record_id", "offset"}
                or len(record_id) != 64 or any(c not in "0123456789abcdef" for c in record_id)):
            raise ValueError("Archive recall requires an exact record_id and optional offset")
    if arguments["mode"] == "method_history":
        reading = "record_id" in arguments
        allowed = {"mode", "record_id", "offset"} if reading else {"mode", "object_id", "revision", "sha256", "cursor"}
        ids = ("record_id",) if reading else ("object_id", "sha256")
        if (set(arguments) - allowed or (not reading and "revision" not in arguments)
                or any(len(arguments.get(key, "")) != 64 or any(c not in "0123456789abcdef" for c in arguments[key]) for key in ids)):
            raise ValueError("Method history requires exact method identity or record_id/offset")
    if arguments["mode"] == "numeric_cases":
        if (set(arguments) - {"mode", "object_id", "revision", "sha256", "case_filter", "cursor"}
                or "revision" not in arguments
                or any(len(arguments.get(key, "")) != 64 or any(c not in "0123456789abcdef" for c in arguments[key])
                       for key in ("object_id", "sha256"))):
            raise ValueError("Numeric feedback requires exact trial object_id/revision/sha256 and optional case_filter/cursor")
        if arguments.get("case_filter", "failed") not in NUMERIC_CASE_FILTERS:
            raise ValueError("Unknown numeric case_filter")
    elif "case_filter" in arguments:
        raise ValueError("Case filter is only supported for numeric feedback")
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
    deadline: float
    event: threading.Event = field(default_factory=threading.Event)
    response: dict | None = None


class RecallBroker:
    def __init__(self, *, request_type=REQUEST, response_type=RESPONSE, contract=CONTRACT):
        self._lock = threading.Lock()
        self._pending: dict[str, Pending] = {}
        self._request_type, self._response_type, self._contract = request_type, response_type, contract

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
        if type(timeout) not in (int, float) or not math.isfinite(timeout) or not 0 < timeout <= 60:
            raise ValueError("Recall timeout must be within the phone request lifetime")
        started = time.monotonic()
        deadline = started + timeout
        nonce = str(uuid.uuid4())
        request = {**scope, "type": self._request_type, "contract": self._contract, "request_id": nonce,
                   "expires_at": int(time.time() * 1000 + timeout * 1000), "arguments": arguments, "phase": phase}
        if delivery is not None:
            request["delivery"] = delivery
        pending = Pending(request, deadline)
        with self._lock:
            if len(self._pending) >= 128 or sum(p.request["task_id"] == scope["task_id"] for p in self._pending.values()) >= 4:
                raise ValueError("Recall capacity busy; retry after current reads finish")
            self._pending[nonce] = pending
        attempts = accepted = 0
        observations = ExchangeObservations()
        next_publish, retry_delay = started, RETRY_INITIAL_SECONDS
        outcome = "aborted"
        try:
            while True:
                if not active() or task_scope(snapshot()) != scope:
                    raise ValueError("Recall assignment changed")
                if pending.event.is_set():
                    outcome = "returned" if pending.response["result"]["success"] else "phone_rejected"
                    return pending.response["result"]
                now = time.monotonic()
                if now >= deadline:
                    if not accepted:
                        outcome = "publish_rejected"
                        raise PublicationRejected(observations.details(phase, attempts, accepted))
                    outcome = "response_timeout"
                    raise ResponseUnconfirmed(observations.details(phase, attempts, accepted))
                if now >= next_publish:
                    # Reuse the nonce and expiry: phone deduplication owns in-flight reads.
                    # Never create a durable outbox or restart the model to retry an observation.
                    attempts += 1
                    accepted += observations.record(publish(json.loads(json.dumps(request))))
                    next_publish = time.monotonic() + retry_delay
                    retry_delay = min(RETRY_MAX_SECONDS, retry_delay * 2)
                    continue
                pending.event.wait(min(.25, deadline - now, next_publish - now))
        finally:
            with self._lock:
                self._pending.pop(nonce, None)
            log.info("Collaboration recall task_id=%s request_id=%s mode=%s phase=%s attempts=%d accepted=%d elapsed_ms=%d outcome=%s publish_reasons=%s",
                     scope["task_id"], nonce, arguments["mode"], phase, attempts, accepted,
                     int((time.monotonic() - started) * 1000), outcome,
                     json.dumps(dict(sorted(observations.reasons.items())), separators=(",", ":")))

    def receive(self, payload, authenticated_route):
        if not isinstance(payload, dict) or not isinstance(payload.get("request_id"), str):
            return False
        with self._lock:
            pending = self._pending.get(payload.get("request_id"))
            if pending is None or pending.response is not None or time.monotonic() >= pending.deadline:
                return False
            request = pending.request
            if (authenticated_route != request["client_route_id"] or payload.get("type") != self._response_type
                    or payload.get("contract") != self._contract
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
