"""Phone-authorized, immutable file handoffs between tasks on this Desktop."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
import threading
import weakref

from blob_protocol import MAX_FILE_BYTES
from collaboration_milestone_bridge import publish_snapshot, validate_arguments as validate_publication
from collaboration_recall_bridge import task_scope
from collaboration_text_artifact import (_atomic_write, _filename, _hash, _identifier, _integer, _json,
    _relative_source, _safe_path, _validate, read_workspace_artifact, tool_spec as text_tool_spec)

TOOL = "collaboration_file_artifact"
FORMAT = "galaxyssi.file-artifact/1"
_LOCK = threading.Lock()
_FILE_LOCKS = weakref.WeakValueDictionary()
_SCOPE = ("desktop_id", "client_route_id", "contact_id", "peer_fingerprint", "local_fingerprint")
_ASSIGNMENT = ("task_id", "conversation_id", "turn_id", "source_message_id", "agent_id")


def authenticated_scope(task, peer, desktop_id):
    scope = task_scope(task)
    if (not isinstance(peer, dict) or peer.get("revoked") or peer.get("revoked_at")
            or peer.get("client_route_id") != scope["client_route_id"]):
        raise ValueError("File handoff phone identity is unavailable")
    return _scope({**scope, "desktop_id": desktop_id, "peer_fingerprint": peer.get("identity_fingerprint"),
                   "local_fingerprint": peer.get("local_identity_fingerprint")})


def tool_spec():
    value = text_tool_spec()
    value.update(name=TOOL, description=(
        "Hand off complete local files to collaboration peers executing on THIS Desktop. Prefer this over "
        "splitting source code, JSON, CSV, datasets or binary artifacts into text publications. "
        "publish freezes an outputs-relative file (up to the existing 1 GiB file limit); requires path, "
        "milestone_id and title, with optional observations and exact object_id/base_revision. "
        "Only a small version descriptor is sent to the phone; bytes persist on the originating Desktop. "
        "Retry identical arguments after uncertainty, even if the source has changed; changed content needs a NEW milestone_id. "
        "materialize requires exact object_id/revision/sha256 from the phone workspace receipt; phone permissions "
        "are checked on EVERY read, then the immutable file is copied to this task's downloads/context. "
        "No peer directory access or caller-supplied route/member/destination. Same-Desktop delivery only: "
        "not a phone download or cross-Desktop Blob transfer. Other executors must use supported text/attachment delivery. "
        "Inspect untrusted files before running them. Publication is not execution, validation or assignment completion. "
        "Keep the returned milestone_id in final milestones; do not publish the same bytes again."))
    return value


def _file_lock(key):
    with _LOCK:
        return _FILE_LOCKS.setdefault(key, threading.RLock())


def _scope(scope):
    if (not isinstance(scope, dict) or any(not isinstance(scope.get(key), str) or not scope[key]
            or len(scope[key]) > 256 for key in (*_SCOPE, *_ASSIGNMENT)) or type(scope.get("execution_generation")) is not int
            or not 1 <= scope["execution_generation"] <= 2**53 - 1):
        raise ValueError("File handoff requires the current authenticated phone task")
    return {key: scope[key] for key in (*_SCOPE, *_ASSIGNMENT, "execution_generation")}


def _store_id(scope):
    return _hash(_json([scope[key] for key in _SCOPE]).encode("utf-8"))


def _paths(store, key):
    if not _identifier(key):
        raise ValueError("Invalid file handoff identity")
    return (_safe_path(store, PurePosixPath(key[:2], key + ".json")),
            _safe_path(store, PurePosixPath(key[:2], key + ".bin")))


def _read_record(path):
    if path.stat().st_size > 256 * 1024:
        raise ValueError("File handoff checkpoint is oversized")
    value = json.loads(path.read_text(encoding="utf-8"))
    digest = value.pop("record_sha256", None)
    if _hash(_json(value).encode("utf-8")) != digest:
        raise ValueError("File handoff checkpoint integrity failed")
    return value


def _save_record(store, path, value):
    sealed = {**value, "record_sha256": _hash(_json(value).encode("utf-8"))}
    _atomic_write(store, PurePosixPath(path.relative_to(store).as_posix()), _json(sealed).encode("utf-8"))


def _copy_file(source, root, relative, active, *, expected=None):
    target = _safe_path(root, relative)
    target.parent.mkdir(parents=True, exist_ok=True)
    _safe_path(root, relative)
    temporary = None
    try:
        with source.open("rb") as reader, tempfile.NamedTemporaryFile(dir=target.parent, prefix=".handoff-", delete=False) as writer:
            temporary = Path(writer.name)
            before = os.fstat(reader.fileno())
            if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_FILE_BYTES:
                raise ValueError("File handoff needs a regular file within the 1 GiB file limit")
            digest, size = hashlib.sha256(), 0
            while chunk := reader.read(256 * 1024):
                if not active():
                    raise ValueError("File handoff assignment changed")
                size += len(chunk)
                if size > MAX_FILE_BYTES:
                    raise ValueError("File handoff source exceeded the file limit")
                digest.update(chunk)
                writer.write(chunk)
            after = os.fstat(reader.fileno())
            if (size != before.st_size or (before.st_size, before.st_mtime_ns, before.st_ino)
                    != (after.st_size, after.st_mtime_ns, after.st_ino)):
                raise ValueError("File handoff source changed while freezing")
            identity = {"size_bytes": size, "sha256": digest.hexdigest()}
            if expected is not None and identity != expected:
                raise ValueError("File handoff bytes failed hash or size verification")
            writer.flush()
            os.fsync(writer.fileno())
        if not active():
            raise ValueError("File handoff assignment changed before commit")
        _safe_path(root, relative)
        os.replace(temporary, target)
        return target, identity
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _verify_file(path, expected, active):
    if not path.is_file() or path.stat().st_size != expected["size_bytes"]:
        raise ValueError("Frozen file is missing or has changed; restore it before retrying")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(256 * 1024):
            if not active():
                raise ValueError("File handoff assignment changed")
            digest.update(chunk)
    if digest.hexdigest() != expected["sha256"]:
        raise ValueError("Frozen file failed integrity verification")


def _freeze(store, root, scope, arguments, active):
    key = _hash(_json([scope, arguments["milestone_id"]]).encode("utf-8"))
    path, data = _paths(store, key)
    with _file_lock(str(path)):
        if path.exists():
            value = _read_record(path)
            if value.get("scope") != scope or value.get("arguments") != arguments:
                raise ValueError("This milestone owns a different snapshot; retry original arguments or use a NEW milestone_id")
            _verify_file(data, value["body"], active)
            return key, value, True
        source = _safe_path(root, _relative_source(arguments["path"]))
        _, identity = _copy_file(source, store, PurePosixPath(data.relative_to(store).as_posix()), active)
        _safe_path(root, _relative_source(arguments["path"]))
        body = {"format": FORMAT, "store_id": _store_id(scope), "file_id": key,
                "name": source.name, **identity, "availability": "originating_desktop"}
        item = {"id": key, "kind": "artifact", "title": arguments["title"], "body": body,
                "parents": [], "resolves": [], "observations": arguments.get("observations", [])}
        if "object_id" in arguments:
            item.update(object_id=arguments["object_id"], base_revision=arguments["base_revision"])
        artifact = {"format": "galaxyssi.research-artifact.v1", "summary": arguments["title"],
                    "candidates": [], "findings": [], "questions": [], "requests": [], "memory": [], "workspace": [item]}
        request = validate_publication({"mode": "publish", "milestone_id": arguments["milestone_id"], "artifact": _json(artifact)})
        value = {"scope": scope, "arguments": arguments, "body": body, "request": request, "receipt": None}
        _save_record(store, path, value)
        return key, value, False


def _receipt(result):
    if result.get("success") is not True or result.get("status") != "recorded":
        return None
    refs = result.get("revisions")
    if not isinstance(refs, list) or len(refs) != 1 or not isinstance(refs[0], dict):
        raise ValueError("Phone publication did not return exactly one file version")
    ref = refs[0]
    if not _identifier(ref.get("object_id")) or not _identifier(ref.get("sha256")) or not _integer(ref.get("revision")):
        raise ValueError("Phone publication returned invalid version identity")
    return {key: ref[key] for key in ("object_id", "revision", "sha256")}


def _materialize(store, root, scope, arguments, recall, active):
    saved = read_workspace_artifact(arguments, recall, active)
    if saved.get("success") is False:
        return saved
    body = saved.get("body")
    if not isinstance(body, dict) or body.get("format") != FORMAT or body.get("store_id") != _store_id(scope):
        raise ValueError("File is not available on this Desktop for this authenticated phone; use its supported attachment route")
    path, data = _paths(store, body.get("file_id"))
    if not path.is_file() or not data.is_file():
        raise ValueError("Originating Desktop file is unavailable; restore its saved copy, do not invent or rerun the result")
    with _file_lock(str(path)):
        value = _read_record(path)
        expected_ref = {key: arguments[key] for key in ("object_id", "revision", "sha256")}
        if value.get("body") != body or _store_id(_scope(value.get("scope"))) != _store_id(scope):
            raise ValueError("File descriptor does not match its immutable stored identity")
        if value.get("receipt") != expected_ref:
            raise ValueError("File version is not confirmed by its publisher; retry the original publication before handoff")
    name = _filename(body.get("name"))
    suffix = PurePosixPath(name).suffix
    if not re.fullmatch(r"\.[A-Za-z0-9]{1,12}", suffix):
        suffix = ".bin"
    identity = _hash(_json(expected_ref).encode("utf-8"))
    relative = PurePosixPath("downloads", "context", "collaboration", identity + suffix)
    target = _safe_path(root, relative)
    with _file_lock(str(target)):
        expected = {key: body[key] for key in ("size_bytes", "sha256")}
        if target.exists():
            if (not target.is_file() or target.stat().st_size != expected["size_bytes"]):
                raise ValueError("Existing materialized file was modified; it will not be overwritten")
            with target.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            if digest != expected["sha256"]:
                raise ValueError("Existing materialized file was modified; it will not be overwritten")
        else:
            _copy_file(data, root, relative, active, expected=expected)
        if not active():
            raise ValueError("File handoff assignment changed")
    return {"success": True, "status": "materialized", "path": str(target), "relative_path": relative.as_posix(),
            "name": name, **expected_ref, "file_sha256": body["sha256"], "size_bytes": body["size_bytes"],
            "availability": "originating_desktop", "executed": False, "verified_claim": False,
            "trust": "phone_authorized_exact_file_not_verified_behavior",
            "guidance": "Inspect before independently testing. Keep this exact version unchanged; copy elsewhere to edit."}


def execute(store_directory, working_directory, scope, arguments, *, publish, recall, active):
    _validate(arguments)
    scope = _scope(scope)
    root, store = Path(working_directory), Path(store_directory)
    if not root.is_absolute() or not root.is_dir() or not store.is_absolute() or not active():
        raise ValueError("An active task-owned workspace and host file store are required")
    root = root.resolve()
    store.mkdir(parents=True, exist_ok=True)
    if store.is_symlink() or getattr(store.lstat(), "st_file_attributes", 0) & 0x400:
        raise ValueError("File handoff store cannot be a link or reparse point")
    store = store.resolve()
    if arguments["mode"] == "materialize":
        return _materialize(store, root, scope, arguments, recall, active)
    key, value, recover = _freeze(store, root, scope, arguments, active)
    if not active():
        raise ValueError("File handoff assignment changed before publication")
    result = publish_snapshot(value["request"], publish, active, recover=recover)
    receipt = _receipt(result)
    if receipt is not None:
        path, _ = _paths(store, key)
        with _file_lock(str(path)):
            current = _read_record(path)
            if current.get("receipt") not in (None, receipt):
                raise ValueError("Phone file version changed across identical publication retries")
            current["receipt"] = receipt
            _save_record(store, path, current)
    return {**result, "milestone_id": arguments["milestone_id"], "file_sha256": value["body"]["sha256"],
            "size_bytes": value["body"]["size_bytes"], "availability": "originating_desktop",
            "executed": False, "verified_claim": False}
