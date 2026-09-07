"""Reviewed CI repair candidates target the original PR, never a replacement PR."""
from __future__ import annotations

from . import legacy


def require_target(manager, repair: dict, *, candidate: str = "") -> dict:
    current = manager.github.pull_request_head(repair["url"])
    repository = manager.github.current_repository()
    if current["repository"] != repository or current["head_repository"] != repository or current["base_repository"] != repository:
        raise legacy.EvolutionError("ci_repository_mismatch", "Automatic CI repair requires a PR in the configured origin repository")
    if current["state"] != "open" or current["head_ref"] != repair["head_ref"]:
        raise legacy.EvolutionError("ci_target_changed", "CI repair PR was closed or its branch changed")
    if current["head_sha"] not in {repair["head_sha"], candidate}:
        raise legacy.EvolutionError("ci_head_changed", "PR head changed; the old CI repair cannot be published")
    return current


def prepare_source(manager, task, repair: dict) -> str:
    require_target(manager, repair)
    for ref in ("main", f"refs/heads/{repair['head_ref']}"):
        result = manager.runner.run(("git", "fetch", "--no-tags", "origin", ref), manager.source_root, timeout_seconds=180)
        if result.returncode:
            raise legacy.EvolutionError("ci_source_fetch_failed", result.stdout[-2000:])
    result = manager.runner.run(("git", "rev-parse", "--verify", "FETCH_HEAD^{commit}"), manager.source_root, timeout_seconds=30)
    if result.returncode or result.stdout.strip() != repair["head_sha"]:
        raise legacy.EvolutionError("ci_head_changed", "Fetched PR branch no longer matches the failed CI head")
    return repair["head_sha"]


def publish_candidate(manager, task, worktree, repair: dict) -> str:
    current = require_target(manager, repair, candidate=task.candidate_commit)
    if current["head_sha"] == task.candidate_commit:
        return repair["url"]
    ancestor = manager.runner.run(("git", "merge-base", "--is-ancestor", repair["head_sha"], task.candidate_commit),
                                  worktree, timeout_seconds=30)
    if ancestor.returncode:
        raise legacy.EvolutionError("ci_repair_ancestry_invalid", "Repair candidate must descend from the observed PR head")
    fetched = manager.runner.run(("git", "fetch", "--no-tags", "origin", "main"), worktree, timeout_seconds=180)
    if fetched.returncode:
        raise legacy.EvolutionError("ci_source_fetch_failed", fetched.stdout[-2000:])
    pushed = manager.runner.run(("git", "push", "origin", f"{task.candidate_commit}:refs/heads/{repair['head_ref']}"),
                               worktree, timeout_seconds=600)
    if pushed.returncode:
        raise legacy.EvolutionError("ci_repair_push_failed", pushed.stdout[-2000:])
    # A lost success response is reconciled against the same candidate on the next attempt.
    verified = require_target(manager, repair, candidate=task.candidate_commit)
    if verified["head_sha"] != task.candidate_commit:
        raise legacy.EvolutionError("ci_repair_push_unconfirmed", "GitHub has not confirmed the repaired PR head")
    return repair["url"]
