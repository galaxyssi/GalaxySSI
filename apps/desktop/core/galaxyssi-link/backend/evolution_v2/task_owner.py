"""Task operation ownership transferable from an admitting thread to its worker."""
from __future__ import annotations

from contextlib import contextmanager
import hashlib
from pathlib import Path
import re
import threading

from .os_owner import OwnerLocks


class TaskOwners:
    def __init__(self, root: Path):
        self.locks = OwnerLocks(root, re.compile(r"task-v1-[0-9a-f]{64}$"))
        self._held = {}
        self._lock = threading.RLock()

    def claim(self, task_id: str) -> bool:
        if not isinstance(task_id, str) or not task_id:
            raise ValueError("Task identity is required")
        with self._lock:
            if task_id in self._held:
                return False
            key = "task-v1-" + hashlib.sha256(task_id.encode("utf-8")).hexdigest()
            guard = self.locks.hold(key, create=True)
            if not guard.__enter__():
                guard.__exit__(None, None, None)
                return False
            self._held[task_id] = guard
            return True

    def release(self, task_id: str) -> None:
        with self._lock:
            guard = self._held.pop(task_id, None)
            if guard is not None:
                guard.__exit__(None, None, None)

    def locally_owned(self, task_id: str) -> bool:
        with self._lock:
            return task_id in self._held

    @contextmanager
    def hold(self, task_id: str):
        acquired = self.claim(task_id)
        try:
            yield acquired
        finally:
            if acquired:
                self.release(task_id)
