"""Project high-level Agent task snapshots into the portable Run ledger."""

from __future__ import annotations

import hashlib
import json
from dataclasses import replace
from pathlib import Path
import sqlite3
from typing import Mapping

from agent_run_kernel import AgentRunEvent, AgentRunEventLedger


_TASK_STATUS_EVENTS = {
    "accepted": "RUN_CREATED",
    "queued": "RUN_QUEUED",
    "starting": "RUN_STARTED",
    "running": "THINKING",
    "recovering": "RUN_RECOVERED",
    "waiting_input": "WAITING_FOR_USER",
    "waiting_approval": "TOOL_PERMISSION_REQUIRED",
    "pausing": "PAUSED",
    "paused": "PAUSED",
    "takeover": "PAUSED",
    "interrupted": "RUN_INTERRUPTED",
    "completed": "RUN_COMPLETED",
    "failed": "RUN_FAILED",
    "timed_out": "RUN_FAILED",
    "cancelled": "RUN_CANCELLED",
}

_TOOL_KINDS = frozenset({
    "command",
    "file",
    "image_view",
    "mcp",
    "search",
    "shell",
    "tool",
})


class AgentTaskRunEventSink:
    """Append-only lifecycle sink used by the Desktop task projection."""

    def __init__(
        self,
        path: Path,
        *,
        ledger: AgentRunEventLedger | None = None,
    ) -> None:
        self.ledger = ledger or AgentRunEventLedger(path)

    def append_snapshot(
        self, snapshot: Mapping[str, object], *, connection: sqlite3.Connection | None = None,
    ) -> tuple[AgentRunEvent, bool]:
        task_id = _identifier(snapshot.get("task_id"), "unknown-task")
        run_id = _identifier(snapshot.get("run_id"), f"task:{task_id}")
        previous = self.ledger.snapshot(run_id, connection=connection)
        event = task_snapshot_event(
            snapshot,
            previous_state=_text((previous or {}).get("state")),
        )
        replay = self.ledger.event_for_idempotency(run_id, event.idempotency_key, connection=connection)
        if replay is not None:
            # The initial state-dependent label is chosen once, not on every replay.
            event = replace(event, type=replay.type)
        return self.ledger.append(event, connection=connection)

    def events(
        self,
        run_id: str,
        *,
        after_sequence: int = 0,
        limit: int | None = None,
    ) -> list[dict]:
        return [
            event.public()
            for event in self.ledger.events(
                run_id,
                after_sequence=after_sequence,
                limit=limit,
            )
        ]

    def snapshot(self, run_id: str) -> dict | None:
        return self.ledger.snapshot(run_id)


def task_snapshot_event(
    snapshot: Mapping[str, object],
    *,
    previous_state: str = "",
) -> AgentRunEvent:
    task_id = _identifier(snapshot.get("task_id"), "unknown-task")
    run_id = _identifier(snapshot.get("run_id"), f"task:{task_id}")
    route_id = _identifier(snapshot.get("client_route_id"), "desktop-local")
    conversation_id = _identifier(
        snapshot.get("client_conversation_id") or snapshot.get("conversation_id"),
        f"conversation:{task_id}",
    )
    goal_id = _identifier(snapshot.get("goal_id"), task_id)
    turn_id = _identifier(
        snapshot.get("client_turn_id")
        or snapshot.get("source_message_id")
        or snapshot.get("turn_id"),
        f"turn:{task_id}",
    )
    status = _text(snapshot.get("status")).lower() or "running"
    status_sequence = max(0, _integer(snapshot.get("status_seq")))
    generation = max(1, _integer(snapshot.get("execution_generation"), 1))
    latest = _latest_projection_event(snapshot)
    event_type = _event_type(status, latest, previous_state)
    action_id = _identifier(
        latest.get("event_id") or snapshot.get("action_id"),
        f"task:{status}:{generation}:{status_sequence}",
    )
    timestamp = max(
        0,
        _integer(latest.get("updated_at")),
        _integer(latest.get("created_at")),
        _integer(snapshot.get("updated_at")),
        _integer(snapshot.get("created_at")),
    )
    payload = {
        "source": "desktop-agent-task-manager",
        "task_status": status,
        "status_sequence": status_sequence,
        "execution_generation": generation,
        "attempt": max(1, _integer(snapshot.get("attempt"), 1)),
        "recovery_state": _text(snapshot.get("recovery_state"))[:64],
        "current_step": _text(snapshot.get("current_step"))[:500],
        "has_result": bool(_text(snapshot.get("result"))),
        "error": _text(snapshot.get("error"))[:1_000],
    }
    if latest:
        payload["projection_event"] = {
            "event_id": _text(latest.get("event_id"))[:256],
            "kind": _text(latest.get("kind"))[:64],
            "status": _text(latest.get("status"))[:64],
            "title": _text(latest.get("title"))[:500],
            "detail": _text(latest.get("detail"))[:2_000],
        }
    semantic_digest = hashlib.sha256(json.dumps(
        {
            "action_id": action_id,
            "payload": payload,
        },
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")).hexdigest()[:24]
    task_key = hashlib.sha256(task_id.encode("utf-8")).hexdigest()[:24]
    event_key = (
        f"task-snapshot:{task_key}:{generation}:{status_sequence}:"
        f"{semantic_digest}"
    )
    event_id = "task-evt-" + hashlib.sha256(
        f"{run_id}\x1f{event_key}".encode("utf-8")
    ).hexdigest()
    return AgentRunEvent.from_mapping({
        "event_id": event_id,
        "idempotency_key": event_key,
        "client_route_id": route_id,
        "conversation_id": conversation_id,
        "goal_id": goal_id,
        "task_id": task_id,
        "run_id": run_id,
        "turn_id": turn_id,
        "action_id": action_id,
        "message_id": _identifier(snapshot.get("source_message_id"), ""),
        "step_id": _identifier(latest.get("event_id"), ""),
        "tool_call_id": _identifier(
            (latest.get("metadata") or {}).get("tool_call_id")
            if isinstance(latest.get("metadata"), Mapping) else "",
            "",
        ),
        "agent_id": _identifier(
            snapshot.get("delegate_agent_id") or snapshot.get("agent_id"),
            "desktop",
        ),
        "device_id": "desktop",
        "type": event_type,
        "sequence": 0,
        "timestamp_millis": timestamp,
        "payload": payload,
    })


def _latest_projection_event(snapshot: Mapping[str, object]) -> Mapping[str, object]:
    events = snapshot.get("events")
    if not isinstance(events, list) or not events:
        return {}
    candidate = events[-1]
    if not isinstance(candidate, Mapping):
        return {}
    event_at = max(
        _integer(candidate.get("updated_at")),
        _integer(candidate.get("created_at")),
    )
    snapshot_at = _integer(snapshot.get("updated_at"))
    return candidate if event_at >= snapshot_at else {}


def _event_type(
    status: str,
    latest: Mapping[str, object],
    previous_state: str,
) -> str:
    if status in {"completed", "failed", "timed_out", "cancelled", "interrupted"}:
        return _TASK_STATUS_EVENTS[status]
    if status in {"accepted", "queued", "waiting_input", "waiting_approval", "pausing", "paused", "takeover"}:
        return _TASK_STATUS_EVENTS[status]
    kind = _text(latest.get("kind")).lower()
    event_status = _text(latest.get("status")).lower()
    if kind in {"replan", "retry"}:
        return "RETRYING"
    if kind == "recovery" or status == "recovering":
        return "RUN_RECOVERED"
    if kind in {"plan", "planning"}:
        return "PLANNING"
    if kind in {"handoff", "delegate", "delegation"}:
        return "HANDOFF"
    if kind in {"checkpoint", "checkpoint_saved"}:
        return "CHECKPOINT_SAVED"
    if kind in {"clarification", "waiting_input"}:
        return "WAITING_FOR_USER"
    if kind in {"approval", "permission"}:
        return "TOOL_PERMISSION_REQUIRED"
    if kind in _TOOL_KINDS:
        if event_status in {"completed", "failed", "cancelled"}:
            return "TOOL_COMPLETED"
        if event_status in {"running", "started", "pending"}:
            return "TOOL_STARTED"
        return "TOOL_PROGRESS"
    if latest:
        return "STEP_COMPLETED" if event_status == "completed" else "STEP_STARTED"
    if status in {"starting", "running"} and previous_state in {"", "created", "queued"}:
        return "RUN_STARTED"
    return _TASK_STATUS_EVENTS.get(status, "THINKING")


def _identifier(value: object, fallback: str) -> str:
    text = _text(value) or fallback
    if len(text) <= 256:
        return text
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()[:24]
    return f"{text[:231]}:{digest}"


def _text(value: object) -> str:
    return str(value or "").strip()


def _integer(value: object, fallback: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return int(fallback)
