import base64
import importlib.util
import sys
import tempfile
import time
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "signalasi_runtime_broker.py"
SPEC = importlib.util.spec_from_file_location("signalasi_runtime_broker", MODULE_PATH)
assert SPEC and SPEC.loader
BROKER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BROKER
SPEC.loader.exec_module(BROKER)


class RuntimeBrokerProtocolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.key = b"s" * 32
        self.temp_dir = tempfile.TemporaryDirectory()
        root = Path(self.temp_dir.name)
        self.config = BROKER.BrokerConfig(
            session_key=self.key,
            linux_command_prefix=(sys.executable, "-c", "import sys; sys.exit(0)"),
            workspace_root=root / "workspaces",
            linux_base_version="1.3.9",
            distribution="test Linux",
            ready_command=("/bin/sh", "-lc", "true"),
        )
        self.config.workspace_root.mkdir(mode=0o700)
        self.runtime = BROKER.RuntimeBroker(self.config)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def request(self, request_id: str = "request-1") -> dict:
        return BROKER.sign({
            "protocol_version": 1,
            "request_id": request_id,
            "operation": "status",
            "input": {},
            "context": {"workspace_id": "workspace-1"},
            "timestamp_epoch_ms": int(time.time() * 1_000),
        }, self.key)

    def test_accepts_signed_status_and_signs_response(self) -> None:
        response = self.runtime.handle(self.request())

        self.assertTrue(response["ok"])
        self.assertTrue(BROKER.is_valid_signature(response, self.key))
        self.assertEqual("ios_jailbreak_runtime_broker", response["result"]["backend"])
        self.assertTrue(response["result"]["backend_ready"])

    def test_rejects_replayed_request(self) -> None:
        request = self.request()
        self.assertTrue(self.runtime.handle(request)["ok"])

        response = self.runtime.handle(request)

        self.assertFalse(response["ok"])
        self.assertEqual("runtime_broker_request_replayed", response["error"]["code"])
        self.assertTrue(BROKER.is_valid_signature(response, self.key))

    def test_rejects_tampered_request(self) -> None:
        request = self.request()
        request["operation"] = "execute"

        response = self.runtime.handle(request)

        self.assertFalse(response["ok"])
        self.assertEqual("runtime_broker_authentication_failed", response["error"]["code"])

    def test_rejects_network_execution_until_a_policy_is_available(self) -> None:
        request = self.request()
        request["operation"] = "execute"
        request["input"] = {
            "language": "shell",
            "source": "echo should-not-run",
            "arguments": [],
            "timeout_ms": 1_000,
            "network_enabled": True,
        }
        request = BROKER.sign({key: value for key, value in request.items() if key != "mac"}, self.key)

        response = self.runtime.handle(request)

        self.assertFalse(response["ok"])
        self.assertEqual("runtime_network_policy_unavailable", response["error"]["code"])


if __name__ == "__main__":
    unittest.main()
