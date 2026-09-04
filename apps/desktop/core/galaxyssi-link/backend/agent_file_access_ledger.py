"""Durable, scope-isolated file access tracking for collaborating Agents."""
from __future__ import annotations

import hashlib
import json
import os
import re
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Mapping

from host_execution_config_guard import (
    HostExecutionConfigGuard,
    HostExecutionConfigViolation,
)


PROTOCOL = "galaxyssi.agent-file-access/1.0"
STATE_VERSION = 1
MAX_SCOPES = 512
MAX_FILES_PER_SCOPE = 4_096
MAX_CONFLICTS_PER_SCOPE = 2_048
MAX_CONTEXT_CONFLICTS = 12
MAX_CONTEXT_CHARS = 8_000
MAX_CAPTURE_FILES = 4_096
MAX_CAPTURE_FILE_BYTES = 16 * 1024 * 1024
MAX_CAPTURE_TOTAL_BYTES = 128 * 1024 * 1024
MAX_PATH_CHARS = 1_024
_IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,255}$")
_SHA256 = re.compile(r"^[a-f0-9]{64}$")
_IGNORED_DIRECTORY_NAMES = frozenset({
    ".git",
    ".gradle",
    ".idea",
    ".next",
    ".pytest_cache",
    ".venv",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "node_modules",
    "target",
    "vendor",
})


class AgentFileAccessError(RuntimeError):
    pass


@dataclass(frozen=True)
class FileAccessScope:
    client_route_id: str
    conversation_id: str
    task_id: str
    repository_id: str = ""
    workspace_id: str = ""

    @classmethod
    def create(
        cls,
        *,
        client_route_id: object,
        conversation_id: object,
        task_id: object,
        repository_id: object = "",
        workspace_id: object = "",
    ) -> "FileAccessScope":
        repository = _safe_identifier(repository_id, "repository")
        workspace = _safe_identifier(workspace_id, "workspace")
        if not repository and not workspace:
            workspace = _safe_identifier(task_id, "task-workspace")
        return cls(
            client_route_id=_safe_identifier(
                client_route_id,
                "desktop-local",
                default="desktop-local",
            ),
            conversation_id=_safe_identifier(
                conversation_id,
                "conversation",
                default="conversation-local",
            ),
            task_id=_safe_identifier(task_id, "task", default="task-local"),
            repository_id=repository,
            workspace_id=workspace,
        )

    def public(self) -> dict:
        return {
            "client_route_id": self.client_route_id,
            "conversation_id": self.conversation_id,
            "task_id": self.task_id,
            "repository_id": self.repository_id,
            "workspace_id": self.workspace_id,
        }

    @property
    def key(self) -> str:
        payload = json.dumps(
            self.public(),
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        return f"scope-{hashlib.sha256(payload).hexdigest()[:32]}"


@dataclass(frozen=True)
class FileObservation:
    path: str
    sha256: str = ""
    exists: bool = True
    size_bytes: int = 0

    @classmethod
    def create(
        cls,
        path: object,
        *,
        sha256: object = "",
        exists: bool = True,
        size_bytes: int = 0,
    ) -> "FileObservation":
        normalized_path = _relative_path(path)
        normalized_sha256 = str(sha256 or "").strip().lower()
        if normalized_sha256 and not _SHA256.fullmatch(normalized_sha256):
            raise AgentFileAccessError("File observation SHA-256 is invalid")
        return cls(
            path=normalized_path,
            sha256=normalized_sha256,
            exists=bool(exists),
            size_bytes=max(0, int(size_bytes or 0)),
        )

    @property
    def signature(self) -> str:
        return f"{1 if self.exists else 0}:{self.sha256}:{self.size_bytes}"


class AgentFileAccessLedger:
    """Records read/write sets and creates conflicts when observed files change."""

    def __init__(
        self,
        path: Path,
        *,
        now: Callable[[], float] = time.time,
        notifier: Callable[[dict, tuple[str, ...]], None] | None = None,
    ) -> None:
        self.path = Path(path)
        self._now = now
        self._notifier = notifier or _publish_conflict_notice
        self._lock = threading.RLock()
        self._state = self._load()

    def record_read(
        self,
        scope: FileAccessScope,
        *,
        agent_id: object,
        observation: FileObservation,
        event_id: object = "",
    ) -> dict:
        return self.record_batch(
            scope,
            agent_id=agent_id,
            reads=(observation,),
            event_id=event_id,
        )

    def record_write(
        self,
        scope: FileAccessScope,
        *,
        agent_id: object,
        observation: FileObservation,
        event_id: object = "",
        collaboration_channel_ids: Iterable[str] = (),
    ) -> dict:
        return self.record_batch(
            scope,
            agent_id=agent_id,
            writes=(observation,),
            event_id=event_id,
            collaboration_channel_ids=collaboration_channel_ids,
        )

    def record_batch(
        self,
        scope: FileAccessScope,
        *,
        agent_id: object,
        reads: Iterable[FileObservation] = (),
        writes: Iterable[FileObservation] = (),
        event_id: object = "",
        collaboration_channel_ids: Iterable[str] = (),
        observation_mode: str = "exact",
    ) -> dict:
        actor = _safe_identifier(agent_id, "agent", default="agent-unknown")
        normalized_event_id = _safe_identifier(event_id, "access-event")
        normalized_channels = tuple(dict.fromkeys(
            _safe_identifier(value, "channel")
            for value in collaboration_channel_ids
            if str(value or "").strip()
        ))
        read_rows = tuple(_coerce_observation(value) for value in reads)
        write_rows = tuple(_coerce_observation(value) for value in writes)
        created_conflicts: list[dict] = []
        now_ms = int(self._now() * 1_000)

        with self._lock:
            row = self._scope_locked(scope, create=True)
            events = row.setdefault("events", {})
            if normalized_event_id and normalized_event_id in events:
                return {
                    "replayed": True,
                    "reads_recorded": 0,
                    "writes_recorded": 0,
                    "conflicts_created": [],
                }

            for observation in read_rows:
                self._record_read_locked(
                    row,
                    actor,
                    observation,
                    now_ms,
                    observation_mode,
                )
            for observation in write_rows:
                created_conflicts.extend(
                    self._record_write_locked(
                        row,
                        scope,
                        actor,
                        observation,
                        now_ms,
                        observation_mode,
                    )
                )
            if normalized_event_id:
                events[normalized_event_id] = now_ms
                if len(events) > 1_024:
                    ordered = sorted(events.items(), key=lambda item: int(item[1]))
                    for key, _value in ordered[:len(events) - 1_024]:
                        events.pop(key, None)
            row["updated_at"] = now_ms
            self._prune_scope_locked(row)
            self._prune_locked()
            self._save_locked()

        for conflict in created_conflicts:
            try:
                self._notifier(dict(conflict), normalized_channels)
            except Exception:
                pass
        return {
            "replayed": False,
            "reads_recorded": len(read_rows),
            "writes_recorded": len(write_rows),
            "conflicts_created": [dict(value) for value in created_conflicts],
        }

    def conflicts(
        self,
        scope: FileAccessScope,
        *,
        requester_agent_id: object = "",
        status: str = "open",
        limit: int = 100,
    ) -> list[dict]:
        requester = _safe_identifier(requester_agent_id, "agent")
        normalized_status = str(status or "").strip().lower()
        if normalized_status not in {"", "open", "resolved"}:
            raise AgentFileAccessError("Conflict status must be open or resolved")
        with self._lock:
            row = self._scope_locked(scope, create=False)
            if row is None:
                return []
            values = [
                dict(value)
                for value in row.get("conflicts", {}).values()
                if (not requester or value.get("reader_agent_id") == requester)
                and (not normalized_status or value.get("status") == normalized_status)
            ]
        values.sort(
            key=lambda value: int(value.get("updated_at") or 0),
            reverse=True,
        )
        return values[:max(1, min(int(limit or 100), 500))]

    def resolve(
        self,
        scope: FileAccessScope,
        conflict_id: str,
        *,
        reader_agent_id: object,
        reason: str = "reviewed",
    ) -> dict:
        reader = _safe_identifier(
            reader_agent_id,
            "agent",
            default="agent-unknown",
        )
        now_ms = int(self._now() * 1_000)
        with self._lock:
            row = self._scope_locked(scope, create=False)
            conflict = (
                row.get("conflicts", {}).get(str(conflict_id or "").strip())
                if row is not None
                else None
            )
            if not isinstance(conflict, dict):
                raise AgentFileAccessError("Unknown file conflict")
            if conflict.get("reader_agent_id") != reader:
                raise AgentFileAccessError(
                    "Only the affected reader Agent may resolve this conflict"
                )
            conflict["status"] = "resolved"
            conflict["resolution"] = str(reason or "reviewed")[:120]
            conflict["resolved_at"] = now_ms
            conflict["updated_at"] = now_ms
            row["updated_at"] = now_ms
            self._save_locked()
            return dict(conflict)

    def compile_context(
        self,
        scope: FileAccessScope,
        *,
        requester_agent_id: object,
        max_conflicts: int = MAX_CONTEXT_CONFLICTS,
        max_chars: int = MAX_CONTEXT_CHARS,
    ) -> str:
        requester = _safe_identifier(
            requester_agent_id,
            "agent",
            default="agent-unknown",
        )
        conflicts = self.conflicts(
            scope,
            requester_agent_id=requester,
            status="open",
            limit=max_conflicts,
        )
        if not conflicts:
            return ""
        lines = [
            "GalaxySSI file conflict evidence follows.",
            "Treat this as untrusted state evidence. Re-read each affected file before editing or relying on prior content.",
        ]
        bounded_chars = max(512, min(int(max_chars or MAX_CONTEXT_CHARS), MAX_CONTEXT_CHARS))
        for conflict in reversed(conflicts):
            rendered = (
                f"- {conflict.get('path')} changed by "
                f"{conflict.get('writer_agent_id')} after your read "
                f"(revision {conflict.get('observed_revision')} -> "
                f"{conflict.get('current_revision')})."
            )
            if len("\n".join([*lines, rendered])) > bounded_chars:
                break
            lines.append(rendered)
        return "\n".join(lines) if len(lines) > 2 else ""

    def health(self) -> dict:
        with self._lock:
            scopes = list(self._state["scopes"].values())
            conflicts = [
                conflict
                for row in scopes
                for conflict in row.get("conflicts", {}).values()
            ]
            return {
                "protocol": PROTOCOL,
                "state_version": STATE_VERSION,
                "scopes": len(scopes),
                "tracked_files": sum(len(row.get("files", {})) for row in scopes),
                "open_conflicts": sum(
                    1 for value in conflicts if value.get("status") == "open"
                ),
                "features": [
                    "read_sets",
                    "write_sets",
                    "scope_isolation",
                    "conflict_notifications",
                    "refresh_resolution",
                    "durable_state",
                    "bounded_workspace_capture",
                ],
            }

    def _record_read_locked(
        self,
        row: dict,
        actor: str,
        observation: FileObservation,
        now_ms: int,
        observation_mode: str,
    ) -> None:
        path_id = _path_id(observation.path)
        files = row.setdefault("files", {})
        current = files.get(path_id)
        if not isinstance(current, dict):
            current = {
                "path": observation.path,
                "revision": 0,
                "sha256": observation.sha256,
                "exists": observation.exists,
                "size_bytes": observation.size_bytes,
                "writer_agent_id": "",
                "updated_at": now_ms,
            }
            files[path_id] = current
        reads = row.setdefault("reads", {}).setdefault(actor, {})
        reads[path_id] = {
            "path": observation.path,
            "observed_revision": int(current.get("revision") or 0),
            "observed_sha256": observation.sha256 or str(current.get("sha256") or ""),
            "observed_exists": observation.exists,
            "size_bytes": observation.size_bytes,
            "read_at": now_ms,
            "observation_mode": str(observation_mode or "exact")[:80],
        }
        current_signature = _row_signature(current)
        if observation.signature == current_signature:
            for conflict in row.setdefault("conflicts", {}).values():
                if (
                    conflict.get("status") == "open"
                    and conflict.get("reader_agent_id") == actor
                    and conflict.get("path_id") == path_id
                ):
                    conflict["status"] = "resolved"
                    conflict["resolution"] = "refreshed"
                    conflict["resolved_at"] = now_ms
                    conflict["updated_at"] = now_ms

    def _record_write_locked(
        self,
        row: dict,
        scope: FileAccessScope,
        actor: str,
        observation: FileObservation,
        now_ms: int,
        observation_mode: str,
    ) -> list[dict]:
        path_id = _path_id(observation.path)
        files = row.setdefault("files", {})
        current = files.get(path_id)
        previous_revision = int(current.get("revision") or 0) if isinstance(current, dict) else 0
        previous_signature = _row_signature(current) if isinstance(current, dict) else ""
        changed = previous_signature != observation.signature
        revision = previous_revision + 1 if changed else previous_revision
        files[path_id] = {
            "path": observation.path,
            "revision": revision,
            "sha256": observation.sha256,
            "exists": observation.exists,
            "size_bytes": observation.size_bytes,
            "writer_agent_id": actor,
            "updated_at": now_ms,
        }
        row.setdefault("writes", {}).setdefault(actor, {})[path_id] = {
            "path": observation.path,
            "revision": revision,
            "sha256": observation.sha256,
            "exists": observation.exists,
            "size_bytes": observation.size_bytes,
            "written_at": now_ms,
            "observation_mode": str(observation_mode or "exact")[:80],
        }
        if not changed:
            return []

        created: list[dict] = []
        for reader, read_set in row.setdefault("reads", {}).items():
            if reader == actor:
                continue
            read = read_set.get(path_id)
            if not isinstance(read, dict):
                continue
            observed_signature = (
                f"{1 if read.get('observed_exists') else 0}:"
                f"{read.get('observed_sha256') or ''}:"
                f"{int(read.get('size_bytes') or 0)}"
            )
            if observed_signature == observation.signature:
                continue
            conflict_id = _conflict_id(
                scope,
                reader,
                actor,
                path_id,
                revision,
            )
            conflicts = row.setdefault("conflicts", {})
            if conflict_id in conflicts:
                continue
            conflict = {
                "conflict_id": conflict_id,
                "scope": scope.public(),
                "path_id": path_id,
                "path": observation.path,
                "reader_agent_id": reader,
                "writer_agent_id": actor,
                "observed_revision": int(read.get("observed_revision") or 0),
                "current_revision": revision,
                "observed_sha256": str(read.get("observed_sha256") or ""),
                "current_sha256": observation.sha256,
                "current_exists": observation.exists,
                "status": "open",
                "created_at": now_ms,
                "updated_at": now_ms,
            }
            conflicts[conflict_id] = conflict
            created.append(dict(conflict))
        return created

    def _scope_locked(
        self,
        scope: FileAccessScope,
        *,
        create: bool,
    ) -> dict | None:
        scopes = self._state["scopes"]
        row = scopes.get(scope.key)
        if isinstance(row, dict):
            if row.get("scope") != scope.public():
                raise AgentFileAccessError("File access scope digest collision")
            return row
        if not create:
            return None
        now_ms = int(self._now() * 1_000)
        row = {
            "scope": scope.public(),
            "created_at": now_ms,
            "updated_at": now_ms,
            "files": {},
            "reads": {},
            "writes": {},
            "conflicts": {},
            "events": {},
        }
        scopes[scope.key] = row
        return row

    def _load(self) -> dict:
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
            if (
                isinstance(payload, dict)
                and int(payload.get("version") or 0) == STATE_VERSION
                and isinstance(payload.get("scopes"), dict)
            ):
                return payload
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            pass
        return {"version": STATE_VERSION, "scopes": {}}

    def _save_locked(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(f"{self.path.suffix}.tmp")
        temporary.write_text(
            json.dumps(
                self._state,
                ensure_ascii=False,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        try:
            os.chmod(temporary, 0o600)
        except OSError:
            pass
        temporary.replace(self.path)

    def _prune_scope_locked(self, row: dict) -> None:
        files = row.get("files", {})
        if len(files) > MAX_FILES_PER_SCOPE:
            ordered = sorted(
                files.items(),
                key=lambda item: int(item[1].get("updated_at") or 0),
            )
            removed = {
                path_id
                for path_id, _value in ordered[:len(files) - MAX_FILES_PER_SCOPE]
            }
            for path_id in removed:
                files.pop(path_id, None)
            for access_sets in (row.get("reads", {}), row.get("writes", {})):
                for values in access_sets.values():
                    for path_id in removed:
                        values.pop(path_id, None)
        conflicts = row.get("conflicts", {})
        if len(conflicts) > MAX_CONFLICTS_PER_SCOPE:
            ordered = sorted(
                conflicts.items(),
                key=lambda item: (
                    1 if item[1].get("status") == "open" else 0,
                    int(item[1].get("updated_at") or 0),
                ),
            )
            for conflict_id, _value in ordered[:len(conflicts) - MAX_CONFLICTS_PER_SCOPE]:
                conflicts.pop(conflict_id, None)

    def _prune_locked(self) -> None:
        scopes = self._state["scopes"]
        if len(scopes) <= MAX_SCOPES:
            return
        ordered = sorted(
            scopes.items(),
            key=lambda item: int(item[1].get("updated_at") or 0),
        )
        for scope_id, _row in ordered[:len(scopes) - MAX_SCOPES]:
            scopes.pop(scope_id, None)


class AgentWorkspaceCapture:
    """Conservative read/write capture for CLI Agents without file telemetry."""

    def __init__(
        self,
        root: Path,
        scope: FileAccessScope,
        agent_id: str,
        ledger: AgentFileAccessLedger,
        before: Mapping[str, FileObservation],
        channel_ids: tuple[str, ...],
        capture_id: str,
        host_config_guard: HostExecutionConfigGuard,
    ) -> None:
        self.root = Path(root)
        self.scope = scope
        self.agent_id = agent_id
        self.ledger = ledger
        self.before = dict(before)
        self.channel_ids = channel_ids
        self.capture_id = capture_id
        self.host_config_guard = host_config_guard
        self._finished = False

    @classmethod
    def begin(
        cls,
        root: Path,
        *,
        scope: FileAccessScope,
        agent_id: object,
        ledger: AgentFileAccessLedger | None = None,
        collaboration_channel_ids: Iterable[str] = (),
        capture_id: str = "",
    ) -> "AgentWorkspaceCapture":
        resolved_root = Path(root).expanduser().resolve()
        active_ledger = ledger or agent_file_access_ledger()
        actor = _safe_identifier(agent_id, "agent", default="agent-unknown")
        host_config_guard = HostExecutionConfigGuard.begin(
            resolved_root,
            agent_id=actor,
            capture_id=capture_id,
        )
        before = capture_workspace(resolved_root)
        active_ledger.record_batch(
            scope,
            agent_id=actor,
            reads=before.values(),
            event_id=f"{capture_id}:reads" if capture_id else "",
            observation_mode="conservative_workspace_snapshot",
        )
        return cls(
            resolved_root,
            scope,
            actor,
            active_ledger,
            before,
            tuple(collaboration_channel_ids),
            capture_id,
            host_config_guard,
        )

    def finish(self) -> dict:
        if self._finished:
            return {"reads_recorded": 0, "writes_recorded": 0, "conflicts_created": []}
        self._finished = True
        after = capture_workspace(self.root)
        violations = self.host_config_guard.finish()
        writes_by_path: dict[str, FileObservation] = {}
        for path in sorted(set(self.before).union(after)):
            previous = self.before.get(path)
            current = after.get(path)
            if previous == current:
                continue
            writes_by_path[path] = (
                current
                if current is not None
                else FileObservation.create(path, exists=False)
            )
        for violation in violations:
            path = str(violation.get("path") or "")
            if not path or path in writes_by_path:
                continue
            after_sha256 = str(violation.get("after_sha256") or "")
            writes_by_path[path] = FileObservation.create(
                path,
                exists=str(violation.get("operation") or "") != "deleted",
                sha256=after_sha256,
                size_bytes=int(violation.get("after_size_bytes") or 0),
            )
        result = self.ledger.record_batch(
            self.scope,
            agent_id=self.agent_id,
            writes=writes_by_path.values(),
            event_id=f"{self.capture_id}:writes" if self.capture_id else "",
            collaboration_channel_ids=self.channel_ids,
            observation_mode="conservative_workspace_snapshot",
        )
        result["host_config_violations"] = [dict(item) for item in violations]
        if violations:
            raise HostExecutionConfigViolation(violations)
        return result


def capture_workspace(root: Path) -> dict[str, FileObservation]:
    resolved_root = Path(root).expanduser().resolve()
    if not resolved_root.is_dir():
        return {}
    observations: dict[str, FileObservation] = {}
    total_bytes = 0
    for current_root, directory_names, file_names in os.walk(resolved_root):
        directory_names[:] = sorted(
            value
            for value in directory_names
            if value not in _IGNORED_DIRECTORY_NAMES
        )
        for file_name in sorted(file_names):
            path = Path(current_root) / file_name
            if path.is_symlink() or not path.is_file():
                continue
            try:
                stat = path.stat()
                relative = path.relative_to(resolved_root).as_posix()
                if (
                    stat.st_size <= MAX_CAPTURE_FILE_BYTES
                    and total_bytes + stat.st_size <= MAX_CAPTURE_TOTAL_BYTES
                ):
                    sha256 = _sha256_file(path)
                    total_bytes += stat.st_size
                else:
                    marker = (
                        f"bounded:{stat.st_size}:{stat.st_mtime_ns}"
                    ).encode("utf-8")
                    sha256 = hashlib.sha256(marker).hexdigest()
                observations[relative] = FileObservation.create(
                    relative,
                    sha256=sha256,
                    size_bytes=stat.st_size,
                )
            except (OSError, ValueError):
                continue
            if len(observations) >= MAX_CAPTURE_FILES:
                return observations
    return observations


def repository_identity(repository_root: str | Path) -> str:
    root = Path(repository_root).expanduser().resolve(strict=False)
    normalized = os.path.normcase(str(root))
    return f"repo-{hashlib.sha256(normalized.encode('utf-8', errors='replace')).hexdigest()[:32]}"


def observation_for_path(root: Path, path: Path) -> FileObservation:
    resolved_root = Path(root).expanduser().resolve()
    resolved_path = Path(path).expanduser().resolve()
    try:
        relative = resolved_path.relative_to(resolved_root).as_posix()
    except ValueError as exc:
        raise AgentFileAccessError("File access path is outside its scope") from exc
    if not resolved_path.exists():
        return FileObservation.create(relative, exists=False)
    if resolved_path.is_symlink() or not resolved_path.is_file():
        raise AgentFileAccessError("File access path is not a regular file")
    return FileObservation.create(
        relative,
        sha256=_sha256_file(resolved_path),
        size_bytes=resolved_path.stat().st_size,
    )


def _coerce_observation(value: FileObservation) -> FileObservation:
    if not isinstance(value, FileObservation):
        raise AgentFileAccessError("File access entries must be FileObservation values")
    return value


def _row_signature(value: Mapping | None) -> str:
    if not isinstance(value, Mapping):
        return ""
    return (
        f"{1 if value.get('exists') else 0}:"
        f"{value.get('sha256') or ''}:"
        f"{int(value.get('size_bytes') or 0)}"
    )


def _path_id(path: str) -> str:
    return f"path-{hashlib.sha256(path.encode('utf-8')).hexdigest()[:32]}"


def _conflict_id(
    scope: FileAccessScope,
    reader: str,
    writer: str,
    path_id: str,
    revision: int,
) -> str:
    payload = (
        f"{scope.key}\0{reader}\0{writer}\0{path_id}\0{revision}"
    ).encode("utf-8")
    return f"conflict-{hashlib.sha256(payload).hexdigest()[:32]}"


def _relative_path(value: object) -> str:
    raw = str(value or "").strip().replace("\\", "/")
    if not raw:
        raise AgentFileAccessError("File access path is required")
    if len(raw) > MAX_PATH_CHARS:
        raise AgentFileAccessError("File access path exceeds the bounded limit")
    path = Path(raw)
    if path.is_absolute() or raw.startswith("/") or ":" in raw.split("/", 1)[0]:
        raise AgentFileAccessError("File access paths must be relative")
    parts = tuple(part for part in path.parts if part not in {"", "."})
    if not parts or any(part == ".." for part in parts):
        raise AgentFileAccessError("File access path escapes its scope")
    return "/".join(parts)


def _safe_identifier(
    value: object,
    prefix: str,
    *,
    default: str = "",
) -> str:
    normalized = str(value or "").strip()
    if not normalized:
        return default
    if _IDENTIFIER.fullmatch(normalized):
        return normalized
    digest = hashlib.sha256(
        normalized.encode("utf-8", errors="replace")
    ).hexdigest()[:32]
    return f"{prefix}-{digest}"


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        while True:
            block = handle.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def _publish_conflict_notice(conflict: dict, channel_ids: tuple[str, ...]) -> None:
    if not channel_ids:
        return
    from agent_collaboration_channels import agent_collaboration_bus

    content = (
        f"File conflict: {conflict.get('path')} changed after "
        f"{conflict.get('reader_agent_id')} read it. The affected Agent must "
        "re-read the file before continuing."
    )
    metadata = {
        "kind": "file_conflict",
        "conflict_id": conflict.get("conflict_id"),
        "reader_agent_id": conflict.get("reader_agent_id"),
        "writer_agent_id": conflict.get("writer_agent_id"),
        "path": conflict.get("path"),
        "current_revision": conflict.get("current_revision"),
    }
    for channel_id in channel_ids:
        try:
            agent_collaboration_bus().publish(
                channel_id,
                sender_agent_id=str(conflict.get("writer_agent_id") or ""),
                content=content,
                message_id=f"file-conflict-{conflict.get('conflict_id')}",
                metadata=metadata,
            )
        except Exception:
            continue


_LEDGER: AgentFileAccessLedger | None = None
_LEDGER_PATH = ""
_LEDGER_LOCK = threading.Lock()


def agent_file_access_ledger(path: Path | None = None) -> AgentFileAccessLedger:
    global _LEDGER, _LEDGER_PATH
    resolved = Path(path) if path is not None else _default_state_path()
    cache_key = str(resolved.resolve(strict=False))
    with _LEDGER_LOCK:
        if _LEDGER is None or _LEDGER_PATH != cache_key:
            _LEDGER = AgentFileAccessLedger(resolved)
            _LEDGER_PATH = cache_key
        return _LEDGER


def _default_state_path() -> Path:
    configured = os.environ.get("GALAXYSSI_STATE_DIR", "").strip()
    root = (
        Path(configured)
        if configured
        else Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"
    )
    return root / "agent-file-access-ledger.json"
