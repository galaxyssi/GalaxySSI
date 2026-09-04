"""Keep-alive process pool for external Agents with a persistent JSONL transport.

Arbitrary one-shot commands cannot be kept alive safely because many of them
only emit output after stdin reaches EOF. This pool therefore requires an
explicit ``galaxyssi-jsonl-v1`` capability and never guesses from a command
name. Codex App Server and future ACP adapters remain managed transports; this
module provides the common lifecycle for persistent stdio Agents.
"""
from __future__ import annotations

import hashlib
import json
import os
import queue
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from latency_feature_flags import agent_output_delta_enabled


CLI_PROTOCOL = "galaxyssi.agent-cli/1.0"
CLI_CLIENT_CAPABILITIES = tuple(filter(None, (
    "user_visible_output_delta_v1" if agent_output_delta_enabled() else "",
    "progress_notification_v1",
    "cancellation_v1",
)))
DEFAULT_MAX_PROCESSES = 4
DEFAULT_MAX_PROCESSES_PER_AGENT = 2
DEFAULT_IDLE_TIMEOUT_SECONDS = 5 * 60
DEFAULT_MAX_REQUESTS_PER_PROCESS = 100
MAX_STDERR_CHARS = 16_000


class ExternalCliPoolError(RuntimeError):
    pass


class ExternalCliPoolTimeout(ExternalCliPoolError):
    pass


class ExternalCliProtocolError(ExternalCliPoolError):
    pass


class ExternalCliProcessExited(ExternalCliPoolError):
    def __init__(self, message: str, *, request_sent: bool) -> None:
        self.request_sent = request_sent
        super().__init__(message)


@dataclass(frozen=True)
class PersistentCliRequest:
    agent_id: str
    prompt: str
    task_id: str
    conversation_id: str = ""
    turn_id: str = ""
    client_route_id: str = ""
    working_directory: str = ""
    response_language: str = ""
    timeout_seconds: float = 120
    priority: str = "foreground"
    metadata: dict = field(default_factory=dict)
    on_process: Callable[[subprocess.Popen], None] | None = field(
        default=None,
        repr=False,
        compare=False,
    )
    on_event: Callable[[dict], None] | None = field(
        default=None,
        repr=False,
        compare=False,
    )


@dataclass(frozen=True)
class PersistentCliResult:
    reply: str
    worker_id: str
    pid: int
    reused: bool
    request_count: int
    session_id: str = ""
    artifacts: tuple[dict, ...] = ()
    capabilities: tuple[str, ...] = ()


@dataclass(frozen=True)
class _WarmTarget:
    agent_id: str
    command: tuple[str, ...]
    environment_key: str
    env: dict[str, str] = field(repr=False, compare=False)
    cwd: Path
    count: int

    @property
    def key(self) -> tuple[str, tuple[str, ...], str]:
        return self.agent_id, self.command, self.environment_key


class _PersistentJsonlWorker:
    def __init__(
        self,
        *,
        worker_id: str,
        agent_id: str,
        command: tuple[str, ...],
        environment_key: str,
        env: dict[str, str],
        cwd: Path,
        now: Callable[[], float],
        popen_factory: Callable[..., subprocess.Popen],
    ) -> None:
        self.worker_id = worker_id
        self.agent_id = agent_id
        self.command = command
        self.environment_key = environment_key
        self.cwd = Path(cwd)
        self._now = now
        self._write_lock = threading.RLock()
        self._responses: queue.Queue[dict | None] = queue.Queue()
        self._stderr_lock = threading.RLock()
        self._stderr = ""
        self.created_at = self._now()
        self.last_used_at = self.created_at
        self.request_count = 0
        self.busy = False
        self.active_priority = ""
        self.retiring = False
        creationflags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        self.process = popen_factory(
            list(command),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            env=env,
            cwd=str(self.cwd),
            creationflags=creationflags,
        )
        self._stdout_thread = threading.Thread(
            target=self._read_stdout,
            daemon=True,
            name=f"galaxyssi-cli-out-{worker_id}",
        )
        self._stderr_thread = threading.Thread(
            target=self._read_stderr,
            daemon=True,
            name=f"galaxyssi-cli-err-{worker_id}",
        )
        self._stdout_thread.start()
        self._stderr_thread.start()

    @property
    def pid(self) -> int:
        return int(self.process.pid or 0)

    def alive(self) -> bool:
        return self.process.poll() is None

    def request(
        self,
        request: PersistentCliRequest,
    ) -> tuple[str, str, tuple[dict, ...], tuple[str, ...]]:
        if not self.alive():
            raise ExternalCliProcessExited(
                self._exit_message(),
                request_sent=False,
            )
        request_id = str(uuid.uuid4())
        payload = {
            "protocol": CLI_PROTOCOL,
            "id": request_id,
            "method": "agent/run",
            "params": {
                "agent_id": request.agent_id,
                "prompt": request.prompt,
                "task_id": request.task_id,
                "conversation_id": request.conversation_id,
                "turn_id": request.turn_id,
                "client_route_id": request.client_route_id,
                "working_directory": request.working_directory,
                "response_language": request.response_language,
                "priority": str(request.priority or "foreground").strip().lower(),
                "metadata": dict(request.metadata),
                "client_capabilities": list(CLI_CLIENT_CAPABILITIES),
            },
        }
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        request_sent = False
        try:
            with self._write_lock:
                if self.process.stdin is None or not self.alive():
                    raise ExternalCliProcessExited(
                        self._exit_message(),
                        request_sent=False,
                    )
                self.process.stdin.write(encoded + "\n")
                self.process.stdin.flush()
                request_sent = True
        except ExternalCliProcessExited:
            raise
        except (BrokenPipeError, OSError, ValueError) as exc:
            raise ExternalCliProcessExited(
                f"Persistent Agent stdin failed: {exc}",
                request_sent=request_sent,
            ) from exc

        deadline = self._now() + max(0.1, float(request.timeout_seconds or 120))
        while True:
            remaining = deadline - self._now()
            if remaining <= 0:
                raise ExternalCliPoolTimeout(
                    f"{request.agent_id} persistent process timed out"
                )
            try:
                message = self._responses.get(timeout=min(remaining, 0.25))
            except queue.Empty:
                if not self.alive():
                    raise ExternalCliProcessExited(
                        self._exit_message(),
                        request_sent=True,
                    )
                continue
            if message is None:
                raise ExternalCliProcessExited(
                    self._exit_message(),
                    request_sent=True,
                )
            if str(message.get("id") or "") != request_id:
                self._dispatch_notification(request, message)
                continue
            if isinstance(message.get("error"), dict):
                error = message["error"]
                raise ExternalCliProtocolError(
                    str(error.get("message") or "Persistent Agent returned an error")
                )
            result = message.get("result")
            if isinstance(result, str):
                reply = result
                session_id = ""
                artifacts: tuple[dict, ...] = ()
                capabilities: tuple[str, ...] = ()
            elif isinstance(result, dict):
                reply = str(result.get("reply") or result.get("content") or "")
                session_id = str(result.get("session_id") or "")
                artifacts = tuple(
                    dict(item)
                    for item in result.get("artifacts", [])
                    if isinstance(item, dict)
                )
                capabilities = tuple(
                    str(item or "").strip()
                    for item in result.get("capabilities", [])
                    if str(item or "").strip()
                )
            else:
                reply = str(message.get("reply") or "")
                session_id = str(message.get("session_id") or "")
                artifacts = ()
                capabilities = ()
            if not reply.strip():
                raise ExternalCliProtocolError(
                    f"{request.agent_id} persistent process returned no reply"
                )
            self.request_count += 1
            self.last_used_at = self._now()
            return reply, session_id, artifacts, capabilities

    @staticmethod
    def _dispatch_notification(
        request: PersistentCliRequest,
        message: dict,
    ) -> None:
        callback = request.on_event
        if callback is None:
            return
        method = str(message.get("method") or "").strip().lower()
        if method not in {
            "agent/output_delta",
            "agent/progress",
            "agent/first_output",
        }:
            return
        params = message.get("params")
        if not isinstance(params, dict):
            return
        notification_task_id = str(params.get("task_id") or "").strip()
        if notification_task_id != request.task_id:
            return
        if params.get("user_visible") is False:
            return
        try:
            sequence = max(0, int(params.get("sequence") or 0))
        except (TypeError, ValueError):
            return
        event = {
            "method": method,
            "task_id": request.task_id,
            "sequence": sequence,
            "text": str(params.get("text") or params.get("content") or "")[:64_000],
            "message": str(params.get("message") or params.get("title") or "")[:2_000],
            "status": str(params.get("status") or "running")[:32],
            "user_visible": True,
        }
        if method == "agent/output_delta" and not event["text"].strip():
            return
        if method != "agent/output_delta" and not event["message"].strip():
            return
        try:
            callback(event)
        except Exception:
            return

    def close(self) -> None:
        self.retiring = True
        process = self.process
        if process.poll() is not None:
            self._close_streams()
            return
        try:
            if process.stdin is not None:
                shutdown = {
                    "protocol": CLI_PROTOCOL,
                    "id": str(uuid.uuid4()),
                    "method": "agent/shutdown",
                    "params": {},
                }
                process.stdin.write(json.dumps(shutdown, separators=(",", ":")) + "\n")
                process.stdin.flush()
            process.wait(timeout=1)
        except Exception:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
        self._close_streams()

    def kill(self) -> None:
        self.retiring = True
        if self.process.poll() is None:
            self.process.kill()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
        self._close_streams()

    def stderr_tail(self) -> str:
        with self._stderr_lock:
            return self._stderr[-2_000:]

    def _read_stdout(self) -> None:
        stream = self.process.stdout
        if stream is None:
            self._responses.put(None)
            return
        for line in stream:
            value = line.strip()
            if not value:
                continue
            try:
                message = json.loads(value)
            except json.JSONDecodeError:
                continue
            if isinstance(message, dict):
                self._responses.put(message)
        self._responses.put(None)

    def _read_stderr(self) -> None:
        stream = self.process.stderr
        if stream is None:
            return
        for line in stream:
            with self._stderr_lock:
                self._stderr = (self._stderr + line)[-MAX_STDERR_CHARS:]

    def _exit_message(self) -> str:
        code = self.process.poll()
        detail = self.stderr_tail().strip()
        suffix = f": {detail}" if detail else ""
        return f"Persistent Agent process exited with code {code}{suffix}"

    def _close_streams(self) -> None:
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            if stream is None:
                continue
            try:
                stream.close()
            except OSError:
                pass
        current = threading.current_thread()
        for thread in (self._stdout_thread, self._stderr_thread):
            if thread is not current and thread.is_alive():
                thread.join(timeout=0.5)


class ExternalCliProcessPool:
    """Bounded, reusable process pool with delayed idle release."""

    def __init__(
        self,
        *,
        max_processes: int = DEFAULT_MAX_PROCESSES,
        max_processes_per_agent: int = DEFAULT_MAX_PROCESSES_PER_AGENT,
        idle_timeout_seconds: float = DEFAULT_IDLE_TIMEOUT_SECONDS,
        max_requests_per_process: int = DEFAULT_MAX_REQUESTS_PER_PROCESS,
        now: Callable[[], float] = time.monotonic,
        popen_factory: Callable[..., subprocess.Popen] = subprocess.Popen,
        start_janitor: bool = True,
    ) -> None:
        self.max_processes = max(1, min(int(max_processes or DEFAULT_MAX_PROCESSES), 32))
        self.max_processes_per_agent = max(
            1,
            min(int(max_processes_per_agent or DEFAULT_MAX_PROCESSES_PER_AGENT), 8),
        )
        self.idle_timeout_seconds = max(1.0, float(idle_timeout_seconds or 1))
        self.max_requests_per_process = max(
            1,
            min(int(max_requests_per_process or DEFAULT_MAX_REQUESTS_PER_PROCESS), 10_000),
        )
        self._now = now
        self._popen_factory = popen_factory
        self._condition = threading.Condition(threading.RLock())
        self._workers: dict[str, _PersistentJsonlWorker] = {}
        self._warm_targets: dict[
            tuple[str, tuple[str, ...], str],
            _WarmTarget,
        ] = {}
        self._active_tasks: dict[str, str] = {}
        self._foreground_waiters = 0
        self._closed = False
        self._metrics = {
            "process_starts": 0,
            "warm_reuses": 0,
            "requests": 0,
            "failures": 0,
            "cancellations": 0,
            "idle_releases": 0,
            "foreground_requests": 0,
            "background_requests": 0,
            "foreground_bursts": 0,
            "cold_starts": 0,
            "prewarm_starts": 0,
            "keepalive_restarts": 0,
            "startup_latency_ms_total": 0,
            "last_startup_latency_ms": 0,
        }
        self._janitor_stop = threading.Event()
        self._janitor_thread: threading.Thread | None = None
        if start_janitor:
            self._janitor_thread = threading.Thread(
                target=self._janitor_loop,
                daemon=True,
                name="galaxyssi-cli-pool-janitor",
            )
            self._janitor_thread.start()

    def execute(
        self,
        request: PersistentCliRequest,
        *,
        command: list[str] | tuple[str, ...],
        env: dict[str, str],
        cwd: Path,
        process_limit: int | None = None,
    ) -> PersistentCliResult:
        normalized_command = tuple(str(item) for item in command if str(item))
        if not normalized_command:
            raise ExternalCliPoolError("Persistent Agent command is empty")
        environment_key = self._environment_key(env)
        effective_process_limit = max(
            1,
            min(
                int(process_limit or self.max_processes_per_agent),
                self.max_processes_per_agent,
                self.max_processes,
            ),
        )
        priority = self._normalize_priority(request.priority)
        worker, reused = self._acquire(
            request.agent_id,
            normalized_command,
            environment_key,
            dict(env),
            Path(cwd),
            task_id=request.task_id,
            process_limit=effective_process_limit,
            timeout_seconds=request.timeout_seconds,
            priority=priority,
        )
        try:
            if request.on_process is not None:
                request.on_process(worker.process)
            reply, session_id, artifacts, capabilities = worker.request(request)
            return PersistentCliResult(
                reply=reply,
                worker_id=worker.worker_id,
                pid=worker.pid,
                reused=reused,
                request_count=worker.request_count,
                session_id=session_id,
                artifacts=artifacts,
                capabilities=capabilities,
            )
        except Exception:
            with self._condition:
                self._metrics["failures"] += 1
                self._retire_locked(worker.worker_id, kill=True)
            raise
        finally:
            with self._condition:
                self._active_tasks.pop(request.task_id, None)
                current = self._workers.get(worker.worker_id)
                if current is not None:
                    current.busy = False
                    current.active_priority = ""
                    current.last_used_at = self._now()
                    if current.request_count >= self.max_requests_per_process:
                        self._retire_locked(current.worker_id)
                self._replenish_warm_targets_locked()
                self._condition.notify_all()

    def prewarm(
        self,
        agent_id: str,
        *,
        command: list[str] | tuple[str, ...],
        env: dict[str, str],
        cwd: Path,
        count: int = 1,
        keep_alive: bool = True,
    ) -> int:
        normalized_command = tuple(str(item) for item in command if str(item))
        if not normalized_command:
            return 0
        environment_key = self._environment_key(env)
        warmed = 0
        with self._condition:
            self._ensure_open_locked()
            self._prune_locked()
            target = _WarmTarget(
                agent_id=str(agent_id),
                command=normalized_command,
                environment_key=environment_key,
                env=dict(env),
                cwd=Path(cwd),
                count=max(
                    0,
                    min(int(count or 1), self.max_processes_per_agent),
                ),
            )
            if keep_alive and target.count:
                self._warm_targets[target.key] = target
            elif not keep_alive:
                self._warm_targets.pop(target.key, None)
            existing = self._matching_workers_locked(
                agent_id,
                normalized_command,
                environment_key,
            )
            while (
                len(existing) < target.count
                and len(self._workers) < self.max_processes
            ):
                worker = self._spawn_locked(
                    agent_id,
                    normalized_command,
                    environment_key,
                    dict(env),
                    Path(cwd),
                    reason="prewarm",
                )
                existing.append(worker)
                warmed += 1
        return warmed

    def cancel(self, task_id: str) -> bool:
        with self._condition:
            worker_id = self._active_tasks.get(str(task_id or ""))
            if not worker_id:
                return False
            self._metrics["cancellations"] += 1
            self._retire_locked(worker_id, kill=True)
            self._condition.notify_all()
            return True

    def reap_idle(self) -> int:
        with self._condition:
            released = self._prune_locked()
            self._replenish_warm_targets_locked()
            return released

    def maintain(self) -> dict:
        with self._condition:
            released = self._prune_locked()
            started = self._replenish_warm_targets_locked()
            return {
                "released": released,
                "started": started,
                "health": self.health(),
            }

    def health(self) -> dict:
        with self._condition:
            workers = []
            now = self._now()
            for worker in self._workers.values():
                workers.append({
                    "worker_id": worker.worker_id,
                    "agent_id": worker.agent_id,
                    "pid": worker.pid,
                    "state": "busy" if worker.busy else "idle",
                    "priority": worker.active_priority,
                    "alive": worker.alive(),
                    "request_count": worker.request_count,
                    "age_seconds": max(0.0, now - worker.created_at),
                    "idle_seconds": 0.0 if worker.busy else max(0.0, now - worker.last_used_at),
                })
            return {
                "protocol": CLI_PROTOCOL,
                "status": "stopped" if self._closed else "ready",
                "max_processes": self.max_processes,
                "max_processes_per_agent": self.max_processes_per_agent,
                "idle_timeout_seconds": self.idle_timeout_seconds,
                "max_requests_per_process": self.max_requests_per_process,
                "process_count": len(workers),
                "busy_count": sum(1 for item in workers if item["state"] == "busy"),
                "idle_count": sum(1 for item in workers if item["state"] == "idle"),
                "workers": workers,
                "warm_targets": [
                    {
                        "agent_id": target.agent_id,
                        "target_count": target.count,
                        "ready_count": len(
                            self._matching_workers_locked(
                                target.agent_id,
                                target.command,
                                target.environment_key,
                            )
                        ),
                    }
                    for target in self._warm_targets.values()
                ],
                "metrics": dict(self._metrics),
                "foreground_waiters": self._foreground_waiters,
            }

    def shutdown(self) -> None:
        self._janitor_stop.set()
        with self._condition:
            if self._closed:
                return
            self._closed = True
            self._warm_targets.clear()
            worker_ids = list(self._workers)
            for worker_id in worker_ids:
                self._retire_locked(worker_id, kill=True)
            self._condition.notify_all()
        if self._janitor_thread is not None and self._janitor_thread.is_alive():
            self._janitor_thread.join(timeout=2)

    def _acquire(
        self,
        agent_id: str,
        command: tuple[str, ...],
        environment_key: str,
        env: dict[str, str],
        cwd: Path,
        *,
        task_id: str,
        process_limit: int,
        timeout_seconds: float,
        priority: str,
    ) -> tuple[_PersistentJsonlWorker, bool]:
        deadline = self._now() + max(0.1, float(timeout_seconds or 120))
        normalized_task_id = str(task_id or "").strip()
        if not normalized_task_id:
            raise ExternalCliPoolError("Persistent Agent task ID is empty")
        with self._condition:
            if normalized_task_id in self._active_tasks:
                raise ExternalCliPoolError(
                    f"Persistent Agent task is already active: {normalized_task_id}"
                )
            foreground = priority != "background"
            if foreground:
                self._foreground_waiters += 1
            try:
                while True:
                    self._ensure_open_locked()
                    self._prune_locked()
                    if not foreground and self._foreground_waiters > 0:
                        remaining = deadline - self._now()
                        if remaining <= 0:
                            raise ExternalCliPoolTimeout(
                                f"No persistent process capacity available for {agent_id}"
                            )
                        self._condition.wait(timeout=min(remaining, 0.1))
                        continue
                    matching = self._matching_workers_locked(
                        agent_id,
                        command,
                        environment_key,
                    )
                    for worker in matching:
                        if not worker.busy and worker.alive():
                            self._activate_locked(
                                worker,
                                normalized_task_id,
                                reused=True,
                                priority=priority,
                            )
                            return worker, True
                    background_matching_busy = any(
                        worker.busy and worker.active_priority == "background"
                        for worker in matching
                    )
                    background_global_busy = any(
                        worker.busy and worker.active_priority == "background"
                        for worker in self._workers.values()
                    )
                    agent_limit = process_limit + (
                        1 if foreground and background_matching_busy else 0
                    )
                    global_limit = self.max_processes + (
                        1 if foreground and background_global_busy else 0
                    )
                    if (
                        len(matching) < agent_limit
                        and len(self._workers) < global_limit
                    ):
                        burst = (
                            foreground
                            and (
                                len(matching) >= process_limit
                                or len(self._workers) >= self.max_processes
                            )
                        )
                        worker = self._spawn_locked(
                            agent_id,
                            command,
                            environment_key,
                            env,
                            cwd,
                            reason="cold",
                        )
                        self._activate_locked(
                            worker,
                            normalized_task_id,
                            reused=False,
                            priority=priority,
                        )
                        if burst:
                            self._metrics["foreground_bursts"] += 1
                        return worker, False
                    idle_other = sorted(
                        (
                            worker
                            for worker in self._workers.values()
                            if not worker.busy and worker not in matching
                        ),
                        key=lambda item: item.last_used_at,
                    )
                    if idle_other:
                        self._retire_locked(idle_other[0].worker_id)
                        continue
                    remaining = deadline - self._now()
                    if remaining <= 0:
                        raise ExternalCliPoolTimeout(
                            f"No persistent process capacity available for {agent_id}"
                        )
                    self._condition.wait(timeout=min(remaining, 0.25))
            finally:
                if foreground:
                    self._foreground_waiters = max(0, self._foreground_waiters - 1)
                    self._condition.notify_all()

    def _activate_locked(
        self,
        worker: _PersistentJsonlWorker,
        task_id: str,
        *,
        reused: bool,
        priority: str,
    ) -> None:
        worker.busy = True
        worker.active_priority = priority
        self._active_tasks[task_id] = worker.worker_id
        self._metrics["requests"] += 1
        if priority == "background":
            self._metrics["background_requests"] += 1
        else:
            self._metrics["foreground_requests"] += 1
        if reused:
            self._metrics["warm_reuses"] += 1

    def _spawn_locked(
        self,
        agent_id: str,
        command: tuple[str, ...],
        environment_key: str,
        env: dict[str, str],
        cwd: Path,
        *,
        reason: str,
    ) -> _PersistentJsonlWorker:
        worker_id = f"cli-{uuid.uuid4().hex[:16]}"
        started_at = time.perf_counter()
        worker = _PersistentJsonlWorker(
            worker_id=worker_id,
            agent_id=agent_id,
            command=command,
            environment_key=environment_key,
            env=env,
            cwd=cwd,
            now=self._now,
            popen_factory=self._popen_factory,
        )
        startup_latency_ms = max(
            0,
            int((time.perf_counter() - started_at) * 1_000),
        )
        self._workers[worker_id] = worker
        self._metrics["process_starts"] += 1
        metric = {
            "prewarm": "prewarm_starts",
            "keepalive": "keepalive_restarts",
        }.get(reason, "cold_starts")
        self._metrics[metric] += 1
        self._metrics["startup_latency_ms_total"] += startup_latency_ms
        self._metrics["last_startup_latency_ms"] = startup_latency_ms
        return worker

    def _matching_workers_locked(
        self,
        agent_id: str,
        command: tuple[str, ...],
        environment_key: str,
    ) -> list[_PersistentJsonlWorker]:
        return [
            worker
            for worker in self._workers.values()
            if worker.agent_id == agent_id
            and worker.command == command
            and worker.environment_key == environment_key
            and not worker.retiring
        ]

    @staticmethod
    def _normalize_priority(priority: str) -> str:
        normalized = str(priority or "foreground").strip().lower()
        if normalized not in {"foreground", "normal", "background"}:
            raise ExternalCliPoolError(
                f"Unsupported persistent Agent priority: {priority}"
            )
        return normalized

    def _prune_locked(self) -> int:
        now = self._now()
        protected = self._protected_warm_workers_locked()
        candidates = [
            worker.worker_id
            for worker in self._workers.values()
            if not worker.busy
            and (
                not worker.alive()
                or worker.request_count >= self.max_requests_per_process
                or (
                    now - worker.last_used_at >= self.idle_timeout_seconds
                    and worker.worker_id not in protected
                )
            )
        ]
        for worker_id in candidates:
            self._retire_locked(worker_id, kill=not self._workers[worker_id].alive())
            self._metrics["idle_releases"] += 1
        return len(candidates)

    def _protected_warm_workers_locked(self) -> set[str]:
        protected: set[str] = set()
        for target in self._warm_targets.values():
            eligible = sorted(
                (
                    worker
                    for worker in self._matching_workers_locked(
                        target.agent_id,
                        target.command,
                        target.environment_key,
                    )
                    if worker.alive()
                    and worker.request_count < self.max_requests_per_process
                ),
                key=lambda item: (item.busy, item.last_used_at),
                reverse=True,
            )
            protected.update(
                worker.worker_id
                for worker in eligible[:target.count]
            )
        return protected

    def _replenish_warm_targets_locked(self) -> int:
        started = 0
        for target in self._warm_targets.values():
            matching = self._matching_workers_locked(
                target.agent_id,
                target.command,
                target.environment_key,
            )
            while (
                len(matching) < target.count
                and len(self._workers) < self.max_processes
            ):
                matching.append(
                    self._spawn_locked(
                        target.agent_id,
                        target.command,
                        target.environment_key,
                        dict(target.env),
                        target.cwd,
                        reason="keepalive",
                    )
                )
                started += 1
        return started

    def _retire_locked(self, worker_id: str, *, kill: bool = False) -> None:
        worker = self._workers.pop(worker_id, None)
        if worker is None:
            return
        self._active_tasks = {
            task_id: active_worker_id
            for task_id, active_worker_id in self._active_tasks.items()
            if active_worker_id != worker_id
        }
        try:
            if kill:
                worker.kill()
            else:
                worker.close()
        except Exception:
            worker.kill()

    def _janitor_loop(self) -> None:
        interval = max(1.0, min(self.idle_timeout_seconds / 2, 30.0))
        while not self._janitor_stop.wait(interval):
            try:
                self.maintain()
            except Exception:
                pass

    def _ensure_open_locked(self) -> None:
        if self._closed:
            raise ExternalCliPoolError("External CLI process pool is stopped")

    @staticmethod
    def _environment_key(env: dict[str, str]) -> str:
        encoded = json.dumps(
            sorted((str(key), str(value)) for key, value in env.items()),
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8", errors="replace")
        return hashlib.sha256(encoded).hexdigest()
