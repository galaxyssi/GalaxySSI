"""Persistent scheduling control plane for desktop Agent adapters.

The runtime server owns Run and Session lifecycle, capacity, cancellation,
idempotency, and recovery. Agent-specific process management remains behind
``DesktopAgentProvider`` so independently installed Agents can evolve without
changing the runtime protocol.
"""
from __future__ import annotations

import hashlib
import json
import os
import threading
import time
from concurrent.futures import Future, ThreadPoolExecutor
from pathlib import Path
from typing import Callable

from desktop_agent_adapters import (
    AgentAdapterConflict,
    AgentAdapterExecutionError,
    AgentAdapterRequest,
    AgentAdapterResult,
    AgentDeliveryMode,
    AgentInvocationMode,
    AgentRunPriority,
    DesktopAgentProvider,
)
from agent_run_kernel import AgentRunEventLedger, runtime_projection_event
from agent_run_storage import RUN_KERNEL_DATABASE_NAME
from desktop_agent_runtime_journal import restore_checkpoint_rows, runtime_checkpoint


RUNTIME_PROTOCOL = "galaxyssi.agent-runtime/1.0"
RUNTIME_STATE_VERSION = 4
DEFAULT_MAX_WORKERS = 4
DEFAULT_MAX_QUEUED_RUNS = 64
DEFAULT_AGENT_FAILURE_THRESHOLD = 3
DEFAULT_AGENT_FAILURE_COOLDOWN_SECONDS = 30.0
MAX_RUNTIME_RUNS = 2_000
MAX_RUNTIME_SESSIONS = 500
MAX_RUNTIME_EVENTS = 96
ACTIVE_STATES = frozenset({"queued", "running"})
TERMINAL_STATES = frozenset({
    "completed",
    "failed",
    "cancelled",
    "observed",
    "ignored",
    "interrupted",
})
SESSION_STATES = frozenset({"active", "idle"})


class DesktopAgentRuntimeError(RuntimeError):
    pass


class DesktopAgentRuntimeConflict(DesktopAgentRuntimeError):
    pass


class DesktopAgentFaultIsolated(DesktopAgentRuntimeError):
    pass


class DesktopAgentCapacityExhausted(DesktopAgentRuntimeError):
    pass


class AgentCapacityController:
    """Bounded global admission state for queued and active Agent Runs."""

    def __init__(
        self,
        *,
        max_active: int,
        max_queued: int = DEFAULT_MAX_QUEUED_RUNS,
        max_background_active: int = 1,
        max_background_queued: int | None = None,
    ) -> None:
        self.max_active = max(1, min(int(max_active or 1), 32))
        self.max_queued = max(0, min(int(max_queued or 0), 10_000))
        self.max_background_active = max(
            1,
            min(int(max_background_active or 1), 4),
        )
        self.max_background_queued = max(
            0,
            min(
                int(
                    max_background_queued
                    if max_background_queued is not None
                    else min(self.max_queued, 16)
                ),
                1_000,
            ),
        )
        self._lock = threading.RLock()
        self._runs: dict[str, dict[str, str | int]] = {}
        self._rejected_runs = 0

    def reserve(
        self,
        run_id: str,
        agent_id: str,
        priority: str | AgentRunPriority = AgentRunPriority.FOREGROUND,
    ) -> None:
        run = str(run_id or "").strip()
        agent = str(agent_id or "").strip()
        normalized_priority = AgentRunPriority.parse(priority)
        if not run or not agent:
            raise DesktopAgentRuntimeError("Agent capacity reservation requires Run and Agent ids")
        with self._lock:
            if run in self._runs:
                return
            is_background = normalized_priority == AgentRunPriority.BACKGROUND
            matching = [
                item
                for item in self._runs.values()
                if (
                    str(item.get("priority") or AgentRunPriority.FOREGROUND.value)
                    == AgentRunPriority.BACKGROUND.value
                ) == is_background
            ]
            queued = sum(1 for item in matching if item["state"] == "queued")
            active = sum(1 for item in matching if item["state"] == "active")
            maximum = (
                self.max_background_active + self.max_background_queued
                if is_background
                else self.max_active + self.max_queued
            )
            if active + queued >= maximum:
                self._rejected_runs += 1
                raise DesktopAgentCapacityExhausted(
                    (
                        "Desktop background Agent queue is full"
                        if is_background
                        else "Desktop Agent Runtime is busy; its bounded foreground queue is full"
                    )
                )
            self._runs[run] = {
                "agent_id": agent,
                "state": "queued",
                "priority": normalized_priority.value,
                "reserved_at": int(time.time() * 1_000),
                "started_at": 0,
            }

    def start(self, run_id: str) -> None:
        with self._lock:
            row = self._runs.get(str(run_id or "").strip())
            if row is None:
                raise DesktopAgentRuntimeError(
                    f"Agent capacity reservation is missing for Run {run_id}"
                )
            row["state"] = "active"
            row["started_at"] = int(time.time() * 1_000)

    def release(self, run_id: str) -> None:
        with self._lock:
            self._runs.pop(str(run_id or "").strip(), None)

    def snapshot(self) -> dict:
        with self._lock:
            queued = [row for row in self._runs.values() if row["state"] == "queued"]
            active = [row for row in self._runs.values() if row["state"] == "active"]
            foreground = [
                row
                for row in self._runs.values()
                if str(row.get("priority") or AgentRunPriority.FOREGROUND.value)
                != AgentRunPriority.BACKGROUND.value
            ]
            background = [
                row
                for row in self._runs.values()
                if str(row.get("priority") or AgentRunPriority.FOREGROUND.value)
                == AgentRunPriority.BACKGROUND.value
            ]
            agent_ids = sorted({
                str(row.get("agent_id") or "")
                for row in self._runs.values()
                if str(row.get("agent_id") or "")
            })
            by_agent = [
                {
                    "agent_id": agent_id,
                    "active_runs": sum(
                        1
                        for row in active
                        if str(row.get("agent_id") or "") == agent_id
                    ),
                    "queued_runs": sum(
                        1
                        for row in queued
                        if str(row.get("agent_id") or "") == agent_id
                    ),
                }
                for agent_id in agent_ids
            ]
            return {
                "max_active": self.max_active,
                "max_queued": self.max_queued,
                "max_background_active": self.max_background_active,
                "max_background_queued": self.max_background_queued,
                "active_runs": len(active),
                "queued_runs": len(queued),
                "foreground_active_runs": sum(
                    1 for row in foreground if row["state"] == "active"
                ),
                "foreground_queued_runs": sum(
                    1 for row in foreground if row["state"] == "queued"
                ),
                "background_active_runs": sum(
                    1 for row in background if row["state"] == "active"
                ),
                "background_queued_runs": sum(
                    1 for row in background if row["state"] == "queued"
                ),
                "available_active_slots": max(
                    0,
                    self.max_active
                    - sum(1 for row in foreground if row["state"] == "active"),
                ),
                "available_queue_slots": max(
                    0,
                    self.max_queued
                    - sum(1 for row in foreground if row["state"] == "queued"),
                ),
                "rejected_runs": self._rejected_runs,
                "by_agent": by_agent,
            }


class AgentFaultDomainRegistry:
    """Independent circuit state for each Agent adapter."""

    def __init__(
        self,
        *,
        failure_threshold: int = DEFAULT_AGENT_FAILURE_THRESHOLD,
        cooldown_seconds: float = DEFAULT_AGENT_FAILURE_COOLDOWN_SECONDS,
        now: Callable[[], float] = time.time,
    ) -> None:
        self.failure_threshold = max(1, min(int(failure_threshold or 1), 100))
        self.cooldown_seconds = max(0.1, float(cooldown_seconds or 0.1))
        self._now = now
        self._lock = threading.RLock()
        self._domains: dict[str, dict] = {}

    def acquire(self, agent_id: str) -> None:
        agent = str(agent_id or "").strip()
        if not agent:
            raise DesktopAgentRuntimeError("Agent fault domain requires an Agent id")
        with self._lock:
            domain = self._domain_locked(agent)
            now = self._now()
            open_until = float(domain.get("open_until") or 0.0)
            if open_until > now:
                remaining = max(1, int(round(open_until - now)))
                raise DesktopAgentFaultIsolated(
                    f"{agent} is temporarily isolated after repeated failures; retry in {remaining}s"
                )
            if open_until and bool(domain.get("probe_active")):
                raise DesktopAgentFaultIsolated(
                    f"{agent} recovery probe is already running"
                )
            if open_until:
                domain["probe_active"] = True
            domain["active_runs"] = int(domain.get("active_runs") or 0) + 1
            domain["last_started_at"] = self._now_ms()

    def succeed(self, agent_id: str) -> None:
        with self._lock:
            domain = self._domain_locked(agent_id)
            self._release_locked(domain)
            domain["status"] = "healthy"
            domain["consecutive_failures"] = 0
            domain["open_until"] = 0.0
            domain["probe_active"] = False
            domain["successful_runs"] = int(domain.get("successful_runs") or 0) + 1
            domain["last_error"] = ""
            domain["last_success_at"] = self._now_ms()

    def fail(self, agent_id: str, error: str) -> None:
        with self._lock:
            domain = self._domain_locked(agent_id)
            self._release_locked(domain)
            failures = int(domain.get("consecutive_failures") or 0) + 1
            domain["consecutive_failures"] = failures
            domain["failed_runs"] = int(domain.get("failed_runs") or 0) + 1
            domain["last_error"] = str(error or "Agent execution failed")[:500]
            domain["last_failure_at"] = self._now_ms()
            domain["probe_active"] = False
            if failures >= self.failure_threshold:
                domain["status"] = "isolated"
                domain["open_until"] = self._now() + self.cooldown_seconds
            else:
                domain["status"] = "degraded"

    def release(self, agent_id: str) -> None:
        with self._lock:
            domain = self._domain_locked(agent_id)
            self._release_locked(domain)
            domain["probe_active"] = False

    def snapshots(self, agent_ids: list[str] | tuple[str, ...] = ()) -> list[dict]:
        with self._lock:
            for agent_id in agent_ids:
                self._domain_locked(agent_id)
            now = self._now()
            rows = [
                self._public_locked(agent_id, domain, now)
                for agent_id, domain in self._domains.items()
            ]
        return sorted(rows, key=lambda row: row["agent_id"])

    def _domain_locked(self, agent_id: str) -> dict:
        agent = str(agent_id or "").strip()
        return self._domains.setdefault(
            agent,
            {
                "status": "healthy",
                "active_runs": 0,
                "successful_runs": 0,
                "failed_runs": 0,
                "consecutive_failures": 0,
                "open_until": 0.0,
                "probe_active": False,
                "last_started_at": 0,
                "last_success_at": 0,
                "last_failure_at": 0,
                "last_error": "",
            },
        )

    @staticmethod
    def _release_locked(domain: dict) -> None:
        domain["active_runs"] = max(0, int(domain.get("active_runs") or 0) - 1)

    def _public_locked(self, agent_id: str, domain: dict, now: float) -> dict:
        open_until = float(domain.get("open_until") or 0.0)
        status = str(domain.get("status") or "healthy")
        if status == "isolated" and open_until <= now:
            status = "recovering"
        return {
            "agent_id": agent_id,
            "status": status,
            "active_runs": max(0, int(domain.get("active_runs") or 0)),
            "successful_runs": max(0, int(domain.get("successful_runs") or 0)),
            "failed_runs": max(0, int(domain.get("failed_runs") or 0)),
            "consecutive_failures": max(
                0,
                int(domain.get("consecutive_failures") or 0),
            ),
            "retry_after_millis": (
                max(0, int((open_until - now) * 1_000))
                if open_until > now
                else 0
            ),
            "last_started_at": max(0, int(domain.get("last_started_at") or 0)),
            "last_success_at": max(0, int(domain.get("last_success_at") or 0)),
            "last_failure_at": max(0, int(domain.get("last_failure_at") or 0)),
            "last_error": str(domain.get("last_error") or ""),
        }

    def _now_ms(self) -> int:
        return int(self._now() * 1_000)


class DesktopAgentRuntimeStore:
    """Runtime projection backed by the portable append-only Run ledger."""

    def __init__(
        self,
        path: Path,
        now: Callable[[], float] = time.time,
        event_ledger: AgentRunEventLedger | None = None,
    ) -> None:
        self.path = Path(path)
        self._checkpoint_kind = f"desktop-runtime:{self.path.name}"
        self._now = now
        self._lock = threading.RLock()
        self._event_ledger = event_ledger or AgentRunEventLedger(
            self.path.with_name(RUN_KERNEL_DATABASE_NAME),
            now=now,
        )
        self._state = self._load()
        self._reconcile_event_ledger_locked()
        self._recover_interrupted_locked()

    def claim(self, request: AgentAdapterRequest) -> tuple[dict, bool]:
        fingerprint = self._fingerprint(request)
        route_id = str(request.checkpoint.get("client_route_id") or "").strip()
        turn_id = str(request.checkpoint.get("turn_id") or "").strip()
        session_id = self._session_id(request.agent_id, route_id, request.conversation_id)
        now_ms = self._now_ms()
        with self._lock:
            existing = self._find_by_idempotency_locked(request.idempotency_key)
            if existing is not None:
                if str(existing.get("fingerprint") or "") != fingerprint:
                    raise DesktopAgentRuntimeConflict(
                        f"Idempotency key {request.idempotency_key} was already used for a different request"
                    )
                return self._public_run(existing, replayed=True), False

            existing_run = self._state["runs"].get(request.run_id)
            if isinstance(existing_run, dict):
                raise DesktopAgentRuntimeConflict(
                    f"Run ID {request.run_id} was already claimed by another request"
                )

            session = self._state["sessions"].get(session_id)
            session_created = not isinstance(session, dict)
            row = {
                "run_id": request.run_id,
                "idempotency_key": request.idempotency_key,
                "fingerprint": fingerprint,
                "session_id": session_id,
                "agent_id": request.agent_id,
                "delivery_mode": request.delivery_mode.value,
                "invocation_mode": request.invocation_mode.value,
                "caller_agent_id": request.caller_agent_id,
                "parent_run_id": request.parent_run_id,
                "handoff_chain": list(request.handoff_chain),
                "client_route_id": route_id,
                "conversation_id": request.conversation_id,
                "task_id": str(request.checkpoint.get("task_id") or request.run_id).strip(),
                "goal_id": str(
                    request.checkpoint.get("goal_id")
                    or request.checkpoint.get("task_id")
                    or request.run_id
                ).strip(),
                "turn_id": turn_id,
                "device_id": str(
                    request.checkpoint.get("device_id") or "desktop"
                ).strip(),
                "source_message_id": request.source_message_id,
                "priority": request.priority.value,
                "session_created": session_created,
                "state": "queued",
                "created_at": now_ms,
                "queued_at": now_ms,
                "started_at": 0,
                "finished_at": 0,
                "updated_at": now_ms,
                "cursor": 0,
                "error": "",
                "adapter_result": None,
                "events": [],
            }
            self._append_event_locked(row, "run_queued", now_ms)
            if not isinstance(session, dict):
                session = {
                    "session_id": session_id,
                    "agent_id": request.agent_id,
                    "client_route_id": route_id,
                    "conversation_id": request.conversation_id,
                    "created_at": now_ms,
                    "updated_at": now_ms,
                    "run_count": 0,
                    "last_run_id": "",
                    "last_task_id": "",
                    "last_turn_id": "",
                    "last_state": "",
                    "state": "idle",
                    "active_run_count": 0,
                    "completed_run_count": 0,
                    "failed_run_count": 0,
                    "cancelled_run_count": 0,
                }
                self._state["sessions"][session_id] = session
            session["updated_at"] = now_ms
            session["run_count"] = int(session.get("run_count") or 0) + 1
            session["last_run_id"] = request.run_id
            self._state["runs"][request.run_id] = row
            self._sync_session_locked(session_id)
            self._prune_locked()
            self._save_locked()
            return self._public_run(row), True

    def will_create_session(self, request: AgentAdapterRequest) -> bool:
        route_id = str(request.checkpoint.get("client_route_id") or "").strip()
        session_id = self._session_id(
            request.agent_id,
            route_id,
            request.conversation_id,
        )
        with self._lock:
            return not isinstance(self._state["sessions"].get(session_id), dict)

    def transition_running(self, run_id: str) -> dict:
        now_ms = self._now_ms()
        with self._lock:
            row = self._required_run_locked(run_id)
            if str(row.get("state") or "") != "queued":
                return self._public_run(row)
            self._append_event_locked(row, "run_started", now_ms)
            row["state"] = "running"
            row["started_at"] = now_ms
            self._sync_session_locked(str(row.get("session_id") or ""))
            self._save_locked()
            return self._public_run(row)

    def finish(self, run_id: str, result: AgentAdapterResult) -> dict:
        now_ms = self._now_ms()
        with self._lock:
            row = self._required_run_locked(run_id)
            if str(row.get("state") or "") in TERMINAL_STATES:
                return self._public_run(row)
            self._append_event_locked(row, f"run_{result.state}", now_ms, {
                "error": result.error, "adapter_result": result.public(),
            })
            row["state"] = result.state
            row["error"] = result.error
            row["adapter_result"] = result.public()
            row["finished_at"] = now_ms
            self._sync_session_locked(str(row.get("session_id") or ""))
            self._save_locked()
            return self._public_run(row)

    def fail(self, run_id: str, error: str) -> dict:
        now_ms = self._now_ms()
        with self._lock:
            row = self._required_run_locked(run_id)
            if str(row.get("state") or "") in TERMINAL_STATES:
                return self._public_run(row)
            self._append_event_locked(row, "run_failed", now_ms, {
                "error": str(error or "Agent runtime execution failed")[:2_000],
            })
            row["state"] = "failed"
            row["error"] = str(error or "Agent runtime execution failed")[:2_000]
            row["finished_at"] = now_ms
            self._sync_session_locked(str(row.get("session_id") or ""))
            self._save_locked()
            return self._public_run(row)

    def cancel(self, run_id: str) -> dict | None:
        now_ms = self._now_ms()
        with self._lock:
            row = self._state["runs"].get(run_id)
            if not isinstance(row, dict):
                return None
            if str(row.get("state") or "") not in TERMINAL_STATES:
                self._append_event_locked(row, "run_cancelled", now_ms)
                row["state"] = "cancelled"
                row["finished_at"] = now_ms
                self._sync_session_locked(str(row.get("session_id") or ""))
                self._save_locked()
            return self._public_run(row)

    def status(self, run_id: str) -> dict | None:
        with self._lock:
            row = self._state["runs"].get(run_id)
            return self._public_run(row) if isinstance(row, dict) else None

    def events(self, run_id: str, after_cursor: int = 0) -> list[dict]:
        with self._lock:
            row = self._state["runs"].get(run_id)
            if not isinstance(row, dict):
                return []
            return [
                dict(item)
                for item in row.get("events", [])
                if int(item.get("cursor") or 0) > int(after_cursor or 0)
            ]

    def kernel_events(
        self,
        run_id: str,
        after_sequence: int = 0,
        limit: int = 1_000,
    ) -> list[dict]:
        return [
            event.public()
            for event in self._event_ledger.events(
                run_id,
                after_sequence=max(0, int(after_sequence or 0)),
                limit=max(1, int(limit or 1)),
            )
        ]

    def kernel_snapshot(self, run_id: str) -> dict | None:
        return self._event_ledger.snapshot(run_id)

    def runs(
        self,
        *,
        state: str = "",
        agent_id: str = "",
        session_id: str = "",
        invocation_mode: str = "",
        caller_agent_id: str = "",
        parent_run_id: str = "",
        limit: int = 100,
    ) -> list[dict]:
        normalized_invocation_mode = str(invocation_mode or "").strip().lower()
        if normalized_invocation_mode:
            AgentInvocationMode.parse(normalized_invocation_mode)
        with self._lock:
            rows = [
                row
                for row in self._state["runs"].values()
                if (not state or str(row.get("state") or "") == state)
                and (not agent_id or str(row.get("agent_id") or "") == agent_id)
                and (not session_id or str(row.get("session_id") or "") == session_id)
                and (
                    not normalized_invocation_mode
                    or str(row.get("invocation_mode") or "direct")
                    == normalized_invocation_mode
                )
                and (
                    not caller_agent_id
                    or str(row.get("caller_agent_id") or "") == caller_agent_id
                )
                and (
                    not parent_run_id
                    or str(row.get("parent_run_id") or "") == parent_run_id
                )
            ]
            rows.sort(key=lambda row: int(row.get("created_at") or 0), reverse=True)
            return [self._public_run(row) for row in rows[:max(1, min(int(limit or 100), 500))]]

    def session(self, session_id: str) -> dict | None:
        with self._lock:
            row = self._state["sessions"].get(str(session_id or "").strip())
            return self._public_session(row) if isinstance(row, dict) else None

    def sessions(
        self,
        *,
        agent_id: str = "",
        client_route_id: str = "",
        conversation_id: str = "",
        state: str = "",
        limit: int = 100,
    ) -> list[dict]:
        normalized_state = str(state or "").strip().lower()
        if normalized_state and normalized_state not in SESSION_STATES:
            raise DesktopAgentRuntimeError(
                f"Unsupported Agent Runtime Session state: {normalized_state}"
            )
        with self._lock:
            rows = [
                row
                for row in self._state["sessions"].values()
                if not agent_id or str(row.get("agent_id") or "") == agent_id
                if not client_route_id
                or str(row.get("client_route_id") or "") == client_route_id
                if not conversation_id
                or str(row.get("conversation_id") or "") == conversation_id
                if not normalized_state
                or str(row.get("state") or "idle") == normalized_state
            ]
            rows.sort(key=lambda row: int(row.get("updated_at") or 0), reverse=True)
            return [
                self._public_session(row)
                for row in rows[:max(1, min(int(limit or 100), 500))]
            ]

    def counts(self) -> dict:
        with self._lock:
            counts: dict[str, int] = {}
            for row in self._state["runs"].values():
                state = str(row.get("state") or "unknown")
                counts[state] = counts.get(state, 0) + 1
            return {
                "runs": len(self._state["runs"]),
                "sessions": len(self._state["sessions"]),
                "by_state": counts,
            }

    def interrupt_active(self, reason: str = "Desktop Agent Runtime stopped") -> None:
        now_ms = self._now_ms()
        with self._lock:
            changed = False
            for row in self._state["runs"].values():
                if str(row.get("state") or "") not in ACTIVE_STATES:
                    continue
                self._append_event_locked(row, "run_interrupted", now_ms, {
                    "error": str(reason or "Desktop Agent Runtime stopped")[:2_000],
                })
                row["state"] = "interrupted"
                row["error"] = str(reason or "Desktop Agent Runtime stopped")[:2_000]
                row["finished_at"] = now_ms
                changed = True
            if changed:
                for session_id in tuple(self._state["sessions"]):
                    self._sync_session_locked(session_id)
                self._save_locked()

    def adapter_result(self, run_id: str) -> AgentAdapterResult | None:
        with self._lock:
            row = self._state["runs"].get(run_id)
            if not isinstance(row, dict):
                return None
            payload = row.get("adapter_result")
            return self._adapter_result(payload) if isinstance(payload, dict) else None

    def _load(self) -> dict:
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
            if isinstance(payload, dict):
                runs = payload.get("runs") if isinstance(payload.get("runs"), dict) else {}
                sessions = payload.get("sessions") if isinstance(payload.get("sessions"), dict) else {}
                return {
                    "version": RUNTIME_STATE_VERSION,
                    "runs": runs,
                    "sessions": sessions,
                }
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            pass
        return {"version": RUNTIME_STATE_VERSION, "runs": {}, "sessions": {}}

    def _reconcile_event_ledger_locked(self) -> None:
        changed = restore_checkpoint_rows(
            self._event_ledger, self._checkpoint_kind, self._state["runs"],
            recent_limit=MAX_RUNTIME_RUNS, event_limit=MAX_RUNTIME_EVENTS,
        )
        for run_id, row in self._state["runs"].items():
            if not isinstance(row, dict):
                continue
            row.setdefault("run_id", str(run_id))
            row.setdefault("task_id", str(row.get("run_id") or run_id))
            row.setdefault("goal_id", str(row.get("task_id") or run_id))
            row.setdefault("client_route_id", "desktop")
            row.setdefault("conversation_id", f"conversation:{row['task_id']}")
            row.setdefault("turn_id", str(row.get("source_message_id") or row["task_id"]))
            row.setdefault("device_id", "desktop")
            row.setdefault("idempotency_key", str(row.get("run_id") or run_id))
            events = sorted(
                (item for item in row.get("events", []) if isinstance(item, dict)),
                key=lambda item: int(item.get("cursor") or 0),
            )
            durable = self._event_ledger.snapshot(str(row["run_id"]))
            durable_cursor = int((durable or {}).get("last_sequence") or 0)
            for item in events:
                cursor = max(1, int(item.get("cursor") or 1))
                if cursor <= durable_cursor:
                    continue
                payload = None
                if cursor == int(row.get("cursor") or 0):
                    payload = {"projection_checkpoint": {
                        "kind": self._checkpoint_kind,
                        "data": {key: value for key, value in row.items() if key != "events"},
                    }}
                event = runtime_projection_event(
                    row,
                    item.get("type") or "run_started",
                    cursor,
                    int(item.get("timestamp") or row.get("updated_at") or self._now_ms()),
                    payload,
                )
                self._event_ledger.append(event)

            projected_cursor = max(0, int(row.get("cursor") or 0))
            missing = self._event_ledger.events(
                str(row.get("run_id") or run_id),
                after_sequence=projected_cursor,
            )
            if not missing:
                continue
            projection = row.setdefault("events", [])
            for event in missing:
                projection.append(self._event(
                    event.sequence,
                    event.type.lower(),
                    event.timestamp_millis,
                ))
                row["cursor"] = event.sequence
                row["updated_at"] = event.timestamp_millis
            del projection[:-MAX_RUNTIME_EVENTS]
            snapshot = self._event_ledger.snapshot(str(row.get("run_id") or run_id))
            if snapshot is not None:
                state = str(snapshot.get("state") or "")
                row["state"] = {
                    "waiting_for_user": "running",
                    "waiting_for_device": "running",
                    "interrupted": "interrupted",
                }.get(state, state or str(row.get("state") or "queued"))
            changed = True
        if changed:
            session_ids = {str(row.get("session_id") or "") for row in self._state["runs"].values()}
            for session_id in session_ids:
                self._sync_session_locked(session_id)
            self._prune_locked()
            self._save_locked()

    def _recover_interrupted_locked(self) -> None:
        self.interrupt_active("Desktop stopped before the Runtime Run reached a terminal state")

    def _required_run_locked(self, run_id: str) -> dict:
        row = self._state["runs"].get(run_id)
        if not isinstance(row, dict):
            raise DesktopAgentRuntimeError(f"Unknown Agent Runtime Run: {run_id}")
        return row

    def _find_by_idempotency_locked(self, idempotency_key: str) -> dict | None:
        for row in self._state["runs"].values():
            if str(row.get("idempotency_key") or "") == idempotency_key:
                return row
        return None

    def _append_event_locked(
        self,
        row: dict,
        event_type: str,
        now_ms: int,
        payload: dict | None = None,
    ) -> None:
        cursor = int(row.get("cursor") or 0) + 1
        event_payload = dict(payload or {})
        event_payload["projection_checkpoint"] = {
            "kind": self._checkpoint_kind,
            "data": runtime_checkpoint(row, event_type, now_ms, event_payload),
        }
        event, _created = self._event_ledger.append(runtime_projection_event(
            row,
            event_type,
            cursor,
            now_ms,
            event_payload,
        ))
        cursor = event.sequence
        row["cursor"] = cursor
        row["updated_at"] = now_ms
        events = row.setdefault("events", [])
        events.append(self._event(cursor, event_type, now_ms))
        del events[:-MAX_RUNTIME_EVENTS]

    def _sync_session_locked(self, session_id: str) -> None:
        session = self._state["sessions"].get(session_id)
        runs = [
            row
            for row in self._state["runs"].values()
            if str(row.get("session_id") or "") == session_id
        ]
        if not runs:
            if not isinstance(session, dict):
                return
            session["state"] = "idle"
            session["active_run_count"] = 0
            return
        runs.sort(
            key=lambda row: (
                int(row.get("created_at") or 0),
                str(row.get("run_id") or ""),
            )
        )
        latest = runs[-1]
        if not isinstance(session, dict):
            first = runs[0]
            session = {
                "session_id": session_id, "agent_id": first.get("agent_id", ""),
                "client_route_id": first.get("client_route_id", ""),
                "conversation_id": first.get("conversation_id", ""),
                "created_at": first.get("created_at", 0),
            }
            self._state["sessions"][session_id] = session
        session["run_count"] = max(int(session.get("run_count") or 0), len(runs))
        active = [
            str(row.get("run_id") or "")
            for row in runs
            if str(row.get("state") or "") in ACTIVE_STATES
        ]
        session.update({
            "state": "active" if active else "idle",
            "active_run_count": len(active),
            "completed_run_count": sum(
                1 for row in runs if str(row.get("state") or "") == "completed"
            ),
            "failed_run_count": sum(
                1 for row in runs if str(row.get("state") or "") in {"failed", "interrupted"}
            ),
            "cancelled_run_count": sum(
                1 for row in runs if str(row.get("state") or "") == "cancelled"
            ),
            "last_run_id": str(latest.get("run_id") or ""),
            "last_task_id": str(latest.get("task_id") or ""),
            "last_turn_id": str(latest.get("turn_id") or ""),
            "last_state": str(latest.get("state") or ""),
            "updated_at": int(latest.get("updated_at") or session.get("updated_at") or 0),
        })

    def _prune_locked(self) -> None:
        runs = self._state["runs"]
        if len(runs) > MAX_RUNTIME_RUNS:
            terminal = sorted(
                (
                    (run_id, row)
                    for run_id, row in runs.items()
                    if str(row.get("state") or "") in TERMINAL_STATES - {"interrupted"}
                ),
                key=lambda item: int(item[1].get("updated_at") or 0),
            )
            for run_id, _row in terminal[:max(0, len(terminal) - MAX_RUNTIME_RUNS)]:
                runs.pop(run_id, None)
        sessions = self._state["sessions"]
        if len(sessions) > MAX_RUNTIME_SESSIONS:
            ordered = sorted(
                (
                    (session_id, row)
                    for session_id, row in sessions.items()
                    if str(row.get("state") or "idle") != "active"
                ),
                key=lambda item: int(item[1].get("updated_at") or 0),
            )
            for session_id, _row in ordered[:max(0, len(sessions) - MAX_RUNTIME_SESSIONS)]:
                sessions.pop(session_id, None)

    def _save_locked(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(f"{self.path.suffix}.tmp")
        temporary.write_text(
            json.dumps(self._state, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        try:
            os.chmod(temporary, 0o600)
        except OSError:
            pass
        temporary.replace(self.path)

    @staticmethod
    def _session_id(agent_id: str, route_id: str, conversation_id: str) -> str:
        identity = "\x1f".join((agent_id, route_id, conversation_id or "default"))
        digest = hashlib.sha256(identity.encode("utf-8", errors="replace")).hexdigest()[:24]
        return f"session-{digest}"

    @staticmethod
    def _fingerprint(request: AgentAdapterRequest) -> str:
        body = json.dumps(
            {
                "agent_id": request.agent_id,
                "prompt": request.prompt,
                "delivery_mode": request.delivery_mode.value,
                "invocation_mode": request.invocation_mode.value,
                "caller_agent_id": request.caller_agent_id,
                "parent_run_id": request.parent_run_id,
                "handoff_chain": request.handoff_chain,
                "protocol": request.protocol,
                "required_features": sorted(request.required_features),
                "allow_protocol_downgrade": request.allow_protocol_downgrade,
                "conversation_id": request.conversation_id,
                "source_message_id": request.source_message_id,
                "return_path": request.return_path,
                "response_language": request.response_language,
                "priority": request.priority.value,
                "client_route_id": str(request.checkpoint.get("client_route_id") or ""),
                "turn_id": str(request.checkpoint.get("turn_id") or ""),
                "checkpoint": request.checkpoint,
                "artifacts": request.artifacts,
            },
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            default=str,
        ).encode("utf-8")
        return hashlib.sha256(body).hexdigest()

    @staticmethod
    def _event(cursor: int, event_type: str, timestamp_ms: int) -> dict:
        return {"cursor": cursor, "type": event_type, "timestamp": timestamp_ms}

    @staticmethod
    def _adapter_result(payload: dict) -> AgentAdapterResult:
        return AgentAdapterResult(
            run_id=str(payload.get("run_id") or ""),
            agent_id=str(payload.get("agent_id") or ""),
            delivery_mode=AgentDeliveryMode.parse(payload.get("delivery_mode") or "respond"),
            state=str(payload.get("state") or "unknown"),
            invocation_mode=AgentInvocationMode.parse(
                payload.get("invocation_mode") or "direct"
            ),
            caller_agent_id=str(payload.get("caller_agent_id") or ""),
            parent_run_id=str(payload.get("parent_run_id") or ""),
            handoff_chain=tuple(
                str(item or "").strip()
                for item in payload.get("handoff_chain", [])
                if str(item or "").strip()
            ),
            reply=str(payload.get("reply") or ""),
            error=str(payload.get("error") or ""),
            cursor=int(payload.get("cursor") or 0),
            negotiated_protocol=str(payload.get("negotiated_protocol") or ""),
            replayed=True,
            executed=False,
            checkpoint=dict(payload.get("checkpoint") or {}),
            artifacts=tuple(
                dict(item)
                for item in payload.get("artifacts", [])
                if isinstance(item, dict)
            ),
        )

    @staticmethod
    def _public_run(row: dict, replayed: bool = False) -> dict:
        return {
            "run_id": str(row.get("run_id") or ""),
            "idempotency_key": str(row.get("idempotency_key") or ""),
            "session_id": str(row.get("session_id") or ""),
            "agent_id": str(row.get("agent_id") or ""),
            "delivery_mode": str(row.get("delivery_mode") or ""),
            "invocation_mode": str(row.get("invocation_mode") or "direct"),
            "caller_agent_id": str(row.get("caller_agent_id") or ""),
            "parent_run_id": str(row.get("parent_run_id") or ""),
            "handoff_chain": [
                str(item or "").strip()
                for item in row.get("handoff_chain", [])
                if str(item or "").strip()
            ],
            "response_owner_agent_id": (
                str(row.get("caller_agent_id") or "")
                if str(row.get("invocation_mode") or "direct") == "tool"
                else str(row.get("agent_id") or "")
            ),
            "client_route_id": str(row.get("client_route_id") or ""),
            "conversation_id": str(row.get("conversation_id") or ""),
            "goal_id": str(row.get("goal_id") or row.get("task_id") or ""),
            "task_id": str(row.get("task_id") or ""),
            "turn_id": str(row.get("turn_id") or ""),
            "source_message_id": str(row.get("source_message_id") or ""),
            "priority": str(
                row.get("priority") or AgentRunPriority.FOREGROUND.value
            ),
            "session_created": bool(row.get("session_created")),
            "state": str(row.get("state") or "unknown"),
            "created_at": int(row.get("created_at") or 0),
            "queued_at": int(row.get("queued_at") or 0),
            "started_at": int(row.get("started_at") or 0),
            "finished_at": int(row.get("finished_at") or 0),
            "updated_at": int(row.get("updated_at") or 0),
            "cursor": int(row.get("cursor") or 0),
            "error": str(row.get("error") or ""),
            "replayed": replayed,
        }

    @staticmethod
    def _public_session(row: dict) -> dict:
        return {
            "session_id": str(row.get("session_id") or ""),
            "agent_id": str(row.get("agent_id") or ""),
            "client_route_id": str(row.get("client_route_id") or ""),
            "conversation_id": str(row.get("conversation_id") or ""),
            "state": str(row.get("state") or "idle"),
            "active_run_count": max(0, int(row.get("active_run_count") or 0)),
            "run_count": max(0, int(row.get("run_count") or 0)),
            "completed_run_count": max(0, int(row.get("completed_run_count") or 0)),
            "failed_run_count": max(0, int(row.get("failed_run_count") or 0)),
            "cancelled_run_count": max(0, int(row.get("cancelled_run_count") or 0)),
            "last_run_id": str(row.get("last_run_id") or ""),
            "last_task_id": str(row.get("last_task_id") or ""),
            "last_turn_id": str(row.get("last_turn_id") or ""),
            "last_state": str(row.get("last_state") or ""),
            "created_at": max(0, int(row.get("created_at") or 0)),
            "updated_at": max(0, int(row.get("updated_at") or 0)),
        }

    def _now_ms(self) -> int:
        return int(self._now() * 1_000)


class DesktopAgentRuntimeServer:
    """Bounded scheduler and lifecycle server for every desktop Agent."""

    def __init__(
        self,
        provider: DesktopAgentProvider,
        store: DesktopAgentRuntimeStore,
        max_workers: int = DEFAULT_MAX_WORKERS,
        max_queued_runs: int = DEFAULT_MAX_QUEUED_RUNS,
        fault_domains: AgentFaultDomainRegistry | None = None,
        capacity: AgentCapacityController | None = None,
        session_memory_reader: Callable[[], tuple[int, str]] | None = None,
        session_memory_observer: Callable[[dict], None] | None = None,
    ) -> None:
        self.provider = provider
        self.store = store
        self.max_workers = max(1, min(int(max_workers or DEFAULT_MAX_WORKERS), 32))
        self._foreground_executor = ThreadPoolExecutor(
            max_workers=self.max_workers,
            thread_name_prefix="galaxyssi-agent-foreground",
        )
        self._background_executor = ThreadPoolExecutor(
            max_workers=1,
            thread_name_prefix="galaxyssi-agent-background",
        )
        self._lock = threading.RLock()
        self._futures: dict[str, Future[AgentAdapterResult]] = {}
        self._closed = False
        self._session_memory_reader = session_memory_reader
        self._session_memory_observer = session_memory_observer
        self.fault_domains = fault_domains or AgentFaultDomainRegistry()
        self.capacity = capacity or AgentCapacityController(
            max_active=self.max_workers,
            max_queued=max_queued_runs,
        )

    def submit(self, request: AgentAdapterRequest) -> dict:
        normalized = request.normalized()
        self._ensure_open()
        self._require_agent(normalized.agent_id)
        memory_before = (
            self._read_session_memory()
            if self.store.will_create_session(normalized)
            else None
        )
        snapshot, created = self.store.claim(normalized)
        if not created:
            return snapshot
        if bool(snapshot.get("session_created")):
            self._observe_session_memory(
                snapshot,
                memory_before,
                self._read_session_memory(),
            )
        try:
            self.capacity.reserve(
                normalized.run_id,
                normalized.agent_id,
                normalized.priority,
            )
        except DesktopAgentCapacityExhausted as exc:
            self.store.fail(normalized.run_id, str(exc))
            raise
        with self._lock:
            if self._closed:
                self.capacity.release(normalized.run_id)
                self.store.fail(normalized.run_id, "Desktop Agent Runtime is shutting down")
                raise DesktopAgentRuntimeError("Desktop Agent Runtime is shutting down")
            try:
                executor = (
                    self._background_executor
                    if normalized.priority == AgentRunPriority.BACKGROUND
                    else self._foreground_executor
                )
                future = executor.submit(self._execute, normalized)
            except Exception:
                self.capacity.release(normalized.run_id)
                self.store.fail(
                    normalized.run_id,
                    "Desktop Agent Runtime could not schedule the Run",
                )
                raise
            self._futures[normalized.run_id] = future
            future.add_done_callback(
                lambda _future, run_id=normalized.run_id: self._release_future(run_id)
            )
        return self.store.status(normalized.run_id) or snapshot

    def execute(
        self,
        request: AgentAdapterRequest,
        timeout_seconds: float | None = None,
    ) -> AgentAdapterResult:
        snapshot = self.submit(request)
        run_id = str(snapshot.get("run_id") or "")
        persisted = self.store.adapter_result(run_id)
        if persisted is not None:
            return persisted
        if str(snapshot.get("state") or "") in TERMINAL_STATES:
            return self._result_from_runtime(snapshot)
        with self._lock:
            future = self._futures.get(run_id)
        if future is None:
            refreshed = self.store.status(run_id) or snapshot
            persisted = self.store.adapter_result(run_id)
            return persisted or self._result_from_runtime(refreshed)
        return future.result(timeout=timeout_seconds)

    def status(self, run_id: str) -> dict | None:
        return self.store.status(run_id)

    def events(self, run_id: str, after_cursor: int = 0) -> list[dict]:
        return self.store.events(run_id, after_cursor)

    def runs(
        self,
        *,
        state: str = "",
        agent_id: str = "",
        session_id: str = "",
        invocation_mode: str = "",
        caller_agent_id: str = "",
        parent_run_id: str = "",
        limit: int = 100,
    ) -> list[dict]:
        return self.store.runs(
            state=state,
            agent_id=agent_id,
            session_id=session_id,
            invocation_mode=invocation_mode,
            caller_agent_id=caller_agent_id,
            parent_run_id=parent_run_id,
            limit=limit,
        )

    def session(self, session_id: str) -> dict | None:
        return self.store.session(session_id)

    def sessions(
        self,
        *,
        agent_id: str = "",
        client_route_id: str = "",
        conversation_id: str = "",
        state: str = "",
        limit: int = 100,
    ) -> list[dict]:
        return self.store.sessions(
            agent_id=agent_id,
            client_route_id=client_route_id,
            conversation_id=conversation_id,
            state=state,
            limit=limit,
        )

    def cancel(self, run_id: str) -> dict | None:
        snapshot = self.store.status(run_id)
        if snapshot is None:
            return None
        if str(snapshot.get("state") or "") in TERMINAL_STATES:
            return snapshot
        with self._lock:
            future = self._futures.get(run_id)
        if future is not None:
            if future.cancel():
                self.capacity.release(run_id)
        try:
            self.provider.cancel(str(snapshot.get("agent_id") or ""), run_id)
        except Exception:
            pass
        return self.store.cancel(run_id)

    def health(self) -> dict:
        counts = self.store.counts()
        state_counts = counts.get("by_state", {})
        active_runs = int(state_counts.get("running") or 0)
        queued_runs = int(state_counts.get("queued") or 0)
        sessions = self.store.sessions(limit=MAX_RUNTIME_SESSIONS)
        with self._lock:
            pending_futures = sum(1 for future in self._futures.values() if not future.done())
            closed = self._closed
        agents = self.provider.enumerate()
        capacity = self.capacity.snapshot()
        return {
            "protocol": RUNTIME_PROTOCOL,
            "state_version": RUNTIME_STATE_VERSION,
            "status": "stopped" if closed else "ready",
            "max_concurrency": self.max_workers,
            "foreground_max_concurrency": self.max_workers,
            "background_max_concurrency": 1,
            "active_runs": active_runs,
            "queued_runs": queued_runs,
            "pending_futures": pending_futures,
            "capacity_available": capacity["available_active_slots"],
            "capacity": capacity,
            "active_sessions": sum(
                1 for session in sessions if session.get("state") == "active"
            ),
            "features": [
                "bounded_async_scheduling",
                "durable_run_registry",
                "durable_session_registry",
                "agent_as_tool",
                "explicit_handoff",
                "parent_child_runs",
                "strict_idempotency",
                "event_cursor",
                "cancellation",
                "restart_recovery",
                "per_agent_fault_domains",
                "bounded_global_queue",
                "capacity_backpressure",
                "foreground_background_isolation",
                "foreground_reserved_capacity",
                "session_memory_budget",
            ],
            "agents": agents,
            "fault_domains": self.fault_domains.snapshots(
                tuple(str(agent.get("agent_id") or "") for agent in agents)
            ),
            **counts,
        }

    def shutdown(self, wait: bool = False) -> None:
        with self._lock:
            if self._closed:
                return
            self._closed = True
            futures = list(self._futures.items())
        for run_id, future in futures:
            if future.cancel():
                self.capacity.release(run_id)
            snapshot = self.store.status(run_id)
            if snapshot is None:
                continue
            try:
                self.provider.cancel(str(snapshot.get("agent_id") or ""), run_id)
            except Exception:
                pass
        self.store.interrupt_active()
        self._foreground_executor.shutdown(wait=wait, cancel_futures=True)
        self._background_executor.shutdown(wait=wait, cancel_futures=True)

    def _execute(self, request: AgentAdapterRequest) -> AgentAdapterResult:
        try:
            self.capacity.start(request.run_id)
            try:
                self.fault_domains.acquire(request.agent_id)
            except DesktopAgentFaultIsolated as exc:
                self.store.fail(request.run_id, str(exc))
                raise
            current = self.store.transition_running(request.run_id)
            if str(current.get("state") or "") != "running":
                self.fault_domains.release(request.agent_id)
                return self._result_from_runtime(current)
            try:
                result = self.provider.deliver(request)
                snapshot = self.store.finish(request.run_id, result)
                if result.state in {"failed", "interrupted"}:
                    self.fault_domains.fail(request.agent_id, result.error)
                elif result.state == "cancelled":
                    self.fault_domains.release(request.agent_id)
                else:
                    self.fault_domains.succeed(request.agent_id)
                if str(snapshot.get("state") or "") != result.state:
                    return self._result_from_runtime(snapshot)
                return result
            except Exception as exc:
                self.store.fail(request.run_id, str(exc))
                self.fault_domains.fail(request.agent_id, str(exc))
                raise
        finally:
            self.capacity.release(request.run_id)

    def _read_session_memory(self) -> tuple[int, str] | None:
        reader = self._session_memory_reader
        if reader is None:
            return None
        try:
            resident_bytes, kind = reader()
            return max(0, int(resident_bytes)), str(kind or "").strip()
        except Exception:
            return None

    def _observe_session_memory(
        self,
        snapshot: dict,
        before: tuple[int, str] | None,
        after: tuple[int, str] | None,
    ) -> None:
        observer = self._session_memory_observer
        if observer is None or before is None or after is None:
            return
        try:
            observer({
                "sampled_at": int(time.time() * 1_000),
                "session_id": str(snapshot.get("session_id") or ""),
                "agent_id": str(snapshot.get("agent_id") or ""),
                "conversation_id": str(snapshot.get("conversation_id") or ""),
                "before_bytes": before[0],
                "after_bytes": after[0],
                "measurement_kind": after[1] or before[1],
            })
        except Exception:
            return

    def _require_agent(self, agent_id: str) -> None:
        if agent_id not in {str(item.get("agent_id") or "") for item in self.provider.enumerate()}:
            raise DesktopAgentRuntimeError(f"Unknown Agent adapter: {agent_id}")

    def _ensure_open(self) -> None:
        with self._lock:
            if self._closed:
                raise DesktopAgentRuntimeError("Desktop Agent Runtime is stopped")

    def _release_future(self, run_id: str) -> None:
        with self._lock:
            future = self._futures.pop(run_id, None)
        if future is not None and future.cancelled():
            self.capacity.release(run_id)

    @staticmethod
    def _result_from_runtime(snapshot: dict) -> AgentAdapterResult:
        return AgentAdapterResult(
            run_id=str(snapshot.get("run_id") or ""),
            agent_id=str(snapshot.get("agent_id") or ""),
            delivery_mode=AgentDeliveryMode.parse(snapshot.get("delivery_mode") or "respond"),
            state=str(snapshot.get("state") or "unknown"),
            invocation_mode=AgentInvocationMode.parse(
                snapshot.get("invocation_mode") or "direct"
            ),
            caller_agent_id=str(snapshot.get("caller_agent_id") or ""),
            parent_run_id=str(snapshot.get("parent_run_id") or ""),
            handoff_chain=tuple(
                str(item or "").strip()
                for item in snapshot.get("handoff_chain", [])
                if str(item or "").strip()
            ),
            error=str(snapshot.get("error") or ""),
            replayed=bool(snapshot.get("replayed")),
        )
