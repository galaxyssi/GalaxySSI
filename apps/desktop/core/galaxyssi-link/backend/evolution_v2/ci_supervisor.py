"""Persistent publish/observe/repair loop, separate from UI and proposal scheduling."""
from __future__ import annotations

import threading
import uuid

from .ci_store import CiLeaseLost
from .common import now_millis, sha256_text


class EvolutionCiSupervisor:
    def __init__(self, manager, store, config):
        self.manager = manager
        self.store = store
        self.config = config
        self.owner = f"ci-worker-{uuid.uuid4().hex}"
        self._stop = threading.Event()
        self._wake = threading.Event()
        self._thread = None
        self._tick_lock = threading.Lock()
        self._indexed = False

    def start(self):
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, name="evolution-ci-observer", daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()
        self._wake.set()
        if self._thread is not None and self._thread is not threading.current_thread():
            self._thread.join(timeout=2)

    def tick(self):
        if not self.config().get("enabled", False):
            return {"status": "disabled", "observations": []}
        if not self._tick_lock.acquire(blocking=False):
            return {"status": "busy", "observations": []}
        try:
            retry_index = getattr(self.manager, "ci_watch_index_needed", None)
            if not self._indexed or (retry_index is not None and retry_index.is_set()):
                if retry_index is not None:
                    retry_index.clear()
                self._indexed = self._index_published()
            results = []
            for data in self.store.claim_due(now_millis(), self.owner):
                if self._stop.is_set() or not self.config().get("enabled", False):
                    self.store.save(data, self.owner, now_millis(), next_poll=0)
                    continue
                try:
                    snapshot = self.manager.github.pull_request_ci_snapshot(data["url"])
                    previous = data.get("snapshot", {})
                    if data.get("repair") and previous.get("head_sha") != snapshot.get("head_sha"):
                        self._cancel_obsolete(data["repair"])
                        data["repair"] = None
                    data.update(snapshot=snapshot, status=snapshot["status"], error="")
                    if snapshot["status"] == "failed":
                        self._repair(data)
                    if snapshot["status"] in {"passed", "closed", "merged"} and data.get("repair"):
                        self._cancel_obsolete(data["repair"])
                    self._save_parent_observation(data)
                    delay = 300_000 if snapshot["status"] == "passed" else 30_000
                    next_poll = -1 if snapshot["status"] in {"closed", "merged"} else now_millis() + delay
                    self.store.save(data, self.owner, now_millis(), next_poll=next_poll)
                    results.append({"task_id": data["task_id"], "status": data["status"]})
                except CiLeaseLost:
                    results.append({"task_id": data["task_id"], "status": "lease_lost"})
                except Exception as exc:
                    from .common import redact_text
                    data["error"] = redact_text(str(exc), maximum=1500)
                    data["status"] = "observation_error"
                    try:
                        self.store.save(data, self.owner, now_millis(), next_poll=now_millis() + 60_000)
                    except CiLeaseLost:
                        pass
                    results.append({"task_id": data["task_id"], "status": "observation_error"})
            return {"status": "observed", "observations": results}
        finally:
            self._tick_lock.release()

    def _repair(self, data):
        snapshot = data["snapshot"]
        if snapshot["head_repository"] != snapshot["repository"]:
            data.update(status="attention_required", error="Automatic repair does not modify fork branches")
            return
        if data.get("repair") is None:
            task_id = "evolve-ci-" + sha256_text(f"{data['task_id']}\0{snapshot['head_sha']}")[:32]
            data["repair"] = {"task_id": task_id, "parent_task_id": data["task_id"],
                              "url": data["url"], "head_sha": snapshot["head_sha"], "head_ref": snapshot["head_ref"]}
        data["status"] = "repairing"
        # Persist the stable child identity before any task creation or external work.
        self.store.save(data, self.owner, now_millis(), next_poll=now_millis() + 30_000, release=False)
        if self._stop.is_set() or not self.config().get("enabled", False):
            return
        task = self.manager.ensure_ci_repair(data["repair"], snapshot)
        if task.status == "proposed":
            task = self.manager.start_ci_repair(task.task_id, self.config())
        if (task.status == "waiting_approval" and not self._stop.is_set()
                and self.config().get("enabled", False) and self.config().get("auto_publish", True)):
            self.store.save(data, self.owner, now_millis(), next_poll=now_millis() + 30_000, release=False)
            task = self.manager.publish(task.task_id, task.approval_hash, base_branch=snapshot["base_ref"])
        if task.status == "published":
            data["status"] = "awaiting_repaired_head"
        elif task.status in {"failed", "blocked", "cancelled", "rolled_back"}:
            data["status"] = "attention_required"
            data["error"] = str(getattr(task, "last_error", ""))

    def _cancel_obsolete(self, repair):
        task = self.manager.store.get(repair["task_id"])
        if task is None:
            return
        metadata = self.manager.v2_store.get_task_metadata(task.task_id)
        if metadata is None or metadata.ci_repair_target != repair:
            return
        if task.status in {"preparing", "running", "validating"}:
            self.manager.cancel(task.task_id)

    def _save_parent_observation(self, data):
        metadata = self.manager.v2_store.get_task_metadata(data["task_id"])
        if metadata is not None:
            metadata.ci = {**data["snapshot"], "watch_status": data["status"],
                           "repair": data.get("repair"), "error": data.get("error", "")}
            self.manager.v2_store.save_task_metadata(metadata)

    def _index_published(self):
        complete = True
        for path in self.manager.store.tasks_root.glob("*.json"):
            if self._stop.is_set() or not self.config().get("enabled", False):
                return False
            try:
                task = self.manager.store.get(path.stem)
                if task and task.status == "published" and task.pull_request_url:
                    metadata = self.manager.v2_store.get_task_metadata(task.task_id)
                    if metadata is None or not metadata.ci_repair_target:
                        self.store.register(task.task_id, task.pull_request_url)
            except Exception as exc:
                complete = False
                self.manager.audit.append("ci_watch_index_error", task_id=path.stem,
                                          payload={"error_type": type(exc).__name__})
        return complete

    def _loop(self):
        while not self._stop.is_set():
            try:
                self.tick()
            except Exception as exc:
                self.manager.audit.append("ci_observer_error", payload={"error_type": type(exc).__name__})
            self._wake.wait(timeout=30)
            self._wake.clear()
