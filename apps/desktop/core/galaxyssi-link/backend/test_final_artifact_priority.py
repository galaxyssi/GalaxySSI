"""Final deliverables must survive bounded inventories without exposing input files."""
import os
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import mqtt_bridge
from agent_execution_harness import finalize_task_artifacts
from agent_task_manager import AgentTaskManager
from rich_output import build_rich_output
from task_workspace import select_reply_artifacts, task_workspace
import test_blob_artifact_final_callback as fixture


def outputs(root):
    inventory = []
    for index in range(60):
        relative = f"outputs/intermediate-{index:03}.json"
        (root / relative).write_text('{"observation": 1}', encoding="utf-8")
        inventory.append({"name": Path(relative).name, "relative_path": relative, "size": 18})
    (root / "outputs/final-report.md").write_text("# Result\nVerified evidence.", encoding="utf-8")
    with zipfile.ZipFile(root / "outputs/final-data.zip", "w") as archive:
        archive.writestr("evidence.json", '{"verified": true}')
    return inventory[:50]


REPLY = "[Report](outputs/final-report.md)\n[Data](outputs/final-data.zip)"
FINAL_PATHS = ["outputs/final-report.md", "outputs/final-data.zip"]


class FinalArtifactSelectionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.enterContext(patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary.name}))
        self.root = task_workspace("final-priority")
        self.inventory = outputs(self.root)

    def select(self, reply=REPLY, inventory=None):
        return select_reply_artifacts(reply, self.inventory if inventory is None else inventory,
                                      "final-priority", discover_unlisted=True)

    def test_final_links_resolve_beyond_first_fifty_files_in_reply_order(self):
        self.assertEqual(FINAL_PATHS, [item["relative_path"] for item in self.select()])
        self.assertEqual(list(reversed(FINAL_PATHS)), [item["relative_path"] for item in
                         self.select("\n".join(reversed(REPLY.splitlines())))])

    def test_existing_metadata_and_duplicate_links_are_preserved_once(self):
        metadata = {**self.select()[0], "source_url": "https://example.test/evidence"}
        selected = self.select(REPLY + "\n" + REPLY, inventory=[metadata])
        self.assertEqual(2, len(selected))
        self.assertEqual(metadata, selected[0])

    def test_no_final_links_keep_existing_inventory(self):
        for reply in ("Done", "[Source](https://example.test/outputs/final-report.md)",
                      "[Missing](outputs/not-found.md)"):
            with self.subTest(reply=reply):
                self.assertEqual(self.inventory, self.select(reply))

    def test_renderer_never_discovers_unprepared_files(self):
        self.assertEqual([], select_reply_artifacts(REPLY, [], "final-priority"))
        _, rich = build_rich_output(REPLY, [], "final-priority", inline_artifacts=False)
        self.assertFalse(any(block["type"] in {"file", "image"} for block in (rich or {}).get("blocks", [])))

    def test_discovery_excludes_input_context_hidden_and_cross_task_files(self):
        forbidden = ["downloads/input/secret.txt", "downloads/context/private.txt", "logs/log.txt",
                     "outputs/.secret", "outputs/result.sig", "outputs/.internal/file.txt",
                     "outputs/__pycache__/code.pyc"]
        for relative in forbidden:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("private", encoding="utf-8")
        other = task_workspace("other") / "outputs/other.txt"
        other.write_text("private", encoding="utf-8")
        targets = forbidden + [other.as_posix(), "galaxyssi-artifact://other/outputs/other.txt",
                              "file://remote/outputs/final-report.md", "https://[broken",
                              "outputs/../downloads/input/secret.txt", "custom:outputs/final-report.md"]
        for target in targets:
            with self.subTest(target=target):
                self.assertEqual([], self.select(f"[File](<{target}>)", inventory=[]))

    def test_discovery_rejects_symbolic_links(self):
        link = self.root / "outputs/alias.md"
        try:
            link.symlink_to(self.root / "outputs/final-report.md")
        except OSError:
            self.skipTest("Host does not permit symbolic links")
        self.assertEqual([], self.select("[File](outputs/alias.md)", inventory=[]))

    def test_discovery_rejects_a_linked_parent_before_resolving(self):
        parent = self.root / "outputs"
        with patch.object(Path, "is_symlink", autospec=True, side_effect=lambda path: path == parent):
            self.assertEqual([], self.select(inventory=[]))

    def test_finalization_verifies_the_selected_files_not_intermediates(self):
        with patch("task_workspace.task_artifacts", return_value=self.inventory):
            result = finalize_task_artifacts("final-priority", "Summarize the evidence", "codex",
                                             reply_content=REPLY)
        self.assertEqual(FINAL_PATHS, [item["relative_path"] for item in result.output_files])
        self.assertEqual(FINAL_PATHS, [item["relative_path"] for item in result.verification["outputs"]])
        self.assertEqual("passed", result.verification["status"])

    def test_invalid_final_archive_is_not_misreported_as_verified(self):
        (self.root / "outputs/final-data.zip").write_bytes(b"broken zip")
        with patch("task_workspace.task_artifacts", return_value=self.inventory):
            result = finalize_task_artifacts("final-priority", "Summarize the evidence", "codex",
                                             reply_content=REPLY)
        self.assertEqual("failed", result.verification["status"])
        self.assertFalse(result.verification["outputs"][1]["valid"])

    def test_terminal_inventory_retains_final_files(self):
        with patch("task_workspace.task_artifacts", return_value=self.inventory):
            selected = AgentTaskManager._task_artifacts("final-priority", REPLY)
        self.assertEqual(FINAL_PATHS, [item["relative_path"] for item in selected])

    def test_final_selection_survives_task_store_reopen(self):
        with patch("agent_task_manager.TASKS_DB_PATH", self.root / "tasks.sqlite3"), \
                patch("task_workspace.task_artifacts", return_value=self.inventory):
            manager = AgentTaskManager()
            task = manager.create_external("codex", "test-contact", "test-message", "Test", lambda _: None,
                                           task_id="final-priority")
            manager.update(task.task_id, "completed", result=REPLY)
            restored = AgentTaskManager().get(task.task_id)
        self.assertEqual(FINAL_PATHS, [item["relative_path"] for item in restored.output_files])

    def test_missing_workspace_is_not_recreated_by_selection(self):
        missing = self.root.parent / "missing"
        self.assertEqual([], select_reply_artifacts(REPLY, [], "missing", discover_unlisted=True))
        self.assertFalse(missing.exists())


class FinalArtifactDeliveryTests(unittest.TestCase):
    setUp = fixture.BlobArtifactFinalCallbackTests.setUp
    stop = fixture.BlobArtifactFinalCallbackTests.stop
    enable = fixture.BlobArtifactFinalCallbackTests.enable
    callback = fixture.BlobArtifactFinalCallbackTests.callback

    def task(self):
        root = task_workspace(self.payload["task_id"])
        inventory = outputs(root)
        return {**self.payload, "status": "completed", "result": REPLY, "output_files": inventory,
                "client_conversation_id": self.payload["conversation_id"],
                "client_turn_id": self.payload["turn_id"]}

    def test_initial_callback_sends_only_two_finals_via_blob(self):
        task = self.task()
        with patch("task_workspace.task_artifacts", return_value=task["output_files"]), \
                patch("agent_latency.record_task"):
            self.callback(policy_prompt="Summarize the evidence")(task)
        self.runtime.sender._register_batches()
        wire = self.bridge._publish_to_registered_client.call_args.args[2]
        files = [b for b in wire["rich_output"]["blocks"] if b["type"] == "file"]
        self.assertEqual([Path(p).name for p in FINAL_PATHS], [b["title"] for b in files])
        self.assertTrue(all(b["metadata"]["transport"] == "encrypted-blob" for b in files))
        self.assertEqual({"pending": 2}, self.runtime.sender.journal.snapshot())

    def test_replay_selects_before_transport_preparation(self):
        task = self.task()
        stored = SimpleNamespace(**task, public=lambda: dict(task))
        with patch.object(mqtt_bridge, "agent_task_manager", SimpleNamespace(get=lambda _: stored)), \
                patch("blob_artifact_replay.republish", return_value=None), \
                patch("blob_artifact_deferred.resume", return_value=None), \
                patch.object(mqtt_bridge, "mobile_connector_agents", return_value=[]), \
                patch.object(mqtt_bridge, "_publish_or_queue_task_result", return_value=True) as publish:
            result = mqtt_bridge.republish_agent_task_result(task["task_id"])
        self.assertTrue(result["ok"], result)
        sent = self.bridge._publish_task_artifacts.call_args.args[2]
        self.assertEqual(FINAL_PATHS, [item.relative_path for item in sent])
        files = [b for b in publish.call_args.args[2]["rich_output"]["blocks"] if b["type"] == "file"]
        self.assertEqual(2, len(files))
        self.assertEqual(50, len(stored.output_files))

    def test_plan_and_read_only_callbacks_do_not_publish_files(self):
        task = self.task()
        for mode in ("plan_only", "read_only_screen_analysis"):
            with self.subTest(mode=mode), \
                    patch("agent_execution_harness.finalize_task_artifacts") as finalize, \
                    patch.object(mqtt_bridge, "_publish_or_queue_task_result", return_value=True) as publish, \
                    patch("agent_latency.record_task"):
                callback = self.callback()
                callback.__globals__[mode] = True
                callback(task)
                finalize.assert_not_called()
                wire = publish.call_args.args[2]
                self.assertFalse(any(b["type"] in {"file", "image"} for b in
                                     wire.get("rich_output", {}).get("blocks", [])))
        self.assertEqual({}, self.runtime.sender.journal.snapshot())

    def test_replay_does_not_discover_files_when_no_outputs_were_published(self):
        task = {**self.task(), "output_files": []}
        stored = SimpleNamespace(**task, public=lambda: dict(task))
        with patch.object(mqtt_bridge, "agent_task_manager", SimpleNamespace(get=lambda _: stored)), \
                patch("blob_artifact_replay.republish", return_value=None), \
                patch("blob_artifact_deferred.resume", return_value=None), \
                patch.object(mqtt_bridge, "mobile_connector_agents", return_value=[]), \
                patch.object(mqtt_bridge, "_publish_or_queue_task_result", return_value=True):
            result = mqtt_bridge.republish_agent_task_result(task["task_id"])
        self.assertTrue(result["ok"], result)
        self.assertEqual([], self.bridge._publish_task_artifacts.call_args.args[2])


if __name__ == "__main__":
    unittest.main()
