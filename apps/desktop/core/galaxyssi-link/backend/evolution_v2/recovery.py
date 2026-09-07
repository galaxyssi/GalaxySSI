"""Incremental restart recovery, fenced against this manager's live operations."""
from __future__ import annotations


def recover_interrupted(manager, *, resume: bool, statuses=None, pending_only=False) -> list[str]:
    statuses = statuses or {"preparing", "running", "validating", "publishing"}
    recovered = []
    for row in manager.store.iter_tasks():
        if row.status not in statuses:
            continue
        if pending_only and row.last_error_code != "process_termination_pending":
            continue
        task_id = row.task_id
        try:
            with manager.task_owners.hold(task_id) as owned:
                if not owned:
                    continue
                with manager._lock:
                    if (task_id in manager._threads or task_id in manager._active_publications
                            or task_id in manager._recovering_tasks):
                        continue
                    task = manager.store.get(task_id)
                    if task is None or task.status not in statuses:
                        continue
                    manager._recovering_tasks.add(task_id)
                try:
                    try:
                        manager._verify_process_termination(task_id)
                    except Exception as error:
                        if getattr(error, "code", "") == "process_termination_pending":
                            with manager._lock:
                                current = manager.store.get(task_id)
                                if current is not None and current.status == task.status:
                                    current.last_error_code = error.code
                                    current.last_error = str(error)
                                    manager.store.save(current)
                        raise
                    from owned_process import owned_process_scope
                    with owned_process_scope(manager._process_journal(task_id)):
                        _recover_reserved(manager, task)
                    recovered.append(task_id)
                finally:
                    with manager._lock:
                        manager._recovering_tasks.discard(task_id)
        except Exception as error:
            manager.audit.append("task_recovery_error", task_id=task_id,
                                 payload={"error_type": type(error).__name__})
    if resume:
        manager.resume_recovered_tasks()
    return recovered


def resume_recovered_tasks(manager, config: dict) -> list[str]:
    from .scheduler import _normalized_config

    config = _normalized_config(config)
    if not config["enabled"] or not config["auto_start_tasks"]:
        return []
    recover_interrupted(manager, resume=False, statuses={"publishing"})
    recover_interrupted(manager, resume=False, statuses={"preparing", "running", "validating"}, pending_only=True)
    capacity = 1 if config["execution_mode"] == "serial" else config["max_parallel_evolutions"]
    started = []
    # Limit admission per tick as well as concurrent workers, even if jobs finish instantly.
    for row in manager.store.iter_tasks():
        if len(started) >= capacity:
            break
        if row.status != "proposed" or row.last_error_code != "desktop_restart":
            continue
        try:
            with manager._lock:
                if manager.active_worker_count() >= capacity:
                    break
                task_id = row.task_id
                if (task_id in manager._threads or task_id in manager._active_publications
                        or task_id in manager._recovering_tasks):
                    continue
                current = manager.store.get(task_id)
                if current is None or current.status != "proposed" or current.last_error_code != "desktop_restart":
                    continue
                metadata = manager.v2_store.get_task_metadata(task_id)
                if metadata and (metadata.ci_repair_target or metadata.campaign_id):
                    continue
                manager.start(task_id)
                started.append(task_id)
        except Exception as error:
            manager.audit.append("task_recovery_start_error", task_id=row.task_id,
                                 payload={"error_type": type(error).__name__})
    return started


def _recover_reserved(manager, task):
    from .legacy import EvolutionError

    original_status = task.status
    if original_status != "publishing" and task.candidate_checkpoint:
        from .candidate_checkpoint import recover_candidate
        return recover_candidate(manager, task)
    cleanup_error = None
    published_url = ""
    if original_status == "publishing":
        from .publication import reconcile_interrupted
        try:
            published_url = reconcile_interrupted(manager, task)
        except Exception as error:
            with manager._lock:
                current = manager.store.get(task.task_id)
                if current is not None and current.status == "publishing":
                    current.last_error_code = getattr(error, "code", "publication_observation_failed")
                    current.last_error = str(error)[:4_000]
                    manager.store.save(current)
            raise
    if original_status != "publishing" and task.attempts:
        try:
            manager._remove_worktree(task.attempts[-1], delete_branch=True)
        except EvolutionError as error:
            cleanup_error = error
    with manager._lock:
        current = manager.store.get(task.task_id)
        if current is None or current.status != original_status:
            return False
        if cleanup_error is not None:
            current.status = "blocked"
            current.last_error_code = cleanup_error.code
            current.last_error = str(cleanup_error)[:4_000]
        elif published_url:
            current.status = "published"
            current.pull_request_url = published_url
            current.last_error_code = ""
            current.last_error = ""
        elif original_status == "publishing":
            current.status = "waiting_approval"
            current.last_error_code = "publish_interrupted"
            current.last_error = "Desktop restarted while publishing. Recheck GitHub and approve publish again."
        else:
            current.last_error_code = "desktop_restart"
            current.last_error = "Desktop restarted during an isolated attempt; the attempt was rolled back."
            current.status = "proposed" if len(current.attempts) < current.max_attempts else "failed"
        manager.store.save(current)
    if published_url:
        metadata = manager.v2_store.get_task_metadata(current.task_id)
        if metadata is None or not metadata.ci_repair_target:
            try:
                manager.ci_watches.register(current.task_id, published_url)
            except Exception:
                manager.ci_watch_index_needed.set()
                raise
        manager._emit(current, "publication_recovered")
    if cleanup_error is not None:
        manager._emit(current, "cleanup_refused", attempt=current.attempts[-1].number)
