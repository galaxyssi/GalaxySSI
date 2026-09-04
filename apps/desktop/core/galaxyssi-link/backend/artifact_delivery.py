"""Reliable, phone-owned delivery for Agent task artifacts."""
from __future__ import annotations

import base64
import hashlib
import json
import mimetypes
import os
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote

from image_transport import MAX_IMAGE_TRANSPORT_BYTES, compress_image_file
from task_workspace import cleanup_task_workspace, task_artifact_path, task_workspace, workspace_root


MAX_ARTIFACT_BYTES = 64 * 1024 * 1024
ARTIFACT_CHUNK_BYTES = 256 * 1024
MAX_ARTIFACT_CHUNKS = MAX_ARTIFACT_BYTES // ARTIFACT_CHUNK_BYTES
LEDGER_NAME = ".artifact-delivery-ledger.json"
LEDGER_TTL_SECONDS = 7 * 24 * 60 * 60
APK_MIME_TYPE = "application/vnd.android.package-archive"
MIME_OVERRIDES = {
    ".apk": APK_MIME_TYPE,
    ".aab": "application/octet-stream",
    ".apks": "application/zip",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
}
IMAGE_SUFFIXES = {".avif", ".bmp", ".gif", ".heic", ".heif", ".jpeg", ".jpg", ".png", ".webp"}
INTERNAL_SUFFIXES = (".idsig", ".sig", ".sha256", ".sha512")
_ledger_lock = threading.RLock()


def should_deliver_task_artifacts(
    *,
    fast_chat_delivery: bool,
    plan_only: bool,
    generated_output_files: list[dict] | tuple[dict, ...] = (),
    referenced_output_paths: list[Path] | tuple[Path, ...] = (),
) -> bool:
    """Keep the chat fast path unless a run actually produced a deliverable."""
    if plan_only:
        return False
    return bool(
        not fast_chat_delivery
        or generated_output_files
        or referenced_output_paths
    )


@dataclass(frozen=True)
class PreparedArtifact:
    artifact_id: str
    task_id: str
    name: str
    relative_path: str
    artifact_uri: str
    mime_type: str
    size_bytes: int
    sha256: str
    original_size_bytes: int
    original_sha256: str
    chunk_count: int
    source_path: Path
    compress_images: bool = True
    transport_bytes: bytes | None = None

    def chunks(self):
        if self.transport_bytes is not None:
            for index in range(self.chunk_count):
                start = index * ARTIFACT_CHUNK_BYTES
                yield index, self.transport_bytes[start : start + ARTIFACT_CHUNK_BYTES]
            return
        with self.source_path.open("rb") as stream:
            for index in range(self.chunk_count):
                chunk = stream.read(ARTIFACT_CHUNK_BYTES)
                if not chunk:
                    raise OSError("Artifact ended before declared chunk count")
                yield index, chunk


def prepare_artifacts(
    task_id: str,
    output_files: list[dict] | None,
    *,
    compress_images: bool = True,
) -> list[PreparedArtifact]:
    prepared: list[PreparedArtifact] = []
    seen: set[str] = set()
    for item in output_files or []:
        if not isinstance(item, dict):
            continue
        relative_path = str(item.get("relative_path") or "").replace("\\", "/").strip("/")
        source = task_artifact_path(task_id, relative_path)
        if source is None or source.stat().st_size <= 0 or source.stat().st_size > MAX_ARTIFACT_BYTES:
            continue
        if source.name.startswith(".") or source.name.lower().endswith(INTERNAL_SUFFIXES):
            continue
        source_key = str(source).casefold()
        if source_key in seen:
            continue
        seen.add(source_key)
        artifact = _prepare_artifact(
            task_id,
            source,
            relative_path,
            item,
            compress_images=compress_images,
        )
        if artifact is not None:
            prepared.append(artifact)
    return prepared


def artifact_chunk_payloads(
    artifact: PreparedArtifact,
    *,
    common: dict | None = None,
):
    base = dict(common or {})
    for chunk_index, chunk in artifact.chunks():
        payload = dict(base)
        payload.update({
            "type": "artifact_chunk",
            "artifact_id": artifact.artifact_id,
            "task_id": artifact.task_id,
            "artifact_uri": artifact.artifact_uri,
            "name": artifact.name,
            "relative_path": artifact.relative_path,
            "mime_type": artifact.mime_type,
            "size_bytes": artifact.size_bytes,
            "sha256": artifact.sha256,
            "original_size_bytes": artifact.original_size_bytes,
            "original_sha256": artifact.original_sha256,
            "chunk_index": chunk_index,
            "chunk_count": artifact.chunk_count,
            "chunk_size_bytes": len(chunk),
            "chunk_sha256": hashlib.sha256(chunk).hexdigest(),
            "data_b64": base64.b64encode(chunk).decode("ascii"),
            "phone_owned": True,
            "sender": "other",
            "time": time.time(),
        })
        yield payload


def register_artifact_batch(
    artifacts: list[PreparedArtifact],
    *,
    client_route_id: str,
    retain_on_desktop: bool,
) -> None:
    if not artifacts:
        return
    with _ledger_lock:
        ledger = _read_ledger()
        _prune_ledger(ledger)
        now = int(time.time())
        for artifact in artifacts:
            ledger[artifact.artifact_id] = {
                "task_id": artifact.task_id,
                "client_route_id": str(client_route_id or ""),
                "sha256": artifact.sha256,
                "source_path": _workspace_relative(artifact.source_path),
                "retain_on_desktop": bool(retain_on_desktop),
                "compress_images": bool(artifact.compress_images),
                "state": "pending",
                "created_at": now,
            }
        _write_ledger(ledger)


def acknowledge_artifact(payload: dict, *, client_route_id: str) -> bool:
    artifact_id = str(payload.get("artifact_id") or "").lower()
    digest = str(payload.get("sha256") or "").lower()
    if (
        len(artifact_id) != 64
        or len(digest) != 64
        or str(payload.get("status") or "") != "stored"
    ):
        return False
    with _ledger_lock:
        ledger = _read_ledger()
        entry = ledger.get(artifact_id)
        if not isinstance(entry, dict):
            return False
        if (
            str(entry.get("client_route_id") or "") != str(client_route_id or "")
            or str(entry.get("sha256") or "").lower() != digest
        ):
            return False
        entry["state"] = "stored"
        entry["stored_at"] = int(time.time())
        task_id = str(entry.get("task_id") or "")
        task_entries = [
            item
            for item in ledger.values()
            if isinstance(item, dict)
            and str(item.get("task_id") or "") == task_id
            and str(item.get("client_route_id") or "") == str(client_route_id or "")
        ]
        complete = bool(task_entries) and all(item.get("state") == "stored" for item in task_entries)
        retain = any(bool(item.get("retain_on_desktop")) for item in task_entries)
        if complete:
            for key in [
                key for key, item in ledger.items()
                if isinstance(item, dict)
                and str(item.get("task_id") or "") == task_id
                and str(item.get("client_route_id") or "") == str(client_route_id or "")
            ]:
                ledger.pop(key, None)
            if task_id and not retain:
                cleanup_task_workspace(task_id)
        _write_ledger(ledger)
        return True


def artifact_for_redelivery(
    payload: dict,
    *,
    client_route_id: str,
) -> PreparedArtifact | None:
    """Restore a pending artifact only for the phone route that owns it."""
    artifact_id = str(payload.get("artifact_id") or "").strip().lower()
    artifact_uri = str(payload.get("artifact_uri") or "").strip()
    digest = str(payload.get("sha256") or "").strip().lower()
    if len(artifact_id) != 64 or len(digest) != 64 or not artifact_uri:
        return None
    with _ledger_lock:
        ledger = _read_ledger()
        _prune_ledger(ledger)
        entry = ledger.get(artifact_id)
        if not isinstance(entry, dict):
            _write_ledger(ledger)
            return None
        if (
            str(entry.get("client_route_id") or "") != str(client_route_id or "")
            or str(entry.get("sha256") or "").lower() != digest
        ):
            return None
        task_id = str(entry.get("task_id") or "").strip()
        source_relative = str(entry.get("source_path") or "").replace("\\", "/").strip("/")
        source = (workspace_root() / source_relative).resolve()
        try:
            source.relative_to(workspace_root().resolve())
            relative_path = source.relative_to(task_workspace(task_id).resolve()).as_posix()
        except (OSError, ValueError):
            return None
        if not source.is_file() or source.is_symlink():
            return None
        restored = _prepare_artifact(
            task_id,
            source,
            relative_path,
            {"name": source.name, "relative_path": relative_path},
            compress_images=bool(entry.get("compress_images", True)),
        )
        if (
            restored is None
            or restored.artifact_id != artifact_id
            or restored.artifact_uri != artifact_uri
            or restored.sha256 != digest
        ):
            return None
        entry["last_redelivery_at"] = int(time.time())
        entry["redelivery_count"] = int(entry.get("redelivery_count") or 0) + 1
        _write_ledger(ledger)
        return restored


def pending_artifacts_for_redelivery(
    *,
    limit: int = 32,
) -> list[tuple[str, PreparedArtifact]]:
    """Rebuild unacknowledged phone-owned artifacts after transport recovery."""
    with _ledger_lock:
        ledger = _read_ledger()
        _prune_ledger(ledger)
        candidates = [
            (artifact_id, dict(entry))
            for artifact_id, entry in ledger.items()
            if isinstance(entry, dict) and str(entry.get("state") or "pending") == "pending"
        ][:max(1, int(limit))]
        _write_ledger(ledger)
    restored: list[tuple[str, PreparedArtifact]] = []
    for artifact_id, entry in candidates:
        client_route_id = str(entry.get("client_route_id") or "")
        task_id = str(entry.get("task_id") or "")
        source_relative = str(entry.get("source_path") or "").replace("\\", "/").strip("/")
        source = (workspace_root() / source_relative).resolve()
        try:
            source.relative_to(workspace_root().resolve())
            relative_path = source.relative_to(task_workspace(task_id).resolve()).as_posix()
        except (OSError, ValueError):
            continue
        if not client_route_id or not source.is_file() or source.is_symlink():
            continue
        artifact = _prepare_artifact(
            task_id,
            source,
            relative_path,
            {"name": source.name, "relative_path": relative_path},
            compress_images=bool(entry.get("compress_images", True)),
        )
        if (
            artifact is not None
            and artifact.artifact_id == artifact_id
            and artifact.sha256 == str(entry.get("sha256") or "").lower()
        ):
            restored.append((client_route_id, artifact))
    return restored


def discard_task_workspace_if_no_artifacts(
    task_id: str,
    artifacts: list[PreparedArtifact],
    *,
    retain_on_desktop: bool,
) -> None:
    if task_id and not artifacts and not retain_on_desktop:
        cleanup_task_workspace(task_id)


def _prepare_artifact(
    task_id: str,
    source: Path,
    relative_path: str,
    metadata: dict,
    *,
    compress_images: bool = True,
) -> PreparedArtifact | None:
    name = str(metadata.get("name") or source.name).strip() or source.name
    original_size = source.stat().st_size
    original_digest = _file_sha256(source)
    mime_type = _guess_mime_type(name)
    transport_bytes: bytes | None = None
    transport_size = original_size
    transport_digest = original_digest
    if compress_images and source.suffix.lower() in IMAGE_SUFFIXES:
        if original_size <= MAX_IMAGE_TRANSPORT_BYTES:
            transport_bytes = source.read_bytes()
        else:
            compressed = compress_image_file(source, MAX_IMAGE_TRANSPORT_BYTES)
            if compressed is None:
                return None
            transport_bytes = compressed.data
            mime_type = compressed.mime_type
        transport_size = len(transport_bytes)
        transport_digest = hashlib.sha256(transport_bytes).hexdigest()
    chunk_count = (transport_size + ARTIFACT_CHUNK_BYTES - 1) // ARTIFACT_CHUNK_BYTES
    if chunk_count not in range(1, MAX_ARTIFACT_CHUNKS + 1):
        return None
    artifact_uri = _artifact_uri(task_id, relative_path)
    artifact_id = hashlib.sha256(
        f"{artifact_uri}\0{transport_digest}".encode("utf-8")
    ).hexdigest()
    return PreparedArtifact(
        artifact_id=artifact_id,
        task_id=str(task_id or ""),
        name=name,
        relative_path=relative_path,
        artifact_uri=artifact_uri,
        mime_type=mime_type,
        size_bytes=transport_size,
        sha256=transport_digest,
        original_size_bytes=original_size,
        original_sha256=original_digest,
        chunk_count=chunk_count,
        source_path=source,
        compress_images=compress_images,
        transport_bytes=transport_bytes,
    )


def _artifact_uri(task_id: str, relative_path: str) -> str:
    return (
        f"galaxyssi-artifact://{quote(str(task_id or 'task'), safe='')}/"
        f"{quote(relative_path, safe='/')}"
    )


def _guess_mime_type(name: str) -> str:
    suffix = Path(str(name or "")).suffix.lower()
    return MIME_OVERRIDES.get(suffix) or mimetypes.guess_type(name)[0] or "application/octet-stream"


def _file_sha256(source: Path) -> str:
    digest = hashlib.sha256()
    with source.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _ledger_path() -> Path:
    return workspace_root() / LEDGER_NAME


def _read_ledger() -> dict:
    path = _ledger_path()
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def _write_ledger(ledger: dict) -> None:
    path = _ledger_path()
    temporary = path.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(ledger, ensure_ascii=True, separators=(",", ":")),
        encoding="utf-8",
    )
    os.replace(temporary, path)


def _prune_ledger(ledger: dict) -> None:
    cutoff = int(time.time()) - LEDGER_TTL_SECONDS
    expired = []
    cleanup_tasks: set[str] = set()
    for artifact_id, entry in ledger.items():
        if not isinstance(entry, dict) or int(entry.get("created_at") or 0) < cutoff:
            expired.append(artifact_id)
            if isinstance(entry, dict) and not bool(entry.get("retain_on_desktop")):
                task_id = str(entry.get("task_id") or "")
                if task_id:
                    cleanup_tasks.add(task_id)
    for artifact_id in expired:
        ledger.pop(artifact_id, None)
    for task_id in cleanup_tasks:
        cleanup_task_workspace(task_id)


def _workspace_relative(source: Path) -> str:
    try:
        return source.resolve().relative_to(workspace_root().resolve()).as_posix()
    except ValueError:
        return ""
