from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

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
            "android": {"device_install_launch_restore": False},
        }
        manager.v2_store = type("Store", (), {
            "paths": {"snapshots": source_root / "snapshots"}
        })()
        return manager

    def test_android_source_gate_builds_without_missing_local_runtime_assets(self):
        with tempfile.TemporaryDirectory() as root:
            manager = self.manager(Path(root))
            commands = manager._gate_commands([
                "apps/android/app/src/main/java/com/signalasi/chat/Feature.kt"
            ])
        android = next(command for command in commands if command.id == "android-unit-build")
        self.assertIn("-Psignalasi.requireEmbeddedRuntime=false", android.argv)

    def test_android_source_gate_uses_complete_embedded_runtime_when_available(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root)
            jni = source / "build/runtime/android-jni-libs"
            assets = source / "build/runtime/android-assets/runtime/qemu"
            jni.mkdir(parents=True)
            assets.mkdir(parents=True)
            (jni / "signalasi-qemu-bundle.json").write_text("{}", encoding="utf-8")
            (assets / "bundle.json").write_text("{}", encoding="utf-8")
            manager = self.manager(source)
            commands = manager._gate_commands([
                "apps/android/app/src/main/java/com/signalasi/chat/Feature.kt"
            ])
        android = next(command for command in commands if command.id == "android-unit-build")
        self.assertNotIn("-Psignalasi.requireEmbeddedRuntime=false", android.argv)

    def test_destructive_android_device_gate_requires_explicit_environment_switch(self):
        with tempfile.TemporaryDirectory() as root:
            manager = self.manager(Path(root))
            changed = ["apps/android/app/src/main/java/com/signalasi/chat/Feature.kt"]
            with patch.dict(os.environ, {}, clear=False):
                os.environ.pop("SIGNALASI_EVOLUTION_ANDROID_DEVICE_TEST", None)
                disabled = manager._gate_commands(changed)
            with patch.dict(
                os.environ,
                {"SIGNALASI_EVOLUTION_ANDROID_DEVICE_TEST": "1"},
                clear=False,
            ):
                enabled = manager._gate_commands(changed)
        self.assertNotIn("android-device-install-restore", [item.id for item in disabled])
        self.assertIn("android-device-install-restore", [item.id for item in enabled])


if __name__ == "__main__":
    unittest.main()
