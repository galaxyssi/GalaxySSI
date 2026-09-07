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
_journal = ContextVar("galaxyssi_owned_process_journal", default=None)


@contextmanager
def owned_process_scope(journal=None):
    token = _owned.set(True)
    journal_token = _journal.set(Path(journal) if journal is not None else _journal.get())
    try:
        yield
    finally:
        _owned.reset(token)
        _journal.reset(journal_token)


class OwnedProcess:
    def __init__(self, argv, **kwargs):
        from windows_process_job import WindowsProcessJob
        if kwargs.get("stdin") not in (None, subprocess.PIPE, subprocess.DEVNULL):
            raise ValueError("Owned execution supports PIPE, DEVNULL, or no stdin")
        self.job = WindowsProcessJob()
        self.process = None
        self._watcher = None
        self._record = None
        mode = "pipe" if kwargs.get("stdin") == subprocess.PIPE else "null"
        # The base interpreter avoids the Windows venv launcher spawning before job assignment.
        guardian = [getattr(sys, "_base_executable", sys.executable), "-I", "-S", "-u",
                    str(Path(__file__).with_name("owned_process_guardian.py")), mode, *argv]
        try:
            if _journal.get() is not None:
                from process_recovery_journal import record_job
                self._record = record_job(_journal.get(), self.job.name)
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
        if self._record is not None:
            from process_recovery_journal import retire_job
            retire_job(self._record, self.job.name)


def popen(argv, **kwargs):
    if os.name == "nt" and _owned.get():
        return OwnedProcess(argv, **kwargs)
    return subprocess.Popen(argv, **kwargs)


def run(argv, *, timeout=None, check=False, **kwargs):
    if os.name != "nt" or not _owned.get():
        return subprocess.run(argv, timeout=timeout, check=check, **kwargs)
    input_data = kwargs.pop("input", None)
    if input_data is not None:
        if "stdin" in kwargs:
            raise ValueError("stdin and input arguments may not both be used")
        kwargs["stdin"] = subprocess.PIPE
    process = popen(argv, **kwargs)
    try:
        stdout, stderr = process.communicate(input_data, timeout=timeout)
        result = subprocess.CompletedProcess(argv, process.returncode, stdout, stderr)
        if check:
            result.check_returncode()
        return result
    finally:
        process.close()
