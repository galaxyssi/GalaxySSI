import threading
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from unittest.mock import mock_open

import signalasi_client


class SignalSidecarLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.original_process = signalasi_client._process
        self.original_port = signalasi_client.SIDECAR_PORT
        self.original_base = signalasi_client.SIDECAR_BASE
        signalasi_client._process = None

    def tearDown(self):
        signalasi_client._process = self.original_process
        signalasi_client.SIDECAR_PORT = self.original_port
        signalasi_client.SIDECAR_BASE = self.original_base

    def test_concurrent_callers_share_one_sidecar_startup(self):
        process = Mock(pid=321)
        process.poll.return_value = None
        healthy = iter([False, True, True])
        errors = []

        def start():
            try:
                signalasi_client.start_signal_sidecar()
            except Exception as error:  # pragma: no cover - asserted below
                errors.append(error)

        with patch.object(signalasi_client, "_is_healthy", side_effect=lambda: next(healthy, True)), \
                patch.object(Path, "exists", return_value=True), \
                patch.object(signalasi_client, "_port_is_in_use", return_value=False), \
                patch.object(signalasi_client, "derived_storage_key", return_value=b"x" * 32), \
                patch.object(signalasi_client, "open", mock_open()), \
                patch.object(signalasi_client.subprocess, "Popen", return_value=process) as popen:
            callers = [threading.Thread(target=start) for _ in range(2)]
            for caller in callers:
                caller.start()
            for caller in callers:
                caller.join(timeout=2)

        self.assertEqual([], errors)
        self.assertEqual(1, popen.call_count)

    def test_failed_startup_terminates_spawned_process(self):
        process = Mock(pid=654)
        process.poll.return_value = 1

        with patch.object(signalasi_client, "_is_healthy", return_value=False), \
                patch.object(Path, "exists", return_value=True), \
                patch.object(signalasi_client, "_port_is_in_use", return_value=False), \
                patch.object(signalasi_client, "derived_storage_key", return_value=b"x" * 32), \
                patch.object(signalasi_client, "open", mock_open()), \
                patch.object(signalasi_client.subprocess, "Popen", return_value=process), \
                patch.object(signalasi_client, "_terminate_process") as terminate:
            with self.assertRaisesRegex(RuntimeError, "did not become healthy"):
                signalasi_client.start_signal_sidecar()

        terminate.assert_called_once_with(process)
        self.assertIsNone(signalasi_client._process)

    def test_configured_sidecar_runtime_is_discovered(self):
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / ("signalasi-link-sidecar.bat" if os.name == "nt" else "signalasi-link-sidecar")
            script.write_text("", encoding="utf-8")
            with patch.dict(os.environ, {"SIGNALASI_LINK_SIDECAR_SCRIPT": str(script)}):
                self.assertEqual(script, signalasi_client.resolve_sidecar_script())

    def test_missing_local_runtime_falls_back_to_trusted_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            fallback = Path(directory) / "signalasi-link-sidecar.bat"
            fallback.write_text("", encoding="utf-8")
            with patch.object(
                signalasi_client,
                "sidecar_script_candidates",
                return_value=[Path(directory) / "missing.bat", fallback],
            ):
                self.assertEqual(fallback, signalasi_client.resolve_sidecar_script())


if __name__ == "__main__":
    unittest.main()
