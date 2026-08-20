import base64
import dataclasses
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
            allow_package_network_refresh=False,
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
        self.assertEqual(BROKER.RuntimeBroker.execution_limits_available(), response["result"]["backend_ready"])

    def test_reports_android_compatible_execution_limits(self) -> None:
        limits = self.runtime.status()["execution_limits"]

        self.assertEqual(60_000, limits["wall_clock_ms"])
        self.assertEqual(45_000, limits["cpu_ms"])
        self.assertEqual(512 * 1024 * 1024, limits["memory_bytes"])
        self.assertEqual(512 * 1024 * 1024, limits["disk_bytes"])
        self.assertEqual(64, limits["max_processes"])
        self.assertEqual(512 * 1024, limits["max_output_bytes"])
        self.assertEqual(256 * 1024 * 1024, limits["max_artifact_bytes"])

    def test_scales_cpu_limit_with_execution_timeout(self) -> None:
        limits = BROKER.DEFAULT_EXECUTION_LIMITS.for_timeout(120_000)

        self.assertEqual(120_000, limits.wall_clock_ms)
        self.assertEqual(90_000, limits.cpu_ms)

    def test_accepts_android_resource_limit_wire_names(self) -> None:
        limits = BROKER.RuntimeResourceLimits.from_input({
            "wall_clock_ms": 10_000,
            "cpu_ms": 7_500,
            "memory_bytes": 64 * 1024 * 1024,
            "disk_bytes": 16 * 1024 * 1024,
            "max_processes": 8,
            "max_output_bytes": 64 * 1024,
            "max_artifact_bytes": 8 * 1024 * 1024,
        }, 60_000)

        self.assertEqual(10_000, limits.wall_clock_ms)
        self.assertEqual(7_500, limits.cpu_ms)
        self.assertEqual(8, limits.max_processes)

    def test_rejects_resource_limit_above_iOS_transport_budget(self) -> None:
        with self.assertRaisesRegex(BROKER.BrokerFailure, "output limit"):
            BROKER.RuntimeResourceLimits.from_input({"max_output_bytes": 513 * 1024}, 60_000)

    def test_rejects_workspace_or_artifacts_that_exceed_limits(self) -> None:
        workspace = self.config.workspace_root / "workspace-1"
        workspace.mkdir(mode=0o700)
        (workspace / "large.bin").write_bytes(b"x" * 3)

        with self.assertRaisesRegex(BROKER.BrokerFailure, "workspace exceeded"):
            self.runtime.require_workspace_within_limit(workspace, 2)
        with self.assertRaisesRegex(BROKER.BrokerFailure, "artifacts exceeded"):
            self.runtime.artifacts(["large.bin"], workspace, 2)

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

    def test_refreshes_package_metadata_before_installing(self) -> None:
        self.runtime.config = dataclasses.replace(self.config, allow_package_network_refresh=True)
        calls: list[list[str]] = []

        def run_linux(command: list[str], workspace: Path, timeout_ms: int):
            calls.append(command)
            return BROKER.subprocess.CompletedProcess(command, 0, b"installed", b"")

        self.runtime.run_linux = run_linux

        result = self.runtime.software_mutate("software.install", {"software_id": "git"})

        self.assertEqual("install", result["operation"])
        self.assertEqual(
            [
                ["apt-get", "update"],
                ["apt-get", "-y", "--no-install-recommends", "install", "git"],
            ],
            calls,
        )

    def test_ranks_exact_package_before_related_candidates_and_honors_limit(self) -> None:
        results = [
            {"software_id": "libgit2-dev", "description": "Git library headers"},
            {"software_id": "python-gitlab", "description": "GitLab API client"},
            {"software_id": "git", "description": "fast distributed version control system"},
            {"software_id": "git-lfs", "description": "Git extension for large files"},
            {"software_id": "git", "description": "duplicate should be ignored"},
        ]

        ranked = self.runtime.rank_software_search_results(results, "Git", 3)

        self.assertEqual(["git", "git-lfs", "libgit2-dev"], [row["software_id"] for row in ranked])


if __name__ == "__main__":
    unittest.main()
