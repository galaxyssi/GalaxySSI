"""Translate actual lifecycle boundaries without adding wire payloads or task writes."""

from agent_latency import record_task
from voice_latency import VoiceTraceEvents


LIFECYCLE_STAGES = {
    VoiceTraceEvents.AGENT_QUEUE_ENTERED: "desktop_task_created",
    VoiceTraceEvents.AGENT_RUN_STARTED: "desktop_agent_started",
    VoiceTraceEvents.AGENT_FIRST_PARTIAL_RESULT: "desktop_first_output",
    VoiceTraceEvents.AGENT_COMPLETED: "desktop_task_completed",
}

TRACE_STAGES = {
    "codex_turn_submit_started": "desktop_model_submit_started",
    "codex_turn_submitted": "desktop_model_submitted",
}


def lifecycle(task, event, attributes=None):
    stage = LIFECYCLE_STAGES.get(event)
    if stage:
        record_task(task.task_id, stage, provider=task.delegate_agent_id or task.agent_id,
                    outcome=str((attributes or {}).get("task_status") or ""), once=True)


def execution_event(task_id, event):
    if event.get("kind") not in {"tool", "command", "mcp", "file_change"}:
        return
    status = event.get("status")
    if status == "running":
        stage = "desktop_tool_started"
    elif status in {"completed", "failed", "cancelled", "timed_out"}:
        stage = "desktop_tool_completed"
    else:
        return
    # Tool IDs, not titles/commands/arguments, isolate concurrent operations.
    record_task(task_id, stage, operation_id=event["event_id"], outcome=status, once=True)


def trace_stage(task_id, stage):
    mapped = TRACE_STAGES.get(stage)
    if mapped:
        record_task(task_id, mapped, once=True)
