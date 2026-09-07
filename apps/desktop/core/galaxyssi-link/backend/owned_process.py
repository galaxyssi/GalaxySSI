"""Opt-in Windows child-tree ownership for isolated execution, not chat pools."""
from __future__ import annotations

from contextlib import contextmanager
from contextvars import ContextVar
import os
from pathlib import Path
import subprocess
import sys
import threading


_owned = ContextVar("galaxyssi_owned_process_scope", default=False)


@contextmanager
def owned_process_scope():
    token = _owned.set(True)
    try:
        yield
    finally:
        _owned.reset(token)


class OwnedProcess:
    def __init__(self, argv, **kwargs):
        from windows_process_job import WindowsProcessJob
        if kwargs.get("stdin") not in (None, subprocess.PIPE, subprocess.DEVNULL):
            raise ValueError("Owned execution supports PIPE, DEVNULL, or no stdin")
        self.job = WindowsProcessJob()
        self.process = None
        self._watcher = None
        mode = "pipe" if kwargs.get("stdin") == subprocess.PIPE else "null"
        # The base interpreter avoids the Windows venv launcher spawning before job assignment.
        guardian = [getattr(sys, "_base_executable", sys.executable), "-I", "-S", "-u",
                    str(Path(__file__).with_name("owned_process_guardian.py")), mode, *argv]
        try:
            self.process = subprocess.Popen(guardian, **{**kwargs, "stdin": subprocess.PIPE})
            self.job.assign(self.process)
            self._watcher = threading.Thread(target=self._watch_exit, daemon=True, name="owned-process-exit")
            self._watcher.start()
            self.process.stdin.write("G" if self.process.text_mode else b"G")
            self.process.stdin.flush()
        except BaseException:
            self.close()
            raise

    def __getattr__(self, name):
        return getattr(self.process, name)

    def _watch_exit(self):
        self.process.wait()
        # Descendants holding inherited stdout must not keep communicate() alive.
        self.job.close()

    def kill(self):
        self.job.close()

    terminate = kill

    def close(self):
        self.job.close()
        if self.process is not None:
            if self.process.poll() is None:
                self.process.kill()
            self.process.wait(timeout=10)
            if self._watcher is not None and self._watcher.ident is not None:
                self._watcher.join(timeout=10)
            for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
                if stream is not None and not stream.closed:
                    stream.close()


def popen(argv, **kwargs):
    if os.name == "nt" and _owned.get():
        return OwnedProcess(argv, **kwargs)
    return subprocess.Popen(argv, **kwargs)


def run(argv, *, timeout=None, check=False, **kwargs):
    if os.name != "nt" or not _owned.get():
        return subprocess.run(argv, timeout=timeout, check=check, **kwargs)
    process = popen(argv, **kwargs)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        result = subprocess.CompletedProcess(argv, process.returncode, stdout, stderr)
        if check:
            result.check_returncode()
        return result
    finally:
        process.close()
