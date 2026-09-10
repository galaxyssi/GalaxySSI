"""Callback ordering regressions; no broker or private delivery store is used."""
import threading
import unittest
from contextlib import ExitStack
from types import SimpleNamespace
from unittest.mock import patch

import mqtt_bridge as bridge


class PublishRegistrationTest(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        for name, value in (("pending_outbound_acks", {}), ("early_outbound_acks", {}),
                            ("pending_outbound_priorities", {}), ("outbound_publish_reservations", {}),
                            ("pending_delivery_acks", {}), ("mqtt_connection_generation", 51)):
            self.stack.enter_context(patch.object(bridge, name, value))
        self.published = self.stack.enter_context(patch.object(bridge, "mark_outbound_published"))
        self.retryable = self.stack.enter_context(patch.object(bridge, "mark_outbound_retryable"))
        self.stack.enter_context(patch.object(bridge, "transport_timing"))
        self.stack.enter_context(patch.object(bridge, "_complete_fragment_publish", return_value=(False, None)))
        self.client = SimpleNamespace(is_connected=lambda: True)
        self.info = SimpleNamespace(mid=71, rc=0, is_published=lambda: False)

    def track(self, generation=51):
        bridge.track_outbound_publish(self.info, "app-a", "message-a",
                                      mqttc=self.client, generation=generation)

    def test_ack_before_registration_before_paho_marks_info_complete(self):
        bridge.on_publish(self.client, None, 71)
        self.track()
        self.published.assert_called_once_with("app-a", "message-a")
        self.assertEqual({}, bridge.pending_outbound_acks)

    def test_ack_after_registration(self):
        self.track()
        bridge.on_publish(self.client, None, 71)
        self.published.assert_called_once_with("app-a", "message-a")
        self.assertEqual({}, bridge.pending_outbound_acks)

    def test_artifact_priority_survives_registration_until_puback(self):
        key = ("app-a", "message-a")
        bridge.outbound_publish_reservations[key] = bridge.OUTBOUND_PRIORITY_ARTIFACT
        self.track()
        bridge.outbound_publish_reservations.clear()
        self.assertEqual({key: bridge.OUTBOUND_PRIORITY_ARTIFACT}, bridge.pending_outbound_priorities)
        bridge.on_publish(self.client, None, 71)
        self.assertEqual({}, bridge.pending_outbound_priorities)

    def test_synchronously_completed_info_leaves_no_priority_metadata(self):
        self.info.is_published = lambda: True
        self.track()
        self.published.assert_called_once_with("app-a", "message-a")
        self.assertEqual({}, bridge.pending_outbound_acks)
        self.assertEqual({}, bridge.pending_outbound_priorities)

    def test_failed_early_ack_remains_retryable(self):
        bridge.on_publish(self.client, None, 71, 128)
        self.track()
        self.retryable.assert_called_once_with("app-a", "message-a")
        self.published.assert_not_called()

    def test_failed_late_ack_remains_retryable(self):
        self.track()
        bridge.on_publish(self.client, None, 71, 128)
        self.retryable.assert_called_once_with("app-a", "message-a")
        self.published.assert_not_called()

    def test_disconnect_during_publish_cannot_register_a_stale_token(self):
        self.track(generation=50)
        self.retryable.assert_called_once_with("app-a", "message-a")
        self.assertEqual({}, bridge.pending_outbound_acks)

    def test_early_ack_from_other_client_does_not_complete_this_client(self):
        bridge.on_publish(object(), None, 71)
        self.track()
        self.published.assert_not_called()
        self.assertEqual({71: ("app-a", "message-a")}, bridge.pending_outbound_acks)

    def test_early_ack_from_old_generation_does_not_complete_reused_mid(self):
        bridge.on_publish(self.client, None, 71)
        with patch.object(bridge, "mqtt_connection_generation", 52):
            self.track(generation=52)
        self.published.assert_not_called()
        self.assertEqual({71: ("app-a", "message-a")}, bridge.pending_outbound_acks)

    def test_untracked_control_ack_history_is_bounded(self):
        with patch.object(bridge, "MAX_EARLY_OUTBOUND_ACKS", 8):
            for mid in range(100):
                bridge.on_publish(self.client, None, mid)
        self.assertEqual(8, len(bridge.early_outbound_acks))

    def test_durable_publish_does_not_block_disconnect_callback(self):
        peer = {"client_route_id": "app-a", "link_secret": "test"}
        pending = {"client_route_id": "app-a", "message_id": "message-a", "wire_payload": "wire"}
        callback_finished = threading.Event()
        observed = []
        threads = []

        def callback():
            with bridge.pending_outbound_acks_lock:
                bridge.pending_outbound_acks.clear()
                bridge.mqtt_connection_generation += 1
            callback_finished.set()

        def publish(*args, **kwargs):
            thread = threading.Thread(target=callback, daemon=True)
            threads.append(thread)
            thread.start()
            observed.append(callback_finished.wait(1))
            return self.info

        for name, result in (("list_clients", [peer]), ("get_client", peer),
                             ("outbound_inflight_count", 0), ("fail_exhausted_outbound", []),
                             ("pending_outbound", [pending]), ("mark_outbound_sending", None),
                             ("_topics_for_client", SimpleNamespace(send="test/topic"))):
            self.stack.enter_context(patch.object(bridge, name, return_value=result))
        self.stack.enter_context(patch.object(bridge, "_publish_mqtt_wire_payload", side_effect=publish))
        bridge.flush_outbound_messages(self.client)
        for thread in threads:
            thread.join(2)
            self.assertFalse(thread.is_alive())
        self.assertEqual([True], observed, "publish held a lock needed by disconnect")
        self.assertEqual({}, bridge.pending_outbound_acks)
        self.assertEqual({}, bridge.pending_outbound_priorities)
        self.assertEqual({}, bridge.outbound_publish_reservations)
        self.retryable.assert_called_once_with("app-a", "message-a")


if __name__ == "__main__":
    unittest.main()
