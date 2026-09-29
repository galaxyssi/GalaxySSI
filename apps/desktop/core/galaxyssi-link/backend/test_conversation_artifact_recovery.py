import hashlib
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from conversation_artifact_recovery import restore_delivered_outputs
from conversation_context import ContextAttachment, MobileConversationContext
from task_workspace import task_workspace


class DeliveredOutputRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.environment = patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": self.directory.name})
        self.environment.start()
        self.source = task_workspace("previous") / "outputs" / "report-v01.pptx"
        self.source.parent.mkdir(parents=True, exist_ok=True)
        self.source.write_bytes(b"original editable output")
        self.artifact_id = "artifact-" + hashlib.sha256(self.source.read_bytes()).hexdigest()[:24]
        self.attachment = ContextAttachment(artifact_id=self.artifact_id, name=self.source.name,
                                            group_id="previous-turn")
        self.context = MobileConversationContext(attachment_index=(self.attachment,))
        self.history = [{"task_id": "previous", "conversation_id": "identity-A:conversation",
                         "client_turn_id": "previous-turn", "status": "completed",
                         "output_files": [{"relative_path": "outputs/report-v01.pptx"}]}]

    def tearDown(self):
        self.environment.stop()
        self.directory.cleanup()

    def restore(self, **overrides):
        arguments = dict(context=self.context, task_history=self.history,
                         requested_ids=[self.artifact_id], conversation_id="identity-A:conversation",
                         current_task_id="current")
        arguments.update(overrides)
        return restore_delivered_outputs(**arguments)

    def test_exact_delivered_file_is_staged_without_changing_original(self):
        restored = self.restore()
        self.assertEqual([self.artifact_id], list(restored))
        target = restored[self.artifact_id]
        self.assertEqual(self.source.read_bytes(), target.read_bytes())
        self.assertTrue(target.is_relative_to(task_workspace("current") / "downloads" / "context"))
        self.assertNotEqual(self.source, target)
        self.assertEqual("report-v01.pptx", target.name)

    def test_another_identity_or_conversation_cannot_supply_the_file(self):
        for identity in ("identity-B:conversation", "identity-A:other", ""):
            with self.subTest(identity=identity):
                self.assertEqual({}, self.restore(conversation_id=identity))

    def test_wrong_turn_failed_task_and_current_task_are_excluded(self):
        for changes in ({"client_turn_id": "other"}, {"status": "failed"}, {"task_id": "current"}):
            with self.subTest(changes=changes):
                self.assertEqual({}, self.restore(task_history=[dict(self.history[0], **changes)]))

    def test_requested_id_must_be_in_the_retained_context(self):
        self.assertEqual({}, self.restore(context=MobileConversationContext()))
        self.assertEqual({}, self.restore(requested_ids=["artifact-" + "0" * 24]))

    def test_same_filename_with_changed_bytes_is_not_the_requested_version(self):
        self.source.write_bytes(b"replacement version")
        self.assertEqual({}, self.restore())

    def test_friendly_caption_does_not_override_content_identity(self):
        context = MobileConversationContext(attachment_index=(ContextAttachment(
            artifact_id=self.artifact_id, name="Friendly preview", group_id="previous-turn"),))
        self.assertIn(self.artifact_id, self.restore(context=context))

    def test_escaping_metadata_and_missing_files_fail_closed(self):
        for relative in ("../../private.pptx", "outputs/missing.pptx", "downloads/input/report.pptx"):
            with self.subTest(relative=relative):
                task = dict(self.history[0], output_files=[{"relative_path": relative}])
                self.assertEqual({}, self.restore(task_history=[task]))

    def test_hash_work_is_bounded(self):
        with patch("conversation_artifact_recovery.MAX_CONTEXT_TOTAL_BYTES", 1):
            self.assertEqual({}, self.restore())

    def test_mutation_during_staging_is_not_returned(self):
        target = task_workspace("current") / "outputs" / "changed.pptx"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(b"changed during staging")
        with patch("conversation_artifact_recovery.stage_conversation_artifacts", return_value=[target]):
            self.assertEqual({}, self.restore())


if __name__ == "__main__":
    unittest.main()
