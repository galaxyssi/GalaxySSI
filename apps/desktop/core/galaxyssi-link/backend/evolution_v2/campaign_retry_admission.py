"""Observed child retry admission, independent of the lifetime of its parent goal."""
from __future__ import annotations


def retry_admission(task):
    status = str(getattr(task, "status", ""))
    blocker = ""
    if getattr(task, "pull_request_url", ""):
        blocker = "candidate_already_published"
    elif status not in {"failed", "blocked"}:
        blocker = "child_not_retryable"
    attempts = getattr(task, "attempts", None)
    maximum = getattr(task, "max_attempts", None)
    counts = {}
    if isinstance(attempts, (list, tuple)) and type(maximum) is int:
        remaining = max(0, maximum - len(attempts))
        counts = {"attempt_count": len(attempts), "attempts_remaining": remaining}
        if not remaining and status in {"failed", "blocked", "proposed"} and not getattr(task, "pull_request_url", ""):
            blocker = "child_attempts_exhausted"
    return {"retryable": not blocker, "retry_blocker": blocker, **counts}


def terminal_observation(task):
    return {"task_id": task.task_id, "status": str(task.status),
            "error": str(getattr(task, "last_error", "")),
            "error_code": str(getattr(task, "last_error_code", "")),
            "pull_request_url": str(getattr(task, "pull_request_url", "")),
            **retry_admission(task)}
