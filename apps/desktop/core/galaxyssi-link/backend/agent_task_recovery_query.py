"""Read-only, route-scoped recovery observations. Never starts or resumes a task."""

from __future__ import annotations

import json
import logging

from agent_recovery_timing import recovery_timing

MAX_ITEMS = 32
INLINE_RESPONSE_BYTES = 32 * 1024
_log = logging.getLogger(__name__)
IDENTITY_FIELDS = (
    "client_route_id", "conversation_id", "task_id", "turn_id", "contact_id",
    "source_message_id", "agent_id",
)
TASK_FIELDS = (
    "client_route_id", "client_conversation_id", "task_id", "client_turn_id",
    "contact_id", "source_message_id", "agent_id",
)
STATUSES = frozenset({
    "accepted", "queued", "starting", "running", "recovering", "waiting_input",
    "waiting_approval", "pausing", "paused", "takeover", "interrupted",
    "completed", "failed", "timed_out", "cancelled",
})


def recovery_query(payload: dict, *, client_route_id: str, manager, result_archive=None) -> dict | None:
    request_id = payload.get("request_id")
    items = payload.get("items")
    if (not isinstance(request_id, str) or not 1 <= len(request_id) <= 128
            or payload.get("client_route_id") != client_route_id
            or not client_route_id or not isinstance(items, list)
            or not 1 <= len(items) <= MAX_ITEMS):
        return None
    # Validate the whole batch before any lookup; malformed requests cannot widen scope.
    if any(not isinstance(item, dict) or any(
        not isinstance(item.get(key), str) or not 1 <= len(item[key]) <= 200
        for key in IDENTITY_FIELDS
    ) or item["client_route_id"] != client_route_id for item in items):
        return None
    observations = []
    for item in items:
        observation = {key: item[key] for key in IDENTITY_FIELDS}
        observation["status"] = "unavailable"
        with recovery_timing(item, "lookup", request_id=request_id) as measurement:
            task = manager.recovery_snapshot(
                item["task_id"], client_route_id=client_route_id,
                conversation_id=item["conversation_id"], turn_id=item["turn_id"],
            )
            if task is not None and all(
                str(task.get(field, "")) == item[key]
                for key, field in zip(IDENTITY_FIELDS, TASK_FIELDS)
            ):
                status = str(task.get("status") or "")
                if status in STATUSES:
                    observation.update(
                        status=status,
                        remote_run_id=str(task.get("run_id") or f"task:{item['task_id']}"),
                        status_sequence=max(0, int(task.get("status_seq") or 0)),
                        execution_generation=max(1, int(task.get("execution_generation") or 1)),
                    )
                    measurement.completed = True
        observations.append(observation)
    response = {
        "type": "agent_task_recovery_result", "request_id": request_id,
        "client_route_id": client_route_id, "items": observations,
    }
    if payload.get("include_result_page") is True and result_archive is not None:
        _attach_first_pages(response, result_archive, client_route_id)
    return response


def _attach_first_pages(response: dict, result_archive, client_route_id: str) -> None:
    def encoded_size(value):
        return len(json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8"))

    try:
        remaining = INLINE_RESPONSE_BYTES - encoded_size(response)
    except (TypeError, ValueError, UnicodeError):
        return
    member_bytes = len(',"result_page":'.encode("ascii"))
    for observation in response["items"]:
        if remaining <= member_bytes:
            break
        if observation["status"] not in {"completed", "failed", "timed_out", "cancelled"}:
            continue
        request = {**{key: observation[key] for key in IDENTITY_FIELDS},
                   "request_id": response["request_id"], "page_index": 0,
                   "execution_generation": observation["execution_generation"]}
        try:
            # Read the immutable archive only; never reconstruct or rerun a task for this optimization.
            page = result_archive.try_page(request, client_route_id=client_route_id)
            if (not isinstance(page, dict) or page.get("status") != "ready"
                    or page.get("type") != "agent_task_result_page"
                    or page.get("request_id") != response["request_id"]
                    or type(page.get("page_index")) is not int or page["page_index"] != 0
                    or type(page.get("execution_generation")) is not int
                    or page["execution_generation"] != observation["execution_generation"]
                    or any(page.get(key) != observation[key] for key in IDENTITY_FIELDS)):
                continue
            cost = member_bytes + encoded_size(page)
            if cost <= remaining:
                observation["result_page"] = page
                remaining -= cost
        except Exception as error:
            # A damaged/missing optional page must not hide an authenticated task observation.
            _log.warning("Inline recovery page deferred: %s", type(error).__name__)
