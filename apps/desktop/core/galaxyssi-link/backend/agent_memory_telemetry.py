"""Durable process-memory telemetry attributed to Agent task identities."""
from __future__ import annotations

import ctypes
import json
import os
import sqlite3
import sys
import threading
import time
import uuid
from contextlib import contextmanager
from ctypes import wintypes
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Mapping


DEFAULT_RETENTION_SECONDS = 24 * 60 * 60
DEFAULT_MAX_SAMPLES = 25_000
DEFAULT_SAMPLE_INTERVAL_SECONDS = 5.0
DEFAULT_SESSION_MEMORY_TARGET_BYTES = 20 * 1024 * 1024
DEFAULT_MAX_SESSION_SAMPLES = 2_000
TERMINAL_TASK_STATES = {"completed", "failed", "cancelled", "timed_out", "interrupted"}


def default_database_path() -> Path:
    configured = str(os.environ.get("GALAXYSSI_STATE_DIR") or "").strip()
    root = (
        Path(configured)
        if configured
        else Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"
    )
    return root / "agent_memory_telemetry.sqlite3"


@dataclass(frozen=True)
class ProcessMemoryReading:
    resident_bytes: int
    measurement_kind: str
    process_id: int


@dataclass(frozen=True)
class AgentMemorySample:
    sample_id: str
    sampled_at: int
    process_total_bytes: int
    attributed_bytes: int
    measurement_kind: str
    attribution_mode: str
    process_id: int = 0
    agent_id: str = ""
    session_id: str = ""
    provider_id: str = ""
    task_id: str = ""

    def public(self) -> dict:
        return {
            "sample_id": self.sample_id,
            "sampled_at": self.sampled_at,
            "process_total_bytes": max(0, int(self.process_total_bytes)),
            "attributed_bytes": max(0, int(self.attributed_bytes)),
            "measurement_kind": self.measurement_kind,
            "attribution_mode": self.attribution_mode,
            "process_id": max(0, int(self.process_id)),
            "agent_id": self.agent_id,
            "session_id": self.session_id,
            "provider_id": self.provider_id,
            "task_id": self.task_id,
        }


@dataclass(frozen=True)
class AgentSessionMemorySample:
    sample_id: str
    sampled_at: int
    session_id: str
    agent_id: str
    conversation_id: str
    before_bytes: int
    after_bytes: int
    incremental_bytes: int
    target_bytes: int = DEFAULT_SESSION_MEMORY_TARGET_BYTES
    measurement_kind: str = ""

    def public(self) -> dict:
        return {
            "sample_id": self.sample_id,
            "sampled_at": max(0, int(self.sampled_at)),
            "session_id": self.session_id,
            "agent_id": self.agent_id,
            "conversation_id": self.conversation_id,
            "before_bytes": max(0, int(self.before_bytes)),
            "after_bytes": max(0, int(self.after_bytes)),
            "incremental_bytes": max(0, int(self.incremental_bytes)),
            "target_bytes": max(1, int(self.target_bytes)),
            "measurement_kind": self.measurement_kind,
            "within_budget": self.incremental_bytes <= self.target_bytes,
        }


def aggregate_session_memory_samples(
    samples: Iterable[AgentSessionMemorySample],
    target_bytes: int = DEFAULT_SESSION_MEMORY_TARGET_BYTES,
) -> dict:
    ordered = sorted(samples, key=lambda item: (item.sampled_at, item.sample_id))
    target = max(1, int(target_bytes))
    if not ordered:
        return {
            "target_bytes": target,
            "latest_incremental_bytes": 0,
            "peak_incremental_bytes": 0,
            "average_incremental_bytes": 0,
            "sample_count": 0,
            "exceeded_count": 0,
            "latest_session_id": "",
            "latest_conversation_id": "",
            "latest_sampled_at": 0,
            "within_budget": True,
        }
    latest = ordered[-1]
    increments = [max(0, int(item.incremental_bytes)) for item in ordered]
    return {
        "target_bytes": target,
        "latest_incremental_bytes": increments[-1],
        "peak_incremental_bytes": max(increments),
        "average_incremental_bytes": sum(increments) // max(1, len(increments)),
        "sample_count": len(ordered),
        "exceeded_count": sum(1 for value in increments if value > target),
        "latest_session_id": latest.session_id,
        "latest_conversation_id": latest.conversation_id,
        "latest_sampled_at": max(0, int(latest.sampled_at)),
        "within_budget": increments[-1] <= target,
    }


def provider_id_for_task(task: Mapping[str, object]) -> str:
    value = str(
        task.get("provider_id")
        or task.get("delegate_agent_id")
        or task.get("agent_id")
        or task.get("contact_id")
        or ""
    ).strip().lower()
    if not value:
        return ""
    for prefix in ("provider:", "model:", "cloud:", "local-model:"):
        if value.startswith(prefix):
            return value.removeprefix(prefix).split(":", 1)[0]
    if value in {"desktop", "galaxyssi-desktop", "galaxyssi"}:
        return "on-device"
    return value.split(":", 1)[0]


def aggregate_memory_samples(samples: Iterable[AgentMemorySample]) -> dict:
    ordered = sorted(samples, key=lambda item: (item.sampled_at, item.sample_id))
    if not ordered:
        return {
            "measurement_kind": measurement_kind(),
            "sampled_at": 0,
            "process_current_bytes": 0,
            "process_peak_bytes": 0,
            "sample_count": 0,
            "by_agent": [],
            "by_session": [],
            "by_provider": [],
        }
    latest_at = ordered[-1].sampled_at
    latest_rows = [item for item in ordered if item.sampled_at == latest_at]
    process_rows = [
        item for item in ordered
        if item.attribution_mode == "process_total"
    ] or ordered

    def groups(field: str) -> list[dict]:
        grouped: dict[str, list[AgentMemorySample]] = {}
        for item in ordered:
            key = str(getattr(item, field) or "").strip()
            if key:
                grouped.setdefault(key, []).append(item)
        result = []
        for key, values in grouped.items():
            values.sort(key=lambda item: (item.sampled_at, item.sample_id))
            attributed = [max(0, item.attributed_bytes) for item in values]
            result.append({
                "id": key,
                "current_bytes": (
                    attributed[-1]
                    if values[-1].sampled_at == latest_at
                    else 0
                ),
                "peak_bytes": max(attributed),
                "average_bytes": sum(attributed) // max(1, len(attributed)),
                "sample_count": len(values),
                "last_sampled_at": values[-1].sampled_at,
                "estimated": any(
                    item.attribution_mode != "exclusive_process_tree"
                    for item in values
                ),
            })
        return sorted(
            result,
            key=lambda item: (
                -item["current_bytes"],
                -item["peak_bytes"],
                item["id"].lower(),
            ),
        )

    return {
        "measurement_kind": ordered[-1].measurement_kind,
        "sampled_at": latest_at,
        "process_current_bytes": max(
            (item.process_total_bytes for item in latest_rows),
            default=0,
        ),
        "process_peak_bytes": max(
            (item.process_total_bytes for item in process_rows),
            default=0,
        ),
        "sample_count": len(ordered),
        "by_agent": groups("agent_id"),
        "by_session": groups("session_id"),
        "by_provider": groups("provider_id"),
    }


class AgentMemoryTelemetryStore:
    def __init__(
        self,
        path: Path | None = None,
        *,
        retention_seconds: int = DEFAULT_RETENTION_SECONDS,
        max_samples: int = DEFAULT_MAX_SAMPLES,
    ) -> None:
        self.path = Path(path) if path is not None else default_database_path()
        self.retention_seconds = max(60, int(retention_seconds))
        self.max_samples = max(100, int(max_samples))
        self._lock = threading.RLock()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def append_many(self, samples: Iterable[AgentMemorySample]) -> None:
        values = list(samples)
        if not values:
            return
        with self._lock, self._database() as database:
            database.executemany(
                """
                INSERT OR REPLACE INTO memory_samples (
                    sample_id, sampled_at, process_total_bytes, attributed_bytes,
                    measurement_kind, attribution_mode, process_id, agent_id,
                    session_id, provider_id, task_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    (
                        item.sample_id,
                        item.sampled_at,
                        item.process_total_bytes,
                        item.attributed_bytes,
                        item.measurement_kind,
                        item.attribution_mode,
                        item.process_id,
                        item.agent_id,
                        item.session_id,
                        item.provider_id,
                        item.task_id,
                    )
                    for item in values
                ],
            )
            self._prune_locked(database, now_millis=max(item.sampled_at for item in values))

    def recent(self, limit: int = DEFAULT_MAX_SAMPLES) -> list[AgentMemorySample]:
        bounded = max(1, min(int(limit), self.max_samples))
        cutoff = int(time.time() * 1000) - self.retention_seconds * 1000
        with self._lock, self._database() as database:
            rows = database.execute(
                """
                SELECT sample_id, sampled_at, process_total_bytes, attributed_bytes,
                       measurement_kind, attribution_mode, process_id, agent_id,
                       session_id, provider_id, task_id
                FROM memory_samples
                WHERE sampled_at >= ?
                ORDER BY sampled_at DESC, sample_id DESC
                LIMIT ?
                """,
                (cutoff, bounded),
            ).fetchall()
        return [
            AgentMemorySample(
                sample_id=row[0],
                sampled_at=int(row[1]),
                process_total_bytes=int(row[2]),
                attributed_bytes=int(row[3]),
                measurement_kind=row[4],
                attribution_mode=row[5],
                process_id=int(row[6]),
                agent_id=row[7],
                session_id=row[8],
                provider_id=row[9],
                task_id=row[10],
            )
            for row in reversed(rows)
        ]

    def append_session(self, sample: AgentSessionMemorySample) -> None:
        with self._lock, self._database() as database:
            database.execute(
                """
                INSERT OR REPLACE INTO session_memory_samples (
                    sample_id, sampled_at, session_id, agent_id, conversation_id,
                    before_bytes, after_bytes, incremental_bytes, target_bytes,
                    measurement_kind
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    sample.sample_id,
                    sample.sampled_at,
                    sample.session_id,
                    sample.agent_id,
                    sample.conversation_id,
                    sample.before_bytes,
                    sample.after_bytes,
                    sample.incremental_bytes,
                    sample.target_bytes,
                    sample.measurement_kind,
                ),
            )
            self._prune_locked(database, now_millis=sample.sampled_at)

    def recent_sessions(
        self,
        limit: int = DEFAULT_MAX_SESSION_SAMPLES,
    ) -> list[AgentSessionMemorySample]:
        bounded = max(1, min(int(limit), DEFAULT_MAX_SESSION_SAMPLES))
        cutoff = int(time.time() * 1000) - self.retention_seconds * 1000
        with self._lock, self._database() as database:
            rows = database.execute(
                """
                SELECT sample_id, sampled_at, session_id, agent_id, conversation_id,
                       before_bytes, after_bytes, incremental_bytes, target_bytes,
                       measurement_kind
                FROM session_memory_samples
                WHERE sampled_at >= ?
                ORDER BY sampled_at DESC, sample_id DESC
                LIMIT ?
                """,
                (cutoff, bounded),
            ).fetchall()
        return [
            AgentSessionMemorySample(
                sample_id=row[0],
                sampled_at=int(row[1]),
                session_id=row[2],
                agent_id=row[3],
                conversation_id=row[4],
                before_bytes=int(row[5]),
                after_bytes=int(row[6]),
                incremental_bytes=int(row[7]),
                target_bytes=int(row[8]),
                measurement_kind=row[9],
            )
            for row in reversed(rows)
        ]

    def _initialize(self) -> None:
        with self._lock, self._database() as database:
            database.execute(
                """
                CREATE TABLE IF NOT EXISTS memory_samples (
                    sample_id TEXT PRIMARY KEY NOT NULL,
                    sampled_at INTEGER NOT NULL,
                    process_total_bytes INTEGER NOT NULL,
                    attributed_bytes INTEGER NOT NULL,
                    measurement_kind TEXT NOT NULL,
                    attribution_mode TEXT NOT NULL,
                    process_id INTEGER NOT NULL,
                    agent_id TEXT NOT NULL,
                    session_id TEXT NOT NULL,
                    provider_id TEXT NOT NULL,
                    task_id TEXT NOT NULL
                )
                """
            )
            database.execute(
                "CREATE INDEX IF NOT EXISTS idx_memory_samples_time "
                "ON memory_samples(sampled_at)"
            )
            database.execute(
                "CREATE INDEX IF NOT EXISTS idx_memory_samples_task "
                "ON memory_samples(task_id, sampled_at)"
            )
            database.execute(
                """
                CREATE TABLE IF NOT EXISTS session_memory_samples (
                    sample_id TEXT PRIMARY KEY NOT NULL,
                    sampled_at INTEGER NOT NULL,
                    session_id TEXT NOT NULL,
                    agent_id TEXT NOT NULL,
                    conversation_id TEXT NOT NULL,
                    before_bytes INTEGER NOT NULL,
                    after_bytes INTEGER NOT NULL,
                    incremental_bytes INTEGER NOT NULL,
                    target_bytes INTEGER NOT NULL,
                    measurement_kind TEXT NOT NULL
                )
                """
            )
            database.execute(
                "CREATE INDEX IF NOT EXISTS idx_session_memory_samples_time "
                "ON session_memory_samples(sampled_at)"
            )

    def _prune_locked(self, database: sqlite3.Connection, *, now_millis: int) -> None:
        cutoff = int(now_millis) - self.retention_seconds * 1000
        database.execute("DELETE FROM memory_samples WHERE sampled_at < ?", (cutoff,))
        database.execute("DELETE FROM session_memory_samples WHERE sampled_at < ?", (cutoff,))
        database.execute(
            """
            DELETE FROM memory_samples
            WHERE sample_id IN (
                SELECT sample_id FROM memory_samples
                ORDER BY sampled_at DESC, sample_id DESC
                LIMIT -1 OFFSET ?
            )
            """,
            (self.max_samples,),
        )
        database.execute(
            """
            DELETE FROM session_memory_samples
            WHERE sample_id IN (
                SELECT sample_id FROM session_memory_samples
                ORDER BY sampled_at DESC, sample_id DESC
                LIMIT -1 OFFSET ?
            )
            """,
            (DEFAULT_MAX_SESSION_SAMPLES,),
        )

    def _connect(self) -> sqlite3.Connection:
        database = sqlite3.connect(self.path, timeout=10.0)
        database.execute("PRAGMA journal_mode=WAL")
        database.execute("PRAGMA synchronous=NORMAL")
        return database

    @contextmanager
    def _database(self):
        database = self._connect()
        try:
            yield database
            database.commit()
        finally:
            database.close()


class AgentMemoryTelemetryRuntime:
    def __init__(
        self,
        task_provider: Callable[[], list[dict]],
        *,
        store: AgentMemoryTelemetryStore | None = None,
        process_sampler: Callable[[int], ProcessMemoryReading] | None = None,
        process_tree_sampler: Callable[[int], ProcessMemoryReading] | None = None,
        clock: Callable[[], float] = time.time,
        sample_interval_seconds: float = DEFAULT_SAMPLE_INTERVAL_SECONDS,
    ) -> None:
        self._task_provider = task_provider
        self._store = store or AgentMemoryTelemetryStore()
        self._process_sampler = process_sampler or process_memory_reading
        self._process_tree_sampler = process_tree_sampler or process_tree_memory_reading
        self._clock = clock
        self._sample_interval_seconds = max(0.2, float(sample_interval_seconds))
        self._stop = threading.Event()
        self._wake = threading.Event()
        self._thread: threading.Thread | None = None
        self._capture_lock = threading.Lock()
        self._observed_lock = threading.Lock()
        self._observed_tasks: list[dict] = []
        self._cached = aggregate_memory_samples(self._store.recent())
        self._session_cached = aggregate_session_memory_samples(
            self._store.recent_sessions()
        )

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(
            target=self._run,
            name="GalaxySSI-Agent-Memory-Telemetry",
            daemon=True,
        )
        self._thread.start()
        self.request_capture()

    def stop(self) -> None:
        self._stop.set()
        self._wake.set()
        thread = self._thread
        if thread is not None and thread.is_alive():
            thread.join(timeout=2.0)
        self._thread = None

    def request_capture(self) -> None:
        self._wake.set()

    def observe_task(self, task: Mapping[str, object]) -> None:
        with self._observed_lock:
            self._observed_tasks.append(dict(task))
            self._observed_tasks = self._observed_tasks[-256:]
        self.request_capture()

    def observe_session_created(self, event: Mapping[str, object]) -> None:
        before_bytes = max(0, int(event.get("before_bytes") or 0))
        after_bytes = max(0, int(event.get("after_bytes") or 0))
        sample = AgentSessionMemorySample(
            sample_id=uuid.uuid4().hex,
            sampled_at=max(
                0,
                int(event.get("sampled_at") or int(self._clock() * 1000)),
            ),
            session_id=str(event.get("session_id") or "").strip(),
            agent_id=str(event.get("agent_id") or "").strip(),
            conversation_id=str(event.get("conversation_id") or "").strip(),
            before_bytes=before_bytes,
            after_bytes=after_bytes,
            incremental_bytes=max(0, after_bytes - before_bytes),
            target_bytes=max(
                1,
                int(
                    event.get("target_bytes")
                    or DEFAULT_SESSION_MEMORY_TARGET_BYTES
                ),
            ),
            measurement_kind=str(
                event.get("measurement_kind") or measurement_kind()
            ).strip(),
        )
        if not sample.session_id:
            return
        self._store.append_session(sample)
        self._session_cached = aggregate_session_memory_samples(
            self._store.recent_sessions(),
            target_bytes=sample.target_bytes,
        )

    def capture(self) -> dict:
        if not self._capture_lock.acquire(blocking=False):
            return self.snapshot()
        try:
            sampled_at = int(self._clock() * 1000)
            backend = self._process_sampler(os.getpid())
            active_tasks = [
                task for task in self._task_provider()
                if str(task.get("status") or "") not in TERMINAL_TASK_STATES
            ]
            with self._observed_lock:
                observed_tasks = self._observed_tasks
                self._observed_tasks = []
            latest_by_task: dict[str, dict] = {}
            for task in active_tasks + observed_tasks:
                task_id = str(task.get("task_id") or "").strip()
                if not task_id:
                    continue
                current = latest_by_task.get(task_id)
                candidate_order = (
                    int(task.get("status_seq") or 0),
                    int(task.get("updated_at") or 0),
                )
                current_order = (
                    int(current.get("status_seq") or 0),
                    int(current.get("updated_at") or 0),
                ) if current is not None else (-1, -1)
                if current is None or candidate_order >= current_order:
                    latest_by_task[task_id] = task
            tasks = list(latest_by_task.values())
            samples = [
                AgentMemorySample(
                    sample_id=uuid.uuid4().hex,
                    sampled_at=sampled_at,
                    process_total_bytes=backend.resident_bytes,
                    attributed_bytes=0,
                    measurement_kind=backend.measurement_kind,
                    attribution_mode="process_total",
                    process_id=backend.process_id,
                )
            ]
            in_process = [
                task for task in tasks
                if int(task.get("process_id") or 0) <= 0
            ]
            shared_bytes = (
                backend.resident_bytes // len(in_process)
                if in_process else 0
            )
            for task in tasks:
                process_id = max(0, int(task.get("process_id") or 0))
                if process_id > 0:
                    reading = self._process_tree_sampler(process_id)
                    attributed = reading.resident_bytes
                    mode = "exclusive_process_tree"
                    kind = reading.measurement_kind
                else:
                    attributed = shared_bytes
                    mode = "shared_weighted"
                    kind = backend.measurement_kind
                agent_id = str(
                    task.get("delegate_agent_id")
                    or task.get("agent_id")
                    or "desktop"
                ).strip()
                session_id = str(
                    task.get("client_conversation_id")
                    or task.get("conversation_id")
                    or task.get("thread_id")
                    or ""
                ).strip()
                samples.append(AgentMemorySample(
                    sample_id=uuid.uuid4().hex,
                    sampled_at=sampled_at,
                    process_total_bytes=backend.resident_bytes,
                    attributed_bytes=max(0, attributed),
                    measurement_kind=kind,
                    attribution_mode=mode,
                    process_id=process_id,
                    agent_id=agent_id,
                    session_id=session_id,
                    provider_id=provider_id_for_task(task),
                    task_id=str(task.get("task_id") or "").strip(),
                ))
            self._store.append_many(samples)
            self._cached = aggregate_memory_samples(self._store.recent())
            return self.snapshot()
        finally:
            self._capture_lock.release()

    def snapshot(self) -> dict:
        payload = json.loads(json.dumps(self._cached))
        payload["session_budget"] = json.loads(json.dumps(self._session_cached))
        return payload

    def _run(self) -> None:
        while not self._stop.is_set():
            self._wake.wait(self._sample_interval_seconds)
            self._wake.clear()
            if self._stop.is_set():
                return
            try:
                self.capture()
            except Exception:
                continue


def measurement_kind() -> str:
    if os.name == "nt":
        return "windows_working_set"
    if sys.platform == "darwin":
        return "macos_resident_set"
    return "linux_rss"


def process_memory_reading(process_id: int) -> ProcessMemoryReading:
    pid = max(0, int(process_id))
    if pid <= 0:
        return ProcessMemoryReading(0, measurement_kind(), pid)
    if os.name == "nt":
        return ProcessMemoryReading(
            _windows_working_set_bytes(pid),
            "windows_working_set",
            pid,
        )
    return ProcessMemoryReading(_posix_rss_bytes(pid), measurement_kind(), pid)


def process_tree_memory_reading(process_id: int) -> ProcessMemoryReading:
    pid = max(0, int(process_id))
    process_ids = _process_tree_ids(pid)
    total = sum(process_memory_reading(item).resident_bytes for item in process_ids)
    return ProcessMemoryReading(total, measurement_kind(), pid)


def _windows_working_set_bytes(process_id: int) -> int:
    class ProcessMemoryCounters(ctypes.Structure):
        _fields_ = [
            ("cb", wintypes.DWORD),
            ("PageFaultCount", wintypes.DWORD),
            ("PeakWorkingSetSize", ctypes.c_size_t),
            ("WorkingSetSize", ctypes.c_size_t),
            ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
            ("QuotaPagedPoolUsage", ctypes.c_size_t),
            ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
            ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
            ("PagefileUsage", ctypes.c_size_t),
            ("PeakPagefileUsage", ctypes.c_size_t),
        ]

    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    PROCESS_VM_READ = 0x0010
    kernel32 = ctypes.windll.kernel32
    psapi = ctypes.windll.psapi
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL
    psapi.GetProcessMemoryInfo.argtypes = [
        wintypes.HANDLE,
        ctypes.c_void_p,
        wintypes.DWORD,
    ]
    psapi.GetProcessMemoryInfo.restype = wintypes.BOOL
    handle = kernel32.OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
        False,
        process_id,
    )
    if not handle:
        return 0
    try:
        counters = ProcessMemoryCounters()
        counters.cb = ctypes.sizeof(counters)
        ok = psapi.GetProcessMemoryInfo(
            handle,
            ctypes.byref(counters),
            counters.cb,
        )
        return max(0, int(counters.WorkingSetSize)) if ok else 0
    finally:
        kernel32.CloseHandle(handle)


def _posix_rss_bytes(process_id: int) -> int:
    status = Path(f"/proc/{process_id}/status")
    if status.exists():
        try:
            for line in status.read_text(encoding="utf-8", errors="ignore").splitlines():
                if line.startswith("VmRSS:"):
                    return max(0, int(line.split()[1]) * 1024)
        except (IndexError, OSError, ValueError):
            return 0
    if process_id == os.getpid():
        try:
            import resource

            resident = int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
            return max(0, resident if sys.platform == "darwin" else resident * 1024)
        except (ImportError, OSError, ValueError):
            return 0
    return 0


def _process_tree_ids(root_process_id: int) -> set[int]:
    root = max(0, int(root_process_id))
    if root <= 0:
        return set()
    parents = _windows_parent_processes() if os.name == "nt" else _posix_parent_processes()
    children_by_parent: dict[int, list[int]] = {}
    for process_id, parent_id in parents.items():
        children_by_parent.setdefault(parent_id, []).append(process_id)
    result = {root}
    pending = [root]
    while pending:
        parent = pending.pop()
        children = [
            pid for pid in children_by_parent.get(parent, [])
            if pid not in result
        ]
        result.update(children)
        pending.extend(children)
    return result


def _windows_parent_processes() -> dict[int, int]:
    TH32CS_SNAPPROCESS = 0x00000002
    INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

    class ProcessEntry32W(ctypes.Structure):
        _fields_ = [
            ("dwSize", wintypes.DWORD),
            ("cntUsage", wintypes.DWORD),
            ("th32ProcessID", wintypes.DWORD),
            ("th32DefaultHeapID", ctypes.c_size_t),
            ("th32ModuleID", wintypes.DWORD),
            ("cntThreads", wintypes.DWORD),
            ("th32ParentProcessID", wintypes.DWORD),
            ("pcPriClassBase", wintypes.LONG),
            ("dwFlags", wintypes.DWORD),
            ("szExeFile", wintypes.WCHAR * 260),
        ]

    kernel32 = ctypes.windll.kernel32
    kernel32.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    kernel32.Process32FirstW.argtypes = [
        wintypes.HANDLE,
        ctypes.c_void_p,
    ]
    kernel32.Process32FirstW.restype = wintypes.BOOL
    kernel32.Process32NextW.argtypes = [
        wintypes.HANDLE,
        ctypes.c_void_p,
    ]
    kernel32.Process32NextW.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL
    snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snapshot == INVALID_HANDLE_VALUE:
        return {}
    result: dict[int, int] = {}
    try:
        entry = ProcessEntry32W()
        entry.dwSize = ctypes.sizeof(entry)
        success = kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
        while success:
            result[int(entry.th32ProcessID)] = int(entry.th32ParentProcessID)
            success = kernel32.Process32NextW(snapshot, ctypes.byref(entry))
    finally:
        kernel32.CloseHandle(snapshot)
    return result


def _posix_parent_processes() -> dict[int, int]:
    result: dict[int, int] = {}
    proc = Path("/proc")
    if not proc.exists():
        return result
    for item in proc.iterdir():
        if not item.name.isdigit():
            continue
        try:
            stat = (item / "stat").read_text(encoding="utf-8", errors="ignore")
            tail = stat.rsplit(")", 1)[1].strip().split()
            result[int(item.name)] = int(tail[1])
        except (IndexError, OSError, ValueError):
            continue
    return result


_runtime_lock = threading.Lock()
_runtime: AgentMemoryTelemetryRuntime | None = None


def agent_memory_telemetry_runtime(
    task_provider: Callable[[], list[dict]] | None = None,
) -> AgentMemoryTelemetryRuntime:
    global _runtime
    with _runtime_lock:
        if _runtime is None:
            if task_provider is None:
                task_provider = lambda: []
            _runtime = AgentMemoryTelemetryRuntime(task_provider)
        elif task_provider is not None:
            _runtime._task_provider = task_provider
        return _runtime
