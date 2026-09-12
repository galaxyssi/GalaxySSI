import base64
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

import codex_generated_images as images
from codex_app_server import CodexAppServer, CodexRun
from task_workspace import task_artifacts, task_workspace, select_reply_artifacts
from artifact_delivery import prepare_artifacts
from rich_output import build_rich_output


class CodexGeneratedImageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {
            "GALAXYSSI_WORKSPACE_ROOT": str(self.root / "workspace"),
            "GALAXYSSI_STATE_DIR": str(self.root / "state"),
        })
        self.env.start()
        stream = io.BytesIO()
        Image.new("RGB", (96, 64), "orange").save(stream, "PNG")
        self.data = stream.getvalue()
        self.item = {"type": "imageGeneration", "id": "image-1", "status": "completed",
                     "result": base64.b64encode(self.data).decode()}
        self.events = []
        self.server = CodexAppServer("codex", {"CODEX_HOME": str(self.root / "codex")},
                                     lambda task, event: self.events.append(event))
        self.run = CodexRun(task_id="task-1", thread_id="thread-1", turn_id="turn-1",
                            prefers_chinese=True)
        self.server._runs[self.run.task_id] = self.run
        self.server._turn_tasks[self.run.turn_id] = self.run.task_id

    def tearDown(self):
        self.env.stop()
        self.temp.cleanup()

    def event(self, method, **params):
        self.server._handle_event({"method": method, "params": {
            "threadId": self.run.thread_id, "turnId": self.run.turn_id, **params}})

    def complete(self, items=None):
        self.run.final_text = "已生成小丑鱼图片。"
        self.event("turn/completed", turn={"id": self.run.turn_id, "status": "completed",
                                            "items": items or []})

    def capture(self, item=None):
        return images.capture_image("task-1", "thread-1", "turn-1", item or self.item,
                                    codex_home=self.root / "codex")

    def test_live_event_registers_artifact_and_rich_image(self):
        self.event("item/started", item={"type": "imageGeneration", "id": "image-1"})
        self.event("item/completed", item=self.item)
        self.complete()
        self.assertEqual("completed", self.events[-1]["status"])
        files = select_reply_artifacts(self.run.final_text, task_artifacts("task-1"), "task-1")
        self.assertEqual(1, len(files))
        self.assertEqual(self.data, (task_workspace("task-1") / files[0]["relative_path"]).read_bytes())
        _text, rich = build_rich_output(self.run.final_text, files, "task-1", inline_artifacts=False)
        self.assertIn('"image"', json.dumps(rich))
        self.assertEqual("已生成小丑鱼图片。", _text)
        self.assertEqual(["已生成小丑鱼图片。"], [b["text"] for b in rich["blocks"] if b["type"] == "text"])
        self.assertNotIn(str(self.root), self.run.final_text)
        artifacts = prepare_artifacts("task-1", files)
        self.assertEqual(1, len(artifacts))

    def test_final_stream_hides_reference_without_losing_artifact_selection(self):
        with patch("codex_app_server.agent_output_delta_enabled", return_value=True):
            self.complete([self.item])
        updates = [event["output_delta"]["text"] for event in self.events if "output_delta" in event]
        self.assertEqual(["已生成小丑鱼图片。"], updates)
        self.assertEqual(1, len(select_reply_artifacts(self.run.final_text, task_artifacts("task-1"), "task-1")))

    def test_terminal_snapshot_captures_missing_notification(self):
        self.complete([self.item])
        self.assertEqual("completed", self.events[-1]["status"])
        self.assertEqual(1, len(task_artifacts("task-1")))

    def test_duplicate_notification_and_snapshot_return_one_image(self):
        self.event("item/completed", item=self.item)
        self.event("item/completed", item=self.item)
        self.event("item/started", item={"type": "imageGeneration", "id": "image-1"})
        self.complete([{**self.item, "result": ""}])
        self.assertEqual(1, self.run.final_text.count("!["))
        self.assertEqual(1, len(task_artifacts("task-1")))

    def test_identical_images_from_two_calls_select_one(self):
        self.event("item/completed", item=self.item)
        self.event("item/completed", item={**self.item, "id": "image-2"})
        self.complete()
        files = select_reply_artifacts(self.run.final_text, task_artifacts("task-1"), "task-1")
        self.assertEqual(1, len(files))

    def test_missing_image_fails_instead_of_claiming_completion(self):
        self.event("item/completed", item={**self.item, "result": ""})
        self.complete()
        self.assertEqual("failed", self.events[-1]["status"])
        self.assertNotIn("已生成", self.events[-1]["result"])
        self.assertIn("附件", self.events[-1]["error"])

    def test_started_without_result_cannot_complete(self):
        self.event("item/started", item={"type": "imageGeneration", "id": "image-1"})
        self.complete()
        self.assertEqual("failed", self.events[-1]["status"])

    def test_storage_error_finishes_with_failure_instead_of_hanging(self):
        with patch.object(images, "_atomic_write", side_effect=OSError("disk full")):
            self.event("item/completed", item=self.item)
        self.complete()
        self.assertEqual("failed", self.events[-1]["status"])

    def test_verification_storage_error_does_not_report_success(self):
        self.event("item/completed", item=self.item)
        with patch.object(images, "verified_images", side_effect=OSError("disk unavailable")):
            self.complete()
        self.assertEqual("failed", self.events[-1]["status"])

    def test_invalid_image_and_size_limits(self):
        for encoded in ("not-base64!", base64.b64encode(b"not-an-image").decode()):
            with self.assertRaises(images.GeneratedImageError):
                self.capture({**self.item, "result": encoded})
        with patch.object(images, "MAX_IMAGE_BYTES", 16):
            with self.assertRaises(images.GeneratedImageError):
                self.capture()
        with patch.object(images, "MAX_PIXELS", 4):
            with self.assertRaises(images.GeneratedImageError):
                self.capture()

    def test_safe_saved_path_and_data_url(self):
        root = self.root / "codex" / "generated_images" / "thread-1"
        root.mkdir(parents=True)
        source = root / "image-1.png"
        source.write_bytes(self.data)
        receipt = self.capture({**self.item, "result": "", "savedPath": str(source)})
        self.assertEqual(len(self.data), receipt["size"])
        self.capture({**self.item, "result": "data:image/png;base64," + self.item["result"]})
        self.assertEqual(self.data, source.read_bytes())

    def test_other_thread_or_event_file_is_rejected(self):
        for thread, name in (("thread-other", "image-1"), ("thread-1", "image-other")):
            source = self.root / "codex" / "generated_images" / thread / (name + ".png")
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(self.data)
            with self.assertRaisesRegex(images.GeneratedImageError, "out_of_scope"):
                self.capture({**self.item, "result": "", "savedPath": str(source)})

    def test_late_and_foreign_turns_do_not_write_outputs(self):
        for thread, turn in (("thread-other", "turn-1"), ("thread-1", "turn-old")):
            self.event("item/completed", threadId=thread, turnId=turn, item=self.item)
        self.assertEqual([], task_artifacts("task-1"))
        self.complete()
        self.event("item/completed", item=self.item)
        self.assertEqual([], task_artifacts("task-1"))

    def test_receipt_recovery_is_scoped_and_detects_tampering(self):
        receipt = self.capture()
        self.assertEqual(1, len(images.verified_images("task-1", "thread-1", "turn-1")))
        self.assertEqual([], images.verified_images("task-1", "thread-1", "turn-other"))
        source = task_workspace("task-1") / receipt["relative_path"]
        source.write_bytes(b"tampered")
        self.assertEqual([], images.verified_images("task-1", "thread-1", "turn-1"))

    def test_missing_file_before_completion_fails(self):
        self.event("item/completed", item=self.item)
        receipt = self.run.generated_images["image-1"]
        (task_workspace("task-1") / receipt["relative_path"]).unlink()
        self.complete()
        self.assertEqual("failed", self.events[-1]["status"])

    def test_malformed_receipt_is_ignored_without_breaking_completion(self):
        self.capture()
        receipt = next(task_workspace("task-1").glob(".codex-image-*.json"))
        for invalid in ([], {"task_id": "task-1"}, "corrupted"):
            receipt.write_text(json.dumps(invalid), encoding="utf-8")
            self.assertEqual([], images.verified_images("task-1", "thread-1", "turn-1"))

    def test_failed_tool_cannot_reuse_previous_success(self):
        self.event("item/completed", item=self.item)
        self.event("item/completed", item={"type": "imageGeneration", "id": "image-1",
                                          "status": "failed", "failure": "unavailable"})
        self.complete()
        self.assertEqual("failed", self.events[-1]["status"])

    def test_image_count_is_bounded(self):
        with patch.object(images, "MAX_IMAGES", 1):
            self.event("item/completed", item=self.item)
            self.event("item/completed", item={**self.item, "id": "image-2"})
            self.complete()
        self.assertEqual("failed", self.events[-1]["status"])

    def test_recovery_snapshot_preserves_native_extension_result(self):
        original = {**self.item, "type": "Extension", "kind": "image_gen.generation"}
        self.complete([original])
        self.assertEqual("completed", self.events[-1]["status"])
        self.assertEqual(1, len(task_artifacts("task-1")))

    def test_completed_turn_resume_restores_image_without_model_rerun(self):
        response = {"thread": {"turns": [{"id": "turn-1", "status": "completed",
                    "items": [self.item, {"type": "agentMessage", "text": "Done"}]}]}}
        with patch.object(self.server, "_ensure_started"), patch.object(
                self.server, "_request", return_value=response):
            self.server.recover_task("task-1", "thread-1", "turn-1", original_prompt="给出图片")
        self.assertEqual("completed", self.events[-1]["status"])
        self.assertIn("galaxyssi-artifact://task-1/", self.events[-1]["result"])


if __name__ == "__main__":
    unittest.main()
