from __future__ import annotations

import io
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

from evolution_v2 import runtime_smoke


class _FakeProcess:
    def __init__(self) -> None:
        self.returncode = None
        self.stdout = _GuardedStdout(self)

    def poll(self):
        return self.returncode

    def terminate(self) -> None:
        self.returncode = 0

    def send_signal(self, _signal) -> None:
        self.returncode = 0

    def kill(self) -> None:
        self.returncode = -9

    def wait(self, timeout=None):
        return self.returncode


class _GuardedStdout(io.StringIO):
    def __init__(self, process: _FakeProcess) -> None:
        super().__init__("candidate log")
        self.process = process

    def read(self, *args, **kwargs):
        if self.process.poll() is None:
            raise AssertionError("runtime smoke attempted to read a live child pipe")
        return super().read(*args, **kwargs)


class RuntimeSmokeTests(unittest.TestCase):
    def test_unhealthy_live_backend_is_terminated_before_pipe_read(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            backend = Path(directory)
            (backend / "main.py").write_text("app = object()\n", encoding="utf-8")
            process = _FakeProcess()
            with (
                mock.patch.object(runtime_smoke.subprocess, "Popen", return_value=process),
                mock.patch.object(runtime_smoke, "free_port", return_value=43123),
                mock.patch.object(runtime_smoke.time, "monotonic", side_effect=[0.0, 10.0]),
                mock.patch.object(
                    runtime_smoke.urllib.request,
                    "urlopen",
                    side_effect=urllib.error.URLError("offline"),
                ),
            ):
                with self.assertRaises(RuntimeError):
                    runtime_smoke.run(backend, 1)
            self.assertIsNotNone(process.poll())


if __name__ == "__main__":
    unittest.main()
