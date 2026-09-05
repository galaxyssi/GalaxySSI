"""Recover terminal facts without invoking a provider, tools, or artifact finalization."""

from __future__ import annotations

import logging
import json
import uuid

from agent_task_recovery_query import IDENTITY_FIELDS, TASK_FIELDS
from agent_task_result_archive import execution_generation, identity

ERROR_STATUSES = frozenset({"failed", "timed_out", "cancelled"})
log = logging.getLogger(__name__)


def terminal_outcome(task: dict) -> dict | None:
    status = task.get("status")
    fields = {key: str(task.get(field) or "") for key, field in zip(IDENTITY_FIELDS, TASK_FIELDS)}
    generation = execution_generation(task)
    sequence = task.get("status_seq", 0)
    if (status not in ERROR_STATUSES or identity(fields) is None or generation is None
            or type(sequence) is not int or sequence < 0):
        return None
    error = str(task.get("error") or "")
    result = str(task.get("result") or "")
    return {
        **fields, "type": "text", "task_status": status, "success": False,
        "execution_generation": generation, "status_sequence": sequence,
        "content": error if error.strip() else result,
        "terminal_reason": status, "error": error, "result": result,
        "message_id": str(uuid.uuid5(uuid.NAMESPACE_URL, json.dumps(
            ["galaxyssi-terminal-outcome", *fields.values(), generation], ensure_ascii=False))),
        "sender": "other", "time": float(task.get("completed_at") or task.get("updated_at") or 0) / 1000,
    }


def persist_terminal_outcome(task: dict, result_archive) -> dict | None:
    try:
        payload = terminal_outcome(task)
        return result_archive.put(payload) if payload is not None else None
    except Exception as error:
        # The canonical task is already durable; a later exact-scope query retries this projection.
        log.warning("Terminal outcome archive deferred: %s", type(error).__name__)
        return None


def recover_terminal_outcome(item: dict, *, client_route_id: str, manager, result_archive) -> dict | None:
    fields = identity(item)
    generation = execution_generation(item)
    if fields is None or generation is None or fields["client_route_id"] != client_route_id:
        return None
    # Snapshot the canonical persisted row, not a live AgentTask that can change during retry.
    snapshot = manager.recovery_snapshot(fields["task_id"], client_route_id=client_route_id,
                                         conversation_id=fields["conversation_id"], turn_id=fields["turn_id"])
    if snapshot is None or any(str(snapshot.get(field) or "") != fields[key]
                               for key, field in zip(IDENTITY_FIELDS, TASK_FIELDS)):
        return None
    if execution_generation(snapshot) != generation or snapshot.get("status") not in ERROR_STATUSES:
        return None
    snapshot = manager.recovery_snapshot(fields["task_id"], client_route_id=client_route_id,
                                         conversation_id=fields["conversation_id"], turn_id=fields["turn_id"],
                                         include_result=True)
    if snapshot is None or execution_generation(snapshot) != generation or any(
        str(snapshot.get(field) or "") != fields[key] for key, field in zip(IDENTITY_FIELDS, TASK_FIELDS)
    ):
        return None
    return persist_terminal_outcome(snapshot, result_archive)
