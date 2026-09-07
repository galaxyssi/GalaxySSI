"""Revalidate retained candidates without publishing or discarding their worktrees."""
from __future__ import annotations

import threading

from .legacy import EvolutionError


def revalidatable(task):
    return bool(task.candidate_commit and task.attempts and (
        task.status == "waiting_approval" or (
            task.status in {"failed", "blocked"} and task.last_error_code in {
                "acceptance_review_failed", "acceptance_review_inconclusive",
                "acceptance_review_unavailable", "acceptance_evidence_incomplete"})))


def record_rejection(manager, task, error):
    with manager._lock:
        saved = manager.require(task.task_id)
        if revalidatable(saved) and saved.candidate_commit == task.candidate_commit:
            saved.status = "failed" if error.code in {"acceptance_review_failed", "acceptance_review_inconclusive"} else "blocked"
            if saved.status == "failed":
                saved.candidate_checkpoint = {}
            saved.approval_hash = ""
            saved.last_error_code, saved.last_error = error.code, str(error)[:4000]
            saved.attempts[-1].status = "failed"
            saved.attempts[-1].failure_code = error.code
            saved.attempts[-1].failure_summary = saved.last_error
            manager.store.save(saved)


def revalidate_candidate(manager, task_id):
    current = threading.current_thread()
    with manager._lock:
        if task_id in manager._threads or task_id in manager._recovering_tasks or task_id in manager._active_publications:
            raise EvolutionError("task_execution_active", "Candidate has an active execution owner")
        task = manager.require(task_id)
        if not revalidatable(task):
            raise EvolutionError("candidate_not_ready", "Only a retained pending candidate can be revalidated")
        manager._claim_task_operation(task_id)
        manager._threads[task_id] = current
    try:
        from owned_process import owned_process_scope
        with owned_process_scope(manager._process_journal(task_id)):
            attempt = task.attempts[-1]
            worktree = manager._managed_worktree_path(attempt.worktree)
            manager._validate_worktree_identity(worktree, branch=attempt.branch, expected_commit=task.candidate_commit)
            if manager._git_text(("status", "--porcelain=v1"), cwd=worktree):
                raise EvolutionError("candidate_dirty_after_review", "Retained candidate has uncommitted changes")
            manager.audit.append("candidate_revalidation_started", task_id=task_id,
                                 payload={"candidate_commit": task.candidate_commit})
            try:
                manager._require_candidate_acceptance(task, worktree, task.candidate_commit, force=True)
            except EvolutionError as error:
                record_rejection(manager, task, error)
                manager.audit.append("candidate_revalidation_rejected", task_id=task_id, payload={"error_code": error.code})
            else:
                with manager._lock:
                    saved = manager.require(task_id)
                    if revalidatable(saved) and saved.candidate_commit == task.candidate_commit:
                        saved.status = "waiting_approval"
                        saved.candidate_checkpoint = {}
                        saved.last_error = saved.last_error_code = ""
                        saved.attempts[-1].status = "passed"
                        saved.attempts[-1].failure_code = saved.attempts[-1].failure_summary = ""
                        saved.approval_hash = manager._approval_hash(saved, saved.attempts[-1])
                        manager.store.save(saved)
                        manager.audit.append("candidate_revalidation_passed", task_id=task_id,
                                             payload={"candidate_commit": task.candidate_commit})
            return manager.require(task_id)
    finally:
        with manager._lock:
            if manager._threads.get(task_id) is current:
                manager._threads.pop(task_id, None)
            manager.task_owners.release(task_id)
