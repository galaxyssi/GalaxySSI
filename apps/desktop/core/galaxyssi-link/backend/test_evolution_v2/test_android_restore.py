from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from evolution_v2.snapshots import (
    AndroidCandidateError,
    AndroidCandidateTester,
    AndroidSnapshot,
)


def completed(*args: str, returncode: int = 0, stdout: str = ""):
    return subprocess.CompletedProcess(list(args), returncode, stdout, "")


class FakeAndroidTester(AndroidCandidateTester):
    def __init__(
        self,
        root: Path,
        snapshot: AndroidSnapshot,
        *,
        fatal: bool = False,
        capture_screenshot: bool = True,
    ):
        super().__init__(root)
        self.snapshot = snapshot
        self.fatal = fatal
        self.capture_screenshot = capture_screenshot
        self.restore_calls = 0

    def _choose_device(self) -> str:
        return "test-device"

    def _snapshot(self, _serial: str) -> AndroidSnapshot:
        return self.snapshot

    def _resolve_activity(self, _serial: str) -> str:
        return "com.galaxyssi.chat/.MainActivity"

    def _screenshot(self, _serial: str, target: Path) -> None:
        if self.capture_screenshot:
            target.write_bytes(b"\x89PNG\r\n\x1a\n")

    def _adb(self, _serial: str, *args: str, timeout: int = 120):
        del timeout
        if args[:3] == ("logcat", "-d", "-v"):
            output = (
                "AndroidRuntime FATAL EXCEPTION com.galaxyssi.chat"
                if self.fatal
                else ""
            )
            return completed(*args, stdout=output)
        return completed(*args, stdout="Success")

    def _restore(
        self,
        serial: str,
        snapshot: AndroidSnapshot,
        *,
        uninstall_only: bool,
    ) -> None:
        self.restore_calls += 1
        super()._restore(serial, snapshot, uninstall_only=uninstall_only)


class AndroidRestoreTests(unittest.TestCase):
    def snapshot(self, root: Path) -> AndroidSnapshot:
        stable = root / "stable.apk"
        stable.write_bytes(b"stable-apk")
        from evolution_v2.common import sha256_file

        return AndroidSnapshot(
            snapshot_id="android-test",
            serial="test-device",
            package_name="com.galaxyssi.chat",
            root=str(root),
            stable_apks=[str(stable)],
            stable_sha256={stable.name: sha256_file(stable)},
        )

    def test_successful_candidate_always_restores_stable_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = root / "candidate.apk"
            candidate.write_bytes(b"candidate")
            tester = FakeAndroidTester(root / "snapshots", self.snapshot(root))
            result = tester.run(candidate, launch_wait_seconds=1)
            self.assertTrue(result["passed"])
            self.assertTrue(result["stable_restored"])
            self.assertEqual(64, len(result["candidate_sha256"]))
            self.assertEqual(64, len(result["screenshot_sha256"]))
            self.assertEqual(64, len(result["logcat_sha256"]))
            self.assertEqual(64, len(result["evidence_sha256"]))
            self.assertTrue(Path(result["evidence_manifest"]).is_file())
            evidence = json.loads(
                Path(result["evidence_manifest"]).read_text(encoding="utf-8")
            )
            self.assertEqual(
                "galaxyssi.evolution.android-evidence.v1",
                evidence["protocol"],
            )
            self.assertEqual(
                {
                    "candidate_apk",
                    "candidate_logcat",
                    "candidate_screenshot",
                    "stable_apk_0",
                },
                set(evidence["artifacts"]),
            )
            self.assertEqual(1, tester.restore_calls)

    def test_crashing_candidate_still_restores_stable_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = root / "candidate.apk"
            candidate.write_bytes(b"candidate")
            tester = FakeAndroidTester(
                root / "snapshots",
                self.snapshot(root),
                fatal=True,
            )
            with self.assertRaises(AndroidCandidateError):
                tester.run(candidate, launch_wait_seconds=1)
            self.assertEqual(1, tester.restore_calls)
            evidence = json.loads(
                (root / "candidate-evidence.json").read_text(encoding="utf-8")
            )
            self.assertFalse(evidence["passed"])
            self.assertTrue(evidence["stable_restored"])
            self.assertTrue(evidence["fatal_lines"])

    def test_missing_candidate_screenshot_fails_and_restores_stable_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = root / "candidate.apk"
            candidate.write_bytes(b"candidate")
            tester = FakeAndroidTester(
                root / "snapshots",
                self.snapshot(root),
                capture_screenshot=False,
            )

            with self.assertRaisesRegex(
                AndroidCandidateError,
                "screenshot was not captured",
            ):
                tester.run(candidate, launch_wait_seconds=1)

            self.assertEqual(1, tester.restore_calls)
            evidence = json.loads(
                (root / "candidate-evidence.json").read_text(encoding="utf-8")
            )
            self.assertFalse(evidence["passed"])
            self.assertTrue(evidence["stable_restored"])

    def test_snapshot_hash_mismatch_blocks_restore(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            snapshot = self.snapshot(root)
            Path(snapshot.stable_apks[0]).write_bytes(b"tampered")
            with self.assertRaisesRegex(AndroidCandidateError, "hash mismatch"):
                AndroidCandidateTester._verify_snapshot_files(snapshot)


if __name__ == "__main__":
    unittest.main()
