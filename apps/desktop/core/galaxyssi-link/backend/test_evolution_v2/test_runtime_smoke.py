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
    def test_candidate_reloads_twice_with_the_same_isolated_state(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            backend = Path(directory)
            (backend / "main.py").write_text("app = object()\n", encoding="utf-8")
            processes = [_FakeProcess(), _FakeProcess()]
            health = [
                io.BytesIO(b'{"status":"ok","cycle":1}'),
                io.BytesIO(b'{"status":"ok","cycle":2}'),
            ]
            with (
                mock.patch.object(
                    runtime_smoke.subprocess,
                    "Popen",
                    side_effect=processes,
                ) as popen,
                mock.patch.object(
                    runtime_smoke,
                    "free_port",
                    side_effect=[43123, 43124],
                ),
                mock.patch.object(
                    runtime_smoke.urllib.request,
                    "urlopen",
                    side_effect=health,
                ),
            ):
                result = runtime_smoke.run(
                    backend,
                    1,
                    reload_cycles=2,
                )

            self.assertTrue(result["passed"])
            self.assertTrue(result["reload_verified"])
            self.assertTrue(result["state_persisted_across_reload"])
            self.assertEqual(2, result["reload_cycles"])
            self.assertEqual([43123, 43124], [item["port"] for item in result["cycles"]])
            self.assertTrue(all(process.poll() is not None for process in processes))
            first_env = popen.call_args_list[0].kwargs["env"]
            second_env = popen.call_args_list[1].kwargs["env"]
            self.assertEqual(
                first_env["GALAXYSSI_STATE_DIR"],
                second_env["GALAXYSSI_STATE_DIR"],
            )

    def test_failed_second_reload_stops_every_candidate_process(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            backend = Path(directory)
            (backend / "main.py").write_text("app = object()\n", encoding="utf-8")
            processes = [_FakeProcess(), _FakeProcess()]
            with (
                mock.patch.object(
                    runtime_smoke.subprocess,
                    "Popen",
                    side_effect=processes,
                ),
                mock.patch.object(
                    runtime_smoke,
                    "free_port",
                    side_effect=[43123, 43124],
                ),
                mock.patch.object(
                    runtime_smoke.time,
                    "monotonic",
                    side_effect=[0.0, 0.0, 10.0, 20.0],
                ),
                mock.patch.object(
                    runtime_smoke.urllib.request,
                    "urlopen",
                    return_value=io.BytesIO(b'{"status":"ok"}'),
                ),
            ):
                with self.assertRaisesRegex(RuntimeError, "Reload cycle 2"):
                    runtime_smoke.run(
                        backend,
                        1,
                        reload_cycles=2,
                    )

            self.assertTrue(all(process.poll() is not None for process in processes))

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
