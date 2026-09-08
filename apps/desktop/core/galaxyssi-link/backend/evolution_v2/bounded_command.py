"""Bound captured diagnostic output before it can exhaust process memory."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import threading
import time

from .common import redact_text


def run_bounded(argv, cwd, *, maximum_bytes, timeout_seconds):
    from owned_process import owned_process_scope, popen
    from .runner import CommandResult
    values = [str(item) for item in argv]
    if not values or any("\x00" in value for value in values) or type(maximum_bytes) is not int or maximum_bytes < 1:
        raise ValueError("Invalid bounded diagnostic command")
    started = time.monotonic()
    expired = threading.Event()
    with owned_process_scope():
        process = popen(values, cwd=str(Path(cwd)), stdin=subprocess.DEVNULL,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, shell=False,
                        env={**os.environ, "GIT_TERMINAL_PROMPT": "0", "CI": "1"})
    def timeout():
        expired.set()
        try:
            process.kill()
        except OSError:
            pass
    timer = threading.Timer(max(1, timeout_seconds), timeout)
    timer.daemon = True
    data = bytearray()
    truncated = False
    timer.start()
    try:
        while len(data) <= maximum_bytes:
            block = process.stdout.read(min(65536, maximum_bytes + 1 - len(data)))
            if not block:
                break
            data.extend(block)
        truncated = len(data) > maximum_bytes
        if truncated:
            process.kill()
        code = process.wait(timeout=10)
        if expired.is_set():
            raise TimeoutError("Diagnostic command stopped responding")
        text = redact_text(bytes(data[:maximum_bytes]).decode("utf-8", errors="replace"), maximum=maximum_bytes)
        return CommandResult(values, str(cwd), 0 if truncated else code, text,
                             int((time.monotonic() - started) * 1000)), truncated
    finally:
        timer.cancel()
        timer.join()
        if process.poll() is None:
            process.kill()
            process.wait(timeout=10)
        close = getattr(process, "close", None)
        if close is not None:
            close()
        else:
            process.stdout.close()
        data[:] = b"\x00" * len(data)
