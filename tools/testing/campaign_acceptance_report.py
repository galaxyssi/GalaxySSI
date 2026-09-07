"""Derive acceptance milestones from current DAG evidence, never saved flags."""
from __future__ import annotations

import re


def snapshot(goal, graph, task_getter, active_workers, planning, outcome_getter):
    nodes = (graph or {}).get("nodes", {})
    tasks, missing, outcomes, urls = [], [], {}, {}
    ready, published = [], []
    for key, node in nodes.items():
        task_id = node["action"]["task_id"]
        task = task_getter(task_id)
        if task is None:
            missing.append(task_id)
            continue
        tasks.append(task.public())
        if node["status"] == "running" and task.status == "waiting_approval":
            ready.append(task_id)
        if task.pull_request_url:
            urls[key] = task.pull_request_url
            outcomes[key] = outcome_getter(task)
            if task.status in {"published", "completed"}:
                published.append(task_id)
    needs_observation = (goal.get("status") in {"waiting", "local_model_unavailable"}
                         or any(row.get("status") in {"waiting", "local_model_unavailable"}
                                for row in planning.get("observations", [])))
    complete = bool(nodes) and not missing and not active_workers and (graph or {}).get("status") == "completed"
    complete = complete and all(node["status"] == "completed" for node in nodes.values())
    complete = complete and all(task["status"] in {"published", "completed"} for task in tasks)
    complete = complete and goal.get("status") not in {"paused", "cancelled"}
    # Publication acceptance requires current integration evidence, not a historical URL.
    complete = complete and bool(outcomes) and all(
        outcome.get("stage") == "completed"
        and outcome.get("task_id") == nodes[key]["action"]["task_id"]
        and outcome.get("pull_request_url") == urls[key]
        and isinstance(outcome.get("integration_commit"), str)
        and re.fullmatch(r"[0-9a-f]{40}", outcome["integration_commit"])
        for key, outcome in outcomes.items())
    stage, exit_code = "running", None
    if complete:
        stage, exit_code = "completed", 0
    elif not active_workers:
        if ready:
            stage, exit_code = "candidate_ready", 2
        elif needs_observation:
            stage, exit_code = "needs_observation", 4
        elif graph and graph.get("status") in {"completed", "cancelled"}:
            stage, exit_code = "completion_unverified", 1
        elif published and all(node["status"] in {"running", "completed"} for node in nodes.values()):
            if all(task["status"] in {"published", "completed"} for task in tasks) and not missing:
                stage, exit_code = "awaiting_integration", 3
    return {"goal": goal, "graph": graph, "tasks": tasks, "missing_task_ids": missing,
            "candidate_ready": bool(ready), "ready_task_ids": ready,
            "current_published_task_ids": published, "integration_outcomes": outcomes,
            "needs_observation": needs_observation, "full_campaign_complete": bool(complete),
            "acceptance_stage": stage, "exit_code": exit_code, "active_workers": active_workers}


def invalidate_cached_milestones(record):
    """A restarted controller has not yet observed any current milestone."""
    record.update(candidate_ready=False, ready_task_ids=[], current_published_task_ids=[],
                  integration_outcomes={}, needs_observation=False, full_campaign_complete=False,
                  acceptance_stage="observing", exit_code=None)
