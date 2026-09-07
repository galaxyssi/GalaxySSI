"""Small, paged file tools for the private candidate implementation loop."""
from __future__ import annotations

import hashlib
import heapq
import os
import re
import stat
from pathlib import Path, PurePosixPath
import tempfile

from .local_tool_observations import WorkspaceToolError
from .local_read_revisions import ReadRevisions


class WorkspaceTools:
    def __init__(self, root: Path, scope=()):
        self.root = root.resolve(strict=True)
        self.scope = tuple(self._path(value) for value in scope)
        self.revisions = ReadRevisions()

    def _path(self, value):
        if not isinstance(value, str) or not value or "\\" in value or ":" in value:
            raise WorkspaceToolError("invalid_source_path", "Use a relative POSIX source path")
        parts = PurePosixPath(value).parts
        if PurePosixPath(value).is_absolute() or any(p.casefold() == ".." or p.rstrip(" .").casefold() == ".git" for p in parts):
            raise WorkspaceToolError("source_path_forbidden", "Path leaves the source workspace or addresses Git metadata")
        path = self.root
        for part in parts:
            path = path / part
            linked = path.is_symlink()
            if path.exists():
                linked = linked or bool(getattr(path.lstat(), "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0))
            if linked:
                raise WorkspaceToolError("linked_source_path", "Linked source paths are not supported")
        resolved = path.resolve()
        if not resolved.is_relative_to(self.root):
            raise WorkspaceToolError("source_path_forbidden", "Path leaves the source workspace")
        if path.is_file() and path.stat().st_nlink != 1:
            raise WorkspaceToolError("hard_linked_source", "Shared hard-linked files are not supported")
        return path

    @staticmethod
    def _digest(path):
        if not path.exists():
            return None
        with path.open("rb") as stream:
            return hashlib.file_digest(stream, "sha256").hexdigest()

    def execute(self, action):
        operation = action.get("operation")
        path = self._path(action.get("path"))
        if operation == "list":
            after = action.get("after", "")
            if not isinstance(after, str):
                raise WorkspaceToolError("invalid_directory_cursor", "after must be a filename cursor")
            names = heapq.nsmallest(65, (p.name for p in path.iterdir() if p.name.casefold() != ".git" and p.name > after))
            page = names[:64]
            return {"entries": page, "next_after": page[-1] if len(names) > 64 else None}
        if operation == "read":
            offset = action.get("offset", 0)
            if type(offset) is not int or offset < 0:
                raise WorkspaceToolError("invalid_text_offset", "offset must be a nonnegative character offset")
            with path.open("rb") as stream:
                raw = stream.read(1_048_577)
            if len(raw) > 1_048_576:
                raise WorkspaceToolError("source_file_too_large", "File exceeds the text-tool envelope")
            text = raw.decode("utf-8")
            end = offset + 16_384
            digest = hashlib.sha256(raw).hexdigest()
            return {"text": text[offset:end], "sha256": digest,
                    "read_revision": self.revisions.remember(path, digest),
                    "next_offset": end if end < len(text) else None}
        if operation == "write":
            if not any(path == allowed or path.is_relative_to(allowed) for allowed in self.scope):
                raise WorkspaceToolError("write_scope_mismatch", "Write is outside the task's declared source scope")
            if "expected_revision" in action:
                if "expected_sha256" in action:
                    raise WorkspaceToolError("ambiguous_read_revision", "Use expected_revision only; do not combine it with expected_sha256")
                revision = action["expected_revision"]
                expected = None if revision is None else self.revisions.resolve(revision, path)
            elif "expected_sha256" not in action:
                raise WorkspaceToolError("read_digest_required", "Read the file and provide expected_sha256; use null only for a new file")
            else:
                expected = action["expected_sha256"]
            if expected is not None and (not isinstance(expected, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", expected)):
                raise WorkspaceToolError("invalid_read_digest", "expected_sha256 must be the complete 64-character hex value returned by read, or null for a new file")
            if (expected.lower() if expected is not None else None) != self._digest(path):
                if "expected_revision" in action:
                    raise WorkspaceToolError("source_revision_mismatch", "The target no longer matches the read_revision, or null was used for an existing file. Read the target and use its current read_revision")
                raise WorkspaceToolError("source_digest_mismatch", "The file does not match expected_sha256; read it again and use the returned hash without inventing or shortening it")
            text = action.get("text")
            if not isinstance(text, str) or len(text.encode("utf-8")) > 1_048_576:
                raise WorkspaceToolError("invalid_write_text", "write requires UTF-8 text within the text-tool envelope")
            path.parent.mkdir(parents=True, exist_ok=True)
            temporary = None
            mode = path.stat().st_mode if path.exists() else None
            try:
                with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
                    temporary = Path(stream.name)
                    stream.write(text.encode("utf-8"))
                    stream.flush()
                    os.fsync(stream.fileno())
                if mode is not None:
                    temporary.chmod(stat.S_IMODE(mode))
                os.replace(temporary, path)
            finally:
                if temporary is not None:
                    temporary.unlink(missing_ok=True)
            return {"sha256": self._digest(path), "bytes": path.stat().st_size}
        raise WorkspaceToolError("unknown_tool_operation", "Unknown tool operation; use list, read, write, or finish")
