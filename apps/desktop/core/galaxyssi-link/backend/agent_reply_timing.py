"""Content-free measurements of reply processing before physical publication."""

import uuid

from agent_latency import record_task
from agent_timing_clock import now_ns

PHASES = ("evidence", "archive", "outbox", "encrypt", "wire_prepare")


def measure(task_id, phase, operation):
    if not task_id or phase not in PHASES:
        return operation()
    key = uuid.uuid4().hex

    def record(boundary, outcome=""):
        try:
            record_task(task_id, f"desktop_reply_{phase}_{boundary}", operation_id=key,
                        outcome=outcome, at_ns=now_ns(), once=True)
        except Exception:
            pass

    record("started")
    outcome = "failed"
    try:
        result = operation()
        outcome = "completed"
        return result
    finally:
        record("finished", outcome)
