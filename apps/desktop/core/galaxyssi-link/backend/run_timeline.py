"""Canonical, privacy-bounded Run Timeline projection."""
from __future__ import annotations

from typing import Any


CONTRACT_VERSION = "galaxyssi.run-timeline/1.0"
TERMINAL_STATES = {"completed", "failed", "cancelled", "timed_out"}


def project_run_timeline(task: Any) -> dict:
    events = [
        _normalize_event(task, event, index)
        for index, event in enumerate(list(getattr(task, "events", []) or []))
        if isinstance(event, dict)
    ]
    kinds = {event["kind"] for event in events}
    created_at = max(0, int(getattr(task, "created_at", 0) or 0))
    completed_at = max(
        created_at,
        int(getattr(task, "completed_at", 0) or getattr(task, "updated_at", 0) or created_at),
    )
    identity = _task_identity(task)

    if "retry" not in kinds and (
        str(getattr(task, "retry_of", "") or "").strip()
        or int(getattr(task, "attempt", 1) or 1) > 1
    ):
        events.append({
            "event_id": f"timeline:retry:{task.task_id}",
            "kind": "retry",
            "source_kind": "retry",
            "title": "Retrying task",
            "status": "completed",
            "detail": "",
            "created_at": created_at,
            "updated_at": created_at,
            "metadata": {
                **identity,
                "retry_of": str(getattr(task, "retry_of", "") or ""),
                "attempt": max(1, int(getattr(task, "attempt", 1) or 1)),
            },
            "synthetic": True,
            "_order": -2,
        })
        kinds.add("retry")

    if "plan" not in kinds:
        policy = dict(getattr(task, "execution_policy", {}) or {})
        events.append({
            "event_id": f"timeline:plan:{task.task_id}",
            "kind": "plan",
            "source_kind": "task",
            "title": "Task plan",
            "status": "completed" if getattr(task, "started_at", 0) else "running",
            "detail": "",
            "created_at": created_at,
            "updated_at": max(created_at, int(getattr(task, "started_at", 0) or created_at)),
            "metadata": {
                **identity,
                "task_kind": str(policy.get("task_kind") or ""),
                "reasoning_effort": str(policy.get("reasoning_effort") or ""),
            },
            "synthetic": True,
            "_order": -1,
        })

    status = str(getattr(task, "status", "") or "").strip().lower()
    terminal_kind = "result" if status == "completed" else "failure"
    if status in TERMINAL_STATES and terminal_kind not in kinds:
        result = str(getattr(task, "result", "") or "")
        error = str(getattr(task, "error", "") or "")
        disposition = str(getattr(task, "task_disposition", "") or "").strip()
        title = {
            "completed": "Result ready",
            "failed": "Task failed",
            "cancelled": "Task cancelled",
            "timed_out": "Task timed out",
        }.get(status, "Task failed")
        if status == "completed" and disposition == "steered":
            title = "Instruction added to active task"
        elif status == "completed" and disposition == "interrupted":
            title = "Active task interrupted"
        events.append({
            "event_id": f"timeline:{terminal_kind}:{task.task_id}",
            "kind": terminal_kind,
            "source_kind": "task",
            "title": title,
            "status": status,
            "detail": error[:1_000] if terminal_kind == "failure" else "",
            "created_at": completed_at,
            "updated_at": completed_at,
            "metadata": {
                **identity,
                "result_chars": len(result),
                "artifact_count": len(list(getattr(task, "output_files", []) or [])),
                "exit_code": getattr(task, "exit_code", None),
            },
            "synthetic": True,
            "_order": len(events) + 1_000,
        })

    events.sort(key=lambda event: (
        int(event.get("created_at") or 0),
        int(event.get("_order") or 0),
        str(event.get("event_id") or ""),
    ))
    for event in events:
        event.pop("_order", None)

    counts: dict[str, int] = {}
    for event in events:
        kind = str(event.get("kind") or "step")
        counts[kind] = counts.get(kind, 0) + 1
    terminal = status in TERMINAL_STATES
    expected_outcome = "result" if status == "completed" else "failure"
    return {
        "contract": CONTRACT_VERSION,
        "events": events[-256:],
        "counts": counts,
        "has_plan": counts.get("plan", 0) > 0,
        "has_tool_activity": counts.get("tool", 0) > 0,
        "has_retry": counts.get("retry", 0) > 0,
        "terminal": terminal,
        "complete": (
            terminal
            and counts.get("plan", 0) > 0
            and counts.get(expected_outcome, 0) > 0
        ),
    }


def _normalize_event(task: Any, event: dict, index: int) -> dict:
    source_kind = str(event.get("kind") or "step").strip().lower()
    source_metadata = event.get("metadata")
    metadata = {
        **(dict(source_metadata) if isinstance(source_metadata, dict) else {}),
        **_task_identity(task),
    }
    return {
        "event_id": str(event.get("event_id") or f"timeline:event:{task.task_id}:{index}"),
        "kind": _canonical_kind(source_kind, str(event.get("status") or ""), metadata),
        "source_kind": source_kind,
        "title": str(event.get("title") or "Task step"),
        "status": str(event.get("status") or "completed"),
        "detail": str(event.get("detail") or ""),
        "created_at": int(event.get("created_at") or getattr(task, "created_at", 0) or 0),
        "updated_at": int(
            event.get("updated_at")
            or event.get("created_at")
            or getattr(task, "updated_at", 0)
            or 0
        ),
        "metadata": metadata,
        "synthetic": False,
        "_order": index,
    }


def _canonical_kind(source_kind: str, status: str, metadata: dict) -> str:
    phase = str(metadata.get("phase") or metadata.get("loop_phase") or "").strip().lower()
    if source_kind in {"plan", "planning"} or phase == "plan":
        return "plan"
    if source_kind in {"retry", "retrying", "replan", "recovery"} or phase == "replan":
        return "retry"
    if (
        source_kind in {
            "tool", "command", "file", "browser", "mcp", "native_tool",
            "shell", "terminal", "image_view", "web_search",
        }
        or phase == "act" and bool(metadata.get("tool_call"))
        or any(key in metadata for key in ("tool_id", "tool_name", "tool_call_id"))
    ):
        return "tool"
    if source_kind in {"result", "final", "finalize"} or phase == "finalize":
        return "result"
    if source_kind in {"failure", "failed", "error"}:
        return "failure"
    if source_kind in {"verify", "verification"} or phase == "verify":
        return "verify"
    if source_kind in {"observe", "observation"} or phase == "observe":
        return "observe"
    if source_kind in {"act", "action"} or phase == "act":
        return "act"
    if source_kind in {"learn", "learning"} or phase == "learn":
        return "learn"
    if str(status or "").strip().lower() == "failed":
        return "failure"
    return source_kind or "step"


def _task_identity(task: Any) -> dict:
    return {
        "client_route_id": str(getattr(task, "client_route_id", "") or ""),
        "conversation_id": str(
            getattr(task, "client_conversation_id", "")
            or getattr(task, "conversation_id", "")
            or ""
        ),
        "task_id": str(getattr(task, "task_id", "") or ""),
        "turn_id": str(getattr(task, "client_turn_id", "") or ""),
        "agent_id": str(getattr(task, "delegate_agent_id", "") or getattr(task, "agent_id", "") or ""),
        "task_disposition": str(getattr(task, "task_disposition", "") or ""),
        "merged_into_task_id": str(getattr(task, "merged_into_task_id", "") or ""),
        "supersedes_task_id": str(getattr(task, "supersedes_task_id", "") or ""),
        "intervention_kind": str(getattr(task, "intervention_kind", "") or ""),
    }
