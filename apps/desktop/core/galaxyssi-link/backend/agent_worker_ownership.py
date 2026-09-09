"""Stable OS file ownership for one worker controller per local Run ledger."""
import hashlib
import os
from pathlib import Path
import threading

from agent_worker_local import WorkerExecutionFenced


class WorkerClientOwnership:
    def __init__(self, ledger):
        self.ledger_path = os.path.normcase(str(Path(ledger.path).resolve()))
        key = hashlib.sha256(self.ledger_path.encode()).hexdigest()
        self.path = Path(ledger.path).resolve().parent / "worker-client-owners" / (key + ".lock")
        self._stream = None
        self._lock = threading.RLock()

    def acquire(self):
        with self._lock:
            if self._stream is not None:
                raise WorkerExecutionFenced("worker_client_owner_already_held")
            stream = None
            try:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                stream = self.path.open("a+b", buffering=0)
                stream.seek(0)
                if os.name == "nt":
                    import msvcrt
                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                self._stream = stream
            except OSError as error:
                if stream is not None:
                    stream.close()
                raise WorkerExecutionFenced("worker_client_owner_unavailable") from error
        return self

    def require(self, ledger):
        with self._lock:
            if (self._stream is None or self._stream.closed
                    or os.path.normcase(str(Path(ledger.path).resolve())) != self.ledger_path):
                raise WorkerExecutionFenced("worker_client_owner_not_held")

    def release(self):
        with self._lock:
            if self._stream is not None:
                self._stream.close()
                self._stream = None
        # Never unlink a lock file: another process may already have it open.
