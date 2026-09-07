"""OS-held CI observer ownership, independent of PID reuse and wall-clock leases."""
from __future__ import annotations

from contextlib import contextmanager
import errno
import os
from pathlib import Path
import re


OWNER_PATTERN = re.compile(r"ci-lock-v1-[0-9a-f]{32}$")


class OwnerLockUnavailable(OSError):
    pass


class CiOwnerLocks:
    def __init__(self, root: Path):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    @contextmanager
    def hold(self, owner: str, *, create: bool = False):
        if not OWNER_PATTERN.fullmatch(owner):
            raise ValueError("Invalid CI observer owner identity")
        path = self.root / (owner + ".lock")
        try:
            stream = path.open("a+b" if create else "r+b", buffering=0)
        except OSError as exc:
            raise OwnerLockUnavailable("Cannot establish CI observer ownership") from exc
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
                    raise OwnerLockUnavailable("Cannot verify CI observer lock") from exc
            yield acquired
        finally:
            # Never unlink lock files: another live process may still hold the same inode.
            stream.close()
