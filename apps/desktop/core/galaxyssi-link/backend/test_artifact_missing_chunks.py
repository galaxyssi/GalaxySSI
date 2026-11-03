import unittest
from contextlib import ExitStack
from types import SimpleNamespace
from unittest.mock import patch

import mqtt_bridge as bridge


class MissingArtifactChunksTest(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch("agent_worker_mqtt.route_worker_payload", return_value=False))
        self.stack.enter_context(patch.object(bridge, "_route_remote_whisper_payload", return_value=False))
        self.stack.enter_context(patch.object(bridge, "desktop_id", return_value="desktop"))
        self.stack.enter_context(patch.object(bridge, "desktop_name", return_value="Desktop"))
        self.artifact = SimpleNamespace(task_id="task", chunk_count=3, artifact_id="a" * 64)
        self.restore = self.stack.enter_context(patch("artifact_delivery.artifact_for_redelivery", return_value=self.artifact))
        self.stack.enter_context(patch.object(bridge.agent_task_manager, "get", return_value=SimpleNamespace(
            client_route_id="owner", source_message_id="123", client_conversation_id="conversation",
            client_turn_id="turn", contact_id="contact", agent_id="agent")))
        self.send = self.stack.enter_context(patch.object(bridge, "_publish_task_artifacts"))
        self.reply = self.stack.enter_context(patch.object(bridge, "_publish_phone_payload"))

    def dispatch(self, **change):
        payload = {"type": "artifact_missing_chunks_request", "task_id": "task", "artifact_id": "a" * 64,
                   "missing_chunks": [2, 0], **change}
        bridge._dispatch_application_payload(object(), {"client_route_id": "owner"},
            {"_client_route_id": "owner"}, {"source_id": "phone"}, payload, [])

    def test_scoped_missing_request_uses_original_identity_and_no_second_outbox(self):
        self.dispatch()
        self.assertEqual("owner", self.restore.call_args.kwargs["client_route_id"])
        values = self.send.call_args.kwargs
        self.assertEqual([0, 2], values["chunk_indices"])
        self.assertFalse(values["durable"])
        self.assertEqual("conversation", values["common"]["conversation_id"])
        self.assertEqual("turn", values["common"]["turn_id"])

    def test_invalid_or_wrong_task_request_sends_no_file(self):
        for change in ({"missing_chunks": []}, {"missing_chunks": [True]}, {"missing_chunks": [3]},
                       {"missing_chunks": [0, 0]}, {"task_id": "other-task"}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.dispatch(**change)
        self.send.assert_not_called()

    def test_missing_source_does_not_rerun_the_task(self):
        self.restore.return_value = None
        self.dispatch()
        self.send.assert_not_called()
        self.reply.assert_not_called()

    def test_manual_missing_source_keeps_existing_receipt_behavior(self):
        self.restore.return_value = None
        self.dispatch(type="artifact_redelivery_request")
        self.assertEqual("unavailable", self.reply.call_args.args[2]["status"])
        self.assertNotIn("durable", self.reply.call_args.kwargs)

    def test_manual_redelivery_keeps_existing_durable_full_file_behavior(self):
        self.dispatch(type="artifact_redelivery_request")
        self.assertNotIn("chunk_indices", self.send.call_args.kwargs)
        self.assertNotIn("durable", self.send.call_args.kwargs)


if __name__ == "__main__":
    unittest.main()
