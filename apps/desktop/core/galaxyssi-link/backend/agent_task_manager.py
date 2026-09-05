"""Persistent lifecycle manager for remote Agent tasks."""
from __future__ import annotations

import json
import math
import os
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field, fields
from pathlib import Path
from typing import Callable

from agent_task_run_events import AgentTaskRunEventSink
from agent_run_storage import RUN_KERNEL_DATABASE_NAME, run_kernel_database_path
from agent_task_run_migration import migrate_task_run_data
from agent_task_store import AgentTaskStore
from voice_latency import VoiceLatencyTracer, VoiceTraceEvents, voice_latency_tracer


TASKS_DB_PATH = run_kernel_database_path()
TERMINAL_STATES = {"completed", "failed", "cancelled", "timed_out"}
PAUSABLE_STATES = {
    "accepted",
    "queued",
    "starting",
    "recovering",
    "running",
    "waiting_input",
    "waiting_approval",
}
PAUSED_STATES = {"pausing", "paused", "takeover"}
MAX_AUTOMATIC_RECOVERY_ATTEMPTS = 2
MAX_TASK_EVENTS = 256
MAX_DELIVERY_TRACE_EVENTS = 64
MAX_PARTIAL_RESULT_CHARACTERS = 64_000
DEFAULT_TAKEOVER_LEASE_SECONDS = 15 * 60
MAX_TAKEOVER_LEASE_SECONDS = 60 * 60
EXECUTION_LOCATION_CONTRACT = "galaxyssi.execution-location/1.0"
EventCallback = Callable[[dict], None]
ExternalRecoveryCallback = Callable[[dict, str], bool]


def desktop_execution_location() -> dict:
    name = str(
        os.environ.get("COMPUTERNAME")
        or os.environ.get("HOSTNAME")
        or "GalaxySSI Desktop"
    ).strip()
    return {
        "kind": "desktop",
        "id": name.lower(),
        "name": name,
    }


def _environment_timeout_seconds(name: str, default: float, minimum: float) -> float:
    try:
        value = float(os.environ.get(name, str(default)))
    except (TypeError, ValueError):
        return default
    return max(minimum, value) if math.isfinite(value) else default


DEFAULT_STALL_TIMEOUT_SECONDS = _environment_timeout_seconds(
    "GALAXYSSI_AGENT_STALL_TIMEOUT_SECONDS",
    default=300.0,
    minimum=30.0,
)


def delivery_trace_metrics(trace: list[dict]) -> dict:
    valid = [
        item for item in trace
        if isinstance(item, dict) and int(item.get("at") or 0) > 0
    ]
    if not valid:
        return {
            "total_ms": 0,
            "first_output_ms": None,
            "milestones": {},
            "stages": [],
        }
    origin = int(valid[0]["at"])
    previous = origin
    milestones: dict[str, int] = {}
    stages: list[dict] = []
    for item in valid:
        stage = str(item.get("stage") or "")
        current = int(item["at"])
        milestones.setdefault(stage, current)
        stages.append({
            "stage": stage,
            "at": current,
            "from_start_ms": max(0, current - origin),
            "from_previous_ms": max(0, current - previous),
        })
        previous = current
    first_output_at = milestones.get("agent_first_output")
    return {
        "total_ms": max(0, previous - origin),
        "first_output_ms": (
            max(0, first_output_at - origin)
            if first_output_at is not None else None
        ),
        "milestones": milestones,
        "stages": stages[-MAX_DELIVERY_TRACE_EVENTS:],
    }


@dataclass
class AgentTask:
    task_id: str
    agent_id: str
    contact_id: str
    source_message_id: str
    prompt: str
    goal_id: str = ""
    run_id: str = ""
    conversation_id: str = ""
    client_conversation_id: str = ""
    client_route_id: str = ""
    status: str = "accepted"
    created_at: int = field(default_factory=lambda: int(time.time() * 1000))
    started_at: int = 0
    updated_at: int = field(default_factory=lambda: int(time.time() * 1000))
    completed_at: int = 0
    result: str = ""
    error: str = ""
    first_output_at: int = 0
    output_delta_sequence: int = 0
    output_delta_event_id: str = ""
    partial_result_text: str = ""
    exit_code: int | None = None
    status_seq: int = 0
    thread_id: str = ""
    turn_id: str = ""
    client_turn_id: str = ""
    delegate_agent_id: str = ""
    current_step: str = ""
    pending_approval: dict = field(default_factory=dict)
    events: list[dict] = field(default_factory=list)
    output_files: list[dict] = field(default_factory=list)
    attachments: list[str] = field(default_factory=list)
    retry_of: str = ""
    task_disposition: str = ""
    merged_into_task_id: str = ""
    supersedes_task_id: str = ""
    intervention_kind: str = ""
    attempt: int = 1
    execution_policy: dict = field(default_factory=dict)
    last_progress_at: int = field(default_factory=lambda: int(time.time() * 1000))
    replan_count: int = 0
    stall_count: int = 0
    last_stall_at: int = 0
    recovery_state: str = "healthy"
    failure_counts: dict[str, int] = field(default_factory=dict)
    trace_id: str = field(default_factory=lambda: uuid.uuid4().hex)
    delivery_trace: list[dict] = field(default_factory=list)
    pause_requested: bool = False
    pause_reason: str = ""
    paused_at: int = 0
    resume_count: int = 0
    execution_generation: int = 1
    execution_checkpoint: dict = field(default_factory=dict)
    takeover: dict = field(default_factory=dict)
    process: subprocess.Popen | None = field(default=None, repr=False, compare=False)
    cancel_requested: bool = field(default=False, repr=False, compare=False)

    def matches_client_identity(
        self,
        *,
        client_route_id: str,
        conversation_id: str,
        task_id: str,
        turn_id: str,
    ) -> bool:
        return all((
            self.client_route_id,
            self.client_conversation_id,
            self.task_id,
            self.client_turn_id,
        )) and (
            self.client_route_id == str(client_route_id or "").strip()
            and self.client_conversation_id == str(conversation_id or "").strip()
            and self.task_id == str(task_id or "").strip()
            and self.client_turn_id == str(turn_id or "").strip()
        )

    def record(self) -> dict:
        data = self.public(include_prompt=True)
        # The timeline is deterministically rebuilt from durable task fields and
        # raw events, so storing a second copy would only inflate the task DB.
        data.pop("run_timeline", None)
        data.pop("recovery_actions", None)
        data["events"] = list(self.events)
        return data

    def public(self, include_prompt: bool = False) -> dict:
        from run_timeline import project_run_timeline

        executor_id = str(self.delegate_agent_id or self.agent_id or "desktop").strip()
        location = desktop_execution_location()
        data = {
            "task_id": self.task_id,
            "agent_id": self.agent_id,
            "contact_id": self.contact_id,
            "source_message_id": self.source_message_id,
            "goal_id": self.goal_id,
            "run_id": self.run_id,
            "conversation_id": self.conversation_id,
            "client_conversation_id": self.client_conversation_id,
            "client_route_id": self.client_route_id,
            "status": self.status,
            "created_at": self.created_at,
            "started_at": self.started_at,
            "updated_at": self.updated_at,
            "completed_at": self.completed_at,
            "elapsed_ms": max(0, (self.completed_at or self.updated_at) - (self.started_at or self.created_at)),
            "result": self.result,
            "error": self.error,
            "first_output_at": self.first_output_at,
            "output_delta_sequence": self.output_delta_sequence,
            "partial_result": (
                {
                    "event_id": self.output_delta_event_id,
                    "sequence": self.output_delta_sequence,
                    "text": self.partial_result_text,
                    "mode": "cumulative",
                    "user_visible": True,
                }
                if self.partial_result_text else {}
            ),
            "exit_code": self.exit_code,
            "status_seq": self.status_seq,
            "thread_id": self.thread_id,
            "turn_id": self.turn_id,
            "client_turn_id": self.client_turn_id,
            "delegate_agent_id": self.delegate_agent_id,
            "current_step": self.current_step,
            "pending_approval": self.pending_approval,
            "events": self.events[-100:],
            "output_files": self.output_files,
            "attachments": self.attachments,
            "retry_of": self.retry_of,
            "task_disposition": self.task_disposition,
            "merged_into_task_id": self.merged_into_task_id,
            "supersedes_task_id": self.supersedes_task_id,
            "intervention_kind": self.intervention_kind,
            "attempt": self.attempt,
            "execution_policy": dict(self.execution_policy),
            "last_progress_at": self.last_progress_at,
            "replan_count": self.replan_count,
            "stall_count": self.stall_count,
            "last_stall_at": self.last_stall_at,
            "recovery_state": self.recovery_state,
            "failure_counts": dict(self.failure_counts),
            "trace_id": self.trace_id,
            "delivery_trace": self.delivery_trace[-MAX_DELIVERY_TRACE_EVENTS:],
            "latency": delivery_trace_metrics(self.delivery_trace),
            "pause_requested": self.pause_requested,
            "pause_reason": self.pause_reason,
            "paused_at": self.paused_at,
            "resume_count": self.resume_count,
            "execution_generation": self.execution_generation,
            "execution_checkpoint": dict(self.execution_checkpoint),
            "takeover": dict(self.takeover),
            "process_id": self.process.pid if self.process is not None and self.process.poll() is None else 0,
            "execution_view": {
                "contract": EXECUTION_LOCATION_CONTRACT,
                "executor_id": executor_id,
                "location_kind": location["kind"],
                "location_id": location["id"],
                "location_name": location["name"],
                "runtime_kind": "desktop_agent",
                "runtime_id": executor_id,
                "runtime_name": "",
                "trusted_source": "paired_desktop",
                "status": self.status,
                "current_step": self.current_step,
                "cancellable": self.status not in TERMINAL_STATES,
                "pausable": self.status in PAUSABLE_STATES,
                "resumable": self.status in {"paused", "takeover"},
                "takeover_available": self.status == "paused",
                "takeover_active": self.status == "takeover",
                "takeover": dict(self.takeover),
                "started_at": self.started_at or self.created_at,
                "completed_at": self.completed_at,
            },
        }
        data["run_timeline"] = project_run_timeline(self)
        if self.status in {"failed", "timed_out", "cancelled", "not_found"}:
            from agent_failure_recovery import recovery_choices

            data["recovery_actions"] = recovery_choices(data)
        else:
            data["recovery_actions"] = []
        if include_prompt:
            data["prompt"] = self.prompt
        return data


class AgentTaskManager:
    def __init__(
        self,
        heartbeat_interval_seconds: float = 5.0,
        stall_timeout_seconds: float | None = None,
        state_path: Path | None = None,
        external_recovery_grace_seconds: float = 30.0,
        latency_tracer: VoiceLatencyTracer | None = None,
        run_event_sink: AgentTaskRunEventSink | None = None,
        legacy_state_path: Path | None = None,
    ) -> None:
        self._lock = threading.RLock()
        self._tasks: dict[str, AgentTask] = {}
        self._recovered_task_ids: set[str] = set()
        self._external_task_ids: set[str] = set()
        self._external_heartbeat_stops: dict[str, threading.Event] = {}
        self._external_watchdog_stops: dict[str, threading.Event] = {}
        self._external_recovery_handlers: dict[
            str,
            tuple[ExternalRecoveryCallback, EventCallback | None, EventCallback | None],
        ] = {}
        self._takeover_timers: dict[str, threading.Timer] = {}
        self._listeners: dict[str, EventCallback] = {}
        self._task_event_callbacks: dict[str, EventCallback] = {}
        self._heartbeat_interval_seconds = max(0.01, float(heartbeat_interval_seconds))
        self._default_stall_timeout_seconds = max(
            0.01,
            float(
                DEFAULT_STALL_TIMEOUT_SECONDS
                if stall_timeout_seconds is None
                else stall_timeout_seconds
            ),
        )
        self._stall_timeout_override = stall_timeout_seconds is not None
        self._external_recovery_grace_seconds = max(
            0.0,
            float(external_recovery_grace_seconds),
        )
        store_path = Path(state_path or TASKS_DB_PATH)
        self._store = AgentTaskStore(store_path)
        self._run_events = run_event_sink or AgentTaskRunEventSink(store_path)
        if self._run_events.ledger.path.resolve() != store_path.resolve():
            raise ValueError("Task store and Run ledger must share one database")
        legacy_path = Path(legacy_state_path) if legacy_state_path is not None else (
            Path.home() / ".galaxyssi" / "agent_tasks.sqlite3"
            if store_path.resolve() == run_kernel_database_path().resolve() else store_path
        )
        migrate_task_run_data(
            self._run_events.ledger, legacy_tasks=legacy_path,
            legacy_events=legacy_path.with_name(RUN_KERNEL_DATABASE_NAME),
        )
        self._latency_tracer = latency_tracer or voice_latency_tracer()
        self._load()

    def subscribe(self, listener: EventCallback) -> str:
        if not callable(listener):
            raise TypeError("Task listener must be callable")
        subscription_id = str(uuid.uuid4())
        with self._lock:
            self._listeners[subscription_id] = listener
        return subscription_id

    def unsubscribe(self, subscription_id: str) -> bool:
        with self._lock:
            return self._listeners.pop(str(subscription_id or ""), None) is not None

    def create(
        self,
        agent_id: str,
        contact_id: str,
        source_message_id: str,
        prompt: str,
        runner: Callable[[AgentTask], str],
        on_event: EventCallback,
        on_result: EventCallback | None = None,
        task_id: str = "",
        conversation_id: str = "",
        client_conversation_id: str = "",
        client_route_id: str = "",
        client_turn_id: str = "",
        attachments: list[str] | None = None,
        retry_of: str = "",
        task_disposition: str = "",
        merged_into_task_id: str = "",
        supersedes_task_id: str = "",
        intervention_kind: str = "",
        attempt: int = 1,
        execution_prompt: str = "",
        execution_policy: dict | None = None,
        trace_id: str = "",
        delivery_trace: list[dict] | None = None,
        goal_id: str = "",
        run_id: str = "",
    ) -> AgentTask:
        from agent_execution_harness import AgentExecutionPolicy, execution_policy_for

        policy = (
            AgentExecutionPolicy.from_public(execution_policy)
            if isinstance(execution_policy, dict) and execution_policy
            else execution_policy_for(
                execution_prompt or prompt,
                attachments=attachments or [],
            )
        )
        resolved_task_id = task_id.strip() or str(uuid.uuid4())
        task = AgentTask(
            task_id=resolved_task_id,
            agent_id=agent_id,
            contact_id=contact_id,
            source_message_id=source_message_id,
            prompt=prompt,
            goal_id=str(goal_id or "").strip() or resolved_task_id,
            run_id=str(run_id or "").strip() or f"task:{resolved_task_id}",
            conversation_id=conversation_id,
            client_conversation_id=client_conversation_id,
            client_route_id=client_route_id,
            client_turn_id=client_turn_id,
            attachments=[str(value) for value in (attachments or [])[:12]],
            retry_of=str(retry_of or ""),
            task_disposition=str(task_disposition or "")[:32],
            merged_into_task_id=str(merged_into_task_id or "")[:200],
            supersedes_task_id=str(supersedes_task_id or "")[:200],
            intervention_kind=str(intervention_kind or "")[:32],
            attempt=max(1, int(attempt or 1)),
            execution_policy=policy.public(),
            trace_id=str(trace_id or "").strip()[:128] or uuid.uuid4().hex,
        )
        with self._lock:
            if task.task_id in self._tasks or self._store.get(task.task_id) is not None:
                raise ValueError(f"Agent task ID already exists: {task.task_id}")
            task.delivery_trace = self._merge_delivery_trace(
                task,
                [],
                delivery_trace or [],
            )
            self._tasks[task.task_id] = task
            self._task_event_callbacks[task.task_id] = on_event
            try:
                self._save_locked(task)
            except Exception:
                self._tasks.pop(task.task_id, None)
                self._task_event_callbacks.pop(task.task_id, None)
                raise
            queue_depth = sum(
                candidate.status in {"accepted", "queued", "starting"}
                for candidate in self._tasks.values()
            )
        self._record_latency(
            task,
            VoiceTraceEvents.AGENT_QUEUE_ENTERED,
            {"queue_depth": queue_depth},
            once=True,
        )
        self._emit(task, on_event)
        self._set_status(task, "queued", on_event)
        threading.Thread(
            target=self._run,
            args=(task, runner, on_event, on_result, task.execution_generation),
            daemon=True,
        ).start()
        return task

    def create_external(
        self, agent_id: str, contact_id: str, source_message_id: str, prompt: str,
        on_event: EventCallback, task_id: str = "", conversation_id: str = "",
        client_conversation_id: str = "",
        client_route_id: str = "", client_turn_id: str = "",
        attachments: list[str] | None = None,
        task_disposition: str = "",
        merged_into_task_id: str = "",
        supersedes_task_id: str = "",
        intervention_kind: str = "",
        execution_prompt: str = "",
        execution_policy: dict | None = None,
        trace_id: str = "",
        delivery_trace: list[dict] | None = None,
        goal_id: str = "",
        run_id: str = "",
    ) -> AgentTask:
        from agent_execution_harness import AgentExecutionPolicy, execution_policy_for

        policy = (
            AgentExecutionPolicy.from_public(execution_policy)
            if isinstance(execution_policy, dict) and execution_policy
            else execution_policy_for(
                execution_prompt or prompt,
                attachments=attachments or [],
            )
        )
        resolved_task_id = task_id.strip() or str(uuid.uuid4())
        task = AgentTask(
            task_id=resolved_task_id, agent_id=agent_id,
            contact_id=contact_id, source_message_id=source_message_id, prompt=prompt,
            goal_id=str(goal_id or "").strip() or resolved_task_id,
            run_id=str(run_id or "").strip() or f"task:{resolved_task_id}",
            conversation_id=conversation_id,
            client_conversation_id=client_conversation_id,
            client_route_id=client_route_id,
            client_turn_id=client_turn_id,
            attachments=[str(value) for value in (attachments or [])[:12]],
            task_disposition=str(task_disposition or "")[:32],
            merged_into_task_id=str(merged_into_task_id or "")[:200],
            supersedes_task_id=str(supersedes_task_id or "")[:200],
            intervention_kind=str(intervention_kind or "")[:32],
            execution_policy=policy.public(),
            trace_id=str(trace_id or "").strip()[:128] or uuid.uuid4().hex,
        )
        with self._lock:
            if task.task_id in self._tasks or self._store.get(task.task_id) is not None:
                raise ValueError(f"Agent task ID already exists: {task.task_id}")
            task.delivery_trace = self._merge_delivery_trace(
                task,
                [],
                delivery_trace or [],
            )
            self._tasks[task.task_id] = task
            self._external_task_ids.add(task.task_id)
            self._task_event_callbacks[task.task_id] = on_event
            try:
                self._save_locked(task)
            except Exception:
                self._tasks.pop(task.task_id, None)
                self._external_task_ids.discard(task.task_id)
                self._task_event_callbacks.pop(task.task_id, None)
                raise
            queue_depth = sum(
                candidate.status in {"accepted", "queued", "starting"}
                for candidate in self._tasks.values()
            )
        self._record_latency(
            task,
            VoiceTraceEvents.AGENT_QUEUE_ENTERED,
            {"queue_depth": queue_depth},
            once=True,
        )
        self._emit(task, on_event)
        return task

    def resume_external(self, task_id: str, on_event: EventCallback) -> AgentTask | None:
        task = self._prepare_recovery(task_id)
        if task is not None:
            with self._lock:
                self._external_task_ids.add(task.task_id)
                self._task_event_callbacks[task.task_id] = on_event
            self._emit(task, on_event)
        return task

    def register_external_recovery(
        self,
        task_id: str,
        recover: ExternalRecoveryCallback,
        *,
        on_event: EventCallback | None = None,
        on_result: EventCallback | None = None,
    ) -> bool:
        """Install a last-resort recovery hook for an externally managed task."""
        if not callable(recover):
            raise TypeError("External recovery callback must be callable")
        clean_task_id = str(task_id or "").strip()
        with self._lock:
            task = self._tasks.get(clean_task_id)
            if (
                task is None
                or clean_task_id not in self._external_task_ids
                or task.status in TERMINAL_STATES
            ):
                return False
            self._external_recovery_handlers[clean_task_id] = (
                recover,
                on_event,
                on_result,
            )
            if task.status == "running":
                self._ensure_external_watchdog_locked(task)
        return True

    def resume(
        self,
        task_id: str,
        runner: Callable[[AgentTask], str],
        on_event: EventCallback,
        on_result: EventCallback | None = None,
    ) -> AgentTask | None:
        task = self._prepare_recovery(task_id)
        if task is None:
            return None
        self._emit(task, on_event)
        self._set_status(task, "queued", on_event)
        threading.Thread(
            target=self._run,
            args=(task, runner, on_event, on_result, task.execution_generation),
            daemon=True,
        ).start()
        return task

    def pause(
        self,
        task_id: str,
        *,
        reason: str = "Paused by user",
        on_event: EventCallback | None = None,
    ) -> AgentTask | None:
        with self._lock:
            task = self._tasks.get(str(task_id or "").strip())
            if task is None:
                return None
            if task.status in TERMINAL_STATES:
                return task
            if task.status in {"paused", "takeover"}:
                snapshot = task.public(include_prompt=True)
                process = None
            elif task.status not in PAUSABLE_STATES and task.status != "pausing":
                return task
            else:
                now = int(time.time() * 1000)
                previous_status = task.status
                previous_step = task.current_step
                task.pause_requested = True
                task.pause_reason = str(reason or "Paused by user")[:500]
                task.paused_at = now
                task.status = "paused"
                task.updated_at = now
                task.last_progress_at = now
                task.status_seq += 1
                task.current_step = "Paused"
                task.recovery_state = "paused"
                task.pending_approval = {}
                task.execution_checkpoint = {
                    "status": previous_status,
                    "thread_id": task.thread_id,
                    "turn_id": task.turn_id,
                    "delegate_agent_id": task.delegate_agent_id,
                    "current_step": previous_step,
                    "event_count": len(task.events),
                    "paused_at": now,
                    "generation": task.execution_generation,
                }
                self._append_control_event_locked(
                    task,
                    "task_paused",
                    "Task paused",
                    task.pause_reason,
                )
                process = task.process
                task.process = None
                self._stop_external_runtime_locked(task.task_id, forget_task=False)
                self._save_locked(task)
                snapshot = task.public(include_prompt=True)
        if process is not None:
            self._terminate(process)
        self._emit_snapshot(snapshot, on_event)
        return task

    def begin_takeover(
        self,
        task_id: str,
        controller: dict,
        *,
        lease_seconds: int = DEFAULT_TAKEOVER_LEASE_SECONDS,
        on_event: EventCallback | None = None,
    ) -> AgentTask | None:
        clean_task_id = str(task_id or "").strip()
        with self._lock:
            task = self._tasks.get(clean_task_id)
            if task is None:
                return None
            if task.status == "takeover":
                return task
            if task.status != "paused":
                return task
            now = int(time.time() * 1000)
            lease_ms = min(
                MAX_TAKEOVER_LEASE_SECONDS,
                max(30, int(lease_seconds or DEFAULT_TAKEOVER_LEASE_SECONDS)),
            ) * 1000
            lease_id = str(uuid.uuid4())
            task.status = "takeover"
            task.updated_at = now
            task.last_progress_at = now
            task.status_seq += 1
            task.current_step = "Manual takeover active"
            task.takeover = {
                "lease_id": lease_id,
                "controller_id": str(controller.get("controller_id") or "")[:200],
                "controller_name": str(controller.get("controller_name") or "User")[:200],
                "controller_platform": str(controller.get("controller_platform") or "")[:64],
                "client_route_id": str(controller.get("client_route_id") or "")[:200],
                "authorization_id": str(controller.get("authorization_id") or "")[:200],
                "started_at": now,
                "expires_at": now + lease_ms,
            }
            self._append_control_event_locked(
                task,
                "manual_takeover_started",
                "Manual takeover started",
                task.takeover["controller_name"],
            )
            self._save_locked(task)
            snapshot = task.public(include_prompt=True)
            previous = self._takeover_timers.pop(clean_task_id, None)
            if previous is not None:
                previous.cancel()
            timer = threading.Timer(
                lease_ms / 1000.0,
                self._expire_takeover,
                args=(clean_task_id, lease_id),
            )
            timer.daemon = True
            self._takeover_timers[clean_task_id] = timer
            timer.start()
        self._emit_snapshot(snapshot, on_event)
        return task

    def release_takeover(
        self,
        task_id: str,
        *,
        reason: str = "Manual takeover ended",
        on_event: EventCallback | None = None,
    ) -> AgentTask | None:
        clean_task_id = str(task_id or "").strip()
        with self._lock:
            task = self._tasks.get(clean_task_id)
            if task is None:
                return None
            if task.status != "takeover":
                return task
            timer = self._takeover_timers.pop(clean_task_id, None)
            if timer is not None:
                timer.cancel()
            now = int(time.time() * 1000)
            task.status = "paused"
            task.updated_at = now
            task.last_progress_at = now
            task.status_seq += 1
            task.current_step = "Paused"
            task.pause_reason = str(reason or "Manual takeover ended")[:500]
            task.takeover = {}
            self._append_control_event_locked(
                task,
                "manual_takeover_ended",
                "Manual takeover ended",
                task.pause_reason,
            )
            self._save_locked(task)
            snapshot = task.public(include_prompt=True)
        self._emit_snapshot(snapshot, on_event)
        return task

    def continue_task(
        self,
        task_id: str,
        runner: Callable[[AgentTask], str],
        on_event: EventCallback,
        on_result: EventCallback | None = None,
        *,
        checkpoint: dict | None = None,
    ) -> AgentTask | None:
        clean_task_id = str(task_id or "").strip()
        with self._lock:
            task = self._tasks.get(clean_task_id)
            if task is None or task.status not in {"paused", "takeover"}:
                return task
            timer = self._takeover_timers.pop(clean_task_id, None)
            if timer is not None:
                timer.cancel()
            now = int(time.time() * 1000)
            previous_takeover = dict(task.takeover)
            task.pause_requested = False
            task.pause_reason = ""
            task.paused_at = 0
            task.takeover = {}
            task.status = "accepted"
            task.resume_count += 1
            task.execution_generation += 1
            task.completed_at = 0
            task.result = ""
            task.error = ""
            task.exit_code = None
            task.current_step = "Resuming from the latest checkpoint"
            task.updated_at = now
            task.last_progress_at = now
            task.status_seq += 1
            task.recovery_state = "healthy"
            task.execution_checkpoint = {
                **dict(task.execution_checkpoint),
                **dict(checkpoint or {}),
                "resumed_at": now,
                "resume_count": task.resume_count,
                "previous_takeover": previous_takeover,
                "generation": task.execution_generation,
            }
            self._append_control_event_locked(
                task,
                "task_resumed",
                "Task resumed",
                "Continuing from the latest Desktop state",
            )
            self._save_locked(task)
            generation = task.execution_generation
        self._emit(task, on_event)
        self._set_status(task, "queued", on_event)
        threading.Thread(
            target=self._run,
            args=(task, runner, on_event, on_result, generation),
            daemon=True,
        ).start()
        return task

    def update(
        self, task_id: str, status: str, on_event: EventCallback | None = None,
        *, thread_id: str | None = None, turn_id: str | None = None,
        delegate_agent_id: str | None = None,
        task_disposition: str | None = None,
        merged_into_task_id: str | None = None,
        supersedes_task_id: str | None = None,
        intervention_kind: str | None = None,
        current_step: str | None = None, result: str | None = None,
        error: str | None = None,
        approval_request: dict | None = None,
    ) -> AgentTask | None:
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None or task.status in TERMINAL_STATES:
                return task
            if (
                (task.pause_requested or task.status in {"paused", "takeover"})
                and status not in {"pausing", "paused", "takeover"}
            ):
                return task
            previous_status = task.status
            now = int(time.time() * 1000)
            meaningful_progress = (
                status != task.status
                or (thread_id is not None and thread_id != task.thread_id)
                or (turn_id is not None and turn_id != task.turn_id)
                or (
                    task_disposition is not None
                    and task_disposition != task.task_disposition
                )
                or (
                    merged_into_task_id is not None
                    and merged_into_task_id != task.merged_into_task_id
                )
                or (
                    supersedes_task_id is not None
                    and supersedes_task_id != task.supersedes_task_id
                )
                or (
                    intervention_kind is not None
                    and intervention_kind != task.intervention_kind
                )
                or (current_step is not None and current_step != task.current_step)
                or (result is not None and result != task.result)
                or (error is not None and error != task.error)
            )
            task.status = status
            task.updated_at = now
            if meaningful_progress:
                task.last_progress_at = now
                task.recovery_state = "healthy"
            task.status_seq += 1
            started_now = not task.started_at and status not in {"accepted", "queued"}
            if started_now:
                task.started_at = now
            if thread_id is not None:
                task.thread_id = thread_id
            if turn_id is not None:
                task.turn_id = turn_id
            if delegate_agent_id is not None:
                task.delegate_agent_id = delegate_agent_id
            if task_disposition is not None:
                task.task_disposition = str(task_disposition or "")[:32]
            if merged_into_task_id is not None:
                task.merged_into_task_id = str(merged_into_task_id or "")[:200]
            if supersedes_task_id is not None:
                task.supersedes_task_id = str(supersedes_task_id or "")[:200]
            if intervention_kind is not None:
                task.intervention_kind = str(intervention_kind or "")[:32]
            if current_step is not None:
                task.current_step = current_step
            if approval_request is not None:
                task.pending_approval = dict(approval_request)
            elif status != "waiting_approval":
                task.pending_approval = {}
            if result is not None:
                task.result = result
            if error is not None:
                task.error = error
            if status in TERMINAL_STATES or status == "interrupted":
                task.completed_at = now
                task.output_files = self._task_artifacts(task.task_id)
            if status in TERMINAL_STATES:
                task.current_step = ""
                task.pending_approval = {}
                task.recovery_state = (
                    "exhausted"
                    if status == "timed_out" else
                    "healthy"
                    if status == "completed" else
                    "stopped"
                )
            if task.task_id in self._external_task_ids and status == "running":
                self._ensure_external_heartbeat_locked(task, on_event)
                self._ensure_external_watchdog_locked(task)
            elif status in TERMINAL_STATES or status == "interrupted":
                self._stop_external_runtime_locked(task.task_id, forget_task=True)
            self._save_locked(task)
        if started_now or (previous_status in {"accepted", "queued", "starting"} and status == "running"):
            self._record_latency(
                task,
                VoiceTraceEvents.AGENT_RUN_STARTED,
                {"task_status": status},
                once=True,
            )
        if meaningful_progress and any((current_step, result)):
            self._record_latency(
                task,
                VoiceTraceEvents.AGENT_FIRST_PROGRESS,
                {"task_status": status},
                once=True,
            )
        if status in TERMINAL_STATES:
            self._record_latency(
                task,
                VoiceTraceEvents.AGENT_COMPLETED,
                {"task_status": status, "success": status == "completed"},
                once=True,
            )
        self._emit(task, on_event)
        return task

    def add_event(
        self,
        task_id: str,
        kind: str,
        title: str,
        *,
        event_id: str = "",
        status: str = "completed",
        detail: str = "",
        metadata: dict | None = None,
        on_event: EventCallback | None = None,
    ) -> AgentTask | None:
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None or task.status in TERMINAL_STATES:
                return task
            if task.pause_requested or task.status in {"paused", "takeover"}:
                return task
            now = int(time.time() * 1000)
            stable_event_id = str(event_id or "").strip()[:200] or str(uuid.uuid4())
            existing_index = next((
                index for index, candidate in enumerate(task.events)
                if str(candidate.get("event_id") or "") == stable_event_id
            ), -1)
            existing = task.events[existing_index] if existing_index >= 0 else None
            identity = self._task_identity(task)
            event = {
                "event_id": stable_event_id,
                "created_at": int((existing or {}).get("created_at") or now),
                "updated_at": now,
                "kind": str(kind or "step")[:48],
                "title": str(title or "Task step")[:240],
                "status": str(status or "completed")[:32],
                "detail": str(detail or "")[:4_000],
                "metadata": {
                    **identity,
                    **dict((existing or {}).get("metadata") or {}),
                    **dict(metadata or {}),
                },
            }
            try:
                encoded = json.dumps(event["metadata"], ensure_ascii=False, separators=(",", ":"))
                if len(encoded.encode("utf-8")) > 16_384:
                    event["metadata"] = {"truncated": True}
            except Exception:
                event["metadata"] = {}
            if existing_index >= 0:
                task.events.pop(existing_index)
            task.events.append(event)
            del task.events[:-MAX_TASK_EVENTS]
            if event["kind"] == "replan":
                try:
                    reported_replan = max(
                        0,
                        int(event["metadata"].get("replan") or 0),
                    )
                except (TypeError, ValueError):
                    reported_replan = 0
                task.replan_count = max(task.replan_count, reported_replan)
                if str(event["metadata"].get("source") or "") in {
                    "stall_watchdog",
                    "task_manager_watchdog",
                }:
                    task.stall_count = max(task.stall_count, reported_replan)
            if task.status in {"accepted", "queued", "starting", "recovering"}:
                task.status = "running"
                if not task.started_at:
                    task.started_at = now
            task.current_step = event["title"]
            task.updated_at = now
            task.last_progress_at = now
            task.recovery_state = (
                "recovering"
                if event["kind"] in {"replan", "recovery"} else
                "healthy"
            )
            task.status_seq += 1
            self._save_locked(task)
        self._record_latency(
            task,
            VoiceTraceEvents.AGENT_RUN_STARTED,
            {"task_status": task.status},
            once=True,
        )
        self._record_latency(
            task,
            VoiceTraceEvents.AGENT_FIRST_PROGRESS,
            {"task_status": task.status},
            once=True,
        )
        self._emit(task, on_event)
        return task

    def append_trace(
        self,
        task_id: str,
        stage: str,
        detail: str = "",
        *,
        at: int = 0,
        once: bool = False,
        meaningful_progress: bool = False,
    ) -> AgentTask | None:
        with self._lock:
            task = self._tasks.get(str(task_id or ""))
            if task is None:
                return None
            clean_stage = str(stage or "").strip()[:96]
            if not clean_stage:
                return task
            if once and any(
                str(item.get("stage") or "") == clean_stage
                for item in task.delivery_trace
            ):
                return task
            event_at = max(0, int(at or time.time() * 1000))
            entry = self._trace_entry(
                task,
                clean_stage,
                event_at,
                str(detail or "")[:240],
            )
            signature = self._trace_signature(entry)
            if any(
                self._trace_signature(item) == signature
                for item in task.delivery_trace
            ):
                return task
            task.delivery_trace.append(entry)
            del task.delivery_trace[:-MAX_DELIVERY_TRACE_EVENTS]
            task.updated_at = max(task.updated_at, event_at)
            if meaningful_progress:
                task.last_progress_at = max(task.last_progress_at, event_at)
                task.status_seq += 1
            self._save_locked(task)
        if meaningful_progress:
            self._record_latency(
                task,
                VoiceTraceEvents.AGENT_FIRST_PROGRESS,
                {"task_status": task.status},
                once=True,
            )
        if clean_stage == "agent_first_output":
            self._record_latency(
                task,
                VoiceTraceEvents.AGENT_FIRST_PARTIAL_RESULT,
                {"task_status": task.status},
                once=True,
            )
        return task

    def record_partial_result(
        self,
        task_id: str,
        text: str,
        *,
        sequence: int = 0,
        event_id: str = "",
        at: int = 0,
        on_event: EventCallback | None = None,
    ) -> AgentTask | None:
        """Persist the latest cumulative user-visible Agent output snapshot."""
        clean_text = str(text or "")[:MAX_PARTIAL_RESULT_CHARACTERS]
        if not clean_text.strip():
            return self.get(task_id)
        with self._lock:
            task = self._tasks.get(str(task_id or ""))
            if task is None or task.status in TERMINAL_STATES:
                return task
            next_sequence = max(1, int(sequence or task.output_delta_sequence + 1))
            if next_sequence < task.output_delta_sequence:
                return task
            if (
                next_sequence == task.output_delta_sequence
                and clean_text == task.partial_result_text
            ):
                return task
            if next_sequence == task.output_delta_sequence:
                return task
            now = max(0, int(at or time.time() * 1000))
            task.output_delta_sequence = next_sequence
            task.output_delta_event_id = (
                str(event_id or "").strip()[:200]
                or f"partial:{task.task_id}:{next_sequence}"
            )
            task.partial_result_text = clean_text
            if not task.first_output_at:
                task.first_output_at = now
            if task.status in {"accepted", "queued", "starting", "recovering"}:
                task.status = "running"
                if not task.started_at:
                    task.started_at = now
            task.updated_at = max(task.updated_at, now)
            task.last_progress_at = max(task.last_progress_at, now)
            task.recovery_state = "healthy"
            task.status_seq += 1
            self._save_locked(task)
        self._record_latency(
            task,
            VoiceTraceEvents.AGENT_FIRST_PARTIAL_RESULT,
            {"task_status": task.status},
            once=True,
        )
        self._emit(task, on_event)
        return task

    def merge_trace(self, task_id: str, trace: list[dict]) -> AgentTask | None:
        with self._lock:
            task = self._tasks.get(str(task_id or ""))
            if task is None:
                return None
            merged = self._merge_delivery_trace(
                task,
                task.delivery_trace,
                trace,
            )
            if merged != task.delivery_trace:
                task.delivery_trace = merged
                task.updated_at = max(
                    task.updated_at,
                    max(
                        (
                            int(item.get("at") or 0)
                            for item in task.delivery_trace
                        ),
                        default=task.updated_at,
                    ),
                )
                self._save_locked(task)
            return task

    def _run(
        self,
        task: AgentTask,
        runner: Callable[[AgentTask], str],
        on_event: EventCallback,
        on_result: EventCallback | None,
        generation: int,
    ) -> None:
        with self._lock:
            if task.execution_generation != generation:
                return
            paused = task.pause_requested or task.status in {"paused", "takeover"}
        if paused:
            return
        if task.cancel_requested:
            self._finish(task, "cancelled", on_event)
            return
        if not task.started_at:
            task.started_at = int(time.time() * 1000)
        self._record_latency(
            task,
            VoiceTraceEvents.AGENT_RUN_STARTED,
            {"task_status": "running"},
            once=True,
        )
        self._set_status(task, "running", on_event)
        heartbeat_stop = threading.Event()
        heartbeat = threading.Thread(target=self._heartbeat, args=(task, on_event, heartbeat_stop), daemon=True)
        heartbeat.start()
        watchdog_stop = threading.Event()
        threading.Thread(
            target=self._progress_watchdog,
            args=(task, on_event, on_result, watchdog_stop),
            daemon=True,
            name=f"galaxyssi-task-progress-{task.task_id[:8]}",
        ).start()
        try:
            result = runner(task)
            transitioned = False
            with self._lock:
                stale_generation = task.execution_generation != generation
                paused = task.pause_requested or task.status in {"paused", "takeover"}
            if stale_generation or paused:
                return
            if task.cancel_requested:
                transitioned = self._finish(task, "cancelled", on_event, generation=generation)
            elif task.status == "timed_out" or self._looks_timed_out(result):
                transitioned = self._finish(
                    task,
                    "timed_out",
                    on_event,
                    result=result,
                    generation=generation,
                )
            elif self._looks_failed(result):
                transitioned = self._finish(
                    task,
                    "failed",
                    on_event,
                    result=result,
                    error=result[:240],
                    generation=generation,
                )
            else:
                transitioned = self._finish(
                    task,
                    "completed",
                    on_event,
                    result=result,
                    generation=generation,
                )
            if transitioned and not task.cancel_requested and task.result and on_result is not None:
                self._emit(task, on_result)
        except Exception as exc:
            with self._lock:
                stale_generation = task.execution_generation != generation
                paused = task.pause_requested or task.status in {"paused", "takeover"}
            if not stale_generation and not paused:
                self._finish(
                    task,
                    "failed",
                    on_event,
                    error=str(exc)[:500],
                    generation=generation,
                )
        finally:
            watchdog_stop.set()
            heartbeat_stop.set()
            with self._lock:
                if task.execution_generation == generation:
                    task.process = None

    def _heartbeat(self, task: AgentTask, on_event: EventCallback, stop: threading.Event) -> None:
        while not stop.wait(self._heartbeat_interval_seconds):
            with self._lock:
                if task.status != "running":
                    return
                task.updated_at = int(time.time() * 1000)
                task.status_seq += 1
                self._save_locked(task)
                snapshot = task.public()
            self._emit_snapshot(snapshot, on_event)

    def _progress_watchdog(
        self,
        task: AgentTask,
        on_event: EventCallback,
        on_result: EventCallback | None,
        stop: threading.Event,
    ) -> None:
        while not stop.wait(min(5.0, max(0.01, self._stall_timeout_seconds(task) / 4))):
            with self._lock:
                if task.status in TERMINAL_STATES:
                    return
                if task.status in {"waiting_approval", "waiting_input", "paused"}:
                    continue
                now = int(time.time() * 1000)
                stalled_for = max(0.0, (now - task.last_progress_at) / 1000.0)
                stall_timeout = self._stall_timeout_seconds(task)
                if stalled_for < stall_timeout:
                    continue
                max_replans = max(0, int(task.execution_policy.get("max_replans") or 0))
                process = task.process
                task.process = None
                if task.replan_count < max_replans:
                    task.replan_count += 1
                    task.stall_count += 1
                    task.last_stall_at = now
                    task.recovery_state = "recovering"
                    task.last_progress_at = now
                    task.updated_at = now
                    task.status_seq += 1
                    event = {
                        "event_id": f"execution-stall-replan:{task.replan_count}",
                        "created_at": now,
                        "updated_at": now,
                        "kind": "replan",
                        "title": "Replanning after stalled execution",
                        "status": "running",
                        "detail": f"No meaningful progress for {stall_timeout:g} seconds",
                        "metadata": {
                            **self._task_identity(task),
                            "replan": task.replan_count,
                            "reason": "no_progress_timeout",
                        },
                    }
                    task.events.append(event)
                    del task.events[:-MAX_TASK_EVENTS]
                    task.current_step = event["title"]
                    self._save_locked(task)
                    snapshot = task.public()
                    should_replan = True
                else:
                    task.recovery_state = "exhausted"
                    task.last_stall_at = now
                    self._save_locked(task)
                    snapshot = {}
                    should_replan = False
            if process is not None:
                self._terminate(process)
            if should_replan:
                self._emit_snapshot(snapshot, on_event)
                continue
            prefers_chinese = any("\u4e00" <= character <= "\u9fff" for character in task.prompt)
            result = (
                "\u4efb\u52a1\u957f\u65f6\u95f4\u6ca1\u6709\u5b9e\u8d28\u8fdb\u5c55\uff0c\u5df2\u5728\u5b8c\u6210\u81ea\u52a8\u91cd\u89c4\u5212\u540e\u505c\u6b62\u3002"
                if prefers_chinese else
                "The task made no meaningful progress and stopped after exhausting automatic replanning."
            )
            transitioned = self._finish(
                task,
                "timed_out",
                on_event,
                result=result,
                error=f"No meaningful progress for {stall_timeout:g} seconds",
            )
            if transitioned and on_result is not None:
                self._emit(task, on_result)
            return

    def _stall_timeout_seconds(self, task: AgentTask) -> float:
        if self._stall_timeout_override:
            return self._default_stall_timeout_seconds
        try:
            value = float(task.execution_policy.get("no_progress_timeout_seconds") or 0)
        except (TypeError, ValueError):
            value = 0
        return max(30.0, value) if value else self._default_stall_timeout_seconds

    def _ensure_external_heartbeat_locked(
        self,
        task: AgentTask,
        on_event: EventCallback | None,
    ) -> None:
        if on_event is None:
            return
        existing = self._external_heartbeat_stops.get(task.task_id)
        if existing is not None and not existing.is_set():
            return
        stop = threading.Event()
        self._external_heartbeat_stops[task.task_id] = stop
        threading.Thread(
            target=self._external_heartbeat,
            args=(task.task_id, on_event, stop),
            daemon=True,
            name=f"galaxyssi-task-heartbeat-{task.task_id[:8]}",
        ).start()

    def _ensure_external_watchdog_locked(self, task: AgentTask) -> None:
        if task.task_id not in self._external_recovery_handlers:
            return
        existing = self._external_watchdog_stops.get(task.task_id)
        if existing is not None and not existing.is_set():
            return
        stop = threading.Event()
        self._external_watchdog_stops[task.task_id] = stop
        threading.Thread(
            target=self._external_progress_watchdog,
            args=(task.task_id, stop),
            daemon=True,
            name=f"galaxyssi-external-watchdog-{task.task_id[:8]}",
        ).start()

    def _external_progress_watchdog(
        self,
        task_id: str,
        stop: threading.Event,
    ) -> None:
        try:
            while True:
                with self._lock:
                    task = self._tasks.get(task_id)
                    if (
                        task is None
                        or task_id not in self._external_task_ids
                        or task.status in TERMINAL_STATES
                        or task.status == "interrupted"
                    ):
                        return
                    timeout = (
                        self._stall_timeout_seconds(task)
                        + self._external_recovery_grace_seconds
                    )
                    binding = self._external_recovery_handlers.get(task_id)
                if binding is None:
                    return
                if stop.wait(min(5.0, max(0.01, timeout / 4))):
                    return
                with self._lock:
                    task = self._tasks.get(task_id)
                    binding = self._external_recovery_handlers.get(task_id)
                    if (
                        task is None
                        or binding is None
                        or task.status in TERMINAL_STATES
                        or task.status == "interrupted"
                    ):
                        return
                    if task.status in {"waiting_approval", "waiting_input", "paused"}:
                        continue
                    if task.status != "running":
                        continue
                    now = int(time.time() * 1000)
                    stalled_for = max(0.0, (now - task.last_progress_at) / 1000.0)
                    timeout = (
                        self._stall_timeout_seconds(task)
                        + self._external_recovery_grace_seconds
                    )
                    if stalled_for < timeout:
                        continue
                    recover, on_event, on_result = binding
                    max_replans = max(
                        0,
                        int(task.execution_policy.get("max_replans") or 0),
                    )
                    if task.replan_count >= max_replans:
                        task.recovery_state = "exhausted"
                        task.last_stall_at = now
                        self._save_locked(task)
                        should_recover = False
                        snapshot = {}
                    else:
                        task.replan_count += 1
                        task.stall_count += 1
                        task.last_stall_at = now
                        task.last_progress_at = now
                        task.updated_at = now
                        task.recovery_state = "recovering"
                        task.status_seq += 1
                        reason = (
                            f"No meaningful external progress for {timeout:g} seconds"
                        )
                        task.events.append({
                            "event_id": f"external-stall-recovery:{task.replan_count}",
                            "created_at": now,
                            "updated_at": now,
                            "kind": "replan",
                            "title": "Recovering stalled external Agent",
                            "status": "running",
                            "detail": reason,
                            "metadata": {
                                **self._task_identity(task),
                                "replan": task.replan_count,
                                "max_replans": max_replans,
                                "reason": "external_no_progress_timeout",
                            },
                        })
                        del task.events[:-MAX_TASK_EVENTS]
                        task.current_step = "Recovering stalled external Agent"
                        self._save_locked(task)
                        snapshot = task.public()
                        should_recover = True
                if not should_recover:
                    self._finish_external_stall(
                        task_id,
                        timeout,
                        on_event,
                        on_result,
                    )
                    return
                self._emit_snapshot(snapshot, on_event)
                reason = (
                    f"No meaningful external progress for {timeout:g} seconds"
                )
                try:
                    recovered = bool(recover(snapshot, reason))
                except Exception:
                    recovered = False
                if recovered:
                    continue
                with self._lock:
                    current = self._tasks.get(task_id)
                    if current is None or current.status in TERMINAL_STATES:
                        return
                    current.failure_counts["stall_recovery"] = (
                        int(current.failure_counts.get("stall_recovery") or 0) + 1
                    )
                    current.recovery_state = "stalled"
                    current.updated_at = int(time.time() * 1000)
                    current.last_progress_at = current.updated_at
                    self._save_locked(current)
                    exhausted = current.replan_count >= max_replans
                if exhausted:
                    self._finish_external_stall(
                        task_id,
                        timeout,
                        on_event,
                        on_result,
                    )
                    return
        finally:
            with self._lock:
                if self._external_watchdog_stops.get(task_id) is stop:
                    self._external_watchdog_stops.pop(task_id, None)

    def _finish_external_stall(
        self,
        task_id: str,
        timeout: float,
        on_event: EventCallback | None,
        on_result: EventCallback | None,
    ) -> None:
        with self._lock:
            task = self._tasks.get(task_id)
        if task is None:
            return
        prefers_chinese = any(
            "\u4e00" <= character <= "\u9fff" for character in task.prompt
        )
        result = (
            "\u5916\u90e8 Agent \u957f\u65f6\u95f4\u6ca1\u6709\u5b9e\u8d28\u8fdb\u5c55\uff0c"
            "\u5df2\u5728\u81ea\u52a8\u6062\u590d\u5c1d\u8bd5\u7528\u5c3d\u540e\u505c\u6b62\u3002"
            if prefers_chinese else
            "The external Agent made no meaningful progress and stopped after "
            "exhausting automatic recovery."
        )
        transitioned = self._finish(
            task,
            "timed_out",
            on_event,
            result=result,
            error=f"No meaningful external progress for {timeout:g} seconds",
        )
        if transitioned and on_result is not None:
            self._emit(task, on_result)

    def _external_heartbeat(
        self,
        task_id: str,
        on_event: EventCallback,
        stop: threading.Event,
    ) -> None:
        try:
            while not stop.wait(self._heartbeat_interval_seconds):
                with self._lock:
                    task = self._tasks.get(task_id)
                    if (
                        task is None
                        or task_id not in self._external_task_ids
                        or task.status in TERMINAL_STATES
                        or task.status == "interrupted"
                    ):
                        return
                    if task.status != "running":
                        continue
                    task.updated_at = int(time.time() * 1000)
                    task.status_seq += 1
                    self._save_locked(task)
                    snapshot = task.public()
                self._emit_snapshot(snapshot, on_event)
        finally:
            with self._lock:
                if self._external_heartbeat_stops.get(task_id) is stop:
                    self._external_heartbeat_stops.pop(task_id, None)

    def _stop_external_heartbeat_locked(self, task_id: str, *, forget_task: bool) -> None:
        stop = self._external_heartbeat_stops.pop(task_id, None)
        if stop is not None:
            stop.set()
        if forget_task:
            self._external_task_ids.discard(task_id)

    def _stop_external_runtime_locked(self, task_id: str, *, forget_task: bool) -> None:
        self._stop_external_heartbeat_locked(task_id, forget_task=False)
        watchdog = self._external_watchdog_stops.pop(task_id, None)
        if watchdog is not None:
            watchdog.set()
        self._external_recovery_handlers.pop(task_id, None)
        if forget_task:
            self._external_task_ids.discard(task_id)

    @staticmethod
    def _looks_timed_out(result: str) -> bool:
        normalized = result.lower()
        return result.startswith("[") and ("timeout" in normalized or "timed out" in normalized or "\u8d85\u65f6" in result)

    @staticmethod
    def _looks_failed(result: str) -> bool:
        if not result.startswith("["):
            return False
        normalized = result.lower()
        return any(marker in normalized for marker in (
            "failed", "failure", "timeout", "not configured", "not detected", "no response",
            "\u5931\u8d25", "\u8d85\u65f6", "\u672a\u914d\u7f6e", "\u672a\u68c0\u6d4b", "\u65e0\u54cd\u5e94", "\u672a\u8fde\u63a5",
        ))

    def register_process(self, task_id: str, process: subprocess.Popen) -> None:
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None:
                return
            task.process = process
            if (
                task.cancel_requested
                or task.pause_requested
                or task.status in {"paused", "takeover"}
            ):
                self._terminate(process)

    def record_exit_code(self, task_id: str, exit_code: int | None) -> None:
        with self._lock:
            task = self._tasks.get(task_id)
            if task is not None:
                task.exit_code = exit_code
                task.updated_at = int(time.time() * 1000)
                self._save_locked(task)

    def cancel(self, task_id: str, on_event: EventCallback | None = None) -> AgentTask | None:
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None:
                return task
            if task.status in TERMINAL_STATES:
                terminal_task = task
                process = None
            else:
                terminal_task = None
                task.cancel_requested = True
                timer = self._takeover_timers.pop(task.task_id, None)
                if timer is not None:
                    timer.cancel()
                process = task.process
        if terminal_task is not None:
            self._emit(terminal_task, on_event)
            return terminal_task
        if process is not None:
            self._terminate(process)
        transitioned = self._finish(task, "cancelled", on_event)
        if not transitioned and on_event is not None:
            try:
                on_event(task.public())
            except Exception:
                pass
        return task

    def get(self, task_id: str) -> AgentTask | None:
        with self._lock:
            task = self._tasks.get(task_id)
            if task is not None:
                return task
            record = self._store.get(task_id)
            if record is None:
                return None
            task = self._decode_task(record)
            self._tasks[task.task_id] = task
            return task

    def run_events(
        self,
        task_id: str,
        *,
        after_sequence: int = 0,
        limit: int | None = None,
    ) -> list[dict]:
        task = self.get(str(task_id or "").strip())
        run_id = task.run_id if task is not None else f"task:{str(task_id or '').strip()}"
        return self._run_events.events(
            run_id,
            after_sequence=max(0, int(after_sequence or 0)),
            limit=None if limit is None else max(1, int(limit)),
        )

    def run_snapshot(self, task_id: str) -> dict | None:
        task = self.get(str(task_id or "").strip())
        run_id = task.run_id if task is not None else f"task:{str(task_id or '').strip()}"
        return self._run_events.snapshot(run_id)

    def get_scoped(
        self,
        task_id: str,
        *,
        client_route_id: str,
        conversation_id: str,
        turn_id: str,
    ) -> AgentTask | None:
        task = self.get(task_id)
        if task is None or not task.matches_client_identity(
            client_route_id=client_route_id,
            conversation_id=conversation_id,
            task_id=task_id,
            turn_id=turn_id,
        ):
            return None
        return task

    def cancel_scoped(
        self,
        task_id: str,
        *,
        client_route_id: str,
        conversation_id: str,
        turn_id: str,
        on_event: EventCallback | None = None,
    ) -> AgentTask | None:
        task = self.get_scoped(
            task_id,
            client_route_id=client_route_id,
            conversation_id=conversation_id,
            turn_id=turn_id,
        )
        if task is None:
            return None
        return self.cancel(task.task_id, on_event)

    def active_for_conversation(
        self,
        conversation_id: str,
        *,
        agent_id: str = "",
        client_route_id: str = "",
        exclude_task_id: str = "",
    ) -> AgentTask | None:
        clean_conversation_id = str(conversation_id or "").strip()
        clean_agent_id = str(agent_id or "").strip()
        clean_route_id = str(client_route_id or "").strip()
        if not clean_conversation_id:
            return None
        with self._lock:
            candidates = [
                task for task in self._tasks.values()
                if task.task_id != exclude_task_id
                and task.conversation_id == clean_conversation_id
                and task.status not in TERMINAL_STATES
                and task.status != "interrupted"
                and task.status not in PAUSED_STATES
                and not task.cancel_requested
                and (not clean_agent_id or task.agent_id == clean_agent_id)
                and (
                    not clean_route_id
                    or task.client_route_id == clean_route_id
                )
            ]
            return max(candidates, key=lambda item: (item.created_at, item.task_id), default=None)

    def list(self, limit: int = 100, include_prompt: bool = False) -> list[dict]:
        with self._lock:
            records = self._store.list_recent(max(1, min(int(limit or 100), 500)))
            return [
                self._public_with_output_preview(
                    self._tasks.get(str(record.get("task_id") or ""))
                    or self._decode_task(record),
                    record,
                    include_prompt=include_prompt,
                )
                for record in records
            ]

    def public_preview(self, task_id: str, include_prompt: bool = False) -> dict | None:
        clean_id = str(task_id or "").strip()
        if not clean_id:
            return None
        with self._lock:
            record = self._store.get(clean_id, hydrate_output=False)
            if record is None:
                return None
            task = self._tasks.get(clean_id) or self._decode_task(record)
            return self._public_with_output_preview(
                task,
                record,
                include_prompt=include_prompt,
            )

    def output_page(
        self,
        task_id: str,
        *,
        offset: int = 0,
        limit: int = 2,
    ) -> dict | None:
        with self._lock:
            return self._store.output_page(task_id, offset=offset, limit=limit)

    def conversation_messages(
        self,
        conversation_id: str,
        limit: int | None = None,
        source_prefix: str | None = "desktop:",
        after_cursor: tuple[int, str] = (0, ""),
    ) -> list[dict]:
        clean_id = str(conversation_id or "").strip()
        if not clean_id:
            return []
        with self._lock:
            records = self._store.conversation(
                clean_id,
                source_prefix=source_prefix,
                after_cursor=after_cursor,
                limit=limit,
            )
            return [
                {
                    "task_id": record.get("task_id"),
                    "prompt": record.get("prompt"),
                    "result": record.get("result"),
                    "status": record.get("status"),
                    "agent_id": record.get("agent_id"),
                    "client_turn_id": record.get("client_turn_id"),
                    "created_at": record.get("created_at"),
                }
                for record in records
                if str(record.get("prompt") or "")
            ]

    def delete_conversation(self, conversation_id: str, task_ids: set[str] | None = None) -> list[str]:
        clean_id = str(conversation_id or "").strip()
        allowed_ids = {str(value).strip() for value in (task_ids or set()) if str(value).strip()}
        if not clean_id and not allowed_ids:
            return []
        with self._lock:
            deleted = self._store.delete_conversation(clean_id, allowed_ids)
            for task_id in deleted:
                task = self._tasks.pop(task_id, None)
                if task is not None and task.process is not None:
                    self._terminate(task.process)
                timer = self._takeover_timers.pop(task_id, None)
                if timer is not None:
                    timer.cancel()
                self._recovered_task_ids.discard(task_id)
                self._stop_external_runtime_locked(task_id, forget_task=True)
        return deleted

    def drain_recovered(self, limit: int = 100) -> list[dict]:
        with self._lock:
            candidates = sorted(
                (self._tasks[task_id] for task_id in self._recovered_task_ids if task_id in self._tasks),
                key=lambda item: item.updated_at,
                reverse=True,
            )[:max(1, min(limit, 500))]
            for task in candidates:
                self._recovered_task_ids.discard(task.task_id)
            return [task.public(include_prompt=True) for task in candidates]

    def retain_recovered(self, task_id: str) -> None:
        with self._lock:
            if task_id in self._tasks:
                self._recovered_task_ids.add(task_id)

    def _prepare_recovery(self, task_id: str) -> AgentTask | None:
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None or task.status != "recovering":
                return None
            now = int(time.time() * 1000)
            task.status = "accepted"
            task.updated_at = now
            task.completed_at = 0
            task.result = ""
            task.error = ""
            task.exit_code = None
            task.current_step = ""
            task.pending_approval = {}
            task.process = None
            task.cancel_requested = False
            task.last_progress_at = now
            task.recovery_state = "healthy"
            task.status_seq += 1
            task.events.append({
                "event_id": str(uuid.uuid4()),
                "created_at": now,
                "kind": "recovery",
                "title": "Resuming after Desktop restart",
                "status": "running",
                "detail": f"Automatic recovery attempt {task.attempt}",
                "metadata": {
                    **self._task_identity(task),
                    "attempt": task.attempt,
                },
            })
            task.delivery_trace = self._merge_delivery_trace(
                task,
                task.delivery_trace,
                [{
                    "stage": "desktop_task_resumed",
                    "at": now,
                    "detail": f"attempt={task.attempt}",
                }],
            )
            self._save_locked(task)
        return task

    def _append_control_event_locked(
        self,
        task: AgentTask,
        kind: str,
        title: str,
        detail: str = "",
    ) -> None:
        now = int(time.time() * 1000)
        task.events.append({
            "event_id": f"{kind}:{task.status_seq}:{uuid.uuid4().hex[:8]}",
            "created_at": now,
            "updated_at": now,
            "kind": str(kind or "task_control")[:48],
            "title": str(title or "Task control updated")[:240],
            "status": "completed",
            "detail": str(detail or "")[:4_000],
            "metadata": {
                **self._task_identity(task),
                "execution_generation": task.execution_generation,
                "resume_count": task.resume_count,
            },
        })
        del task.events[:-MAX_TASK_EVENTS]

    def _expire_takeover(self, task_id: str, lease_id: str) -> None:
        with self._lock:
            task = self._tasks.get(task_id)
            if (
                task is None
                or task.status != "takeover"
                or str(task.takeover.get("lease_id") or "") != lease_id
            ):
                return
            now = int(time.time() * 1000)
            task.status = "paused"
            task.updated_at = now
            task.last_progress_at = now
            task.status_seq += 1
            task.current_step = "Paused"
            task.pause_reason = "Manual takeover lease expired"
            task.takeover = {}
            self._takeover_timers.pop(task_id, None)
            self._append_control_event_locked(
                task,
                "manual_takeover_expired",
                "Manual takeover ended",
                task.pause_reason,
            )
            self._save_locked(task)
            snapshot = task.public(include_prompt=True)
        self._emit_snapshot(snapshot, None)

    def _record_latency(
        self,
        task: AgentTask,
        event: str,
        attributes: dict | None = None,
        *,
        once: bool = False,
    ) -> None:
        metadata = {
            "agent_provider": str(task.delegate_agent_id or task.agent_id or "desktop"),
            **dict(attributes or {}),
        }
        try:
            self._latency_tracer.record(task.trace_id, event, metadata, once=once)
        except Exception:
            # Diagnostics must never affect task execution.
            pass

    def _set_status(self, task: AgentTask, status: str, on_event: EventCallback | None) -> None:
        with self._lock:
            if task.status in TERMINAL_STATES and status not in TERMINAL_STATES:
                return
            if (
                (task.pause_requested or task.status in {"paused", "takeover"})
                and status not in {"pausing", "paused", "takeover"}
            ):
                return
            task.status = status
            task.updated_at = int(time.time() * 1000)
            task.last_progress_at = task.updated_at
            task.recovery_state = "healthy"
            task.status_seq += 1
            self._save_locked(task)
        self._emit(task, on_event)

    def _finish(
        self,
        task: AgentTask,
        status: str,
        on_event: EventCallback | None,
        result: str = "",
        error: str = "",
        generation: int | None = None,
    ) -> bool:
        with self._lock:
            if (
                task.status in TERMINAL_STATES
                or task.pause_requested
                or task.status in {"paused", "takeover"}
                or (
                    generation is not None
                    and task.execution_generation != generation
                )
            ):
                return False
            now = int(time.time() * 1000)
            task.status = status
            task.updated_at = now
            task.status_seq += 1
            task.completed_at = now
            task.result = result
            task.error = error
            task.current_step = ""
            task.pending_approval = {}
            task.output_files = self._task_artifacts(task.task_id)
            task.recovery_state = (
                "exhausted"
                if status == "timed_out" else
                "healthy"
                if status == "completed" else
                "stopped"
            )
            timer = self._takeover_timers.pop(task.task_id, None)
            if timer is not None:
                timer.cancel()
            self._stop_external_runtime_locked(task.task_id, forget_task=True)
            self._save_locked(task)
        self._record_latency(
            task,
            VoiceTraceEvents.AGENT_COMPLETED,
            {"task_status": status, "success": status == "completed"},
            once=True,
        )
        self._emit(task, on_event)
        return True

    def _emit(self, task: AgentTask, on_event: EventCallback | None) -> None:
        self._emit_snapshot(task.public(), on_event)

    def _emit_snapshot(self, snapshot: dict, on_event: EventCallback | None) -> None:
        callbacks: list[EventCallback] = []
        if on_event is not None:
            callbacks.append(on_event)
        with self._lock:
            if on_event is None:
                task_callback = self._task_event_callbacks.get(
                    str(snapshot.get("task_id") or "")
                )
                if task_callback is not None:
                    callbacks.append(task_callback)
            callbacks.extend(self._listeners.values())
        for callback in callbacks:
            try:
                callback(snapshot)
            except Exception:
                pass
        if str(snapshot.get("status") or "") in TERMINAL_STATES:
            with self._lock:
                self._task_event_callbacks.pop(
                    str(snapshot.get("task_id") or ""),
                    None,
                )

    @staticmethod
    def _terminate(process: subprocess.Popen) -> None:
        if os.name == "nt" and process.poll() is None:
            try:
                subprocess.run(
                    ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                    capture_output=True,
                    timeout=5,
                    check=False,
                )
                return
            except Exception:
                pass
        try:
            process.terminate()
            process.wait(timeout=3)
        except Exception:
            try:
                process.kill()
            except Exception:
                pass

    def _load(self) -> None:
        for row in self._store.recoverable(TERMINAL_STATES):
            task = self._decode_task(row)
            recovered_at = int(time.time() * 1000)
            task.updated_at = recovered_at
            task.status_seq += 1
            if task.status in PAUSED_STATES or task.pause_requested:
                task.status = "paused"
                task.pause_requested = True
                task.takeover = {}
                task.current_step = "Paused"
                task.pause_reason = (
                    task.pause_reason
                    or "Paused state restored after Desktop restart"
                )
                task.recovery_state = "paused"
                self._append_control_event_locked(
                    task,
                    "task_pause_restored",
                    "Paused task restored",
                    "Desktop restarted; the task will remain paused until continued.",
                )
                self._tasks[task.task_id] = task
                self._save_locked(task)
                continue
            previous_attempt = max(1, task.attempt)
            if previous_attempt >= MAX_AUTOMATIC_RECOVERY_ATTEMPTS:
                task.status = "failed"
                task.error = "Task recovery stopped after repeated Desktop restarts"
                task.completed_at = recovered_at
                task.current_step = ""
                task.recovery_state = "exhausted"
            else:
                task.status = "recovering"
                task.attempt = previous_attempt + 1
                task.completed_at = 0
                task.result = ""
                task.error = ""
                task.exit_code = None
                task.current_step = "Recovering after Desktop restart"
                task.recovery_state = "recovering"
            task.delivery_trace = self._merge_delivery_trace(
                task,
                task.delivery_trace,
                [{
                    "stage": "desktop_task_recovering",
                    "at": recovered_at,
                    "detail": f"attempt={task.attempt}",
                }],
            )
            self._tasks[task.task_id] = task
            self._recovered_task_ids.add(task.task_id)
            self._save_locked(task)

    def _save_locked(self, task: AgentTask) -> None:
        try:
            record = task.record()
            with self._run_events.ledger.transaction() as connection:
                self._run_events.append_snapshot(record, connection=connection)
                self._store.upsert(record, connection=connection)
        except Exception as error:
            # Keep live task references consistent with the rolled-back durable state.
            try:
                previous = self._store.get(task.task_id)
                if previous is not None:
                    restored = self._decode_task(previous)
                    for attribute in fields(AgentTask):
                        if attribute.name not in {"process", "cancel_requested"}:
                            setattr(task, attribute.name, getattr(restored, attribute.name))
            except Exception as recovery_error:
                error.add_note(f"Could not reload the rolled-back task: {type(recovery_error).__name__}")
            raise

    @staticmethod
    def _public_with_output_preview(
        task: AgentTask,
        record: dict,
        *,
        include_prompt: bool,
    ) -> dict:
        payload = task.public(include_prompt=include_prompt)
        if not bool(record.get("result_chunked")):
            return payload
        payload["result"] = str(record.get("result") or "")
        for key in (
            "result_chunked",
            "result_length",
            "result_chunk_count",
            "result_sha256",
            "result_preview_length",
        ):
            payload[key] = record.get(key)
        return payload

    @staticmethod
    def _decode_task(row: dict) -> AgentTask:
        status = str(row.get("status") or "failed")
        task_id = str(row.get("task_id") or uuid.uuid4())
        task = AgentTask(
            task_id=task_id,
            agent_id=str(row.get("agent_id") or ""),
            contact_id=str(row.get("contact_id") or ""),
            source_message_id=str(row.get("source_message_id") or ""),
            prompt=str(row.get("prompt") or ""),
            goal_id=str(row.get("goal_id") or task_id),
            run_id=str(row.get("run_id") or f"task:{task_id}"),
            conversation_id=str(row.get("conversation_id") or ""),
            client_conversation_id=str(
                row.get("client_conversation_id")
                or row.get("conversation_id")
                or ""
            ),
            client_route_id=str(row.get("client_route_id") or ""),
            status=status,
            created_at=int(row.get("created_at") or 0),
            started_at=int(row.get("started_at") or 0),
            updated_at=int(row.get("updated_at") or 0),
            completed_at=int(row.get("completed_at") or 0),
            result=str(row.get("result") or ""),
            error=str(row.get("error") or ""),
            first_output_at=max(0, int(row.get("first_output_at") or 0)),
            output_delta_sequence=max(
                0,
                int(row.get("output_delta_sequence") or 0),
            ),
            output_delta_event_id=str(
                (
                    row.get("partial_result")
                    if isinstance(row.get("partial_result"), dict) else {}
                ).get("event_id")
                or row.get("output_delta_event_id")
                or ""
            )[:200],
            partial_result_text=str(
                (
                    row.get("partial_result")
                    if isinstance(row.get("partial_result"), dict) else {}
                ).get("text")
                or row.get("partial_result_text")
                or ""
            )[:MAX_PARTIAL_RESULT_CHARACTERS],
            exit_code=row.get("exit_code"),
            status_seq=int(row.get("status_seq") or 0),
            thread_id=str(row.get("thread_id") or ""),
            turn_id=str(row.get("turn_id") or ""),
            client_turn_id=str(row.get("client_turn_id") or ""),
            delegate_agent_id=str(row.get("delegate_agent_id") or ""),
            current_step="" if status in TERMINAL_STATES else str(row.get("current_step") or ""),
            pending_approval=(
                {}
                if status in TERMINAL_STATES else
                dict(row.get("pending_approval") or {})
            ),
            events=list(row.get("events") or []),
            output_files=list(row.get("output_files") or [])[:100],
            attachments=[str(value) for value in list(row.get("attachments") or [])[:12]],
            retry_of=str(row.get("retry_of") or ""),
            task_disposition=str(row.get("task_disposition") or ""),
            merged_into_task_id=str(row.get("merged_into_task_id") or ""),
            supersedes_task_id=str(row.get("supersedes_task_id") or ""),
            intervention_kind=str(row.get("intervention_kind") or ""),
            attempt=max(1, int(row.get("attempt") or 1)),
            execution_policy=dict(row.get("execution_policy") or {}),
            last_progress_at=int(
                row.get("last_progress_at")
                or row.get("updated_at")
                or row.get("created_at")
                or 0
            ),
            replan_count=max(0, int(row.get("replan_count") or 0)),
            stall_count=max(0, int(row.get("stall_count") or 0)),
            last_stall_at=max(0, int(row.get("last_stall_at") or 0)),
            recovery_state=str(row.get("recovery_state") or "healthy"),
            failure_counts={
                str(key): max(0, int(value or 0))
                for key, value in dict(row.get("failure_counts") or {}).items()
            },
            trace_id=(
                str(row.get("trace_id") or "").strip()[:128]
                or uuid.uuid5(
                    uuid.NAMESPACE_URL,
                    f"galaxyssi:agent-task:{task_id}",
                ).hex
            ),
            pause_requested=bool(row.get("pause_requested")),
            pause_reason=str(row.get("pause_reason") or "")[:500],
            paused_at=max(0, int(row.get("paused_at") or 0)),
            resume_count=max(0, int(row.get("resume_count") or 0)),
            execution_generation=max(
                1,
                int(row.get("execution_generation") or 1),
            ),
            execution_checkpoint=dict(row.get("execution_checkpoint") or {}),
            takeover=dict(row.get("takeover") or {}),
        )
        task.delivery_trace = AgentTaskManager._merge_delivery_trace(
            task,
            [],
            list(row.get("delivery_trace") or []),
        )
        return task

    @staticmethod
    def _task_identity(task: AgentTask) -> dict[str, str]:
        return {
            key: value
            for key, value in {
                "client_route_id": task.client_route_id,
                "conversation_id": task.conversation_id,
                "client_conversation_id": task.client_conversation_id,
                "goal_id": task.goal_id,
                "task_id": task.task_id,
                "run_id": task.run_id,
                "turn_id": task.turn_id,
                "client_turn_id": task.client_turn_id,
            }.items()
            if value
        }

    @staticmethod
    def _trace_entry(
        task: AgentTask,
        stage: str,
        at: int,
        detail: str,
    ) -> dict:
        return {
            "stage": str(stage or "")[:96],
            "at": max(0, int(at or 0)),
            "detail": str(detail or "")[:240],
            **AgentTaskManager._task_identity(task),
        }

    @staticmethod
    def _trace_signature(item: dict) -> tuple[str, int, str]:
        return (
            str(item.get("stage") or ""),
            int(item.get("at") or 0),
            str(item.get("detail") or ""),
        )

    @staticmethod
    def _merge_delivery_trace(
        task: AgentTask,
        current: list[dict],
        incoming: list[dict],
    ) -> list[dict]:
        merged: list[dict] = []
        signatures: set[tuple[str, int, str]] = set()
        for item in [*current, *incoming]:
            if not isinstance(item, dict):
                continue
            stage = str(item.get("stage") or "").strip()[:96]
            if not stage:
                continue
            try:
                at = max(0, int(item.get("at") or 0))
            except (TypeError, ValueError):
                continue
            if not at:
                continue
            entry = AgentTaskManager._trace_entry(
                task,
                stage,
                at,
                str(item.get("detail") or "")[:240],
            )
            signature = AgentTaskManager._trace_signature(entry)
            if signature in signatures:
                continue
            signatures.add(signature)
            merged.append(entry)
        return merged[-MAX_DELIVERY_TRACE_EVENTS:]

    @staticmethod
    def _task_artifacts(task_id: str) -> list[dict]:
        try:
            from task_workspace import task_artifacts
            return task_artifacts(task_id)
        except Exception:
            return []


agent_task_manager = AgentTaskManager()
