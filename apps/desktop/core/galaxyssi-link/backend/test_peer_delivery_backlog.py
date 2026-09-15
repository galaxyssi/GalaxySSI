"""Backlog regressions using isolated state, no live broker or phone."""
import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import link_delivery as delivery
import mqtt_bridge as bridge
from peer_chat_store import PeerChatStore
from peer_delivery_status import reconcile
from mqtt_receipt_replay_gate import ReceiptReplayGate


class ReceiveBacklogTests(unittest.TestCase):
    def test_reply_commits_to_queue_without_scanning_outbox_in_receive_thread(self):
        mqtt = Mock(spec=bridge.MqttPoolClient)
        paired = {"client_route_id": "phone"}
        with patch.object(bridge, "_wire_client", return_value=paired), \
                patch.object(bridge, "_topics_for_client"), \
                patch("agent_worker_routing.recipient_allowed", return_value=True), \
                patch.object(bridge, "_publish_to_registered_client", return_value=bridge._DeferredPublishInfo()) as publish:
            self.assertTrue(bridge._publish_phone_payload(mqtt, {}, {"type": "agent_task_recovery_result"}))
            self.assertTrue(publish.call_args.kwargs["queue_only"])
            self.assertTrue(publish.call_args.kwargs["durable"])

    def test_framed_receipt_keeps_confirmation_for_expired_sender_attempts(self):
        mqtt = Mock(spec=bridge.MqttPoolClient)
        mqtt.peer_routes = Mock()
        for admitted in (True, False, None):
            with self.subTest(admitted=admitted), \
                    patch.object(bridge, "get_client", return_value={"client_route_id": "phone"}), \
                    patch.object(bridge, "accepted_delivery_ack_payload", return_value={"client_source_message_id": 9}), \
                    patch.object(bridge, "complete_message") as stored, \
                    patch.object(bridge, "_publish_phone_payload") as signal:
                mqtt.peer_routes.publish_stored_receipt.return_value = admitted
                bridge._ack_stored_application(mqtt, {"_client_route_id": "phone"}, {"message_id": "message"},
                    {"type": "peer_message"}, {}, delivery_frame=Mock(), wire_hash="a" * 64)
                stored.assert_called_once()
                self.assertEqual(1, signal.call_count)

    def test_receipt_admission_exception_keeps_signal_fallback(self):
        mqtt = Mock(spec=bridge.MqttPoolClient)
        mqtt.peer_routes = Mock()
        mqtt.peer_routes.publish_stored_receipt.side_effect = RuntimeError("temporarily full")
        with patch.object(bridge, "get_client", return_value={"client_route_id": "phone"}), \
                patch.object(bridge, "accepted_delivery_ack_payload", return_value={"client_source_message_id": 9}), \
                patch.object(bridge, "complete_message"), patch.object(bridge, "_publish_phone_payload") as signal:
            bridge._ack_stored_application(mqtt, {"_client_route_id": "phone"}, {"message_id": "message"},
                {"type": "peer_message"}, {}, delivery_frame=Mock(), wire_hash="a" * 64)
            signal.assert_called_once()

    def test_receipts_never_generate_receipts(self):
        with patch.object(bridge, "_publish_phone_payload") as publish:
            bridge._ack_stored_application(Mock(), {"_client_route_id": "phone"}, {"message_id": "message"},
                {"type": "delivery_ack"}, {}, wire_hash="a" * 64)
            publish.assert_not_called()

    def test_woken_sender_stops_without_running_another_pass(self):
        stop, wake = threading.Event(), threading.Event()
        stop.set()
        wake.set()
        with patch.object(bridge, "outbound_retry_stop_event", stop), \
                patch.object(bridge, "outbound_retry_wake_event", wake), \
                patch.object(bridge, "flush_outbound_messages") as flush:
            bridge._outbound_retry_loop()
            flush.assert_not_called()


class PeerFailureProjectionTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.store = PeerChatStore(Path(temp.name) / "peer.db")
        patcher = patch.object(delivery, "DB_PATH", Path(temp.name) / "link.db")
        patcher.start()
        self.addCleanup(patcher.stop)
        self.store.append(client_route_id="a", direction="outbound", content="hello", message_id="message", delivery_status="queued")
        delivery.queue_outbound("a", "message", "topic", json.dumps({"scheme": "signal", "body": "AAAA"}))

    def exhaust(self, callback=None):
        delivery.mark_outbound_sending("a", "message")
        return delivery.fail_exhausted_outbound(max_attempts=1, now=10**12, before_quarantine=callback)

    def test_failure_projection_is_scoped_idempotent_and_does_not_regress_delivery(self):
        with self.assertRaises(ValueError):
            self.store.mark_outbound_failed("b", "message")
        events = []
        self.store.subscribe(events.append)
        self.exhaust(self.store.mark_outbound_failed)
        self.assertEqual("failed", self.store.get_message("message")["delivery_status"])
        self.store.mark_outbound_failed("a", "message")
        self.assertEqual(1, len(events))
        self.store.mark_outbound_stored("a", "message")
        self.store.mark_outbound_failed("a", "message")
        self.assertEqual("delivered", self.store.get_message("message")["delivery_status"])

    def test_failed_projection_leaves_retry_state_recoverable(self):
        self.assertEqual([], self.exhaust(Mock(side_effect=OSError("disk busy"))))
        self.assertEqual("sending", delivery.outbound_status("a", "message"))

    def test_one_failed_projection_does_not_block_another_route(self):
        delivery.queue_outbound("b", "other", "topic", json.dumps({"scheme": "signal", "body": "AAAA"}))
        delivery.mark_outbound_sending("b", "other")
        def project(route, message):
            if route == "a":
                raise OSError("one unavailable projection")
        result = self.exhaust(project)
        self.assertEqual(["other"], [item["message_id"] for item in result])
        self.assertEqual("sending", delivery.outbound_status("a", "message"))
        self.assertEqual("failed", delivery.outbound_status("b", "other"))

    def test_read_repairs_preexisting_failed_rows_without_resending(self):
        self.exhaust()
        result = reconcile(self.store, self.store.list_messages())
        self.assertEqual("failed", result[0]["delivery_status"])
        self.assertEqual("failed", delivery.outbound_status("a", "message"))

    def test_missing_outbox_row_is_not_proof_of_delivery(self):
        delivery.acknowledge_outbound("a", "message")
        result = reconcile(self.store, self.store.list_messages())
        self.assertEqual("queued", result[0]["delivery_status"])

    def test_bulk_status_read_does_not_leak_across_routes(self):
        self.assertEqual({("a", "message"): "queued"},
            delivery.outbound_statuses([("a", "message"), ("b", "message")]))


class ReceiptReplayGateTests(unittest.TestCase):
    def test_burst_duplicates_coalesce_but_late_retry_and_restart_confirm_again(self):
        now = [0.0]
        gate = ReceiptReplayGate(clock=lambda: now[0])
        send = Mock(return_value=True)
        key = ("route", "message", "hash")
        gate.publish(key, send)
        for _ in range(128):
            gate.publish(key, send, duplicate=True)
        send.assert_called_once()
        now[0] = 31
        gate.publish(key, send, duplicate=True)
        self.assertEqual(2, send.call_count)
        ReceiptReplayGate().publish(key, send, duplicate=True)
        self.assertEqual(3, send.call_count)

    def test_rejected_or_failed_send_does_not_suppress_next_receipt(self):
        gate = ReceiptReplayGate()
        send = Mock(side_effect=[False, OSError("offline"), True])
        key = ("route", "message", "hash")
        self.assertFalse(gate.publish(key, send))
        with self.assertRaises(OSError):
            gate.publish(key, send, duplicate=True)
        self.assertTrue(gate.publish(key, send, duplicate=True))
        self.assertEqual(3, send.call_count)

    def test_pair_and_hash_isolation_and_bounded_memory(self):
        gate = ReceiptReplayGate(capacity=2)
        send = Mock(return_value=True)
        for key in [("a", "m", "h1"), ("b", "m", "h1"), ("a", "m", "h2")]:
            gate.publish(key, send, duplicate=True)
        self.assertEqual(3, send.call_count)
        self.assertEqual(2, len(gate._sent))
        gate.publish(("a", "m", "h1"), send, duplicate=True)
        self.assertEqual(4, send.call_count)


if __name__ == "__main__":
    unittest.main()
