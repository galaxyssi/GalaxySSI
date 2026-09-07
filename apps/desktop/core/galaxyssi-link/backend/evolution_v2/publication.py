"""Reconcile GitHub publication side effects against a durable reviewed candidate."""
from __future__ import annotations

import re

from . import legacy
from .github_client import _safe_repository
from .models import TaskMetadata


def _intent(manager, task, base_branch: str | None = None) -> dict | None:
    metadata = manager.v2_store.get_task_metadata(task.task_id)
    saved = metadata.publication_intent if metadata else {}
    if base_branch is None and not saved:
        return None
    repository = _safe_repository(manager.github.current_repository())
    wanted = {"repository": repository, "head_ref": task.candidate_branch,
              "head_sha": task.candidate_commit, "base_ref": base_branch or saved.get("base_ref")}
    if not re.fullmatch(r"[0-9a-f]{40}", str(wanted["head_sha"])):
        raise legacy.EvolutionError("publication_identity_invalid", "Candidate commit is invalid")
    for key in ("head_ref", "base_ref"):
        ref = wanted[key]
        if (not isinstance(ref, str) or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._/-]*", ref)
                or ".." in ref or "//" in ref or ref.endswith(("/", ".", ".lock"))):
            raise legacy.EvolutionError("publication_identity_invalid", "Publication branch is invalid")
    if saved and saved != wanted:
        raise legacy.EvolutionError("publication_intent_changed", "Recorded publication target differs from this candidate")
    if not saved:
        metadata = metadata or TaskMetadata(task_id=task.task_id)
        metadata.publication_intent = wanted
        manager.v2_store.save_task_metadata(metadata)
    return wanted


def find_published_candidate(manager, intent: dict) -> str:
    repository = intent["repository"]
    pages = manager.github._api((
        "--paginate", "--slurp", "-X", "GET", f"repos/{repository}/pulls",
        "-f", f"head={repository.split('/')[0]}:{intent['head_ref']}",
        "-f", f"base={intent['base_ref']}", "-f", "state=all", "-f", "per_page=100",
    ))
    if not isinstance(pages, list) or not pages or any(not isinstance(page, list) for page in pages):
        raise legacy.EvolutionError("publication_observation_invalid", "GitHub PR listing is incomplete")
    numbers = []
    for page in pages:
        for row in page:
            if not isinstance(row, dict) or type(row.get("number")) is not int or row["number"] <= 0:
                raise legacy.EvolutionError("publication_observation_invalid", "GitHub PR identity is invalid")
            numbers.append(row["number"])
    if len(numbers) > 1:
        raise legacy.EvolutionError("publication_ambiguous", "More than one PR matches the candidate branch")
    if not numbers:
        return ""
    url = f"https://github.com/{repository}/pull/{numbers[0]}"
    current = manager.github.pull_request_head(url)
    expected = {"repository": repository, "head_repository": repository, "base_repository": repository,
                "head_ref": intent["head_ref"], "base_ref": intent["base_ref"], "head_sha": intent["head_sha"]}
    if any(current.get(key) != value for key, value in expected.items()):
        raise legacy.EvolutionError("publication_target_changed", "Existing PR does not match the reviewed candidate")
    if current["state"] != "open" and not current["merged"]:
        raise legacy.EvolutionError("publication_closed", "The candidate PR was closed without merging")
    return url


def publish_candidate(manager, task, attempt, worktree, base_branch: str) -> str:
    intent = _intent(manager, task, base_branch)
    existing = find_published_candidate(manager, intent)
    if existing:
        return existing
    pushed = manager.runner.run(("git", "push", "--set-upstream", "origin",
                                 f"{task.candidate_commit}:refs/heads/{task.candidate_branch}"),
                                worktree, timeout_seconds=600)
    if pushed.returncode:
        raise legacy.EvolutionError("candidate_push_failed", pushed.stdout[-4_000:])
    # Recheck after push: another actor may already have created this branch's PR.
    existing = find_published_candidate(manager, intent)
    if existing:
        return existing
    error = None
    try:
        created = manager.runner.run((
            "gh", "pr", "create", "--repo", intent["repository"], "--base", base_branch,
            "--head", task.candidate_branch, "--title", manager._pull_request_title(task),
            "--body", manager._pull_request_body(task, attempt)), worktree, timeout_seconds=300)
        if created.returncode:
            error = legacy.EvolutionError("pull_request_create_failed", created.stdout[-4_000:])
    except Exception as exc:
        error = exc
    # Even a failed/lost command response can have created the PR. Verify remotely.
    existing = find_published_candidate(manager, intent)
    if existing:
        return existing
    if error is not None:
        raise error
    raise legacy.EvolutionError("publication_unconfirmed", "GitHub has not confirmed the candidate PR")


def reconcile_interrupted(manager, task) -> str:
    metadata = manager.v2_store.get_task_metadata(task.task_id)
    if metadata and metadata.ci_repair_target:
        from .ci_repair import require_target
        current = require_target(manager, metadata.ci_repair_target, candidate=task.candidate_commit)
        return current["url"] if current["head_sha"] == task.candidate_commit else ""
    intent = _intent(manager, task)
    return find_published_candidate(manager, intent) if intent else ""
