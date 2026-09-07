"""Small, paged file tools for the private candidate implementation loop."""
from __future__ import annotations

import hashlib
import heapq
import os
import stat
from pathlib import Path, PurePosixPath
import tempfile


class WorkspaceTools:
    def __init__(self, root: Path, scope=()):
        self.root = root.resolve(strict=True)
        self.scope = tuple(self._path(value) for value in scope)

    def _path(self, value):
        if not isinstance(value, str) or not value or "\\" in value or ":" in value:
            raise ValueError("Use a relative POSIX source path")
        parts = PurePosixPath(value).parts
        if PurePosixPath(value).is_absolute() or any(p.casefold() == ".." or p.rstrip(" .").casefold() == ".git" for p in parts):
            raise ValueError("Path leaves the source workspace")
        path = self.root
        for part in parts:
            path = path / part
            linked = path.is_symlink()
            if path.exists():
                linked = linked or bool(getattr(path.lstat(), "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0))
            if linked:
                raise ValueError("Linked source paths are not supported")
        resolved = path.resolve()
        if not resolved.is_relative_to(self.root):
            raise ValueError("Path leaves the source workspace")
        if path.is_file() and path.stat().st_nlink != 1:
            raise ValueError("Shared hard-linked files are not supported")
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
                raise ValueError("after must be a filename cursor")
            names = heapq.nsmallest(65, (p.name for p in path.iterdir() if p.name.casefold() != ".git" and p.name > after))
            page = names[:64]
            return {"entries": page, "next_after": page[-1] if len(names) > 64 else None}
        if operation == "read":
            offset = action.get("offset", 0)
            if type(offset) is not int or offset < 0:
                raise ValueError("offset must be a nonnegative character offset")
            with path.open("rb") as stream:
                raw = stream.read(1_048_577)
            if len(raw) > 1_048_576:
                raise ValueError("File exceeds the text-tool envelope; split the source module first")
            text = raw.decode("utf-8")
            end = offset + 16_384
            return {"text": text[offset:end], "sha256": hashlib.sha256(raw).hexdigest(),
                    "next_offset": end if end < len(text) else None}
        if operation == "write":
            if not any(path == allowed or path.is_relative_to(allowed) for allowed in self.scope):
                raise ValueError("Write is outside the task's declared source scope")
            if "expected_sha256" not in action or action["expected_sha256"] != self._digest(path):
                raise ValueError("Source changed or was not read; read it again before writing")
            text = action.get("text")
            if not isinstance(text, str) or len(text.encode("utf-8")) > 1_048_576:
                raise ValueError("write requires UTF-8 text within the text-tool envelope")
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
        raise ValueError("Unknown tool operation; use list, read, write, or finish")
