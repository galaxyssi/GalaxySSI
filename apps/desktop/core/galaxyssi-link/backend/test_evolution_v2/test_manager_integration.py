from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from evolution_v2.manager import EvolutionManager


class FakePolicy:
    def __init__(self, config_path: Path):
        self.config_path = config_path

    def quality(self, _key, default=None):
        return default


class ManagerIntegrationTests(unittest.TestCase):
    def manager(self, source_root: Path) -> EvolutionManager:
        manager = object.__new__(EvolutionManager)
        manager.source_root = source_root
        manager.policy = FakePolicy(source_root / "config" / "evolution-policy.json")
        manager.gate_config = {
            "desktop": {"isolated_backend_health": True},
            "android": {"device_install_launch_restore": True},
        }
        manager.v2_store = type("Store", (), {
            "paths": {"snapshots": source_root / "snapshots"}
        })()
        return manager

    def test_android_source_gate_builds_without_missing_local_runtime_assets(self):
        with tempfile.TemporaryDirectory() as root:
            manager = self.manager(Path(root))
            commands = manager._gate_commands([
                "apps/android/app/src/main/java/com/galaxyssi/chat/Feature.kt"
            ])
        android = next(command for command in commands if command.id == "android-unit-build")
        self.assertIn("-Pgalaxyssi.requireEmbeddedRuntime=false", android.argv)

    def test_android_source_gate_uses_complete_embedded_runtime_when_available(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root)
            jni = source / "build/runtime/android-jni-libs"
            assets = source / "build/runtime/android-assets/runtime/qemu"
            jni.mkdir(parents=True)
            assets.mkdir(parents=True)
            (jni / "galaxyssi-qemu-bundle.json").write_text("{}", encoding="utf-8")
            (assets / "bundle.json").write_text("{}", encoding="utf-8")
            manager = self.manager(source)
            commands = manager._gate_commands([
                "apps/android/app/src/main/java/com/galaxyssi/chat/Feature.kt"
            ])
        android = next(command for command in commands if command.id == "android-unit-build")
        self.assertNotIn("-Pgalaxyssi.requireEmbeddedRuntime=false", android.argv)

    def test_desktop_candidate_gate_requires_two_reload_cycles(self):
        with tempfile.TemporaryDirectory() as root:
            manager = self.manager(Path(root))
            commands = manager._gate_commands([
                "apps/desktop/core/galaxyssi-link/backend/feature.py"
            ])

        runtime = next(
            command
            for command in commands
            if command.id == "desktop-isolated-runtime"
        )
        self.assertIn("--reload-cycles", runtime.argv)
        reload_index = runtime.argv.index("--reload-cycles")
        self.assertEqual("2", runtime.argv[reload_index + 1])

    def test_android_device_evidence_gate_is_required_after_build(self):
        with tempfile.TemporaryDirectory() as root:
            manager = self.manager(Path(root))
            changed = ["apps/android/app/src/main/java/com/galaxyssi/chat/Feature.kt"]
            commands = manager._gate_commands(changed)

        gate_ids = [item.id for item in commands]
        self.assertIn("android-unit-build", gate_ids)
        self.assertIn("android-device-install-restore", gate_ids)
        self.assertLess(
            gate_ids.index("android-unit-build"),
            gate_ids.index("android-device-install-restore"),
        )


if __name__ == "__main__":
    unittest.main()
