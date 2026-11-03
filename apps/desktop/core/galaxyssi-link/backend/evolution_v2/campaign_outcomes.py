"""Bind campaign dependency completion to observed CI and integrated source code."""
from __future__ import annotations

import re

from . import legacy
from .ci_snapshot import CiObservationError, target
from .ci_verification import verification_issue


def published_outcome(manager, task) -> dict:
    evidence = {"task_id": task.task_id, "pull_request_url": task.pull_request_url}
    def result(stage, error="", **extra):
        return {**evidence, "stage": stage, "error": error, **extra}
    watch = manager.ci_watches.get(task.task_id)
    if not watch or watch.get("url") != task.pull_request_url:
        return result("awaiting_ci", "Published task has no matching CI observation")
    snapshot = watch.get("snapshot") or {}
    if watch.get("error") or watch.get("status") == "observation_error":
        return result("awaiting_ci", str(watch.get("error") or "CI observation is unavailable"))
    if snapshot.get("url") != task.pull_request_url:
        return result("awaiting_ci", "CI observation does not match the published PR")
    evidence["head_sha"] = snapshot.get("head_sha", "")
    if snapshot.get("state") == "closed" and not snapshot.get("merged"):
        return result("failed", "Pull request was closed without integrating the candidate")
    try:
        repository, _ = target(task.pull_request_url)
    except CiObservationError:
        return result("awaiting_ci", "Published task has no canonical PR identity")
    if snapshot.get("repository") != repository:
        return result("awaiting_ci", "CI repository does not match the published PR")
    issue = verification_issue(snapshot, repository=repository)
    if issue:
        if snapshot.get("merged") and not snapshot.get("pending"):
            from .integration_verification import accepted_integration
            commit = accepted_integration(watch.get("integration"), snapshot, task.task_id)
            if commit:
                return result("completed", integration_commit=commit,
                              ci_fingerprint=watch["integration"]["ci"].get("fingerprint", ""),
                              integration_evidence=watch["integration"],
                              historical_ci_failed=snapshot.get("failed", 0) > 0,
                              historical_ci_unverified=True)
            integration = watch.get("integration") or {}
            detail = integration.get("reason", "") if isinstance(integration, dict) else ""
            stage = "failed" if snapshot.get("failed", 0) > 0 else "awaiting_ci"
            return result(stage, "Merged candidate has no verified CI success: " + issue +
                          (": " + detail if isinstance(detail, str) and detail else ""))
        return result("awaiting_ci", issue)
    if not snapshot.get("merged"):
        return result("awaiting_integration", "CI passed; the dependency PR is not merged yet")
    commit = snapshot.get("merge_commit_sha", "")
    if (not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit)
            or snapshot.get("base_ref") != "main"
            or snapshot.get("base_repository") != snapshot.get("repository")):
        return result("awaiting_integration", "No verified integration into the execution base")
    return result("completed", integration_commit=commit, ci_fingerprint=snapshot.get("fingerprint", ""))


def verify_dependency_source(manager, task, pinned: str) -> None:
    metadata = manager.v2_store.get_task_metadata(task.task_id)
    if metadata is None or not metadata.campaign_id or metadata.ci_repair_target:
        return
    durable = manager.campaigns.durable
    graph = durable.graph_store.load(durable.identity(metadata.campaign_id))
    if graph is None:
        raise legacy.EvolutionError("campaign_dependency_missing", "Campaign checkpoint is unavailable")
    nodes = graph["nodes"]
    matches = [node for node in nodes.values() if node["action"]["task_id"] == task.task_id]
    if len(matches) != 1:
        raise legacy.EvolutionError("campaign_dependency_missing", "Task has no unique campaign node")
    pending = list(matches[0]["depends_on"])
    visited = set()
    while pending:
        key = pending.pop()
        if key in visited:
            continue
        visited.add(key)
        dependency = nodes[key]
        pending.extend(dependency["depends_on"])
        outcome = dependency["result"]
        if dependency["status"] != "completed":
            raise legacy.EvolutionError("campaign_dependency_pending", "Campaign dependency is not complete")
        if not outcome.get("pull_request_url"):
            continue
        commit = outcome.get("integration_commit", "")
        if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
            raise legacy.EvolutionError("campaign_dependency_unverified", "Dependency has no integration commit")
        published = manager.require(dependency["action"]["task_id"])
        current = published_outcome(manager, published)
        if (published.pull_request_url != outcome["pull_request_url"] or current.get("stage") != "completed"):
            raise legacy.EvolutionError("campaign_dependency_unverified",
                "Retained dependency needs current CI verification: " + current.get("error", "Publication identity changed"))
        # Reopened watches must not be bypassed by an old completed graph checkpoint.
        # If newer integration evidence is used, the child's source must contain it too.
        commit = current["integration_commit"]
        checked = manager.runner.run(("git", "merge-base", "--is-ancestor", commit, pinned),
                                     manager.source_root, timeout_seconds=30)
        if checked.returncode != 0:
            raise legacy.EvolutionError("campaign_dependency_not_in_source",
                f"Dependency {key} integration commit {commit} is not in the pinned source {pinned}")
