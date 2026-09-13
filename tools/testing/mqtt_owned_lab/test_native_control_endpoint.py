from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from native_control_endpoint import ControlEndpoint
from native_measurements import Measurements


class ControlEndpointTests(unittest.TestCase):
    def setUp(self):
        self.manager = Mock()
        self.endpoint = SimpleNamespace(route="A" * 22, client=object(), measurements=Measurements(),
            bridge=SimpleNamespace(agent_task_manager=self.manager, _publish_phone_payload=Mock(return_value=True)))
        self.control = ControlEndpoint(self.endpoint)

    def test_create_persists_scope_without_starting_a_model_runner(self):
        record = self.control.create()
        args = self.manager.create_external.call_args.kwargs
        self.assertEqual("", args["agent_id"])
        self.assertEqual(record["task_id"], args["task_id"])
        self.assertEqual(record["client_route_id"], args["client_route_id"])
        self.assertEqual(record["conversation_id"], args["client_conversation_id"])
        self.assertEqual(record["turn_id"], args["client_turn_id"])
        self.manager.create.assert_not_called()

    def test_real_publish_retains_control_identity_and_measures_event(self):
        record = self.control.create()
        sent = self.control.send(record)
        payload = self.endpoint.bridge._publish_phone_payload.call_args.args[2]
        self.assertEqual("agent_task_cancel", payload["type"])
        self.assertTrue(sent["queued"])
        for key, value in record.items():
            self.assertEqual(value, payload[key])
        self.control.capture({**record, "type": "agent_task_event", "task_status": "cancelled"})
        sample = self.endpoint.measurements.snapshot(sent["message_id"])
        self.assertIn("cancel_event_received", sample["stages"])

    def test_invalid_event_cannot_complete_measurement(self):
        record = self.control.create()
        sent = self.control.send(record)
        event = {**record, "task_status": "cancelled"}
        for key in ("task_id", "conversation_id", "turn_id", "source_message_id", "contact_id", "task_status"):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.control.capture({**event, key: "wrong"})
        self.assertNotIn("cancel_event_received", self.endpoint.measurements.snapshot(sent["message_id"])["stages"])

    def test_bounded_tasks_samples_and_events(self):
        record = self.control.create()
        self.control.send(record)
        with self.assertRaises(ValueError):
            self.control.send(record)
        for _ in range(8):
            self.control.capture({**record, "task_status": "cancelled"})
        with self.assertRaises(ValueError):
            self.control.capture({**record, "task_status": "cancelled"})
        self.control.tasks = set(map(str, range(128)))
        with self.assertRaises(ValueError):
            self.control.create()
        with self.assertRaises(ValueError):
            self.control.command({"operation": "inspect", "task_id": "unowned"})

    def test_receiver_stage_measurements_are_owned_and_copied(self):
        self.control.stage("unowned", "dispatch_enter")
        self.control.observe_envelope({"message_id": "unowned", "payload": {
            "type": "agent_task_event", "task_id": "unowned"}})
        self.assertEqual({}, self.control.command({"operation": "diagnostics"}))
        record = self.control.create()
        self.control.stage(record["task_id"], "dispatch_enter")
        self.control.observe_envelope({"message_id": "reply", "payload": {
            "type": "agent_task_event", "task_id": record["task_id"]}})
        result = self.control.command({"operation": "diagnostics"})[record["task_id"]]
        self.assertEqual(["reply"], result["reply_ids"])
        self.assertIn("reply_encrypt_enter", result["stages"])
        self.assertIn("started", self.endpoint.measurements.snapshot("reply")["stages"])
        result["reply_ids"].clear()
        self.assertEqual(["reply"], self.control.command({"operation": "diagnostics"})[record["task_id"]]["reply_ids"])


if __name__ == "__main__":
    unittest.main()
