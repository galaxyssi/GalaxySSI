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
    continuation = bool(getattr(task, "candidate_checkpoint", None))
    if isinstance(attempts, (list, tuple)) and type(maximum) is int:
        remaining = max(0, maximum - len(attempts))
        counts = {"attempt_count": len(attempts), "attempts_remaining": remaining}
        if continuation:
            counts["candidate_continuation"] = True
        if not remaining and not continuation and status in {"failed", "blocked", "proposed"} and not getattr(task, "pull_request_url", ""):
            blocker = "child_attempts_exhausted"
    return {"retryable": not blocker, "retry_blocker": blocker, **counts}


def terminal_observation(task):
    return {"task_id": task.task_id, "status": str(task.status),
            "error": str(getattr(task, "last_error", "")),
            "error_code": str(getattr(task, "last_error_code", "")),
            "pull_request_url": str(getattr(task, "pull_request_url", "")),
            **retry_admission(task), **candidate_recovery_observation(task)}


def candidate_recovery_observation(task):
    if not getattr(task, "candidate_checkpoint", None):
        return {}
    result = {"candidate_commit": str(getattr(task, "candidate_commit", "")),
              "retry_effect": "resume_candidate_validation_without_reimplementation"}
    code = str(getattr(task, "last_error_code", ""))
    if code in {"acceptance_review_unavailable", "acceptance_evidence_incomplete", "agent_review_unavailable",
                "acceptance_review_inconclusive"}:
        result.update(failure_phase="candidate_evaluation",
                      candidate_verdict="inconclusive" if code == "acceptance_review_inconclusive" else "unavailable",
                      candidate_failure_established=False)
    return result


def require_replacement_evidence(graph, decision):
    """Evaluation outages cannot authorize retiring an unassessed candidate."""
    from agent_task_dag import TaskDagError
    operation = decision.get("operation")
    keys = [decision.get("node_id")] if operation == "replace" else decision.get("supersede_ids", []) if operation == "revise" else []
    if not isinstance(keys, list):
        raise TaskDagError("supersede_ids must be an array of node IDs")
    for key in keys:
        if not isinstance(key, str):
            raise TaskDagError("Replacement requires a string node ID")
        result = graph["nodes"].get(key, {}).get("result", {})
        if (result.get("candidate_continuation") is True
                and result.get("failure_phase") == "candidate_evaluation"
                and result.get("candidate_failure_established") is False):
            raise TaskDagError(
                f"Cannot retire node {key}: candidate evaluation has no usable verdict. "
                "The implementation has not been shown to fail. Retry validation of the retained candidate, "
                "add diagnostic work without superseding this node, or wait for evaluator capability. "
                "No candidate files or DAG nodes were changed by this rejected operation.")
