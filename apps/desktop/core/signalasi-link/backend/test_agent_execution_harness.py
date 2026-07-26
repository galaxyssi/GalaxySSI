import json
import os
import tempfile
import threading
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from agent_execution_harness import (
    AgentExecutionHarness,
    AgentReasoningEffort,
    AgentTaskKind,
    execution_policy_for,
    finalize_task_artifacts,
)
from task_workspace import task_workspace


class AgentExecutionHarnessTests(unittest.TestCase):
    def test_policy_classifies_complex_tasks_and_has_no_absolute_deadline(self):
        policy = execution_policy_for(
            "Build an Android phone game and return the APK"
        )

        self.assertEqual(AgentTaskKind.BUILD, policy.task_kind)
        self.assertEqual(AgentReasoningEffort.MEDIUM, policy.reasoning_effort)
        self.assertEqual("android", policy.target_platform)
        self.assertTrue(policy.requires_artifact)
        self.assertIsNone(policy.public()["absolute_timeout_seconds"])

    def test_input_attachment_uses_medium_reasoning_without_requiring_new_output(self):
        policy = execution_policy_for(
            "Summarize this spreadsheet",
            attachments=("downloads/input/report.xlsx",),
        )

        self.assertEqual(AgentTaskKind.ARTIFACT, policy.task_kind)
        self.assertEqual(AgentReasoningEffort.MEDIUM, policy.reasoning_effort)
        self.assertFalse(policy.requires_artifact)

    def test_checkpoint_and_same_failure_budget_are_persistent(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": temporary},
        ):
            harness = AgentExecutionHarness(
                "task-checkpoint",
                "hermes",
                "Build a small program",
            )
            can_replan, first_count = harness.record_failure(
                "command",
                "python verify.py exited 1",
            )
            second_replan, second_count = harness.record_failure(
                "command",
                "python verify.py exited 2",
            )
            checkpoint = (
                task_workspace("task-checkpoint", "hermes")
                / ".signalasi"
                / "execution-checkpoint.json"
            )
            data = json.loads(checkpoint.read_text(encoding="utf-8"))

            self.assertTrue(can_replan)
            self.assertEqual(1, first_count)
            self.assertFalse(second_replan)
            self.assertEqual(2, second_count)
            self.assertEqual("failed", data["phase"])
            self.assertEqual(1, data["replans"])
            self.assertEqual([2], list(data["failure_counts"].values()))

            AgentExecutionHarness(
                "task-checkpoint",
                "codex",
                "Build a small program",
            ).begin_attempt()
            restored = AgentExecutionHarness(
                "task-checkpoint",
                "hermes",
                "Build a small program",
            )

            self.assertEqual("failed", restored.checkpoint.phase)
            self.assertEqual(1, restored.checkpoint.replans)
            self.assertEqual([2], list(restored.checkpoint.failure_counts.values()))

    def test_concurrent_checkpoint_progress_keeps_valid_json(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": temporary},
        ):
            harness = AgentExecutionHarness(
                "task-concurrent-checkpoint",
                "codex",
                "Build a small program",
            )
            failures = []

            def update(index):
                try:
                    harness.progress("act", event_index=index)
                except Exception as exc:
                    failures.append(exc)

            threads = [
                threading.Thread(target=update, args=(index,))
                for index in range(40)
            ]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join()

            checkpoint = (
                task_workspace("task-concurrent-checkpoint", "codex")
                / ".signalasi"
                / "execution-checkpoint.json"
            )
            data = json.loads(checkpoint.read_text(encoding="utf-8"))
            temporary_files = list(checkpoint.parent.glob("*.tmp"))

            self.assertEqual([], failures)
            self.assertEqual("task-concurrent-checkpoint", data["task_id"])
            self.assertEqual("act", data["phase"])
            self.assertEqual([], temporary_files)

    def test_locked_checkpoint_does_not_interrupt_execution(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": temporary},
        ):
            harness = AgentExecutionHarness(
                "task-locked-checkpoint",
                "codex",
                "Build a small program",
            )
            with patch(
                "agent_execution_harness.os.replace",
                side_effect=PermissionError(5, "access denied"),
            ):
                harness.progress("observe", tool="python verify.py")

            self.assertEqual("observe", harness.checkpoint.phase)
            self.assertEqual(
                "python verify.py",
                harness.checkpoint.verification["tool"],
            )

    def test_single_file_stays_native(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": temporary},
        ):
            root = task_workspace("task-single", "codex")
            (root / "main.py").write_text("print('ok')\n", encoding="utf-8")

            result = finalize_task_artifacts(
                "task-single",
                "Write a program and return the file",
                "codex",
            )

            self.assertFalse(result.packaged)
            self.assertEqual(["main.py"], [item["name"] for item in result.output_files])
            self.assertEqual("passed", result.verification["status"])

    def test_multi_file_project_is_packaged_and_verified(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": temporary},
        ):
            root = task_workspace("task-project", "claude")
            project = root / "game"
            project.mkdir()
            (project / "index.html").write_text("<canvas></canvas>", encoding="utf-8")
            (project / "game.js").write_text("console.log('ok')", encoding="utf-8")

            result = finalize_task_artifacts(
                "task-project",
                "Build a phone game and return the project",
                "claude",
            )

            self.assertTrue(result.packaged)
            self.assertEqual(1, len(result.output_files))
            archive = root / result.output_files[0]["relative_path"]
            with zipfile.ZipFile(archive) as bundle:
                self.assertEqual(
                    {"game/game.js", "game/index.html"},
                    set(bundle.namelist()),
                )
            self.assertEqual("passed", result.verification["status"])

    def test_valid_apk_requires_phone_handoff_when_install_is_not_authorized(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": temporary},
        ):
            root = task_workspace("task-apk", "codex")
            apk = root / "build" / "app-debug.apk"
            apk.parent.mkdir()
            with zipfile.ZipFile(apk, "w") as bundle:
                bundle.writestr("AndroidManifest.xml", b"manifest")
                bundle.writestr("classes.dex", b"dex")

            result = finalize_task_artifacts(
                "task-apk",
                "Build and install an Android APK on the phone",
                "codex",
                allow_device_install=False,
            )

            self.assertEqual(["app-debug.apk"], [item["name"] for item in result.output_files])
            self.assertEqual("passed", result.verification["status"])
            self.assertEqual(
                "phone_handoff_required",
                result.verification["installation"]["status"],
            )


if __name__ == "__main__":
    unittest.main()
