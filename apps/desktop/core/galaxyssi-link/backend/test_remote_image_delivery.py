"""Remote images through the production final callback and existing byte transport."""
import unittest
import base64
from types import SimpleNamespace
from unittest.mock import Mock, patch

from agent_execution_harness import ArtifactFinalization
import mqtt_bridge
from remote_reply_images import _image_spans
from task_workspace import task_artifacts
from test_remote_reply_images import FakeTransport, image_bytes
from codex_generated_images import capture_image
import test_blob_artifact_final_callback as fixture


class RemoteImageDeliveryTests(unittest.TestCase):
    setUp = fixture.BlobArtifactFinalCallbackTests.setUp
    stop = fixture.BlobArtifactFinalCallbackTests.stop
    enable = fixture.BlobArtifactFinalCallbackTests.enable
    callback = fixture.BlobArtifactFinalCallbackTests.callback

    def task(self):
        return {**self.payload, "status": "completed",
                "result": "Fish: ![Fish](https://example.com/fish.png)",
                "client_conversation_id": self.payload["conversation_id"],
                "client_turn_id": self.payload["turn_id"]}

    def test_final_callback_publishes_one_scoped_blob_image(self):
        task = self.task()
        transport = FakeTransport()
        with patch("remote_reply_images.PublicImageTransport", return_value=transport), \
                patch("agent_execution_harness.finalize_task_artifacts", side_effect=lambda task_id, *a, **kw:
                      ArtifactFinalization(tuple(task_artifacts(task_id)), {"status": "passed"})), \
                patch("agent_latency.record_task"):
            self.callback()(task)
        self.assertEqual(["https://example.com/fish.png"], transport.calls)
        self.runtime.sender._register_batches()
        wire = self.bridge._publish_to_registered_client.call_args.args[2]
        images = [block for block in wire["rich_output"]["blocks"] if block["type"] == "image"]
        self.assertEqual(1, len(images))
        self.assertTrue(images[0]["uri"].startswith("galaxyssi-artifact://blob/"))
        self.assertEqual("encrypted-blob", images[0]["metadata"]["transport"])
        self.assertEqual("https://example.com/fish.png", images[0]["metadata"]["source_url"])
        for key in ("task_id", "conversation_id", "turn_id", "client_route_id", "execution_generation"):
            self.assertEqual(str(self.payload[key]), images[0]["metadata"]["blob_" + key])
        self.assertEqual([], list(_image_spans(wire["content"])))
        self.assertEqual({"pending": 1}, self.runtime.sender.journal.snapshot())

    def test_generation_changed_during_download_cannot_publish(self):
        execution = Mock()
        execution.accepts.side_effect = [True, False]
        with patch("remote_reply_images.PublicImageTransport", return_value=FakeTransport()), \
                patch("agent_execution_harness.finalize_task_artifacts") as finalize:
            self.callback(execution)(self.task())
        self.assertEqual(2, execution.accepts.call_count)
        finalize.assert_not_called()
        self.bridge._publish_to_registered_client.assert_not_called()
        self.assertEqual({}, self.runtime.sender.journal.snapshot())

    def test_unnegotiated_phone_uses_existing_mqtt_attachment_path(self):
        task = self.task()
        with patch("remote_reply_images.PublicImageTransport", return_value=FakeTransport()), \
                patch("blob_pair_configuration.can_receive_artifacts", return_value=False), \
                patch("agent_execution_harness.finalize_task_artifacts", side_effect=lambda task_id, *a, **kw:
                      ArtifactFinalization(tuple(task_artifacts(task_id)), {"status": "passed"})), \
                patch.object(mqtt_bridge, "_publish_or_queue_task_result", return_value=True) as publish, \
                patch("agent_latency.record_task"):
            self.callback()(task)
        wire = publish.call_args.args[2]
        images = [block for block in wire["rich_output"]["blocks"] if block["type"] == "image"]
        self.assertEqual(1, len(images))
        self.assertTrue(images[0]["uri"].startswith("galaxyssi-artifact://" + task["task_id"] + "/outputs/"))
        self.assertEqual("encrypted-fragmented", images[0]["metadata"]["transport"])
        self.bridge._publish_task_artifacts.assert_called_once()
        self.assertEqual({}, self.runtime.sender.journal.snapshot())

    def test_progress_and_terminal_snapshot_keep_routing_but_not_external_image_rendering(self):
        for status in ("running", "completed"):
            task = {**self.task(), "status": status,
                    "partial_result": {"sequence": 3, "text": self.task()["result"]}}
            with patch.object(mqtt_bridge, "agent_output_delta_enabled", return_value=True), \
                    patch.object(mqtt_bridge, "_task_reputation_evidence", return_value=(None, None)):
                payload = mqtt_bridge._agent_task_payload(task, [], resolved_desktop_id="desktop",
                                                         resolved_desktop_name="Desktop")
            text = payload["partial_result"]["text"] if status == "running" else payload["result_summary"]
            self.assertEqual([], list(_image_spans(text)))
            self.assertIn("https://example.com/fish.png", text)
            self.assertEqual(task["client_turn_id"], payload["turn_id"])
            self.assertEqual(task["execution_generation"], payload["execution_generation"])

    def test_legacy_republish_materializes_image_without_rerunning_model(self):
        task = self.task()
        stored = SimpleNamespace(**task, public=lambda: dict(task))
        with patch.object(mqtt_bridge, "agent_task_manager", SimpleNamespace(get=lambda _: stored)), \
                patch("blob_artifact_replay.republish", return_value=None), \
                patch("blob_artifact_deferred.resume", return_value=None), \
                patch("remote_reply_images.PublicImageTransport", return_value=FakeTransport()), \
                patch.object(mqtt_bridge, "mobile_connector_agents", return_value=[]), \
                patch.object(mqtt_bridge, "_publish_or_queue_task_result", return_value=True) as publish:
            result = mqtt_bridge.republish_agent_task_result(task["task_id"])
        self.assertTrue(result["ok"], result)
        wire = publish.call_args.args[2]
        self.assertEqual("turn", wire["turn_id"])
        self.assertEqual(task["source_message_id"], wire["source_message_id"])
        self.assertTrue(any(block["type"] == "image" and block["uri"].startswith("galaxyssi-artifact://")
                            for block in wire["rich_output"]["blocks"]))
        self.bridge._publish_task_artifacts.assert_called_once()
        self.assertEqual("Fish: ![Fish](https://example.com/fish.png)", stored.result)

    def test_republish_rejects_generation_change_during_download(self):
        task = self.task()
        stored = SimpleNamespace(**task, public=lambda: dict(task))
        changed = SimpleNamespace(public=lambda: {**task, "execution_generation": 2})
        with patch.object(mqtt_bridge, "agent_task_manager", SimpleNamespace(get=Mock(side_effect=[stored, changed]))), \
                patch("blob_artifact_replay.republish", return_value=None), \
                patch("blob_artifact_deferred.resume", return_value=None), \
                patch("remote_reply_images.PublicImageTransport", return_value=FakeTransport()), \
                patch.object(mqtt_bridge, "_publish_or_queue_task_result") as publish:
            result = mqtt_bridge.republish_agent_task_result(task["task_id"])
        self.assertFalse(result["ok"], result)
        publish.assert_not_called()
        self.bridge._publish_task_artifacts.assert_not_called()

    def test_native_image_receipt_republishes_without_model_or_remote_download(self):
        task = {**self.task(), "result": "Image generated.", "thread_id": "native-thread",
                "turn_id": "native-turn", "agent_id": "codex", "output_files": []}
        receipt = capture_image(task["task_id"], task["thread_id"], task["turn_id"], {
            "type": "imageGeneration", "id": "native-image", "status": "completed",
            "result": base64.b64encode(image_bytes()).decode(),
        }, codex_home="unused")
        task["result"] += f"\n\n![Generated image](galaxyssi-artifact://{task['task_id']}/{receipt['relative_path']})"
        stored = SimpleNamespace(**task, public=lambda: dict(task))
        with patch.object(mqtt_bridge, "agent_task_manager", SimpleNamespace(get=lambda _: stored)), \
                patch("blob_artifact_replay.republish", return_value=None), \
                patch("blob_artifact_deferred.resume", return_value=None), \
                patch("remote_reply_images.PublicImageTransport") as transport, \
                patch.object(mqtt_bridge, "mobile_connector_agents", return_value=[]), \
                patch.object(mqtt_bridge, "_publish_or_queue_task_result", return_value=True) as publish:
            result = mqtt_bridge.republish_agent_task_result(task["task_id"])
        self.assertTrue(result["ok"], result)
        transport.assert_not_called()
        wire = publish.call_args.args[2]
        self.assertEqual(task["client_turn_id"], wire["turn_id"])
        self.assertEqual(1, len([b for b in wire["rich_output"]["blocks"] if b["type"] == "image"]))
        self.assertEqual("Image generated.", wire["content"])
        self.assertEqual(["Image generated."], [b["text"] for b in wire["rich_output"]["blocks"] if b["type"] == "text"])
        self.assertEqual([], stored.output_files)
        self.bridge._publish_task_artifacts.assert_called_once()

    def test_native_image_exits_chat_fast_path_and_enters_scoped_blob_delivery(self):
        task = {**self.task(), "thread_id": "native-thread", "turn_id": "native-turn"}
        receipt = capture_image(task["task_id"], task["thread_id"], task["turn_id"], {
            "type": "imageGeneration", "id": "native-image", "status": "completed",
            "result": base64.b64encode(image_bytes()).decode(),
        }, codex_home="unused")
        task["result"] = f"![Generated image](galaxyssi-artifact://{task['task_id']}/{receipt['relative_path']})"
        callback = self.callback()
        callback.__globals__["fast_chat_delivery"] = True
        with patch("agent_execution_harness.finalize_task_artifacts", side_effect=lambda task_id, *a, **kw:
                   ArtifactFinalization(tuple(task_artifacts(task_id)), {"status": "passed"})), \
                patch("agent_latency.record_task"):
            callback(task)
        self.runtime.sender._register_batches()
        wire = self.bridge._publish_to_registered_client.call_args.args[2]
        blocks = [block for block in wire["rich_output"]["blocks"] if block["type"] == "image"]
        self.assertEqual(1, len(blocks))
        self.assertNotIn("galaxyssi-artifact://", wire["content"])
        self.assertFalse(any(b["type"] == "text" for b in wire["rich_output"]["blocks"]))
        self.assertEqual("encrypted-blob", blocks[0]["metadata"]["transport"])
        self.assertEqual(str(self.payload["task_id"]), blocks[0]["metadata"]["blob_task_id"])
        self.assertEqual({"pending": 1}, self.runtime.sender.journal.snapshot())


if __name__ == "__main__":
    unittest.main()
