import copy
import unittest
from unittest.mock import patch

from agent_transport_timing import transport_task_id, TransportTiming
import mqtt_bridge as bridge
from tests.test_mqtt_durable_delivery import paired_client, DurableMqttClient


def batch(kind="agent_task_recovery_result"):
    return {"type": kind, "request_id": "nonce", "client_route_id": "route", "items": [
        {"client_route_id": "route", "conversation_id": "conversation", "task_id": task, "turn_id": "turn",
         "contact_id": "contact", "source_message_id": "42", "agent_id": "codex"} for task in ("first", "second")]}


class RecoveryTransportTraceTest(unittest.TestCase):
    def test_both_directions_use_first_identity_without_mutating_envelope(self):
        for kind in ("agent_task_recovery_result", "agent_task_recovery_request"):
            payload = batch(kind)
            original = copy.deepcopy(payload)
            self.assertEqual("first", transport_task_id(payload))
            self.assertEqual(original, payload)
            payload["task_id"] = "unrelated"
            self.assertEqual("first", transport_task_id(payload))

    def test_every_identity_must_have_valid_shape_and_route(self):
        for field in batch()["items"][0]:
            for value in ("", " ", "x" * 201, 42, None):
                with self.subTest(field=field, value_type=type(value).__name__):
                    payload = batch()
                    payload["items"][1][field] = value
                    self.assertEqual("", transport_task_id(payload))
        for size in (0, 33):
            payload = batch()
            payload["items"] = [payload["items"][0]] * size
            self.assertEqual("", transport_task_id(payload))
        for key, value in (("request_id", "x" * 129), ("client_route_id", "wrong"), ("items", [None])):
            payload = batch()
            payload[key] = value
            self.assertEqual("", transport_task_id(payload))

    def test_normal_tasks_are_unchanged_and_contacts_are_excluded(self):
        self.assertEqual("task", transport_task_id({"type": "text", "task_id": "task"}))
        self.assertEqual("", transport_task_id({**batch(), "peer_chat": True}))
        self.assertEqual("", transport_task_id(None))

    def test_real_durable_publish_hook_registers_one_batch_trace(self):
        payload = batch()
        client = paired_client("route")
        with (patch.object(bridge, "make_envelope", return_value={"message_id": "message"}),
              patch.object(bridge, "outbound_status", return_value=None),
              patch.object(bridge, "encrypt_signal_payload", return_value={"ciphertext": "fixture"}),
              patch.object(bridge, "queue_outbound") as queue,
              patch.object(bridge, "flush_outbound_messages", return_value={}),
              patch.object(bridge.transport_timing, "queued") as timing):
            bridge._publish_to_registered_client(DurableMqttClient(), client, payload)
            timing.assert_called_once_with("route", "message", "first")
            queue.assert_called_once()

    def test_batch_keeps_queue_broker_and_peer_boundaries_separate(self):
        points = []
        now = [0]
        trace = TransportTiming(lambda *args: points.append(args), now_ns=lambda: now[0])
        trace.queued("route", "message", transport_task_id(batch()))
        now[0] = 5
        attempt = trace.begin("route", "message")
        now[0] = 9
        trace.broker(attempt)
        now[0] = 17
        trace.received("route", "message")
        self.assertEqual(["desktop_transport_queued", "desktop_transport_dispatched", "desktop_wire_started",
                          "desktop_broker_acked", "desktop_peer_received"], [point[1] for point in points])
        self.assertEqual([0, 5, 5, 9, 17], [point[4] for point in points])
        self.assertEqual(1, len({point[0] for point in points}))


if __name__ == "__main__":
    unittest.main()
