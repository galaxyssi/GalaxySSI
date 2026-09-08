"""Reverify retained candidate bytes against an independently green integration."""
from __future__ import annotations

import re

from .ci_snapshot import CiObservationError, observe_commit
from .common import sha256_text, stable_json


def verify_integration(manager, task_id, snapshot):
    evidence = {"version": 1, "task_id": task_id, "url": snapshot["url"],
                "head_sha": snapshot["head_sha"], "merge_commit_sha": snapshot.get("merge_commit_sha"),
                "repository": snapshot["repository"], "base_ref": snapshot.get("base_ref"),
                "base_repository": snapshot.get("base_repository"), "passed": False}
    def unavailable(reason):
        return {**evidence, "reason": reason}
    if (not snapshot.get("merged") or snapshot.get("state") != "closed"
            or snapshot.get("base_ref") != "main"
            or snapshot.get("base_repository") != snapshot["repository"]
            or snapshot.get("head_repository") != snapshot["repository"]):
        return unavailable("The candidate has no same-repository main integration")
    task = manager.require(task_id)
    metadata = manager.v2_store.get_task_metadata(task_id)
    source = getattr(metadata, "source_commit", "")
    head, merged = evidence["head_sha"], evidence["merge_commit_sha"]
    if (getattr(task, "candidate_commit", "") != head or task.pull_request_url != snapshot["url"]
            or any(not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha)
                   for sha in (source, head, merged))):
        return unavailable("The observed PR does not match the retained accepted candidate")
    if manager.github.current_repository() != snapshot["repository"]:
        return unavailable("The source repository does not match the published candidate")

    def git(*args):
        result = manager.runner.run(("git", *args), manager.source_root, timeout_seconds=120)
        if result.returncode != 0:
            raise CiObservationError("Integration Git evidence is unavailable")
        if len(result.stdout) >= 2_000_000 or "[REDACTED" in result.stdout or "\ufffd" in result.stdout:
            raise CiObservationError("Integration Git evidence was truncated or transformed")
        return result.stdout

    # Fetch objects only. The user's checkout and index are never changed.
    endpoint = f"repos/{snapshot['repository']}/git/ref/heads/main"
    ref = manager.github._api((endpoint,))
    obj = ref.get("object") if isinstance(ref, dict) else None
    integrated = obj.get("sha") if isinstance(obj, dict) else None
    if (not isinstance(integrated, str) or not re.fullmatch(r"[0-9a-f]{40}", integrated)
            or ref.get("ref") != "refs/heads/main" or ref["object"].get("type") != "commit"):
        raise CiObservationError("Integration commit identity is invalid")
    git("fetch", "origin", integrated)
    evidence.update(source_commit=source, integration_commit=integrated)
    ancestor = manager.runner.run(("git", "merge-base", "--is-ancestor", merged, integrated),
                                   manager.source_root, timeout_seconds=30)
    if ancestor.returncode == 1:
        return unavailable("The integration no longer contains the candidate's merge commit")
    if ancestor.returncode != 0:
        raise CiObservationError("Integration ancestry could not be checked")
    def changed_paths(before, after):
        # No rename inference, external diff, text conversion, or submodule suppression.
        paths = git("diff", "--no-ext-diff", "--no-textconv", "--ignore-submodules=none",
                    "--no-renames", "--name-only", "-z", before, after, "--").split("\0")
        if paths[-1] != "":
            raise CiObservationError("Candidate path evidence is incomplete")
        if any("\r" in path or "\n" in path for path in paths):
            raise CiObservationError("Candidate paths cannot be represented losslessly by the text runner")
        return paths[:-1]

    paths = changed_paths(source, head)
    if not paths:
        return unavailable("The retained candidate has no changed paths to verify")
    if set(paths).intersection(changed_paths(head, integrated)):
        return unavailable("A candidate path changed after publication; fresh semantic acceptance is required")
    ci = observe_commit(manager.github, snapshot["repository"], integrated)
    evidence.update(ci=ci, retained_paths=len(paths),
                    retention_fingerprint=sha256_text(stable_json([source, head, integrated, sorted(paths)])))
    if ci.get("passed") is not True:
        return unavailable("The integrated commit has not passed all reported CI checks")
    if manager.github._api((endpoint,)) != ref:
        raise CiObservationError("Main changed during integration verification")
    if manager.github.pull_request_head(snapshot["url"]) != {
            key: snapshot[key] for key in ("url", "repository", "number", "head_sha", "head_ref",
                "head_repository", "base_ref", "base_repository", "state", "merged", "merge_commit_sha")}:
        raise CiObservationError("Published candidate changed during integration verification")
    evidence.update(passed=True, reason="Candidate paths are unchanged in a green descendant integration")
    return evidence


def accepted_integration(proof, snapshot, task_id):
    if not isinstance(proof, dict) or proof.get("version") != 1 or proof.get("passed") is not True:
        return None
    if (snapshot.get("merged") is not True or snapshot.get("state") != "closed"
            or snapshot.get("base_ref") != "main" or snapshot.get("base_repository") != snapshot.get("repository")
            or snapshot.get("head_repository") != snapshot.get("repository")
            or proof.get("task_id") != task_id or any(proof.get(key) != snapshot.get(key)
            for key in ("url", "repository", "head_sha", "merge_commit_sha", "base_ref", "base_repository"))):
        return None
    ci = proof.get("ci") or {}
    if not isinstance(ci, dict) or not isinstance(ci.get("checks"), list):
        return None
    commit = proof.get("integration_commit")
    if (not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit)
            or ci.get("head_sha") != commit or ci.get("repository") != snapshot.get("repository")
            or ci.get("passed") is not True or ci.get("failed") != 0 or ci.get("pending") != 0 or not ci["checks"]
            or any(not isinstance(row, dict) or row.get("outcome") != "passed" for row in ci["checks"])
            or type(proof.get("retained_paths")) is not int or proof["retained_paths"] <= 0
            or not re.fullmatch(r"[0-9a-f]{64}", str(proof.get("retention_fingerprint", "")))):
        return None
    return commit
