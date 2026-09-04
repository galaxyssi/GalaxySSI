"""Managed Agent Client Protocol runtime for independently installed agents.

GalaxySSI acts as an ACP client. Each configured agent owns a long-lived
subprocess while GalaxySSI owns conversation isolation, cancellation,
workspace-scoped file callbacks, timeline projection, and crash recovery.
"""
from __future__ import annotations

import asyncio
import concurrent.futures
import hashlib
import json
import logging
import os
import shlex
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from agent_config import acp_runtime_config

try:
    import acp
    from acp.exceptions import RequestError
    from acp.schema import (
        AllowedOutcome,
        ClientCapabilities,
        DeniedOutcome,
        FileSystemCapabilities,
        Implementation,
        ReadTextFileResponse,
        RequestPermissionResponse,
        WriteTextFileResponse,
    )
except ImportError:  # Packaged installations can still use the legacy CLI path.
    acp = None
    RequestError = None
    AllowedOutcome = ClientCapabilities = DeniedOutcome = None
    FileSystemCapabilities = Implementation = None
    ReadTextFileResponse = RequestPermissionResponse = WriteTextFileResponse = None


log = logging.getLogger("galaxyssi.acp_runtime")
ACP_PROTOCOL_VERSION = 1
ACP_CLIENT_VERSION = "0.2"
MAX_FILE_CALLBACK_BYTES = 2 * 1024 * 1024
MAX_EVENT_DETAIL_CHARS = 4_000
STARTUP_BACKOFF_SECONDS = 60
DEFAULT_MAINTENANCE_INTERVAL_SECONDS = 15

EventSink = Callable[..., None]


class AcpRuntimeError(RuntimeError):
    pass


class AcpStartupError(AcpRuntimeError):
    pass


class AcpExecutionError(AcpRuntimeError):
    pass


@dataclass
class _RunBinding:
    run_id: str
    agent_id: str
    access_profile: str
    event_sink: EventSink | None
    session_id: str = ""
    message_parts: list[str] = field(default_factory=list)
    thought_parts: dict[str, str] = field(default_factory=dict)
    meaningful_update: bool = False

    def emit(
        self,
        kind: str,
        title: str,
        *,
        event_id: str,
        status: str = "running",
        detail: str = "",
        metadata: dict[str, Any] | None = None,
    ) -> None:
        if self.event_sink is None:
            return
        self.event_sink(
            kind,
            title,
            event_id=event_id,
            status=status,
            detail=str(detail or "")[:MAX_EVENT_DETAIL_CHARS],
            metadata={
                "transport": "acp",
                "agent_id": self.agent_id,
                **dict(metadata or {}),
            },
        )


@dataclass
class _SessionRecord:
    key: str
    agent_id: str
    external_session_id: str
    cwd: str
    command_digest: str
    updated_at: int

    def public(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "agent_id": self.agent_id,
            "external_session_id": self.external_session_id,
            "cwd": self.cwd,
            "command_digest": self.command_digest,
            "updated_at": self.updated_at,
        }


@dataclass
class _ProcessEntry:
    agent_id: str
    command: tuple[str, ...]
    command_digest: str
    context: Any
    connection: Any
    process: Any
    client: "_AcpClient"
    capabilities: Any
    generation: int
    started_at: float
    last_used_at: float
    startup_latency_ms: int
    ready_at: float
    loaded_sessions: set[str] = field(default_factory=set)
    active_prompts: int = 0
    warm_reuses: int = 0


class _AcpClient:
    def __init__(self, runtime: "AcpRuntime", agent_id: str) -> None:
        self.runtime = runtime
        self.agent_id = agent_id

    def on_connect(self, _connection: Any) -> None:
        return None

    async def session_update(self, session_id: str, update: Any, **_kwargs: Any) -> None:
        self.runtime._session_update(self.agent_id, session_id, update)

    async def request_permission(
        self,
        options: list[Any],
        session_id: str,
        tool_call: Any,
        **_kwargs: Any,
    ) -> Any:
        return self.runtime._permission_response(
            self.agent_id,
            session_id,
            options,
            tool_call,
        )

    async def read_text_file(
        self,
        path: str,
        session_id: str,
        limit: int | None = None,
        line: int | None = None,
        **_kwargs: Any,
    ) -> Any:
        target = self.runtime._session_file(self.agent_id, session_id, path)
        if target.stat().st_size > MAX_FILE_CALLBACK_BYTES:
            raise PermissionError("ACP file callback exceeds the 2 MB safety limit")
        text = target.read_text(encoding="utf-8")
        if line is not None or limit is not None:
            lines = text.splitlines(keepends=True)
            start = max(0, int(line or 1) - 1)
            stop = start + max(0, int(limit)) if limit is not None else None
            text = "".join(lines[start:stop])
        return ReadTextFileResponse(content=text)

    async def write_text_file(
        self,
        content: str,
        path: str,
        session_id: str,
        **_kwargs: Any,
    ) -> Any:
        encoded = str(content or "").encode("utf-8")
        if len(encoded) > MAX_FILE_CALLBACK_BYTES:
            raise PermissionError("ACP file callback exceeds the 2 MB safety limit")
        target = self.runtime._session_file(
            self.agent_id,
            session_id,
            path,
            require_exists=False,
        )
        from host_execution_config_guard import (
            HostExecutionConfigViolation,
            assert_host_execution_path_writable,
        )

        try:
            assert_host_execution_path_writable(
                self.runtime._session_root(self.agent_id, session_id),
                target,
                agent_id=self.agent_id,
                capture_id=f"acp-callback:{session_id}",
            )
        except HostExecutionConfigViolation as exc:
            relative_path = target.relative_to(
                self.runtime._session_root(self.agent_id, session_id)
            ).as_posix()
            if RequestError is not None:
                raise RequestError(
                    -32003,
                    "Host execution configuration write is not allowed",
                    {"path": relative_path},
                ) from exc
            raise PermissionError(str(exc)) from exc
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(encoded)
        return WriteTextFileResponse()

    async def create_terminal(self, **_kwargs: Any) -> Any:
        raise PermissionError("ACP client terminal callbacks are disabled")

    async def terminal_output(self, **_kwargs: Any) -> Any:
        raise PermissionError("ACP client terminal callbacks are disabled")

    async def release_terminal(self, **_kwargs: Any) -> Any:
        raise PermissionError("ACP client terminal callbacks are disabled")

    async def wait_for_terminal_exit(self, **_kwargs: Any) -> Any:
        raise PermissionError("ACP client terminal callbacks are disabled")

    async def kill_terminal(self, **_kwargs: Any) -> Any:
        raise PermissionError("ACP client terminal callbacks are disabled")

    async def ext_method(self, _method: str, _params: dict[str, Any]) -> dict[str, Any]:
        return {}

    async def ext_notification(self, _method: str, _params: dict[str, Any]) -> None:
        return None


class AcpRuntime:
    def __init__(
        self,
        *,
        state_path: Path | None = None,
        config_loader: Callable[[], dict[str, Any]] = acp_runtime_config,
        maintenance_interval_seconds: float = DEFAULT_MAINTENANCE_INTERVAL_SECONDS,
    ) -> None:
        self._config_loader = config_loader
        self._state_path = state_path or self._default_state_path()
        self._snapshot_lock = threading.RLock()
        self._sessions = self._load_sessions()
        self._processes: dict[str, _ProcessEntry] = {}
        self._run_bindings: dict[str, _RunBinding] = {}
        self._session_runs: dict[tuple[str, str], str] = {}
        self._session_locks: dict[str, asyncio.Lock] = {}
        self._generation = 0
        self._failures: dict[str, dict[str, Any]] = {}
        self._loop: asyncio.AbstractEventLoop | None = None
        self._thread: threading.Thread | None = None
        self._loop_ready = threading.Event()
        self._closed = False
        self._maintenance_interval_seconds = max(
            0.05,
            float(maintenance_interval_seconds),
        )
        self._metrics = {
            "process_starts": 0,
            "cold_starts": 0,
            "prewarm_starts": 0,
            "keepalive_restarts": 0,
            "warm_reuses": 0,
            "explicit_restarts": 0,
            "startup_latency_ms_total": 0,
            "last_startup_latency_ms": 0,
        }

    @staticmethod
    def _default_state_path() -> Path:
        configured = str(os.environ.get("GALAXYSSI_STATE_DIR") or "").strip()
        root = (
            Path(configured)
            if configured
            else Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"
        )
        return root / "acp-runtime.json"

    @property
    def dependency_available(self) -> bool:
        return acp is not None

    def supports(self, agent_id: str) -> bool:
        config = self._agent_config(agent_id)
        if not self.dependency_available:
            return False
        if not config["runtime_enabled"] or not config["enabled"]:
            return False
        return self._command_available(config["command"])

    def execute(
        self,
        agent_id: str,
        prompt: str,
        *,
        run_id: str,
        client_route_id: str,
        conversation_id: str,
        working_directory: Path | None,
        access_profile: str,
        timeout_seconds: float,
        event_sink: EventSink | None = None,
    ) -> str | None:
        if not self.supports(agent_id):
            return None
        self._ensure_loop()
        future = asyncio.run_coroutine_threadsafe(
            self._execute(
                agent_id,
                prompt,
                run_id=run_id,
                client_route_id=client_route_id,
                conversation_id=conversation_id,
                working_directory=working_directory,
                access_profile=access_profile,
                timeout_seconds=timeout_seconds,
                event_sink=event_sink,
            ),
            self._loop,
        )
        wait_seconds = max(1.0, float(timeout_seconds or 0)) + 10.0
        try:
            return future.result(timeout=wait_seconds)
        except concurrent.futures.TimeoutError as exc:
            self.cancel(run_id)
            future.cancel()
            raise AcpExecutionError(
                f"{agent_id} ACP prompt timed out after {int(timeout_seconds)} seconds"
            ) from exc
        except AcpStartupError as exc:
            self._record_failure(agent_id, str(exc))
            log.warning("ACP startup unavailable agent=%s: %s", agent_id, exc)
            return None

    def cancel(self, run_id: str) -> bool:
        clean_run_id = str(run_id or "").strip()
        with self._snapshot_lock:
            binding = self._run_bindings.get(clean_run_id)
            loop = self._loop
        if binding is None or loop is None or not loop.is_running():
            return False
        asyncio.run_coroutine_threadsafe(
            self._cancel_async(binding.agent_id, binding.session_id),
            loop,
        )
        return True

    def prewarm(self, agent_id: str) -> dict[str, Any]:
        if not self.supports(agent_id):
            return self.agent_health(agent_id)
        self._ensure_loop()
        future = asyncio.run_coroutine_threadsafe(
            self._ensure_process(agent_id, reason="prewarm"),
            self._loop,
        )
        try:
            future.result(timeout=30)
        except Exception as exc:
            self._record_failure(agent_id, str(exc))
        return self.agent_health(agent_id)

    def maintain(self) -> dict[str, Any]:
        self._ensure_loop()
        future = asyncio.run_coroutine_threadsafe(
            self._maintain_prewarmed(),
            self._loop,
        )
        try:
            future.result(timeout=30)
        except Exception as exc:
            log.warning("ACP keep-alive maintenance failed: %s", exc)
        return self.health()

    def restart(self, agent_id: str) -> dict[str, Any]:
        self._ensure_loop()
        self._metrics["explicit_restarts"] += 1
        future = asyncio.run_coroutine_threadsafe(
            self._restart_async(agent_id),
            self._loop,
        )
        try:
            future.result(timeout=15)
        except Exception as exc:
            self._record_failure(agent_id, str(exc))
        if self.supports(agent_id):
            return self.prewarm(agent_id)
        return self.agent_health(agent_id)

    def health(self) -> dict[str, Any]:
        config = self._runtime_config()
        return {
            "protocol": "ACP",
            "protocol_version": ACP_PROTOCOL_VERSION,
            "dependency_available": self.dependency_available,
            "enabled": bool(config.get("enabled")),
            "max_processes": int(config.get("max_processes") or 0),
            "idle_timeout_seconds": int(config.get("idle_timeout_seconds") or 0),
            "processes": [
                self.agent_health(agent_id)
                for agent_id in config.get("agents", {})
            ],
            "sessions": len(self._sessions),
            "metrics": dict(self._metrics),
        }

    def agent_health(self, agent_id: str) -> dict[str, Any]:
        config = self._agent_config(agent_id)
        command_available = self._command_available(config["command"])
        with self._snapshot_lock:
            entry = self._processes.get(agent_id)
            failure = dict(self._failures.get(agent_id, {}))
            session_count = sum(
                1 for row in self._sessions.values() if row.agent_id == agent_id
            )
            running = (
                entry is not None
                and getattr(entry.process, "returncode", None) is None
            )
            return {
                "agent_id": agent_id,
                "enabled": bool(config["runtime_enabled"] and config["enabled"]),
                "prewarm": bool(config["prewarm"]),
                "command": config["command"],
                "command_available": command_available,
                "status": (
                    "running"
                    if running else
                    "backoff"
                    if float(failure.get("retry_after") or 0) > time.time() else
                    "ready"
                    if self.dependency_available and command_available
                    and config["runtime_enabled"] and config["enabled"] else
                    "disabled"
                    if not config["runtime_enabled"] or not config["enabled"] else
                    "needs_setup"
                ),
                "pid": int(getattr(entry.process, "pid", 0) or 0) if entry else 0,
                "generation": int(entry.generation if entry else 0),
                "active_prompts": int(entry.active_prompts if entry else 0),
                "sessions": session_count,
                "startup_latency_ms": int(
                    entry.startup_latency_ms if entry else 0
                ),
                "idle_seconds": (
                    max(0.0, time.monotonic() - entry.last_used_at)
                    if entry and not entry.active_prompts else 0.0
                ),
                "warm_reuses": int(entry.warm_reuses if entry else 0),
                "last_error": str(failure.get("error") or "")[:240],
                "retry_after": int(float(failure.get("retry_after") or 0) * 1000),
            }

    def shutdown(self) -> None:
        with self._snapshot_lock:
            loop = self._loop
            thread = self._thread
            self._closed = True
        if loop is None or thread is None:
            return
        if loop.is_running():
            future = asyncio.run_coroutine_threadsafe(self._shutdown_async(), loop)
            try:
                future.result(timeout=15)
            except Exception:
                pass
            loop.call_soon_threadsafe(loop.stop)
        thread.join(timeout=15)
        with self._snapshot_lock:
            self._loop = None
            self._thread = None
            self._loop_ready.clear()

    async def _execute(
        self,
        agent_id: str,
        prompt: str,
        *,
        run_id: str,
        client_route_id: str,
        conversation_id: str,
        working_directory: Path | None,
        access_profile: str,
        timeout_seconds: float,
        event_sink: EventSink | None,
    ) -> str:
        await self._evict_idle_processes()
        config = self._agent_config(agent_id)
        command_digest = self._command_digest(config["command"])
        cwd = self._workspace(
            agent_id,
            client_route_id,
            conversation_id or run_id,
            working_directory,
        )
        session_key = self._session_key(
            agent_id,
            client_route_id,
            conversation_id or run_id,
            cwd,
        )
        session_lock = self._session_locks.setdefault(session_key, asyncio.Lock())
        binding = _RunBinding(
            run_id=run_id,
            agent_id=agent_id,
            access_profile=access_profile,
            event_sink=event_sink,
        )
        async with session_lock:
            entry = await self._ensure_process(agent_id, reason="execute")
            from host_execution_config_guard import (
                HostExecutionConfigGuard,
                HostExecutionConfigViolation,
            )

            host_config_guard = HostExecutionConfigGuard.begin(
                cwd,
                agent_id=agent_id,
                capture_id=f"acp:{run_id}:{time.time_ns()}",
            )
            entry.active_prompts += 1
            try:
                session_id = await self._ensure_session(
                    entry,
                    session_key,
                    cwd,
                    command_digest,
                )
                binding.session_id = session_id
                with self._snapshot_lock:
                    self._run_bindings[run_id] = binding
                    self._session_runs[(agent_id, session_id)] = run_id
                binding.emit(
                    "transport",
                    f"{agent_id} ACP session ready",
                    event_id=f"acp:session:{session_id}",
                    status="completed",
                    metadata={"session_id": session_id},
                )
                prompt_call = entry.connection.prompt(
                    session_id=session_id,
                    prompt=[acp.text_block(str(prompt or ""))],
                    message_id=self._message_id(run_id),
                )
                try:
                    if timeout_seconds > 0:
                        response = await asyncio.wait_for(
                            prompt_call,
                            timeout=float(timeout_seconds),
                        )
                    else:
                        response = await prompt_call
                except asyncio.TimeoutError as exc:
                    await self._cancel_async(agent_id, session_id)
                    raise AcpExecutionError(
                        f"{agent_id} ACP prompt timed out after {int(timeout_seconds)} seconds"
                    ) from exc
                stop_reason = str(getattr(response, "stop_reason", "") or "")
                if stop_reason == "cancelled":
                    raise AcpExecutionError(f"{agent_id} ACP prompt was cancelled")
                reply = "".join(binding.message_parts).strip()
                if not reply:
                    raise AcpExecutionError(
                        f"{agent_id} ACP completed without an assistant message"
                    )
                self._clear_failure(agent_id)
                return reply
            finally:
                entry.active_prompts = max(0, entry.active_prompts - 1)
                entry.last_used_at = time.monotonic()
                with self._snapshot_lock:
                    self._run_bindings.pop(run_id, None)
                    if binding.session_id:
                        self._session_runs.pop(
                            (agent_id, binding.session_id),
                            None,
                        )
                violations = host_config_guard.finish()
                if violations:
                    raise AcpExecutionError(
                        str(HostExecutionConfigViolation(violations))
                    )

    async def _ensure_process(
        self,
        agent_id: str,
        *,
        reason: str,
    ) -> _ProcessEntry:
        if acp is None:
            raise AcpStartupError("The agent-client-protocol package is not installed")
        config = self._agent_config(agent_id)
        if not config["runtime_enabled"] or not config["enabled"]:
            raise AcpStartupError("ACP is disabled for this agent")
        failure = self._failures.get(agent_id, {})
        if float(failure.get("retry_after") or 0) > time.time():
            raise AcpStartupError(str(failure.get("error") or "ACP startup is in backoff"))
        command = self._split_command(config["command"])
        if not command or not self._command_available(config["command"]):
            raise AcpStartupError(f"ACP command was not found: {config['command']}")
        command = self._spawn_command(command)
        digest = self._command_digest(config["command"])
        existing = self._processes.get(agent_id)
        if (
            existing is not None
            and existing.command_digest == digest
            and getattr(existing.process, "returncode", None) is None
        ):
            if reason == "execute":
                existing.last_used_at = time.monotonic()
                existing.warm_reuses += 1
                self._metrics["warm_reuses"] += 1
            return existing
        replacing_dead_process = existing is not None
        if existing is not None:
            await self._stop_process(existing)
        await self._enforce_capacity(agent_id)
        self._state_path.parent.mkdir(parents=True, exist_ok=True)
        self._generation += 1
        client = _AcpClient(self, agent_id)
        context = acp.spawn_agent_process(
            client,
            command[0],
            *command[1:],
            env=self._agent_environment(agent_id),
            cwd=self._state_path.parent,
            transport_kwargs={"stderr": asyncio.subprocess.DEVNULL},
        )
        startup_started_at = time.perf_counter()
        try:
            connection, process = await context.__aenter__()
            initialized = await asyncio.wait_for(
                connection.initialize(
                    protocol_version=ACP_PROTOCOL_VERSION,
                    client_capabilities=ClientCapabilities(
                        fs=FileSystemCapabilities(
                            read_text_file=True,
                            write_text_file=True,
                        ),
                        terminal=False,
                    ),
                    client_info=Implementation(
                        name="galaxyssi-desktop",
                        title="GalaxySSI Desktop",
                        version=ACP_CLIENT_VERSION,
                    ),
                ),
                timeout=20,
            )
        except Exception as exc:
            try:
                await context.__aexit__(type(exc), exc, exc.__traceback__)
            except Exception:
                pass
            raise AcpStartupError(f"ACP initialize failed: {exc}") from exc
        startup_latency_ms = max(
            0,
            int((time.perf_counter() - startup_started_at) * 1_000),
        )
        ready_at = time.time()
        entry = _ProcessEntry(
            agent_id=agent_id,
            command=tuple(command),
            command_digest=digest,
            context=context,
            connection=connection,
            process=process,
            client=client,
            capabilities=getattr(initialized, "agent_capabilities", None),
            generation=self._generation,
            started_at=time.monotonic(),
            last_used_at=time.monotonic(),
            startup_latency_ms=startup_latency_ms,
            ready_at=ready_at,
        )
        with self._snapshot_lock:
            self._processes[agent_id] = entry
        self._metrics["process_starts"] += 1
        if reason == "prewarm":
            self._metrics["prewarm_starts"] += 1
        elif reason == "keepalive" or replacing_dead_process:
            self._metrics["keepalive_restarts"] += 1
        else:
            self._metrics["cold_starts"] += 1
        self._metrics["startup_latency_ms_total"] += startup_latency_ms
        self._metrics["last_startup_latency_ms"] = startup_latency_ms
        self._clear_failure(agent_id)
        return entry

    async def _ensure_session(
        self,
        entry: _ProcessEntry,
        session_key: str,
        cwd: Path,
        command_digest: str,
    ) -> str:
        record = self._sessions.get(session_key)
        if (
            record is not None
            and record.command_digest == command_digest
            and record.external_session_id in entry.loaded_sessions
        ):
            return record.external_session_id
        can_load = bool(getattr(entry.capabilities, "load_session", False))
        if record is not None and record.command_digest == command_digest and can_load:
            try:
                await entry.connection.load_session(
                    cwd=str(cwd),
                    session_id=record.external_session_id,
                    mcp_servers=[],
                )
                entry.loaded_sessions.add(record.external_session_id)
                return record.external_session_id
            except Exception as exc:
                log.info(
                    "ACP session load failed agent=%s session=%s: %s",
                    entry.agent_id,
                    record.external_session_id,
                    exc,
                )
        try:
            response = await entry.connection.new_session(
                cwd=str(cwd),
                mcp_servers=[],
            )
        except Exception as exc:
            if getattr(entry.process, "returncode", None) is not None:
                raise AcpStartupError(
                    f"{entry.agent_id} ACP process exited before session creation"
                ) from exc
            raise AcpExecutionError(
                f"{entry.agent_id} ACP session creation failed: {exc}"
            ) from exc
        external_session_id = str(response.session_id)
        entry.loaded_sessions.add(external_session_id)
        self._sessions[session_key] = _SessionRecord(
            key=session_key,
            agent_id=entry.agent_id,
            external_session_id=external_session_id,
            cwd=str(cwd),
            command_digest=command_digest,
            updated_at=int(time.time() * 1000),
        )
        self._persist_sessions()
        return external_session_id

    async def _cancel_async(self, agent_id: str, session_id: str) -> None:
        if not session_id:
            return
        entry = self._processes.get(agent_id)
        if entry is None or getattr(entry.process, "returncode", None) is not None:
            return
        try:
            await asyncio.wait_for(
                entry.connection.cancel(session_id=session_id),
                timeout=5,
            )
        except Exception:
            return

    async def _restart_async(self, agent_id: str) -> None:
        entry = self._processes.pop(agent_id, None)
        if entry is not None:
            await self._stop_process(entry)
        self._clear_failure(agent_id)

    async def _shutdown_async(self) -> None:
        entries = list(self._processes.values())
        self._processes.clear()
        for entry in entries:
            await self._stop_process(entry)
        self._run_bindings.clear()
        self._session_runs.clear()

    async def _stop_process(self, entry: _ProcessEntry) -> None:
        try:
            await entry.context.__aexit__(None, None, None)
        except Exception as exc:
            log.debug("ACP process shutdown failed agent=%s: %s", entry.agent_id, exc)

    async def _evict_idle_processes(self) -> None:
        idle_timeout = int(
            self._runtime_config().get("idle_timeout_seconds") or 600
        )
        now = time.monotonic()
        stale = [
            entry
            for entry in self._processes.values()
            if entry.active_prompts == 0
            and not self._agent_config(entry.agent_id)["prewarm"]
            and now - entry.last_used_at >= idle_timeout
        ]
        for entry in stale:
            self._processes.pop(entry.agent_id, None)
            await self._stop_process(entry)

    async def _maintain_prewarmed(self) -> None:
        await self._evict_idle_processes()
        config = self._runtime_config()
        for agent_id, item in config.get("agents", {}).items():
            if not item.get("enabled") or not item.get("prewarm"):
                continue
            if not self.supports(agent_id):
                continue
            try:
                await self._ensure_process(agent_id, reason="keepalive")
            except AcpStartupError as exc:
                self._record_failure(agent_id, str(exc))
            except Exception as exc:
                self._record_failure(agent_id, str(exc))
                log.warning(
                    "ACP keep-alive failed agent=%s: %s",
                    agent_id,
                    exc,
                )

    async def _maintenance_loop(self) -> None:
        while not self._closed:
            await asyncio.sleep(self._maintenance_interval_seconds)
            if self._closed:
                return
            try:
                await self._maintain_prewarmed()
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                log.debug("ACP maintenance iteration failed: %s", exc)

    async def _enforce_capacity(self, incoming_agent_id: str) -> None:
        maximum = int(self._runtime_config().get("max_processes") or 5)
        if incoming_agent_id in self._processes or len(self._processes) < maximum:
            return
        idle = sorted(
            (
                entry for entry in self._processes.values()
                if entry.active_prompts == 0
            ),
            key=lambda item: item.last_used_at,
        )
        if not idle:
            raise AcpStartupError("ACP process capacity is full")
        victim = idle[0]
        self._processes.pop(victim.agent_id, None)
        await self._stop_process(victim)

    def _session_update(self, agent_id: str, session_id: str, update: Any) -> None:
        with self._snapshot_lock:
            run_id = self._session_runs.get((agent_id, session_id), "")
            binding = self._run_bindings.get(run_id)
        if binding is None:
            return
        update_name = type(update).__name__
        if update_name == "AgentMessageChunk":
            text = self._content_text(getattr(update, "content", None))
            if text:
                binding.message_parts.append(text)
                binding.meaningful_update = True
            return
        if update_name == "AgentThoughtChunk":
            text = self._content_text(getattr(update, "content", None))
            message_id = str(getattr(update, "message_id", "") or "current")
            combined = (binding.thought_parts.get(message_id, "") + text)[
                -MAX_EVENT_DETAIL_CHARS:
            ]
            binding.thought_parts[message_id] = combined
            binding.meaningful_update = True
            binding.emit(
                "reasoning",
                f"{agent_id} reasoning",
                event_id=f"acp:thought:{message_id}",
                detail=combined,
            )
            return
        if update_name == "AgentPlanUpdate":
            entries = []
            for item in getattr(update, "entries", []) or []:
                title = str(getattr(item, "content", "") or getattr(item, "title", ""))
                status = str(getattr(item, "status", "") or "")
                entries.append(f"{status}: {title}".strip(": "))
            binding.meaningful_update = True
            binding.emit(
                "plan",
                f"{agent_id} plan updated",
                event_id="acp:plan",
                detail="\n".join(entries),
                metadata={"entries": self._model_public(update).get("entries", [])},
            )
            return
        if update_name in {"ToolCallStart", "ToolCallProgress"}:
            tool_call_id = str(getattr(update, "tool_call_id", "") or "tool")
            status = str(getattr(update, "status", "") or "in_progress")
            title = str(getattr(update, "title", "") or "Agent tool")
            binding.meaningful_update = True
            binding.emit(
                "tool",
                title,
                event_id=f"acp:tool:{tool_call_id}",
                status="failed" if status == "failed" else
                "completed" if status == "completed" else "running",
                metadata={
                    "tool_call_id": tool_call_id,
                    "tool_kind": str(getattr(update, "kind", "") or "other"),
                    "acp_status": status,
                    "locations": self._safe_locations(update),
                },
            )
            return
        if update_name == "UsageUpdate":
            binding.emit(
                "usage",
                f"{agent_id} context usage updated",
                event_id="acp:usage",
                status="completed",
                metadata={
                    "used": int(getattr(update, "used", 0) or 0),
                    "size": int(getattr(update, "size", 0) or 0),
                },
            )

    def _permission_response(
        self,
        agent_id: str,
        session_id: str,
        options: list[Any],
        tool_call: Any,
    ) -> Any:
        option_by_kind = {
            str(getattr(option, "kind", "") or ""): option
            for option in options
        }
        selected = (
            option_by_kind.get("allow_always")
            or option_by_kind.get("allow_once")
        )
        if selected is not None:
            return RequestPermissionResponse(
                outcome=AllowedOutcome(
                    outcome="selected",
                    option_id=str(selected.option_id),
                )
            )
        return RequestPermissionResponse(outcome=DeniedOutcome(outcome="cancelled"))

    def _session_file(
        self,
        agent_id: str,
        session_id: str,
        path: str,
        *,
        require_exists: bool = True,
    ) -> Path:
        root = self._session_root(agent_id, session_id)
        offered = Path(str(path or ""))
        target = (offered if offered.is_absolute() else root / offered).resolve()
        try:
            target.relative_to(root)
        except ValueError as exc:
            raise PermissionError("ACP file callback escaped the session workspace") from exc
        if require_exists and (not target.is_file() or target.is_symlink()):
            raise FileNotFoundError(str(target))
        return target

    def _session_root(
        self,
        agent_id: str,
        session_id: str,
    ) -> Path:
        record = next(
            (
                row for row in self._sessions.values()
                if row.agent_id == agent_id
                and row.external_session_id == session_id
            ),
            None,
        )
        if record is None:
            raise PermissionError("Unknown ACP session")
        return Path(record.cwd).resolve()

    def _ensure_loop(self) -> None:
        with self._snapshot_lock:
            if self._closed:
                self._closed = False
            if self._thread is not None and self._thread.is_alive():
                return
            self._loop_ready.clear()
            self._thread = threading.Thread(
                target=self._loop_main,
                name="galaxyssi-acp-runtime",
                daemon=True,
            )
            self._thread.start()
        if not self._loop_ready.wait(timeout=5):
            raise AcpStartupError("ACP event loop did not start")

    def _loop_main(self) -> None:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        with self._snapshot_lock:
            self._loop = loop
        self._loop_ready.set()
        try:
            loop.create_task(self._maintenance_loop())
            loop.run_forever()
        finally:
            pending = asyncio.all_tasks(loop)
            for task in pending:
                task.cancel()
            if pending:
                loop.run_until_complete(
                    asyncio.gather(*pending, return_exceptions=True)
                )
            loop.close()

    def _workspace(
        self,
        agent_id: str,
        client_route_id: str,
        conversation_id: str,
        working_directory: Path | None,
    ) -> Path:
        if working_directory is not None:
            root = Path(working_directory).expanduser().resolve()
            root.mkdir(parents=True, exist_ok=True)
            return root
        digest = hashlib.sha256(
            f"{agent_id}\0{client_route_id}\0{conversation_id}".encode("utf-8")
        ).hexdigest()[:24]
        root = self._state_path.parent / "acp-workspaces" / agent_id / digest
        root.mkdir(parents=True, exist_ok=True)
        return root.resolve()

    @staticmethod
    def _session_key(
        agent_id: str,
        client_route_id: str,
        conversation_id: str,
        cwd: Path,
    ) -> str:
        return hashlib.sha256(
            "\0".join((
                str(agent_id or ""),
                str(client_route_id or ""),
                str(conversation_id or ""),
                str(cwd),
            )).encode("utf-8")
        ).hexdigest()

    @staticmethod
    def _message_id(run_id: str) -> str:
        import uuid

        try:
            return str(uuid.UUID(str(run_id)))
        except (ValueError, TypeError, AttributeError):
            return str(uuid.uuid5(uuid.NAMESPACE_URL, f"galaxyssi:acp:{run_id}"))

    @staticmethod
    def _split_command(command: str) -> list[str]:
        try:
            return shlex.split(str(command or ""), posix=True)
        except ValueError:
            return []

    @classmethod
    def _command_available(cls, command: str) -> bool:
        parts = cls._split_command(command)
        if not parts:
            return False
        executable = Path(parts[0]).expanduser()
        return executable.is_file() or shutil.which(parts[0]) is not None

    @staticmethod
    def _spawn_command(command: list[str]) -> list[str]:
        executable = shutil.which(command[0]) or command[0]
        command = [executable, *command[1:]]
        if os.name == "nt" and Path(executable).suffix.casefold() in {".cmd", ".bat"}:
            shell = os.environ.get("COMSPEC") or "cmd.exe"
            return [shell, "/d", "/s", "/c", subprocess.list2cmdline(command)]
        return command

    @staticmethod
    def _command_digest(command: str) -> str:
        return hashlib.sha256(str(command or "").encode("utf-8")).hexdigest()

    @staticmethod
    def _agent_environment(agent_id: str) -> dict[str, str]:
        env = dict(os.environ)
        env["GALAXYSSI_AGENT_MODE"] = "1"
        env["GALAXYSSI_ACP_CLIENT"] = "1"
        env["GALAXYSSI_ACP_AGENT_ID"] = agent_id
        if (
            agent_id == "hermes"
            and str(
                env.get("GALAXYSSI_HERMES_ACP_USE_USER_EXTENSIONS") or ""
            ).strip().casefold() not in {"1", "true", "yes", "on"}
        ):
            # GalaxySSI owns the MCP/Skill permission boundary. Loading the same
            # user extensions again inside Hermes can block ACP initialization
            # on an unavailable remote server and duplicate tool surfaces.
            env["HERMES_SAFE_MODE"] = "1"
        return env

    @staticmethod
    def _content_text(content: Any) -> str:
        text = str(getattr(content, "text", "") or "")
        if text:
            return text
        uri = str(getattr(content, "uri", "") or "")
        name = str(getattr(content, "name", "") or "")
        if uri:
            return f"[{name or Path(uri).name or 'artifact'}]({uri})"
        return ""

    @staticmethod
    def _model_public(value: Any) -> dict[str, Any]:
        try:
            return value.model_dump(
                mode="json",
                by_alias=True,
                exclude_none=True,
            )
        except Exception:
            return {}

    @classmethod
    def _safe_locations(cls, update: Any) -> list[dict[str, Any]]:
        locations = []
        for value in getattr(update, "locations", []) or []:
            public = cls._model_public(value)
            if public:
                locations.append(public)
        return locations[:20]

    def _load_sessions(self) -> dict[str, _SessionRecord]:
        try:
            payload = json.loads(self._state_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, OSError, json.JSONDecodeError):
            return {}
        rows = payload.get("sessions", {}) if isinstance(payload, dict) else {}
        result: dict[str, _SessionRecord] = {}
        if not isinstance(rows, dict):
            return result
        for key, value in rows.items():
            if not isinstance(value, dict):
                continue
            external_id = str(value.get("external_session_id") or "")
            agent_id = str(value.get("agent_id") or "")
            cwd = str(value.get("cwd") or "")
            if not key or not external_id or not agent_id or not cwd:
                continue
            result[str(key)] = _SessionRecord(
                key=str(key),
                agent_id=agent_id,
                external_session_id=external_id,
                cwd=cwd,
                command_digest=str(value.get("command_digest") or ""),
                updated_at=int(value.get("updated_at") or 0),
            )
        return result

    def _persist_sessions(self) -> None:
        with self._snapshot_lock:
            rows = {
                key: value.public()
                for key, value in self._sessions.items()
            }
        self._state_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self._state_path.with_suffix(".tmp")
        temporary.write_text(
            json.dumps(
                {"version": 1, "sessions": rows},
                ensure_ascii=False,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        temporary.replace(self._state_path)

    def _record_failure(self, agent_id: str, error: str) -> None:
        with self._snapshot_lock:
            self._failures[agent_id] = {
                "error": str(error or "")[:240],
                "retry_after": time.time() + STARTUP_BACKOFF_SECONDS,
            }

    def _clear_failure(self, agent_id: str) -> None:
        with self._snapshot_lock:
            self._failures.pop(agent_id, None)

    def _runtime_config(self) -> dict[str, Any]:
        raw = self._config_loader()
        if (
            isinstance(raw, dict)
            and isinstance(raw.get("agents"), dict)
            and "enabled" in raw
        ):
            return raw
        return acp_runtime_config(raw if isinstance(raw, dict) else None)

    def _agent_config(self, agent_id: str) -> dict[str, Any]:
        runtime = self._runtime_config()
        item = dict(runtime.get("agents", {}).get(agent_id, {}))
        return {
            "runtime_enabled": bool(runtime.get("enabled")),
            "enabled": bool(item.get("enabled")),
            "command": str(item.get("command") or "").strip(),
            "prewarm": bool(item.get("prewarm")),
            "max_processes": int(runtime.get("max_processes") or 5),
            "idle_timeout_seconds": int(
                runtime.get("idle_timeout_seconds") or 600
            ),
        }


_runtime_lock = threading.RLock()
_runtime: AcpRuntime | None = None


def acp_runtime() -> AcpRuntime:
    global _runtime
    with _runtime_lock:
        if _runtime is None:
            _runtime = AcpRuntime()
        return _runtime


def shutdown_acp_runtime() -> None:
    global _runtime
    with _runtime_lock:
        runtime = _runtime
        _runtime = None
    if runtime is not None:
        runtime.shutdown()
