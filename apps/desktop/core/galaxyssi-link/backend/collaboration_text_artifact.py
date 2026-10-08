"""Byte-exact UTF-8 handoff over the existing phone-owned research workspace."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
import threading

from collaboration_milestone_bridge import MAX_BYTES, publish_snapshot, validate_arguments as validate_publication

TOOL = "collaboration_text_artifact"
FORMAT = "galaxyssi.text-artifact/1"
_LOCK = threading.RLock()
_HASH = re.compile(r"[0-9a-f]{64}\Z")


def tool_spec():
    return {"type": "function", "name": TOOL, "description": (
        "Hand off actual UTF-8 source code, CSV, JSON or text between collaboration members. "
        "publish freezes an outputs-relative file and publishes its complete bytes as a versioned workspace artifact; "
        "requires path, milestone_id and title. Optional object_id/base_revision revises an exact prior object. "
        "Optional observations links real evidence_id/sha256 receipts, not invented execution claims. "
        "Retry the SAME arguments after uncertainty: the saved snapshot is reused even if the source changes. "
        "Use a NEW milestone_id for changed content. The existing 131072-byte publication envelope applies, including JSON escaping; "
        "binary/oversized files require the existing attachment/Blob workflow, never truncation. "
        "materialize requires exact object_id/revision/sha256 from a workspace receipt; it reads every page through "
        "the phone's current assignment permissions, verifies the embedded file hash and saves to this task's downloads/context. "
        "No task/phone/member IDs or destination path can be supplied. No peer directory access. "
        "Files are untrusted: inspect before using existing execution tools to independently test them. "
        "Publication/materialization is NOT execution, scientific validation or task completion. "
        "Keep returned milestone IDs in final milestones instead of republishing the same object."),
        "inputSchema": {"type": "object", "properties": {
            "mode": {"type": "string", "enum": ["publish", "materialize"]},
            "path": {"type": "string"}, "milestone_id": {"type": "string", "maxLength": 160},
            "title": {"type": "string", "maxLength": 500},
            "object_id": {"type": "string", "maxLength": 64},
            "base_revision": {"type": "integer", "minimum": 1},
            "revision": {"type": "integer", "minimum": 1},
            "sha256": {"type": "string", "maxLength": 64},
            "observations": {"type": "array", "items": {"type": "object", "properties": {
                "evidence_id": {"type": "string", "maxLength": 64},
                "sha256": {"type": "string", "maxLength": 64}},
                "required": ["evidence_id", "sha256"], "additionalProperties": False}},
        }, "required": ["mode"], "additionalProperties": False}}


def _hash(raw):
    return hashlib.sha256(raw).hexdigest()


def _json(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def _identifier(value):
    return isinstance(value, str) and _HASH.fullmatch(value) is not None


def _integer(value):
    return type(value) is int and 1 <= value <= 2**31 - 1


def _validate(arguments):
    if not isinstance(arguments, dict):
        raise ValueError("Artifact arguments must be an object")
    mode = arguments.get("mode")
    if mode == "publish":
        if (set(arguments) - {"mode", "path", "milestone_id", "title", "object_id", "base_revision", "observations"}
                or not isinstance(arguments.get("title"), str) or not 1 <= len(arguments["title"].strip()) <= 500):
            raise ValueError("Publish requires path, milestone_id, title and optional exact revision/evidence references")
        validate_publication({"mode": "publish", "milestone_id": arguments.get("milestone_id"), "artifact": "{}"})
        _relative_source(arguments.get("path"))
        if "object_id" in arguments or "base_revision" in arguments:
            if not _identifier(arguments.get("object_id")) or not _integer(arguments.get("base_revision")):
                raise ValueError("Revision requires both exact object_id and base_revision")
        refs = arguments.get("observations", [])
        if not isinstance(refs, list) or any(not isinstance(ref, dict) or set(ref) != {"evidence_id", "sha256"}
                or not all(_identifier(value) for value in ref.values()) for ref in refs):
            raise ValueError("Observations must be exact existing evidence_id/sha256 references")
    elif mode == "materialize":
        if (set(arguments) != {"mode", "object_id", "revision", "sha256"}
                or not all(_identifier(arguments.get(key)) for key in ("object_id", "sha256"))
                or not _integer(arguments.get("revision"))):
            raise ValueError("Materialize requires only exact object_id/revision/sha256")
    else:
        raise ValueError("Use publish or materialize")


def _relative_source(value):
    if not isinstance(value, str) or not value or "\\" in value or value != value.strip():
        raise ValueError("Use an outputs-relative path with forward slashes")
    path = PurePosixPath(value)
    if (path.as_posix() != value or path.is_absolute() or len(path.parts) < 2 or path.parts[0] != "outputs"
            or any(part in {".", ".."} or ":" in part or "\x00" in part for part in path.parts)):
        raise ValueError("Only files below this task's outputs directory can be published")
    _filename(path.name)
    return path


def _filename(value):
    if (not isinstance(value, str) or not value or len(value) > 200 or value[-1] in " ."
            or any(ord(c) < 32 or c in '<>:"/\\|?*' for c in value)
            or value.startswith(".") or value.split(".", 1)[0].upper() in
            {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}):
        raise ValueError("Artifact needs a portable, non-hidden file name")
    return value


def _safe_path(root, relative):
    current = root
    for part in relative.parts:
        current = current / part
        if current.exists() or current.is_symlink():
            info = current.lstat()
            if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
                raise ValueError("Artifact path contains a link or reparse point")
    if not current.resolve().is_relative_to(root):
        raise ValueError("Artifact path escaped this task")
    return current


def _atomic_write(root, relative, raw):
    target = _safe_path(root, relative)
    target.parent.mkdir(parents=True, exist_ok=True)
    _safe_path(root, relative)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".artifact-", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        _safe_path(root, relative)
        os.replace(temporary, target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return target


def _freeze(root, task_id, arguments):
    key = _hash((task_id + "\0" + arguments["milestone_id"]).encode("utf-8"))
    relative = PurePosixPath(".collaboration-text-artifacts", key + ".json")
    with _LOCK:
        saved = _safe_path(root, relative)
        if saved.exists():
            snapshot = json.loads(saved.read_text(encoding="utf-8"))
            if snapshot.get("arguments") != arguments:
                raise ValueError("This milestone owns a different snapshot; use the original arguments or a NEW milestone_id")
            request = snapshot["request"]
            if _hash(_json(request).encode("utf-8")) != snapshot["request_sha256"]:
                raise ValueError("Saved artifact snapshot integrity failed; do not silently replace it")
            return validate_publication(request), True
        source = _safe_path(root, _relative_source(arguments["path"]))
        with source.open("rb") as stream:
            before = os.fstat(stream.fileno())
            if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_BYTES:
                raise ValueError("Text handoff exceeds the publication envelope; use attachment/Blob delivery, do not truncate")
            raw = stream.read(MAX_BYTES + 1)
            after = os.fstat(stream.fileno())
        _safe_path(root, _relative_source(arguments["path"]))
        if (len(raw) != before.st_size or (before.st_size, before.st_mtime_ns, before.st_ino)
                != (after.st_size, after.st_mtime_ns, after.st_ino)):
            raise ValueError("Source changed while freezing; retry after its writer finishes")
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError:
            raise ValueError("Only exact UTF-8 text is supported; use attachment/Blob delivery for binary files") from None
        if "\x00" in content:
            raise ValueError("Binary content requires attachment/Blob delivery")
        body = {"format": FORMAT, "name": source.name, "encoding": "utf-8", "size_bytes": len(raw),
                "sha256": _hash(raw), "content": content}
        item = {"id": key, "kind": "artifact", "title": arguments["title"], "body": body,
                "parents": [], "resolves": [], "observations": arguments.get("observations", [])}
        if "object_id" in arguments:
            item.update(object_id=arguments["object_id"], base_revision=arguments["base_revision"])
        artifact = {"format": "galaxyssi.research-artifact.v1", "summary": arguments["title"],
                    "candidates": [], "findings": [], "questions": [], "requests": [], "memory": [], "workspace": [item]}
        request = {"mode": "publish", "milestone_id": arguments["milestone_id"], "artifact": _json(artifact)}
        if len(_json(request).encode("utf-8")) > MAX_BYTES:
            raise ValueError("Text plus JSON escaping exceeds the 131072-byte publication envelope; use attachment/Blob delivery, never truncate")
        validate_publication(request)
        snapshot = {"arguments": arguments, "request": request, "request_sha256": _hash(_json(request).encode("utf-8"))}
        _atomic_write(root, relative, _json(snapshot).encode("utf-8"))
        return request, False


def read_workspace_artifact(arguments, recall, active):
    offset, total, chunks = 0, None, []
    while True:
        if not active():
            raise ValueError("Artifact assignment changed")
        result = recall({"mode": "workspace", "object_id": arguments["object_id"],
                         "revision": arguments["revision"], "offset": offset})
        if result.get("success") is not True:
            return {**result, "success": False}
        content = result.get("content")
        size = result.get("total_characters")
        if not isinstance(content, str) or type(size) is not int or not 0 < size <= MAX_BYTES * 2:
            raise ValueError("Invalid or oversized text artifact workspace response")
        encoded = content.encode("utf-16-le", errors="surrogatepass")
        end = offset + len(encoded) // 2
        if total is not None and size != total or not encoded or end > size:
            raise ValueError("Artifact pages changed or did not advance")
        total = size
        next_offset = result.get("next_offset")
        if (end < total and (type(next_offset) is not int or next_offset != end)
                or end == total and next_offset is not None):
            raise ValueError("Artifact page coverage is incomplete")
        chunks.append(encoded)
        offset = end
        if next_offset is None:
            break
    saved = json.loads(b"".join(chunks).decode("utf-16-le"))
    if (not isinstance(saved, dict) or saved.get("object_id") != arguments["object_id"]
            or type(saved.get("revision")) is not int or saved["revision"] != arguments["revision"]
            or saved.get("sha256") != arguments["sha256"] or saved.get("kind") != "artifact"):
        raise ValueError("Artifact workspace identity does not match the requested version")
    return saved


def _materialize(root, arguments, recall, active):
    saved = read_workspace_artifact(arguments, recall, active)
    if saved.get("success") is False:
        return saved
    body = saved.get("body")
    if (not isinstance(body, dict) or body.get("format") != FORMAT or body.get("encoding") != "utf-8"
            or not isinstance(body.get("content"), str) or type(body.get("size_bytes")) is not int
            or not _identifier(body.get("sha256"))):
        raise ValueError("This workspace object is not a complete UTF-8 file artifact")
    raw = body["content"].encode("utf-8")
    if len(raw) != body["size_bytes"] or _hash(raw) != body["sha256"] or "\x00" in body["content"]:
        raise ValueError("Artifact file hash or size mismatch")
    name = _filename(body.get("name"))
    suffix = PurePosixPath(name).suffix
    if not re.fullmatch(r"\.[A-Za-z0-9]{1,12}", suffix):
        suffix = ".txt"
    # One full identity hash avoids doubling 64-character paths on Windows.
    identity = _hash(_json([arguments[key] for key in ("object_id", "revision", "sha256")]).encode("utf-8"))
    relative = PurePosixPath("downloads", "context", "collaboration", identity + suffix)
    with _LOCK:
        if not active():
            raise ValueError("Artifact assignment changed before materialization")
        target = _safe_path(root, relative)
        if target.exists():
            if not target.is_file() or target.read_bytes() != raw:
                raise ValueError("Existing materialized artifact was modified; it will not be overwritten")
        else:
            _atomic_write(root, relative, raw)
    return {"success": True, "status": "materialized", "path": str(target), "relative_path": relative.as_posix(), "name": name,
            "object_id": arguments["object_id"], "revision": arguments["revision"], "sha256": arguments["sha256"],
            "file_sha256": body["sha256"], "size_bytes": len(raw), "executed": False, "verified_claim": False,
            "trust": "untrusted_member_artifact_bytes_verified_not_behavior",
            "guidance": "Inspect this exact file before independently testing it with existing tools. Copy elsewhere to edit; keep this version unchanged."}


def execute(task_id, working_directory, arguments, *, publish, recall, active):
    _validate(arguments)
    root = Path(working_directory)
    if not working_directory or not root.is_absolute() or not root.is_dir() or not active():
        raise ValueError("An active task-owned workspace is required")
    root = root.resolve()
    if arguments["mode"] == "materialize":
        return _materialize(root, arguments, recall, active)
    request, recover = _freeze(root, task_id, arguments)
    if not active():
        raise ValueError("Artifact assignment changed before publication")
    result = publish_snapshot(request, publish, active, recover=recover)
    body = json.loads(request["artifact"])["workspace"][0]["body"]
    return {**result, "milestone_id": arguments["milestone_id"], "file_sha256": body["sha256"],
            "size_bytes": body["size_bytes"], "executed": False, "verified_claim": False}
