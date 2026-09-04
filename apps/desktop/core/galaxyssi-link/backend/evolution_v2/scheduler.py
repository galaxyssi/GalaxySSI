"""Persistent self-evolution scheduler with bounded serial or parallel execution."""
from __future__ import annotations

import threading
from pathlib import Path
from typing import Any

from .common import atomic_write_json, now_millis, read_json

DAY_MILLIS = 24 * 60 * 60 * 1_000
MIN_EVOLUTIONS_PER_DAY = 1
MAX_EVOLUTIONS_PER_DAY = 96
MAX_PARALLEL_EVOLUTIONS = 4
TERMINAL_TASK_STATUSES = {
    "published",
    "completed",
    "failed",
    "blocked",
    "cancelled",
    "rolled_back",
}

DEFAULT_SCHEDULE = {
    "schema": "galaxyssi.evolution-scheduler.v2",
    "enabled": False,
    "run_on_start": False,
    "evolutions_per_day": 1,
    "execution_mode": "serial",
    "max_parallel_evolutions": 2,
    "research_interval_hours": 168,
    "diagnostics_interval_hours": 24,
    "create_research_proposals": True,
    "create_diagnostic_proposals": True,
    "auto_create_tasks": True,
    "auto_start_tasks": True,
    "auto_publish": True,
    "auto_merge": False,
}

USER_CONFIG_KEYS = {
    "enabled",
    "evolutions_per_day",
    "execution_mode",
    "max_parallel_evolutions",
}


def _bounded_int(value: Any, fallback: int, minimum: int, maximum: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = fallback
    return max(minimum, min(maximum, parsed))


def _normalized_config(value: dict[str, Any]) -> dict[str, Any]:
    config = {**DEFAULT_SCHEDULE, **value}
    config["schema"] = DEFAULT_SCHEDULE["schema"]
    config["enabled"] = bool(config.get("enabled", False))
    config["run_on_start"] = bool(config.get("run_on_start", False))
    config["evolutions_per_day"] = _bounded_int(
        config.get("evolutions_per_day"),
        int(DEFAULT_SCHEDULE["evolutions_per_day"]),
        MIN_EVOLUTIONS_PER_DAY,
        MAX_EVOLUTIONS_PER_DAY,
    )
    mode = str(config.get("execution_mode") or "serial").strip().casefold()
    config["execution_mode"] = mode if mode in {"serial", "parallel"} else "serial"
    config["max_parallel_evolutions"] = _bounded_int(
        config.get("max_parallel_evolutions"),
        int(DEFAULT_SCHEDULE["max_parallel_evolutions"]),
        2,
        MAX_PARALLEL_EVOLUTIONS,
    )
    config["research_interval_hours"] = max(
        1.0,
        min(24 * 365.0, float(config.get("research_interval_hours") or 168)),
    )
    config["diagnostics_interval_hours"] = max(
        1.0,
        min(24 * 365.0, float(config.get("diagnostics_interval_hours") or 24)),
    )
    for key in (
        "create_research_proposals",
        "create_diagnostic_proposals",
        "auto_create_tasks",
        "auto_start_tasks",
        "auto_publish",
    ):
        config[key] = bool(config.get(key, DEFAULT_SCHEDULE[key]))
    config["auto_merge"] = False
    return config


class EvolutionScheduler:
    def __init__(self, manager, config_path: Path | None = None) -> None:
        self.manager = manager
        configured = config_path or manager.source_root / "config" / "evolution-scheduler.json"
        shipped = read_json(Path(configured), {})
        scheduler_root = manager.v2_store.paths["scheduler"]
        self.settings_path = scheduler_root / "settings.json"
        persisted = read_json(self.settings_path, {})
        self.config = _normalized_config({
            **(shipped if isinstance(shipped, dict) else {}),
            **(persisted if isinstance(persisted, dict) else {}),
        })
        self.state_path = scheduler_root / "state.json"
        self._stop = threading.Event()
        self._wake = threading.Event()
        self._thread: threading.Thread | None = None
        self._lock = threading.RLock()

    def start(self) -> None:
        if not bool(self.config.get("enabled", False)):
            return
        with self._lock:
            if self._thread and self._thread.is_alive():
                return
            self._stop.clear()
            self._thread = threading.Thread(
                target=self._loop,
                name="evolution-v2-scheduler",
                daemon=True,
            )
            self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._wake.set()
        thread = self._thread
        if thread and thread.is_alive() and thread is not threading.current_thread():
            thread.join(timeout=5)

    def update_config(self, updates: dict[str, Any]) -> dict[str, Any]:
        clean_updates = {
            key: value
            for key, value in dict(updates or {}).items()
            if key in USER_CONFIG_KEYS
        }
        with self._lock:
            previous = dict(self.config)
            self.config = _normalized_config({**self.config, **clean_updates})
            persisted = {
                "schema": self.config["schema"],
                **{key: self.config[key] for key in sorted(USER_CONFIG_KEYS)},
            }
            atomic_write_json(self.settings_path, persisted)
            state = self._state()
            if (
                previous.get("enabled") != self.config["enabled"]
                or previous.get("evolutions_per_day") != self.config["evolutions_per_day"]
            ):
                state["next_evolution_millis"] = (
                    now_millis() + self._evolution_interval_millis()
                    if self.config["enabled"]
                    else 0
                )
                state["pending_evolution"] = False
            state["last_config_update_millis"] = now_millis()
            self._save_state(state)
        if self.config["enabled"]:
            self.start()
            self.wake()
        else:
            self.stop()
        self.manager.audit.append(
            "scheduler_config_updated",
            payload={
                "enabled": self.config["enabled"],
                "evolutions_per_day": self.config["evolutions_per_day"],
                "execution_mode": self.config["execution_mode"],
                "max_parallel_evolutions": self.config["max_parallel_evolutions"],
            },
        )
        return self.status()

    def status(self) -> dict[str, Any]:
        state = self._state()
        active = list(state.get("active_evolutions") or [])
        enabled = bool(self.config.get("enabled", False))
        return {
            "running": bool(enabled and self._thread and self._thread.is_alive()),
            "config": dict(self.config),
            "state": state,
            "computed": {
                "interval_millis": self._evolution_interval_millis(),
                "active_count": len(active),
                "pending": bool(state.get("pending_evolution", False)),
                "next_evolution_millis": int(state.get("next_evolution_millis") or 0),
            },
        }

    def run_due(
        self,
        *,
        force: bool = False,
        evolution_only: bool = False,
    ) -> dict[str, Any]:
        with self._lock:
            state = self._state()
            now = now_millis()
            result: dict[str, Any] = {
                "research": None,
                "diagnostics": None,
                "evolution": {"status": "not_due"},
                "published": [],
                "errors": [],
            }
            self._reconcile_active(state, result, now, allow_publish=bool(self.config["enabled"]))
            self._initialize_schedule(state, now)
            if not bool(self.config["enabled"]):
                result["evolution"] = {"status": "disabled"}
                state["last_tick_millis"] = now
                state["last_result"] = result
                self._save_state(state)
                return result

            first = not int(state.get("last_tick_millis") or 0)
            run_on_start = bool(self.config.get("run_on_start", False))
            research_due = not evolution_only and (
                force
                or (
                    (not first or run_on_start)
                    and now >= int(state.get("next_research_millis") or 0)
                )
            )
            diagnostics_due = not evolution_only and (
                force
                or (
                    (not first or run_on_start)
                    and now >= int(state.get("next_diagnostics_millis") or 0)
                )
            )
            if research_due:
                self._run_research(state, result, now)
            if diagnostics_due:
                self._run_diagnostics(state, result, now)

            next_evolution = int(state.get("next_evolution_millis") or 0)
            evolution_due = (
                force
                or evolution_only
                or bool(state.get("pending_evolution", False))
                or now >= next_evolution
            )
            if evolution_due:
                capacity = self._available_capacity(state)
                if capacity <= 0:
                    state["pending_evolution"] = True
                    result["evolution"] = {
                        "status": "deferred",
                        "reason": "previous_evolution_active",
                        "active_count": len(state.get("active_evolutions") or []),
                    }
                else:
                    proposal = self._next_proposal()
                    if proposal is None and result["diagnostics"] is None:
                        self._run_diagnostics(state, result, now)
                        proposal = self._next_proposal()
                    if proposal is None and result["research"] is None:
                        self._run_research(state, result, now)
                        proposal = self._next_proposal()
                    if proposal is None:
                        state["pending_evolution"] = False
                        state["next_evolution_millis"] = now + self._evolution_interval_millis()
                        result["evolution"] = {
                            "status": "idle",
                            "reason": "no_actionable_proposal",
                        }
                    else:
                        self._start_evolution(state, result, proposal, now, next_evolution)

            state["last_tick_millis"] = now
            state["last_result"] = result
            self._save_state(state)
            return result

    def wake(self) -> None:
        self._wake.set()

    def _state(self) -> dict[str, Any]:
        loaded = read_json(self.state_path, {})
        state = dict(loaded) if isinstance(loaded, dict) else {}
        state["active_evolutions"] = [
            dict(value)
            for value in state.get("active_evolutions") or []
            if isinstance(value, dict) and value.get("task_id")
        ][-MAX_PARALLEL_EVOLUTIONS:]
        state["history"] = [
            dict(value)
            for value in state.get("history") or []
            if isinstance(value, dict)
        ][:100]
        return state

    def _save_state(self, state: dict[str, Any]) -> None:
        atomic_write_json(self.state_path, state)

    def _initialize_schedule(self, state: dict[str, Any], now: int) -> None:
        state.setdefault(
            "next_research_millis",
            now + int(float(self.config["research_interval_hours"]) * 3_600_000),
        )
        state.setdefault(
            "next_diagnostics_millis",
            now + int(float(self.config["diagnostics_interval_hours"]) * 3_600_000),
        )
        if not int(state.get("next_evolution_millis") or 0):
            state["next_evolution_millis"] = now + self._evolution_interval_millis()
        state.setdefault("pending_evolution", False)
        state.setdefault("active_evolutions", [])
        state.setdefault("history", [])

    def _run_research(self, state: dict[str, Any], result: dict[str, Any], now: int) -> None:
        try:
            run = self.manager.radar.run(trusted_only=False, limit=40)
            proposals = (
                self.manager.radar.proposals(run)
                if self.config.get("create_research_proposals", True)
                else []
            )
            result["research"] = {
                "run_id": run.run_id,
                "items": len(run.items),
                "proposals": len(proposals),
            }
            state["last_research_millis"] = now
        except Exception as exc:
            result["errors"].append(f"research: {str(exc)[:1_000]}")
            result["research"] = {"status": "failed"}
        state["next_research_millis"] = (
            now + int(float(self.config["research_interval_hours"]) * 3_600_000)
        )

    def _run_diagnostics(self, state: dict[str, Any], result: dict[str, Any], now: int) -> None:
        try:
            signals = self.manager.issue_scanner.scan()
            proposals = []
            if self.config.get("create_diagnostic_proposals", True):
                proposals = [
                    self.manager.issue_scanner.proposal(signal)
                    for signal in signals
                    if signal.status == "open"
                ]
            result["diagnostics"] = {
                "signals": len(signals),
                "proposals": len(proposals),
            }
            state["last_diagnostics_millis"] = now
        except Exception as exc:
            result["errors"].append(f"diagnostics: {str(exc)[:1_000]}")
            result["diagnostics"] = {"status": "failed"}
        state["next_diagnostics_millis"] = (
            now + int(float(self.config["diagnostics_interval_hours"]) * 3_600_000)
        )

    def _next_proposal(self):
        proposals = self.manager.v2_store.list_proposals(500)
        consumed = {
            self._proposal_key(proposal)
            for proposal in proposals
            if proposal.status != "proposed" or proposal.task_id
        }
        risk_order = {"low": 0, "medium": 1, "high": 2, "critical": 3}
        origin_order = {"diagnostics": 0, "roadmap": 1, "research": 2}
        eligible = sorted(
            (
                proposal
                for proposal in proposals
                if proposal.status == "proposed" and not proposal.task_id
            ),
            key=lambda proposal: (
                origin_order.get(proposal.origin, 3),
                risk_order.get(proposal.risk_level, 4),
                proposal.created_at_millis,
            ),
        )
        for proposal in eligible:
            if self._proposal_key(proposal) in consumed:
                proposal.status = "superseded"
                proposal.updated_at_millis = now_millis()
                self.manager.v2_store.save_proposal(proposal)
                continue
            return proposal
        return None

    @staticmethod
    def _proposal_key(proposal) -> tuple[str, tuple[str, ...]]:
        return (
            " ".join(str(proposal.problem or proposal.title).casefold().split()),
            tuple(sorted(str(value).casefold() for value in proposal.scope)),
        )

    def _start_evolution(
        self,
        state: dict[str, Any],
        result: dict[str, Any],
        proposal,
        now: int,
        scheduled_for: int,
    ) -> None:
        try:
            task = self.manager.create_from_proposal(
                proposal,
                agent_id="auto",
                max_attempts=5,
                start=bool(self.config.get("auto_start_tasks", True)),
            )
            record = {
                "task_id": task.task_id,
                "proposal_id": proposal.proposal_id,
                "title": proposal.title,
                "scheduled_for_millis": scheduled_for or now,
                "started_at_millis": now,
                "status": task.status,
                "publish_attempts": 0,
                "next_publish_retry_millis": 0,
            }
            active = list(state.get("active_evolutions") or [])
            active.append(record)
            state["active_evolutions"] = active[-MAX_PARALLEL_EVOLUTIONS:]
            state["pending_evolution"] = False
            state["last_evolution_started_millis"] = now
            state["next_evolution_millis"] = now + self._evolution_interval_millis()
            result["evolution"] = {
                "status": "started",
                "task_id": task.task_id,
                "proposal_id": proposal.proposal_id,
                "title": proposal.title,
            }
            self.manager.audit.append(
                "scheduled_evolution_started",
                task_id=task.task_id,
                payload={
                    "proposal_id": proposal.proposal_id,
                    "execution_mode": self.config["execution_mode"],
                    "scheduled_for_millis": scheduled_for or now,
                },
            )
        except Exception as exc:
            state["pending_evolution"] = False
            state["next_evolution_millis"] = now + self._evolution_interval_millis()
            result["evolution"] = {"status": "failed_to_start"}
            result["errors"].append(f"evolution: {str(exc)[:1_000]}")

    def _available_capacity(self, state: dict[str, Any]) -> int:
        active_count = len(state.get("active_evolutions") or [])
        if self.config["execution_mode"] == "serial":
            return 1 if active_count == 0 else 0
        return max(0, int(self.config["max_parallel_evolutions"]) - active_count)

    def _reconcile_active(
        self,
        state: dict[str, Any],
        result: dict[str, Any],
        now: int,
        *,
        allow_publish: bool,
    ) -> None:
        active: list[dict[str, Any]] = []
        history = list(state.get("history") or [])
        for source in state.get("active_evolutions") or []:
            record = dict(source)
            task_id = str(record.get("task_id") or "")
            try:
                task = self.manager.require(task_id)
            except Exception as exc:
                record.update({
                    "status": "missing",
                    "completed_at_millis": now,
                    "last_error": str(exc)[:500],
                })
                history.insert(0, record)
                continue

            if (
                task.status == "waiting_approval"
                and allow_publish
                and bool(self.config.get("auto_publish", True))
                and now >= int(record.get("next_publish_retry_millis") or 0)
            ):
                try:
                    task = self.manager.publish(
                        task.task_id,
                        task.approval_hash,
                        base_branch="main",
                    )
                    result["published"].append({
                        "task_id": task.task_id,
                        "pull_request_url": task.pull_request_url,
                    })
                except Exception as exc:
                    attempts = int(record.get("publish_attempts") or 0) + 1
                    record["publish_attempts"] = attempts
                    record["next_publish_retry_millis"] = (
                        now + min(60 * 60_000, 5 * 60_000 * (2 ** min(attempts - 1, 4)))
                    )
                    record["last_error"] = str(exc)[:1_000]
                    result["errors"].append(f"publish {task_id}: {str(exc)[:1_000]}")
                    task = self.manager.require(task_id)

            record["status"] = task.status
            record["pull_request_url"] = task.pull_request_url
            if task.status in TERMINAL_TASK_STATUSES:
                record["completed_at_millis"] = now
                history.insert(0, record)
                self.manager.audit.append(
                    "scheduled_evolution_completed",
                    task_id=task.task_id,
                    payload={
                        "status": task.status,
                        "pull_request_url": task.pull_request_url,
                    },
                )
            else:
                active.append(record)
        state["active_evolutions"] = active[-MAX_PARALLEL_EVOLUTIONS:]
        state["history"] = history[:100]

    def _evolution_interval_millis(self) -> int:
        return max(
            15 * 60_000,
            int(DAY_MILLIS / int(self.config["evolutions_per_day"])),
        )

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                self.run_due()
            except Exception as exc:
                self.manager.audit.append(
                    "scheduler_tick_failed",
                    payload={"error": str(exc)[:2_000]},
                )
            self._wake.wait(timeout=30)
            self._wake.clear()
