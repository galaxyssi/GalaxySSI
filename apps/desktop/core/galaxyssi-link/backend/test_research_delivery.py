"""Research originals remain available without flooding the phone artifact queue."""
import json
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
from research_delivery import FORMAT, DELIVERY_INSTRUCTIONS, research_summary
from task_workspace import select_reply_artifacts, task_artifacts, task_workspace
import test_blob_artifact_final_callback as fixture


def publication(summary="Evidence saved; no phone download requested.", **extra):
    return json.dumps({"format": FORMAT, "summary": summary, "milestones": ["saved-v5"], **extra})


def populate(root):
    for index in range(60):
        (root / f"outputs/intermediate-{index:03}.json").write_text('{"measurement":1}', encoding="utf-8")
    for name in ("candidate-v5.zip", "checkpoint-v1.zip"):
        with zipfile.ZipFile(root / "outputs" / name, "w") as bundle:
            bundle.writestr("method.py", "def solve(): return 1\n")
    # A newer timestamp does not make an older candidate the chosen deliverable.
    os.utime(root / "outputs/checkpoint-v1.zip", (1900000000, 1900000000))


class ResearchDeliveryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.enterContext(patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary.name}))
        self.root = task_workspace("research")
        populate(self.root)
        self.inventory = task_artifacts("research")

    def select(self, text):
        return select_reply_artifacts(text, self.inventory, "research", discover_unlisted=True)

    def test_exact_envelope_and_fenced_envelope_are_recognized(self):
        for text in (publication("Summary"), "```json\n" + publication("Summary") + "\n```"):
            self.assertEqual("Summary", research_summary(text))
        for text in ("Ordinary answer", '{"format":"other","summary":"hello"}', "{broken"):
            self.assertIsNone(research_summary(text))
        self.assertEqual("", research_summary(publication(None)))

    def test_unlinked_research_does_not_send_inventory_or_nested_evidence_links(self):
        text = publication(workspace=[{"body": {"content": "[Old](outputs/checkpoint-v1.zip)"}}])
        self.assertEqual([], self.select(text))
        self.assertEqual(62, len(list((self.root / "outputs").iterdir())))
        self.assertEqual(self.inventory, self.select("Ordinary unlinked reply"))

    def test_section_anchor_is_not_a_missing_download(self):
        result = finalize_task_artifacts("research", "Review evidence", "codex",
            reply_content=publication("See [limitations](#limitations)."))
        self.assertEqual("passed", result.verification["status"])
        self.assertEqual((), result.output_files)

    def test_only_explicit_summary_version_is_selected_beyond_inventory_limit(self):
        text = publication("[Final](outputs/candidate-v5.zip)", workspace=[
            {"body": {"content": "[Old](outputs/checkpoint-v1.zip)"}}])
        self.assertEqual(["outputs/candidate-v5.zip"], [f["relative_path"] for f in self.select(text)])
        self.assertEqual([], select_reply_artifacts(text, [], "research"))

    def test_missing_summary_link_never_falls_back_to_old_archive(self):
        self.assertEqual([], self.select(publication("[Final](outputs/missing-v6.zip)")))
        result = finalize_task_artifacts("research", "Review the evidence", "codex",
            reply_content=publication("[Final](outputs/missing-v6.zip)"))
        self.assertEqual("failed", result.verification["status"])
        self.assertEqual(["outputs/missing-v6.zip"], result.verification["missing_deliverables"])

    def test_missing_one_of_multiple_declared_files_is_reported(self):
        result = finalize_task_artifacts("research", "Return a downloadable file", "codex",
            reply_content=publication("[V5](outputs/candidate-v5.zip) [Data](outputs/missing.csv)"))
        self.assertEqual("failed", result.verification["status"])
        self.assertEqual(["outputs/missing.csv"], result.verification["missing_deliverables"])
        self.assertEqual(1, len(result.output_files))

    def test_required_file_cannot_be_satisfied_by_unselected_internal_outputs(self):
        result = finalize_task_artifacts("research", "Return a downloadable file", "codex",
            reply_content=publication())
        self.assertEqual("failed", result.verification["status"])
        self.assertFalse(result.packaged)
        self.assertEqual((), result.output_files)

    def test_finalization_does_not_choose_newest_archive(self):
        result = finalize_task_artifacts("research", "Return a downloadable file", "codex",
            reply_content=publication("[Final](outputs/candidate-v5.zip)"))
        self.assertEqual("passed", result.verification["status"])
        self.assertEqual(["candidate-v5.zip"], [f["name"] for f in result.output_files])
        self.assertFalse(result.packaged)

    def test_unsafe_and_remote_links_cannot_trigger_broad_fallback(self):
        for target in ("https://example.test/outputs/candidate-v5.zip", "outputs/../.galaxyssi-task.json",
                       "galaxyssi-artifact://other/outputs/candidate-v5.zip", "downloads/context/secret.txt"):
            with self.subTest(target=target):
                self.assertEqual([], self.select(publication(f"[Source](<{target}>)")))

    def test_selected_version_survives_task_store_reopen(self):
        text = publication("[Final](outputs/candidate-v5.zip)")
        with patch("agent_task_manager.TASKS_DB_PATH", self.root / "test.sqlite3"):
            manager = AgentTaskManager()
            task = manager.create_external("codex", "test-contact", "test-message", "Review",
                                           lambda _: None, task_id="research")
            manager.update(task.task_id, "completed", result=text)
            restored = AgentTaskManager().get(task.task_id)
        self.assertEqual(text, restored.result)
        self.assertEqual(["candidate-v5.zip"], [f["name"] for f in restored.output_files])

    def test_tools_explain_delivery_selection_before_execution(self):
        import collaboration_milestone_bridge
        import collaboration_file_artifact
        import collaboration_text_artifact
        for tool in (collaboration_milestone_bridge, collaboration_file_artifact, collaboration_text_artifact):
            self.assertIn(DELIVERY_INSTRUCTIONS, tool.tool_spec()["description"])


class ResearchDeliveryCallbackTests(unittest.TestCase):
    setUp = fixture.BlobArtifactFinalCallbackTests.setUp
    stop = fixture.BlobArtifactFinalCallbackTests.stop
    enable = fixture.BlobArtifactFinalCallbackTests.enable
    callback = fixture.BlobArtifactFinalCallbackTests.callback

    def task(self, summary="Evidence preserved."):
        root = task_workspace(self.payload["task_id"])
        populate(root)
        return {**self.payload, "status": "completed", "result": publication(summary),
                "output_files": task_artifacts(self.payload["task_id"]),
                "client_conversation_id": self.payload["conversation_id"],
                "client_turn_id": self.payload["turn_id"]}

    def test_unlinked_publication_keeps_workspace_and_sends_no_files(self):
        task = self.task()
        with patch.object(mqtt_bridge, "_publish_or_queue_task_result", return_value=True) as publish, \
                patch("remote_reply_images.prepare_reply_images") as prepare_images, \
                patch("agent_latency.record_task"):
            callback = self.callback(policy_prompt="Review evidence")
            callback(task)
        prepare_images.assert_not_called()
        self.assertEqual(task["result"], publish.call_args.args[2]["content"])
        self.assertEqual({}, self.runtime.sender.journal.snapshot())
        self.assertTrue((task_workspace(task["task_id"]) / "outputs/candidate-v5.zip").exists())

    def test_selected_archive_blob_batch_retains_research_workspace(self):
        task = self.task("[Final](outputs/candidate-v5.zip)")
        callback = self.callback(policy_prompt="Return a downloadable file")
        callback.__globals__["structured_connector_response"] = True
        with patch("agent_latency.record_task"):
            callback(task)
        self.runtime.sender._register_batches()
        self.assertEqual({"pending": 1}, self.runtime.sender.journal.snapshot())
        wire = self.bridge._publish_to_registered_client.call_args.args[2]
        self.assertEqual(task["result"], wire["content"])
        self.assertNotIn("rich_output", wire)
        import artifact_delivery
        entries = list(artifact_delivery._read_ledger().values())
        self.assertTrue(entries)
        self.assertTrue(all(e["retain_on_desktop"] for e in entries))
        for entry in entries:
            self.assertTrue(artifact_delivery.acknowledge_artifact(
                {"artifact_id": entry["artifact_id"], "sha256": entry["sha256"], "status": "stored"},
                client_route_id=entry["client_route_id"], delivery_scope=entry.get("delivery_scope", "")))
        root = task_workspace(task["task_id"])
        self.assertTrue((root / "outputs/intermediate-000.json").exists())
        self.assertTrue((root / "outputs/checkpoint-v1.zip").exists())
        self.assertTrue(all(e["cleanup_done"] for e in artifact_delivery._read_ledger().values()))

    def test_replay_preserves_envelope_selection_and_retention(self):
        task = self.task("[Final](outputs/candidate-v5.zip)")
        stored = SimpleNamespace(**task, public=lambda: dict(task))
        with patch.object(mqtt_bridge, "agent_task_manager", SimpleNamespace(get=lambda _: stored)), \
                patch("blob_artifact_replay.republish", return_value=None), \
                patch("blob_artifact_deferred.resume", return_value=None), \
                patch.object(mqtt_bridge, "mobile_connector_agents", return_value=[]), \
                patch("remote_reply_images.prepare_reply_images") as prepare_images, \
                patch.object(mqtt_bridge, "_publish_or_queue_task_result", return_value=True) as publish, \
                patch("artifact_delivery.register_artifact_batch") as register:
            result = mqtt_bridge.republish_agent_task_result(task["task_id"])
        self.assertTrue(result["ok"], result)
        prepare_images.assert_not_called()
        self.assertEqual(task["result"], publish.call_args.args[2]["content"])
        self.assertNotIn("rich_output", publish.call_args.args[2])
        self.assertTrue(register.call_args.kwargs["retain_on_desktop"])
        sent = self.bridge._publish_task_artifacts.call_args.args[2]
        self.assertEqual(["outputs/candidate-v5.zip"], [f.relative_path for f in sent])


if __name__ == "__main__":
    unittest.main()
