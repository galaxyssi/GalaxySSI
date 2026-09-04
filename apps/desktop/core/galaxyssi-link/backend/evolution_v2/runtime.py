"""Lifecycle integration for the Desktop FastAPI backend."""
from __future__ import annotations

import threading
from typing import Any

from .agent_adapters import default_evolution_patch_agent
from .manager import evolution_manager
from .scheduler import EvolutionScheduler


class EvolutionV2Runtime:
    def __init__(self) -> None:
        self.manager = evolution_manager(patch_agent=default_evolution_patch_agent)
        self.scheduler = EvolutionScheduler(self.manager)
        self._started = False
        self._lock = threading.RLock()
        self.recovered_tasks: list[str] = []

    def start(self) -> None:
        with self._lock:
            if self._started:
                return
            self.recovered_tasks = self.manager.recover_interrupted(resume=True)
            self.scheduler.start()
            self.manager.audit.append(
                "runtime_started",
                payload={"recovered_tasks": self.recovered_tasks},
            )
            self._started = True

    def stop(self) -> None:
        with self._lock:
            if not self._started:
                return
            self.scheduler.stop()
            self.manager.audit.append("runtime_stopped")
            self._started = False

    def health(self) -> dict[str, Any]:
        return {
            "protocol": "galaxyssi.self-evolution.v2",
            "started": self._started,
            "source_root": str(self.manager.source_root),
            "recovered_tasks": self.recovered_tasks,
            "scheduler": self.scheduler.status(),
            "audit": self.manager.audit.verify(),
        }


_runtime: EvolutionV2Runtime | None = None
_runtime_lock = threading.Lock()


def evolution_v2_runtime() -> EvolutionV2Runtime:
    global _runtime
    with _runtime_lock:
        if _runtime is None:
            _runtime = EvolutionV2Runtime()
        return _runtime
