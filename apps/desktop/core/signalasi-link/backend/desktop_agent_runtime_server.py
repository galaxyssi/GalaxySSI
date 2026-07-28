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
    DesktopAgentProvider,
)


RUNTIME_PROTOCOL = "signalasi.agent-runtime/1.0"
RUNTIME_STATE_VERSION = 1
DEFAULT_MAX_WORKERS = 4
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


class DesktopAgentRuntimeError(RuntimeError):
    pass


class DesktopAgentRuntimeConflict(DesktopAgentRuntimeError):
    pass


class DesktopAgentRuntimeStore:
    """Atomic persistent Run and Session registry."""

    def __init__(self, path: Path, now: Callable[[], float] = time.time) -> None:
        self.path = Path(path)
        self._now = now
        self._lock = threading.RLock()
        self._state = self._load()
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

            session = self._state["sessions"].get(session_id)
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
                }
                self._state["sessions"][session_id] = session
            session["updated_at"] = now_ms
            session["run_count"] = int(session.get("run_count") or 0) + 1
            session["last_run_id"] = request.run_id

            row = {
                "run_id": request.run_id,
                "idempotency_key": request.idempotency_key,
                "fingerprint": fingerprint,
                "session_id": session_id,
                "agent_id": request.agent_id,
                "delivery_mode": request.delivery_mode.value,
                "client_route_id": route_id,
                "conversation_id": request.conversation_id,
                "task_id": str(request.checkpoint.get("task_id") or request.run_id).strip(),
                "turn_id": turn_id,
                "source_message_id": request.source_message_id,
                "state": "queued",
                "created_at": now_ms,
                "queued_at": now_ms,
                "started_at": 0,
                "finished_at": 0,
                "updated_at": now_ms,
                "cursor": 1,
                "error": "",
                "adapter_result": None,
                "events": [self._event(1, "run_queued", now_ms)],
            }
            self._state["runs"][request.run_id] = row
            self._prune_locked()
            self._save_locked()
            return self._public_run(row), True

    def transition_running(self, run_id: str) -> dict:
        now_ms = self._now_ms()
        with self._lock:
            row = self._required_run_locked(run_id)
            if str(row.get("state") or "") != "queued":
                return self._public_run(row)
            row["state"] = "running"
            row["started_at"] = now_ms
            self._append_event_locked(row, "run_started", now_ms)
            self._save_locked()
            return self._public_run(row)

    def finish(self, run_id: str, result: AgentAdapterResult) -> dict:
        now_ms = self._now_ms()
        with self._lock:
            row = self._required_run_locked(run_id)
            if str(row.get("state") or "") in TERMINAL_STATES:
                return self._public_run(row)
            row["state"] = result.state
            row["error"] = result.error
            row["adapter_result"] = result.public()
            row["finished_at"] = now_ms
            self._append_event_locked(row, f"run_{result.state}", now_ms)
            self._save_locked()
            return self._public_run(row)

    def fail(self, run_id: str, error: str) -> dict:
        now_ms = self._now_ms()
        with self._lock:
            row = self._required_run_locked(run_id)
            if str(row.get("state") or "") in TERMINAL_STATES:
                return self._public_run(row)
            row["state"] = "failed"
            row["error"] = str(error or "Agent runtime execution failed")[:2_000]
            row["finished_at"] = now_ms
            self._append_event_locked(row, "run_failed", now_ms)
            self._save_locked()
            return self._public_run(row)

    def cancel(self, run_id: str) -> dict | None:
        now_ms = self._now_ms()
        with self._lock:
            row = self._state["runs"].get(run_id)
            if not isinstance(row, dict):
                return None
            if str(row.get("state") or "") not in TERMINAL_STATES:
                row["state"] = "cancelled"
                row["finished_at"] = now_ms
                self._append_event_locked(row, "run_cancelled", now_ms)
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

    def runs(
        self,
        *,
        state: str = "",
        agent_id: str = "",
        session_id: str = "",
        limit: int = 100,
    ) -> list[dict]:
        with self._lock:
            rows = [
                row
                for row in self._state["runs"].values()
                if (not state or str(row.get("state") or "") == state)
                and (not agent_id or str(row.get("agent_id") or "") == agent_id)
                and (not session_id or str(row.get("session_id") or "") == session_id)
            ]
            rows.sort(key=lambda row: int(row.get("created_at") or 0), reverse=True)
            return [self._public_run(row) for row in rows[:max(1, min(int(limit or 100), 500))]]

    def sessions(self, agent_id: str = "", limit: int = 100) -> list[dict]:
        with self._lock:
            rows = [
                row
                for row in self._state["sessions"].values()
                if not agent_id or str(row.get("agent_id") or "") == agent_id
            ]
            rows.sort(key=lambda row: int(row.get("updated_at") or 0), reverse=True)
            return [dict(row) for row in rows[:max(1, min(int(limit or 100), 500))]]

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
                row["state"] = "interrupted"
                row["error"] = str(reason or "Desktop Agent Runtime stopped")[:2_000]
                row["finished_at"] = now_ms
                self._append_event_locked(row, "run_interrupted", now_ms)
                changed = True
            if changed:
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

    def _append_event_locked(self, row: dict, event_type: str, now_ms: int) -> None:
        cursor = int(row.get("cursor") or 0) + 1
        row["cursor"] = cursor
        row["updated_at"] = now_ms
        events = row.setdefault("events", [])
        events.append(self._event(cursor, event_type, now_ms))
        del events[:-MAX_RUNTIME_EVENTS]

    def _prune_locked(self) -> None:
        runs = self._state["runs"]
        if len(runs) > MAX_RUNTIME_RUNS:
            terminal = sorted(
                (
                    (run_id, row)
                    for run_id, row in runs.items()
                    if str(row.get("state") or "") in TERMINAL_STATES
                ),
                key=lambda item: int(item[1].get("updated_at") or 0),
            )
            for run_id, _row in terminal[:len(runs) - MAX_RUNTIME_RUNS]:
                runs.pop(run_id, None)
        sessions = self._state["sessions"]
        if len(sessions) > MAX_RUNTIME_SESSIONS:
            ordered = sorted(
                sessions.items(),
                key=lambda item: int(item[1].get("updated_at") or 0),
            )
            for session_id, _row in ordered[:len(sessions) - MAX_RUNTIME_SESSIONS]:
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
                "protocol": request.protocol,
                "required_features": sorted(request.required_features),
                "allow_protocol_downgrade": request.allow_protocol_downgrade,
                "conversation_id": request.conversation_id,
                "source_message_id": request.source_message_id,
                "return_path": request.return_path,
                "response_language": request.response_language,
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
            "client_route_id": str(row.get("client_route_id") or ""),
            "conversation_id": str(row.get("conversation_id") or ""),
            "task_id": str(row.get("task_id") or ""),
            "turn_id": str(row.get("turn_id") or ""),
            "source_message_id": str(row.get("source_message_id") or ""),
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

    def _now_ms(self) -> int:
        return int(self._now() * 1_000)


class DesktopAgentRuntimeServer:
    """Bounded scheduler and lifecycle server for every desktop Agent."""

    def __init__(
        self,
        provider: DesktopAgentProvider,
        store: DesktopAgentRuntimeStore,
        max_workers: int = DEFAULT_MAX_WORKERS,
    ) -> None:
        self.provider = provider
        self.store = store
        self.max_workers = max(1, min(int(max_workers or DEFAULT_MAX_WORKERS), 32))
        self._executor = ThreadPoolExecutor(
            max_workers=self.max_workers,
            thread_name_prefix="signalasi-agent-runtime",
        )
        self._lock = threading.RLock()
        self._futures: dict[str, Future[AgentAdapterResult]] = {}
        self._closed = False

    def submit(self, request: AgentAdapterRequest) -> dict:
        normalized = request.normalized()
        self._ensure_open()
        self._require_agent(normalized.agent_id)
        snapshot, created = self.store.claim(normalized)
        if not created:
            return snapshot
        with self._lock:
            if self._closed:
                self.store.fail(normalized.run_id, "Desktop Agent Runtime is shutting down")
                raise DesktopAgentRuntimeError("Desktop Agent Runtime is shutting down")
            future = self._executor.submit(self._execute, normalized)
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
        limit: int = 100,
    ) -> list[dict]:
        return self.store.runs(
            state=state,
            agent_id=agent_id,
            session_id=session_id,
            limit=limit,
        )

    def sessions(self, agent_id: str = "", limit: int = 100) -> list[dict]:
        return self.store.sessions(agent_id=agent_id, limit=limit)

    def cancel(self, run_id: str) -> dict | None:
        snapshot = self.store.status(run_id)
        if snapshot is None:
            return None
        if str(snapshot.get("state") or "") in TERMINAL_STATES:
            return snapshot
        with self._lock:
            future = self._futures.get(run_id)
        if future is not None:
            future.cancel()
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
        with self._lock:
            pending_futures = sum(1 for future in self._futures.values() if not future.done())
            closed = self._closed
        return {
            "protocol": RUNTIME_PROTOCOL,
            "state_version": RUNTIME_STATE_VERSION,
            "status": "stopped" if closed else "ready",
            "max_concurrency": self.max_workers,
            "active_runs": active_runs,
            "queued_runs": queued_runs,
            "pending_futures": pending_futures,
            "capacity_available": max(0, self.max_workers - active_runs),
            "features": [
                "bounded_async_scheduling",
                "durable_run_registry",
                "durable_session_registry",
                "strict_idempotency",
                "event_cursor",
                "cancellation",
                "restart_recovery",
            ],
            "agents": self.provider.enumerate(),
            **counts,
        }

    def shutdown(self, wait: bool = False) -> None:
        with self._lock:
            if self._closed:
                return
            self._closed = True
            futures = list(self._futures.items())
        for run_id, future in futures:
            future.cancel()
            snapshot = self.store.status(run_id)
            if snapshot is None:
                continue
            try:
                self.provider.cancel(str(snapshot.get("agent_id") or ""), run_id)
            except Exception:
                pass
        self.store.interrupt_active()
        self._executor.shutdown(wait=wait, cancel_futures=True)

    def _execute(self, request: AgentAdapterRequest) -> AgentAdapterResult:
        current = self.store.transition_running(request.run_id)
        if str(current.get("state") or "") != "running":
            return self._result_from_runtime(current)
        try:
            result = self.provider.deliver(request)
            snapshot = self.store.finish(request.run_id, result)
            if str(snapshot.get("state") or "") != result.state:
                return self._result_from_runtime(snapshot)
            return result
        except Exception as exc:
            self.store.fail(request.run_id, str(exc))
            raise

    def _require_agent(self, agent_id: str) -> None:
        if agent_id not in {str(item.get("agent_id") or "") for item in self.provider.enumerate()}:
            raise DesktopAgentRuntimeError(f"Unknown Agent adapter: {agent_id}")

    def _ensure_open(self) -> None:
        with self._lock:
            if self._closed:
                raise DesktopAgentRuntimeError("Desktop Agent Runtime is stopped")

    def _release_future(self, run_id: str) -> None:
        with self._lock:
            self._futures.pop(run_id, None)

    @staticmethod
    def _result_from_runtime(snapshot: dict) -> AgentAdapterResult:
        return AgentAdapterResult(
            run_id=str(snapshot.get("run_id") or ""),
            agent_id=str(snapshot.get("agent_id") or ""),
            delivery_mode=AgentDeliveryMode.parse(snapshot.get("delivery_mode") or "respond"),
            state=str(snapshot.get("state") or "unknown"),
            error=str(snapshot.get("error") or ""),
            replayed=bool(snapshot.get("replayed")),
        )
