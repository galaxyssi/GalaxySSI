import tempfile
import unittest
from pathlib import Path

from desktop_native_tools import RUNTIME_STATUS, DesktopNativeToolRegistry
from desktop_runtime import DesktopRuntimeManager, ProbeResult


class _FakeRuntime:
    def __init__(self):
        self.refresh_values = []

    def snapshot(self, *, refresh=False):
        self.refresh_values.append(refresh)
        return {
            "contract_version": "galaxyssi.desktop-runtime/1.0",
            "checked_at_epoch_ms": 42,
            "summary": {"ready": 1, "partial": 0, "missing": 0, "total": 1},
            "capabilities": ["code.python.run"],
            "runtimes": [{
                "id": "python",
                "title": "Python",
                "status": "ready",
                "capabilities": ["code.python.run"],
            }],
        }

    @staticmethod
    def resolve_executable(value, *, refresh_if_missing=True):
        del refresh_if_missing
        return "C:/tools/python.exe" if value.casefold() in {"python", "python.exe"} else None


class DesktopRuntimeManagerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.model = self.root / "whisper-medium"
        self.model.mkdir()
        (self.model / "config.json").write_text("{}", encoding="utf-8")
        (self.model / "model.bin").write_bytes(b"model")
        self.calls = []
        self.commands = {
            "python": "C:/tools/python.exe",
            "python3": "C:/tools/python.exe",
            "py": "C:/tools/python.exe",
            "pip": "C:/tools/pip.exe",
            "node": "C:/tools/node.exe",
            "git": "C:/tools/git.exe",
            "ffmpeg": "C:/tools/ffmpeg.exe",
            "ffprobe": "C:/tools/ffprobe.exe",
            "tar": "C:/Windows/System32/tar.exe",
            "powershell.exe": "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe",
        }

    def tearDown(self):
        self.temporary.cleanup()

    def which(self, value):
        return self.commands.get(value)

    def run_probe(self, argv, timeout):
        self.calls.append((tuple(argv), timeout))
        source = " ".join(argv)
        if "playwright" in source:
            return ProbeResult(False, "", 1)
        if "faster_whisper" in source:
            return ProbeResult(True, "", 0)
        return ProbeResult(True, f"{Path(argv[0]).stem} version 1.2.3", 0)

    def manager(self, **overrides):
        values = {
            "which": self.which,
            "runner": self.run_probe,
            "environment": {"GALAXYSSI_WHISPER_MODEL": str(self.model)},
            "python_executable": "",
            "platform_name": "Windows",
            "home": self.root,
        }
        values.update(overrides)
        return DesktopRuntimeManager(**values)

    def test_inventory_reports_verified_capabilities_and_partial_components(self):
        snapshot = self.manager().snapshot()
        runtimes = {item["id"]: item for item in snapshot["runtimes"]}

        self.assertEqual("galaxyssi.desktop-runtime/1.0", snapshot["contract_version"])
        self.assertEqual("ready", runtimes["python"]["status"])
        self.assertEqual("partial", runtimes["node"]["status"])
        self.assertEqual(["npm", "npx"], runtimes["node"]["missing_components"])
        self.assertEqual("ready", runtimes["asr"]["status"])
        self.assertEqual("ready", runtimes["tts"]["status"])
        self.assertEqual("missing", runtimes["browser_automation"]["status"])
        self.assertIn("speech.transcribe", snapshot["capabilities"])
        self.assertIn("code.python.run", snapshot["capabilities"])

    def test_cached_inventory_avoids_repeated_process_probes_until_refresh(self):
        manager = self.manager()
        first = manager.snapshot()
        first_call_count = len(self.calls)
        second = manager.snapshot()

        self.assertEqual(first, second)
        self.assertEqual(first_call_count, len(self.calls))
        manager.snapshot(refresh=True)
        self.assertGreater(len(self.calls), first_call_count)

    def test_alias_resolution_uses_verified_inventory(self):
        manager = self.manager()

        self.assertEqual("C:/tools/python.exe", manager.resolve_executable("python3"))
        self.assertEqual("C:/tools/ffmpeg.exe", manager.resolve_executable("ffmpeg.exe"))
        self.assertIsNone(manager.resolve_executable("cmd.exe", refresh_if_missing=False))

    def test_explicit_runtime_override_is_reported_as_configured(self):
        self.commands["custom-ffmpeg"] = "D:/GalaxySSI/ffmpeg.exe"
        manager = self.manager(environment={
            "GALAXYSSI_WHISPER_MODEL": str(self.model),
            "GALAXYSSI_RUNTIME_FFMPEG_FFMPEG": "custom-ffmpeg",
        })

        runtime = next(item for item in manager.snapshot()["runtimes"] if item["id"] == "ffmpeg")

        self.assertEqual("D:/GalaxySSI/ffmpeg.exe", runtime["commands"]["ffmpeg"])
        self.assertEqual("configured", runtime["source"])

    def test_capability_query_returns_only_matching_runtimes(self):
        rows = self.manager().capability_status("media.video.process")

        self.assertEqual(["ffmpeg"], [row["id"] for row in rows])

    def test_native_runtime_tool_returns_verified_inventory(self):
        fake = _FakeRuntime()
        registry = DesktopNativeToolRegistry(
            state_root=self.root / "state",
            workspace_root=self.root / "workspaces",
            runtime_manager=fake,
        )

        result = registry.invoke(
            RUNTIME_STATUS,
            {"refresh": True},
            {"invocation_id": "runtime-status-1"},
        )

        self.assertEqual("succeeded", result["status"])
        self.assertEqual(1, result["output"]["summary"]["ready"])
        self.assertEqual([True], fake.refresh_values)
        self.assertEqual("passed", result["verification"]["status"])


if __name__ == "__main__":
    unittest.main()
