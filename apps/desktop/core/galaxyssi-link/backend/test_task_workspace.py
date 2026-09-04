import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import task_workspace


class TaskWorkspaceTests(unittest.TestCase):
    def test_creates_isolated_task_layout(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "GalaxySSI_Workspace"
            with patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(root)}):
                directory = task_workspace.task_workspace("task-123", "codex")
            self.assertEqual(directory, (root / "tasks" / "task-123").resolve())
            for name in task_workspace.TASK_SUBDIRECTORIES:
                self.assertTrue((directory / name).is_dir())
            self.assertTrue((directory / ".galaxyssi-task.json").is_file())

    def test_task_id_cannot_escape_workspace(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "GalaxySSI_Workspace"
            with patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(root)}):
                directory = task_workspace.task_workspace("../../source/project", "codex")
            self.assertTrue(directory.is_relative_to((root / "tasks").resolve()))
            self.assertNotIn("..", directory.name)

    def test_source_tree_configuration_falls_back_to_user_workspace(self):
        unsafe = task_workspace.BACKEND_DIR / "generated-tasks"
        with patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(unsafe)}):
            root = task_workspace.workspace_root()
        self.assertEqual(root, task_workspace.DEFAULT_WORKSPACE_ROOT.resolve())
        self.assertFalse(root.is_relative_to(task_workspace.BACKEND_DIR))

    def test_cleanup_removes_only_temporary_directories(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "GalaxySSI_Workspace"
            with patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(root)}):
                directory = task_workspace.task_workspace("task-clean", "codex")
                (directory / "temp" / "scratch.txt").write_text("temp", encoding="utf-8")
                (directory / "logs" / "run.txt").write_text("log", encoding="utf-8")
                (directory / "outputs" / "result.txt").write_text("keep", encoding="utf-8")
                artifacts = task_workspace.task_artifacts("task-clean")
                cleaned = task_workspace.cleanup_task_temporary_files({"task-clean"})
            self.assertEqual(artifacts[0]["relative_path"], "outputs/result.txt")
            self.assertEqual(artifacts[0]["size"], 4)
            self.assertEqual(cleaned, ["task-clean"])
            self.assertFalse((directory / "temp").exists())
            self.assertFalse((directory / "logs").exists())
            self.assertEqual((directory / "outputs" / "result.txt").read_text(encoding="utf-8"), "keep")

    def test_task_artifacts_hide_signing_sidecars(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "GalaxySSI_Workspace"
            with patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(root)}):
                directory = task_workspace.task_workspace("signed-apk", "codex")
                (directory / "outputs" / "GalaxySSI.apk").write_bytes(b"apk")
                (directory / "outputs" / "GalaxySSI.apk.idsig").write_bytes(b"internal")
                artifacts = task_workspace.task_artifacts("signed-apk")
            self.assertEqual(["GalaxySSI.apk"], [item["name"] for item in artifacts])

    def test_imports_artifact_referenced_from_an_earlier_task(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "GalaxySSI_Workspace"
            with patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(root)}):
                earlier = task_workspace.task_workspace("earlier", "codex")
                source = earlier / "outputs" / "marked.jpg"
                source.write_bytes(b"image")
                response = f"![Marked image](<{source.as_posix()}>)"
                artifacts = task_workspace.import_referenced_task_artifacts("current", response)
            self.assertEqual(["outputs/marked.jpg"], [item["relative_path"] for item in artifacts])
            self.assertEqual(b"image", (root / "tasks" / "current" / "outputs" / "marked.jpg").read_bytes())

    def test_rejects_referenced_file_outside_task_workspace(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "GalaxySSI_Workspace"
            outside = Path(temporary) / "private.jpg"
            outside.write_bytes(b"private")
            with patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(root)}):
                artifacts = task_workspace.import_referenced_task_artifacts(
                    "current",
                    f"![Private](<{outside.as_posix()}>)",
                )
            self.assertEqual([], artifacts)

    def test_imports_relative_artifact_from_current_conversation_task(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "GalaxySSI_Workspace"
            with patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(root)}):
                source_task = task_workspace.task_workspace("source-turn", "codex")
                source = source_task / "outputs" / "\u4f5c\u4e1a\u6279\u6539_\u5168\u5bf9.jpg"
                source.write_bytes(b"annotated-image")
                response = """```galaxyssi-rich
{"blocks":[{"type":"file","name":"\u4f5c\u4e1a\u6279\u6539_\u5168\u5bf9.jpg","uri":"outputs/\u4f5c\u4e1a\u6279\u6539_\u5168\u5bf9.jpg"}]}
```"""
                artifacts = task_workspace.import_referenced_task_artifacts(
                    "current-turn",
                    response,
                    source_task_ids=["source-turn"],
                )
            self.assertEqual(["outputs/\u4f5c\u4e1a\u6279\u6539_\u5168\u5bf9.jpg"], [item["relative_path"] for item in artifacts])
            copied = root / "tasks" / "current-turn" / "outputs" / "\u4f5c\u4e1a\u6279\u6539_\u5168\u5bf9.jpg"
            self.assertEqual(b"annotated-image", copied.read_bytes())

    def test_rejects_relative_artifact_traversal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "GalaxySSI_Workspace"
            with patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(root)}):
                source_task = task_workspace.task_workspace("source-turn", "codex")
                (source_task / "private.jpg").write_bytes(b"private")
                artifacts = task_workspace.import_referenced_task_artifacts(
                    "current-turn",
                    "outputs/../private.jpg",
                    source_task_ids=["source-turn"],
                )
            self.assertEqual([], artifacts)

    def test_current_relative_artifact_wins_over_prior_version(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "GalaxySSI_Workspace"
            with patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(root)}):
                prior_root = task_workspace.task_workspace("prior-task", "codex")
                prior = prior_root / "outputs" / "project.zip"
                prior.write_bytes(b"prior")
                current_root = task_workspace.task_workspace("current-task", "codex")
                current = current_root / "outputs" / "project.zip"
                current.write_bytes(b"updated")
                artifacts = task_workspace.import_referenced_task_artifacts(
                    "current-task",
                    "[Download](sandbox:/outputs/project.zip)",
                    source_task_ids=["prior-task"],
                )

            self.assertEqual(["project.zip"], [item["name"] for item in artifacts])
            self.assertEqual(b"updated", current.read_bytes())
            self.assertFalse((current_root / "outputs" / "project-2.zip").exists())


if __name__ == "__main__":
    unittest.main()
