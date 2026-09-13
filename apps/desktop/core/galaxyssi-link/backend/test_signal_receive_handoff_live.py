"""Real Python -> HTTP -> JVM Signal -> SQLite crash/retry acceptance."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import galaxyssi_client as client
import link_delivery as delivery
import signal_receive_handoff as handoff


class SignalReceiveHandoffLiveTest(unittest.TestCase):
    def test_jvm_death_before_and_after_python_durable_handoff(self):
        script = client.SIDECAR_SCRIPT
        java = Path(os.environ.get("JAVA_HOME", "")) / "bin" / ("java.exe" if os.name == "nt" else "java")
        if not java.is_file():
            java = Path(shutil.which("java") or "missing-java")
        if not script.is_file() or not java.is_file():
            self.skipTest("Build this worktree's sidecar installDist and configure Java first")
        libraries = script.parent.parent / "lib" / "*"
        with tempfile.TemporaryDirectory(prefix="galaxyssi-handoff-live-") as directory:
            root = Path(directory)
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            with patch.multiple(client, _process=None, SIDECAR_DIR=root, SIDECAR_PORT=port,
                                SIDECAR_BASE=f"http://127.0.0.1:{port}", SIGNAL_STORE_PATH=root / "signal.db"), \
                    patch.object(client, "resolve_sidecar_script", return_value=script), \
                    patch.object(delivery, "DB_PATH", root / "delivery.db"):
                try:
                    bundle = client.get_signal_bundle()
                    bundle_path = root / "bundle.json"
                    bundle_path.write_text(json.dumps(bundle), encoding="utf-8")
                    generated = subprocess.run([str(java), "-cp", str(libraries), "com.galaxyssi.link.SignalAtomicReceiveProbe",
                                                "wire", str(bundle_path)], check=True, capture_output=True, text=True, timeout=30,
                                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                    wire = json.loads(generated.stdout)
                    remote_name = wire["from"]
                    with patch.object(handoff, "persist_receive", side_effect=OSError("injected Python disk failure")):
                        with self.assertRaises(OSError):
                            client.decrypt_signal_envelope(wire, remote_name)
                    first_process = client._process
                    client._terminate_process(first_process)
                    # The same pre-key ciphertext can only succeed through the durable JVM journal now.
                    recovered = client.decrypt_signal_envelope(wire, remote_name)
                    self.assertEqual("private-atomic-receive-marker", recovered["payload"]["content"])
                    self.assertIsNot(first_process, client._process)
                    self.assertEqual(bundle["identityKeySha256"], client.get_signal_bundle()["identityKeySha256"])
                    client._terminate_process(client._process)
                    actual_request = client._request
                    with patch.object(client, "_request", wraps=actual_request) as requests:
                        replay = client.decrypt_signal_envelope(wire, remote_name)
                    self.assertEqual(recovered, replay)
                    self.assertNotIn("/decrypt", [call.args[1] for call in requests.call_args_list])
                    self.assertNotIn("/receive-stored", [call.args[1] for call in requests.call_args_list])
                    print("LIVE_SIGNAL_HANDOFF_OK jvm_restart_before_python_commit=true after_python_commit=true no_second_decrypt=true", flush=True)
                finally:
                    client.stop_signal_sidecar()
