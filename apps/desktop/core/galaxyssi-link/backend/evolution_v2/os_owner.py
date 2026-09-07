"""Nonblocking OS ownership with stable lock files and no expiring live lease."""
from __future__ import annotations

from contextlib import contextmanager
import errno
import os
from pathlib import Path
import re


class OwnerLockUnavailable(OSError):
    pass


class OwnerLocks:
    def __init__(self, root: Path, pattern: re.Pattern):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        self.pattern = pattern

    @contextmanager
    def hold(self, owner: str, *, create: bool = False):
        if not self.pattern.fullmatch(owner):
            raise ValueError("Invalid operation owner identity")
        path = self.root / (owner + ".lock")
        try:
            stream = path.open("a+b" if create else "r+b", buffering=0)
        except OSError as exc:
            raise OwnerLockUnavailable("Cannot establish operation ownership") from exc
        acquired = False
        try:
            stream.seek(0)
            try:
                if os.name == "nt":
                    import msvcrt
                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                acquired = True
            except OSError as exc:
                if exc.errno not in {errno.EACCES, errno.EAGAIN, errno.EDEADLK}:
                    raise OwnerLockUnavailable("Cannot verify operation lock") from exc
            yield acquired
        finally:
            # Never unlink: another process may still have the same inode open.
            stream.close()
