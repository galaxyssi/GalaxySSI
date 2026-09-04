"""Project self-evolution runs into the Desktop task timeline contract."""
from __future__ import annotations

from typing import Any


_VISIBLE_STATUSES = {
    "preparing",
    "running",
    "validating",
    "waiting_approval",
    "publishing",
    "published",
    "blocked",
    "failed",
    "cancelled",
    "rolled_back",
}
_EVENT_TITLES = {
    "start_requested": "Self-evolution task started",
    "worktree_ready": "Isolated workspace prepared",
    "agent_started": "Implementation Agent started",
    "validation_started": "Quality validation started",
    "gate_started": "Quality gate started",
    "gate_finished": "Quality gate finished",
    "attempt_failed": "Implementation attempt failed",
    "candidate_ready": "Candidate ready for review",
    "publishing": "Publishing candidate",
    "publish_label_skipped": "Pull request label skipped",
    "published": "Pull request created",
    "publish_failed": "Candidate publish failed",
    "publish_rejected": "Candidate publish rejected",
    "blocked": "Self-evolution needs attention",
    "failed": "Self-evolution failed",
    "cancel_requested": "Cancellation requested",
    "cancelled": "Self-evolution cancelled",
    "rolled_back": "Candidate rolled back",
}
_FAILURE_EVENTS = {
    "attempt_failed",
    "publish_failed",
    "publish_rejected",
    "blocked",
    "failed",
    "cancelled",
    "rolled_back",
}
_RUNNING_EVENTS = {
    "start_requested",
    "agent_started",
    "validation_started",
    "gate_started",
    "publishing",
    "cancel_requested",
}


def evolution_task_is_visible(task: Any) -> bool:
    return bool(getattr(task, "attempts", None)) or str(getattr(task, "status", "")) in _VISIBLE_STATUSES


def evolution_task_timeline_item(
    manager: Any,
    task: Any,
    *,
    live_event: dict[str, Any] | None = None,
    audit_rows: list[dict[str, Any]] | None = None,
) -> dict[str, Any] | None:
    if not evolution_task_is_visible(task):
        return None

    raw_status = str(getattr(task, "status", "") or "proposed")
    attempts = list(getattr(task, "attempts", None) or [])
    latest_attempt = attempts[-1] if attempts else None
    metadata = _task_metadata(manager, str(task.task_id))
    audit_rows = (
        [dict(row) for row in audit_rows if isinstance(row, dict)]
        if audit_rows is not None
        else _task_audit_rows(manager, str(task.task_id))
    )
    if live_event:
        audit_rows.append({
            "event": str(live_event.get("event") or ""),
            "timestamp_millis": int(live_event.get("timestamp_millis") or task.updated_at_millis or 0),
            "payload": dict(live_event.get("metadata") or {}),
        })
    events = _timeline_events(task, audit_rows)
    status = _desktop_status(raw_status)
    created_at = int(getattr(task, "created_at_millis", 0) or 0)
    updated_at = int(getattr(task, "updated_at_millis", 0) or created_at)
    started_at = int(
        getattr(latest_attempt, "started_at_millis", 0)
        if latest_attempt is not None
        else created_at
    ) or created_at
    completed_at = updated_at if status in {"completed", "failed", "cancelled"} else 0
    delegate_agent_id = str(
        getattr(latest_attempt, "agent_id", "")
        if latest_attempt is not None
        else ""
    )
    if delegate_agent_id == "auto":
        delegate_agent_id = ""
    origin = str(metadata.get("origin") or "manual")
    automatic = origin != "manual" or any(
        row.get("event") == "scheduled_evolution_started" for row in audit_rows
    )
    result = _result_text(task, latest_attempt)

    return {
        "task_id": str(task.task_id),
        "task_kind": "self_evolution",
        "agent_id": "self-evolution",
        "delegate_agent_id": delegate_agent_id,
        "contact_id": "self-evolution",
        "source_message_id": f"desktop:evolution:{task.task_id}",
        "conversation_id": f"evolution:{task.task_id}",
        "client_conversation_id": "",
        "client_route_id": "",
        "status": status,
        "evolution_status": raw_status,
        "evolution_origin": origin,
        "automatic": automatic,
        "created_at": created_at,
        "started_at": started_at,
        "updated_at": updated_at,
        "completed_at": completed_at,
        "elapsed_ms": max(0, (completed_at or updated_at) - (started_at or created_at)),
        "prompt": str(getattr(task, "problem", "") or "Self-evolution task"),
        "result": result,
        "error": _bounded_text(getattr(task, "last_error", ""), 1_200),
        "exit_code": None,
        "status_seq": len(events),
        "thread_id": str(getattr(task, "candidate_branch", "") or ""),
        "turn_id": "",
        "client_turn_id": "",
        "current_step": _current_step(raw_status),
        "pending_approval": {},
        "events": events[-80:],
        "output_files": [],
        "attachments": [],
        "retry_of": "",
        "attempt": max(1, len(attempts)),
        "execution_policy": {
            "risk_level": str(getattr(task, "risk_level", "") or "medium"),
            "max_attempts": int(getattr(task, "max_attempts", 1) or 1),
        },
        "last_progress_at": updated_at,
        "replan_count": max(0, len(attempts) - 1),
        "failure_counts": _failure_counts(attempts),
        "process_id": 0,
        "candidate_commit": str(getattr(task, "candidate_commit", "") or ""),
        "candidate_branch": str(getattr(task, "candidate_branch", "") or ""),
        "pull_request_url": str(getattr(task, "pull_request_url", "") or ""),
        "changed_files": [
            str(value)[:500]
            for value in list(getattr(latest_attempt, "changed_files", None) or [])[:100]
        ],
        "quality_gates": [
            _gate_public(gate)
            for gate in list(getattr(latest_attempt, "gates", None) or [])
        ],
        "acceptance": [
            str(value)[:500]
            for value in list(getattr(task, "acceptance", None) or [])[:40]
        ],
        "scope": [
            str(value)[:500]
            for value in list(getattr(task, "scope", None) or [])[:40]
        ],
    }


def _desktop_status(status: str) -> str:
    if status in {"waiting_approval", "published"}:
        return "completed"
    if status in {"blocked", "failed"}:
        return "failed"
    if status in {"cancelled", "rolled_back"}:
        return "cancelled"
    if status == "proposed":
        return "accepted"
    return "running"


def _current_step(status: str) -> str:
    return {
        "proposed": "Preparing self-evolution task",
        "preparing": "Preparing isolated workspace",
        "running": "Implementation Agent is working",
        "validating": "Running quality gates",
        "waiting_approval": "Candidate ready for review",
        "publishing": "Publishing candidate",
        "published": "Pull request created",
        "blocked": "Self-evolution needs attention",
        "failed": "Self-evolution failed",
        "cancelled": "Self-evolution cancelled",
        "rolled_back": "Candidate rolled back",
    }.get(status, "Self-evolution is running")


def _result_text(task: Any, attempt: Any | None) -> str:
    summary = str(getattr(attempt, "agent_summary", "") or "").strip() if attempt is not None else ""
    pull_request_url = str(getattr(task, "pull_request_url", "") or "").strip()
    if pull_request_url:
        link = f"[Open pull request]({pull_request_url})"
        return f"{summary}\n\n{link}".strip()
    if summary:
        return summary
    if str(getattr(task, "status", "")) == "waiting_approval":
        return "The isolated candidate passed its quality gates and is ready for review."
    if str(getattr(task, "status", "")) == "published":
        return "The self-evolution candidate was published as a pull request."
    return ""


def _task_metadata(manager: Any, task_id: str) -> dict[str, Any]:
    try:
        value = manager.task_metadata(task_id)
    except (AttributeError, OSError, RuntimeError, TypeError, ValueError):
        return {}
    return dict(value) if isinstance(value, dict) else {}


def _task_audit_rows(manager: Any, task_id: str) -> list[dict[str, Any]]:
    audit = getattr(manager, "audit", None)
    if audit is None:
        return []
    try:
        rows = audit.list_for_task(task_id, limit=200)
    except (AttributeError, OSError, RuntimeError, TypeError, ValueError):
        return []
    return [dict(row) for row in rows if isinstance(row, dict)]


def _timeline_events(task: Any, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    seen: set[tuple[str, int, str]] = set()
    finished_gates = {
        (
            int((row.get("payload") or {}).get("attempt") or 0),
            str((row.get("payload") or {}).get("gate") or ""),
        )
        for row in rows
        if str(row.get("event") or "") == "gate_finished"
    }
    for row in rows:
        event = str(row.get("event") or "")
        if event not in _EVENT_TITLES:
            continue
        payload = dict(row.get("payload") or {})
        attempt_number = int(payload.get("attempt") or 0)
        gate_id = str(payload.get("gate") or "")
        if event == "gate_started" and (attempt_number, gate_id) in finished_gates:
            continue
        key = (event, attempt_number, gate_id)
        if key in seen:
            continue
        seen.add(key)
        result.append({
            "event": event,
            "title": _EVENT_TITLES[event],
            "detail": _event_detail(task, event, attempt_number, gate_id, payload),
            "status": _event_status(task, event, attempt_number, gate_id),
            "timestamp": int(row.get("timestamp_millis") or 0),
        })
    if not result:
        result.extend(_events_from_attempts(task))
    return result


def _event_detail(
    task: Any,
    event: str,
    attempt_number: int,
    gate_id: str,
    payload: dict[str, Any],
) -> str:
    attempt = _attempt(task, attempt_number)
    gate = _gate(attempt, gate_id)
    if event == "agent_started":
        agent_id = str(getattr(attempt, "agent_id", "") or getattr(task, "agent_id", "") or "Agent")
        return f"Attempt {attempt_number or 1} of {int(getattr(task, 'max_attempts', 1) or 1)} - {agent_id}"
    if event == "worktree_ready":
        branch = str(getattr(attempt, "branch", "") or "")
        return f"Attempt {attempt_number or 1}" + (f" - {branch}" if branch else "")
    if event in {"gate_started", "gate_finished"}:
        if event == "gate_started":
            return gate_id
        summary = str(getattr(gate, "summary", "") or "")
        return _bounded_text(gate_id + (f" - {summary}" if summary else ""), 700)
    if event == "attempt_failed":
        return _bounded_text(getattr(attempt, "failure_summary", ""), 700)
    if event == "candidate_ready":
        changed = len(list(getattr(attempt, "changed_files", None) or []))
        return f"Attempt {attempt_number or 1} - {changed} changed file(s)"
    if event in _FAILURE_EVENTS:
        return _bounded_text(
            getattr(task, "last_error", "") or payload.get("reason") or "",
            700,
        )
    if event == "published":
        return str(getattr(task, "pull_request_url", "") or "")
    return ""


def _event_status(task: Any, event: str, attempt_number: int, gate_id: str) -> str:
    if event in _FAILURE_EVENTS:
        return "failed"
    raw_status = str(getattr(task, "status", "") or "")
    if event == "gate_started":
        gate = _gate(_attempt(task, attempt_number), gate_id)
        return "running" if gate is None or str(getattr(gate, "status", "")) == "running" else "completed"
    if event == "gate_finished":
        gate = _gate(_attempt(task, attempt_number), gate_id)
        return "failed" if gate is not None and str(getattr(gate, "status", "")) != "passed" else "completed"
    if event == "agent_started" and raw_status == "running":
        return "running"
    if event == "validation_started" and raw_status == "validating":
        return "running"
    if event == "publishing" and raw_status == "publishing":
        return "running"
    if event == "start_requested" and raw_status == "preparing":
        return "running"
    return "completed"


def _events_from_attempts(task: Any) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for attempt in list(getattr(task, "attempts", None) or []):
        number = int(getattr(attempt, "number", 0) or 0)
        rows.append({
            "event": "worktree_ready",
            "title": _EVENT_TITLES["worktree_ready"],
            "detail": _event_detail(task, "worktree_ready", number, "", {}),
            "status": "completed",
            "timestamp": int(getattr(attempt, "started_at_millis", 0) or 0),
        })
        for gate in list(getattr(attempt, "gates", None) or []):
            gate_id = str(getattr(gate, "id", "") or "")
            rows.append({
                "event": "gate_finished",
                "title": _EVENT_TITLES["gate_finished"],
                "detail": _event_detail(task, "gate_finished", number, gate_id, {}),
                "status": "completed" if str(getattr(gate, "status", "")) == "passed" else "failed",
                "timestamp": int(getattr(attempt, "completed_at_millis", 0) or 0),
            })
    return rows


def _attempt(task: Any, number: int) -> Any | None:
    attempts = list(getattr(task, "attempts", None) or [])
    if number > 0:
        return next((item for item in attempts if int(getattr(item, "number", 0) or 0) == number), None)
    return attempts[-1] if attempts else None


def _gate(attempt: Any | None, gate_id: str) -> Any | None:
    if attempt is None or not gate_id:
        return None
    return next(
        (
            item
            for item in list(getattr(attempt, "gates", None) or [])
            if str(getattr(item, "id", "") or "") == gate_id
        ),
        None,
    )


def _gate_public(gate: Any) -> dict[str, Any]:
    return {
        "id": str(getattr(gate, "id", "") or ""),
        "status": str(getattr(gate, "status", "") or ""),
        "duration_millis": int(getattr(gate, "duration_millis", 0) or 0),
        "summary": _bounded_text(getattr(gate, "summary", ""), 700),
    }


def _failure_counts(attempts: list[Any]) -> dict[str, int]:
    result: dict[str, int] = {}
    for attempt in attempts:
        code = str(getattr(attempt, "failure_code", "") or "")
        if code:
            result[code] = result.get(code, 0) + 1
    return result


def _bounded_text(value: Any, maximum: int) -> str:
    text = str(value or "")
    if len(text) <= maximum:
        return text
    return f"{text[: max(0, maximum - 3)].rstrip()}..."
