"""Write-ahead candidate identity and same-attempt acceptance continuation."""
from __future__ import annotations

import re

from .common import sha256_text, stable_json
from .legacy import EvolutionError, _now_millis


REJECTED = {"cancelled", "candidate_review_failed", "agent_review_failed",
            "acceptance_review_failed", "quality_gate_failed"}


def requirements(manager, task):
    return sha256_text(stable_json({"problem": task.problem, "scope": task.scope,
        "acceptance": task.acceptance, "reproduction": task.reproduction_steps,
        "risk": task.risk_level, "context": manager._implementation_context(task)}))


def record_intent(manager, task, attempt):
    worktree = manager._managed_worktree_path(attempt.worktree)
    task.candidate_checkpoint = {"version": 1, "task_id": task.task_id,
        "attempt": attempt.number, "base": task.base_commit, "branch": attempt.branch,
        "worktree": str(worktree), "requirements": requirements(manager, task),
        "tree": manager._git_text(("write-tree",), cwd=worktree), "commit": ""}
    task.candidate_commit = task.candidate_branch = task.approval_hash = ""
    save_checkpoint(manager, task)
    manager._emit(task, "candidate_commit_intent", attempt=attempt.number)


def record_commit(manager, task, commit):
    task.candidate_checkpoint = {**task.candidate_checkpoint, "commit": commit}
    task.candidate_commit, task.candidate_branch = commit, task.attempts[-1].branch
    task.approval_hash = ""
    save_checkpoint(manager, task)
    manager._emit(task, "candidate_committed", attempt=task.attempts[-1].number)


def save_checkpoint(manager, task):
    with manager._lock:
        current = manager.require(task.task_id)
        if current.status in {"cancelled", "rolled_back"}:
            raise EvolutionError("cancelled", "Candidate checkpoint cannot overwrite a cancelled task.")
        manager.store.save(task)


def save_outcome(manager, task):
    with manager._lock:
        current = manager.require(task.task_id)
        if current.status in {"cancelled", "rolled_back"}:
            task.status = current.status
            task.last_error_code, task.last_error = current.last_error_code, current.last_error
            task.approval_hash = ""
        manager.store.save(task)


def invalid(reason):
    return EvolutionError("candidate_checkpoint_invalid", "Retained candidate checkpoint: " + reason)


def inspect(manager, task):
    checkpoint = task.candidate_checkpoint
    if not isinstance(checkpoint, dict) or checkpoint.get("version") != 1 or not task.attempts:
        raise invalid("missing or unsupported identity")
    attempt = task.attempts[-1]
    worktree = manager._managed_worktree_path(attempt.worktree)
    expected = {"task_id": task.task_id, "attempt": attempt.number,
                "base": task.base_commit, "branch": attempt.branch,
                "worktree": str(worktree), "requirements": requirements(manager, task)}
    if any(checkpoint.get(key) != value for key, value in expected.items()):
        raise invalid("task, attempt, workspace or source requirements changed")
    from .campaign_outcomes import verify_dependency_source
    verify_dependency_source(manager, task, task.base_commit)
    tree, commit = checkpoint.get("tree"), checkpoint.get("commit")
    if not isinstance(tree, str) or not re.fullmatch(r"[0-9a-f]{40}", tree):
        raise invalid("invalid expected Git tree")
    if not isinstance(commit, str) or (commit and not re.fullmatch(r"[0-9a-f]{40}", commit)):
        raise invalid("invalid candidate commit")
    manager._validate_worktree_identity(worktree, branch=attempt.branch, expected_commit=None)
    head = manager._git_text(("rev-parse", "HEAD"), cwd=worktree)
    if manager._git_text(("ls-files", "--others", "--exclude-standard"), cwd=worktree):
        raise invalid("untracked files appeared")
    if manager._git_text(("diff", "--name-only"), cwd=worktree):
        raise invalid("unstaged files changed")
    if manager._git_text(("write-tree",), cwd=worktree) != tree:
        raise invalid("staged tree differs from the commit intent")
    if commit and head != commit:
        raise invalid("candidate HEAD changed")
    if head != task.base_commit:
        if manager._git_text(("rev-parse", "HEAD^{tree}"), cwd=worktree) != tree:
            raise invalid("committed tree differs from the intent")
        if manager._git_text(("rev-list", "--parents", "-n", "1", "HEAD"), cwd=worktree).split() != [head, task.base_commit]:
            raise invalid("candidate is not one commit above the pinned base")
        return worktree, head
    if commit:
        raise invalid("recorded candidate reverted to its base")
    return worktree, ""


def retain_failure(manager, task, attempt):
    if not task.candidate_checkpoint:
        return False
    if manager.require(task.task_id).status in {"cancelled", "rolled_back"}:
        attempt.failure_code = "cancelled"
    if attempt.failure_code in REJECTED:
        try:
            inspect(manager, task)
        except Exception as error:
            cancelled = attempt.failure_code == "cancelled"
            task.status = "cancelled" if cancelled else "blocked"
            task.last_error_code = "cancelled" if cancelled else getattr(error, "code", "candidate_checkpoint_invalid")
            task.last_error = "Candidate retained without cleanup: " + str(error)[:3800]
            task.approval_hash = ""
            save_outcome(manager, task)
            manager._emit(task, "candidate_checkpoint_blocked", reason=task.last_error_code)
            return True
        task.candidate_checkpoint = {}
        task.candidate_commit = task.candidate_branch = task.approval_hash = ""
        save_outcome(manager, task)
        return False
    task.status = "blocked"
    task.approval_hash = ""
    save_outcome(manager, task)
    manager._emit(task, "candidate_review_pending", attempt=attempt.number,
                  reason=task.last_error_code)
    return True


def recover_candidate(manager, task):
    try:
        inspect(manager, task)
        status, code = "proposed", "desktop_restart"
        message = "Desktop restarted during candidate validation; resume the retained attempt without reimplementation."
    except Exception as error:
        status, code = "blocked", getattr(error, "code", "candidate_checkpoint_invalid")
        message = str(error)[:4000]
    with manager._lock:
        current = manager.require(task.task_id)
        if current.status != task.status:
            return False
        current.status, current.last_error_code, current.last_error = status, code, message
        current.approval_hash = ""
        manager.store.save(current)
    manager._emit(current, "candidate_checkpoint_recovered" if status == "proposed" else "candidate_checkpoint_blocked")
    return True


def check_cancelled(manager, task, cancellation):
    if cancellation.is_set() or manager.require(task.task_id).status in {"cancelled", "rolled_back"}:
        raise EvolutionError("cancelled", "Evolution task was cancelled during candidate continuation.")


def continue_candidate(manager, task_id, cancellation):
    task = manager.require(task_id)
    if not task.candidate_checkpoint:
        return False
    attempt = task.attempts[-1] if task.attempts else None
    try:
        check_cancelled(manager, task, cancellation)
        worktree, commit = inspect(manager, task)
        task.status = attempt.status = "validating"
        task.approval_hash = ""
        save_checkpoint(manager, task)
        manager._emit(task, "candidate_validation_resumed", attempt=attempt.number)
        # Re-run the current gates; a restored checkpoint never grants publication.
        manager._attach_gate_dependencies(worktree)
        try:
            attempt.gates = manager._run_gates(task, attempt, cancellation)
        finally:
            manager._detach_gate_dependencies(worktree)
        failed = next((gate for gate in attempt.gates if gate.status != "passed"), None)
        if failed is not None:
            raise manager._gate_failure_error(failed)
        check_cancelled(manager, task, cancellation)
        _, observed_commit = inspect(manager, task)
        if observed_commit != commit:
            raise invalid("HEAD changed while gates ran")
        if not commit:
            # The intent was persisted before Git commit; commit the unchanged tree once.
            commit = manager._commit_candidate(task, attempt)
        else:
            record_commit(manager, task, commit)
            manager._review_committed_candidate(task, attempt, commit)
        check_cancelled(manager, task, cancellation)
        inspect(manager, task)
        with manager._lock:
            check_cancelled(manager, task, cancellation)
            task.candidate_commit, task.candidate_branch = commit, attempt.branch
            task.candidate_checkpoint = {}
            task.last_error = task.last_error_code = ""
            attempt.failure_code = attempt.failure_summary = ""
            task.status, attempt.status = "waiting_approval", "passed"
            attempt.completed_at_millis = _now_millis()
            task.approval_hash = manager._approval_hash(task, attempt)
            manager.store.save(task)
        manager._emit(task, "candidate_ready", attempt=attempt.number)
    except Exception as error:
        code = getattr(error, "code", "unexpected_failure")
        task.last_error_code, task.last_error = code, str(error)[:4000]
        task.approval_hash = ""
        if attempt is not None:
            attempt.status = "cancelled" if code == "cancelled" else "failed"
            attempt.failure_code, attempt.failure_summary = code, task.last_error
            attempt.completed_at_millis = _now_millis()
        task.status = "cancelled" if code == "cancelled" else "blocked"
        save_outcome(manager, task)
        if code in REJECTED and attempt is not None:
            manager._cleanup_failed_attempt(task, attempt)
        manager._emit(task, "cancelled" if code == "cancelled" else "candidate_review_pending",
                      reason=code)
    return True
