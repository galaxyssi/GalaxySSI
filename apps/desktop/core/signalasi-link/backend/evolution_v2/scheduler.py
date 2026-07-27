"""Conservative scheduler: autonomously research and diagnose, never auto-publish or auto-merge."""
from __future__ import annotations

import threading
import time
from pathlib import Path
from typing import Any

from .common import atomic_write_json, now_millis, read_json

DEFAULT_SCHEDULE = {
    "schema": "signalasi.evolution-scheduler.v2",
    "enabled": True,
    "run_on_start": False,
    "research_interval_hours": 168,
    "diagnostics_interval_hours": 24,
    "create_research_proposals": True,
    "create_diagnostic_proposals": True,
    "auto_create_tasks": False,
    "auto_start_tasks": False,
    "auto_publish": False,
    "auto_merge": False,
}


class EvolutionScheduler:
    def __init__(self, manager, config_path: Path | None = None) -> None:
        self.manager = manager
        configured = config_path or manager.source_root / "config" / "evolution-scheduler.json"
        loaded = read_json(Path(configured), {})
        self.config = {**DEFAULT_SCHEDULE, **(loaded if isinstance(loaded, dict) else {})}
        self.state_path = manager.v2_store.paths["scheduler"] / "state.json"
        self._stop = threading.Event()
        self._wake = threading.Event()
        self._thread: threading.Thread | None = None
        self._lock = threading.RLock()

    def start(self) -> None:
        if not bool(self.config.get("enabled", True)):
            return
        with self._lock:
            if self._thread and self._thread.is_alive():
                return
            self._stop.clear()
            self._thread = threading.Thread(target=self._loop, name="evolution-v2-scheduler", daemon=True)
            self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._wake.set()
        thread = self._thread
        if thread and thread.is_alive():
            thread.join(timeout=5)

    def status(self) -> dict[str, Any]:
        state = read_json(self.state_path, {})
        return {
            "running": bool(self._thread and self._thread.is_alive()),
            "config": self.config,
            "state": state if isinstance(state, dict) else {},
        }

    def run_due(self, *, force: bool = False) -> dict[str, Any]:
        with self._lock:
            state = read_json(self.state_path, {})
            if not isinstance(state, dict):
                state = {}
            now = now_millis()
            first = not state
            run_on_start = bool(self.config.get("run_on_start", False))
            research_due = force or (not first or run_on_start) and now >= int(state.get("next_research_millis") or 0)
            diagnostics_due = force or (not first or run_on_start) and now >= int(state.get("next_diagnostics_millis") or 0)
            result: dict[str, Any] = {"research": None, "diagnostics": None, "errors": []}
            if first and not run_on_start and not force:
                research_due = diagnostics_due = False
            if research_due:
                try:
                    run = self.manager.radar.run(trusted_only=False, limit=40)
                    proposals = self.manager.radar.proposals(run) if self.config.get("create_research_proposals", True) else []
                    result["research"] = {"run_id": run.run_id, "items": len(run.items), "proposals": len(proposals)}
                    state["last_research_millis"] = now
                except Exception as exc:
                    result["errors"].append(f"research: {str(exc)[:1_000]}")
                state["next_research_millis"] = now + int(float(self.config.get("research_interval_hours", 168)) * 3_600_000)
            if diagnostics_due:
                try:
                    signals = self.manager.issue_scanner.scan()
                    proposals = []
                    if self.config.get("create_diagnostic_proposals", True):
                        proposals = [self.manager.issue_scanner.proposal(signal) for signal in signals if signal.status == "open"]
                    result["diagnostics"] = {"signals": len(signals), "proposals": len(proposals)}
                    state["last_diagnostics_millis"] = now
                except Exception as exc:
                    result["errors"].append(f"diagnostics: {str(exc)[:1_000]}")
                state["next_diagnostics_millis"] = now + int(float(self.config.get("diagnostics_interval_hours", 24)) * 3_600_000)
            state.setdefault("next_research_millis", now + int(float(self.config.get("research_interval_hours", 168)) * 3_600_000))
            state.setdefault("next_diagnostics_millis", now + int(float(self.config.get("diagnostics_interval_hours", 24)) * 3_600_000))
            state["last_tick_millis"] = now
            state["last_result"] = result
            atomic_write_json(self.state_path, state)
            return result

    def wake(self) -> None:
        self._wake.set()

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                self.run_due()
            except Exception as exc:
                self.manager.audit.append("scheduler_tick_failed", payload={"error": str(exc)[:2_000]})
            self._wake.wait(timeout=60)
            self._wake.clear()
