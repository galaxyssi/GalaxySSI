"""Real durable inbox and receipt scheduling, without models or a live broker."""
import copy
from concurrent.futures import ThreadPoolExecutor
import json
import threading
import unittest
from unittest.mock import Mock, patch

import link_delivery as delivery
import link_protocol
import mqtt_bridge as bridge
import signal_receive_dispatch as dispatch
from mqtt_delivery_envelope import content_hash
from mqtt_stored_receipt_publisher import StoredReceiptPublisher
import test_mqtt_stored_dispatch as fixtures
from tests.receive_test_support import store_received_envelope


class StoredReceiptPublisherTest(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.MqttStoredDispatchTest()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.publisher = StoredReceiptPublisher(max_pending=4, route_pending=1)
        self.fixture.mock("stored_receipt_publisher", new=self.publisher)
        self.addCleanup(lambda: self.publisher.close(timeout=5))
        self.mqtt = Mock(spec=bridge.MqttPoolClient)
        self.mqtt.peer_routes = Mock()
        self.release = threading.Event()
        self.entered = threading.Event()
        self.addCleanup(self.release.set)

    def block_ack(self, *_args, **_kwargs):
        self.entered.set()
        if not self.release.wait(5):
            raise TimeoutError("test receipt was not released")
        return True

    def envelope(self):
        return link_protocol.make_envelope(self.fixture.envelope["payload"],
            source_id="phone", target_id="desktop", conversation_id="conversation")

    def deliver(self, envelope, *, store=True):
        if store:
            store_received_envelope("pair", envelope)
            delivery.bind_ciphertext("pair", envelope["message_id"], envelope["message_id"],
                                     receipt_hash=content_hash(self.fixture.wire))
        bridge._deliver_stored_application(self.mqtt, self.fixture.paired,
            {**self.fixture.wire, "_client_route_id": "pair"}, envelope,
            copy.deepcopy(envelope["payload"]), [])

    def test_blocked_ack_does_not_block_business_or_next_message(self):
        self.fixture.publish.side_effect = self.block_ack
        first, second = self.envelope(), self.envelope()
        with ThreadPoolExecutor(max_workers=1) as ingress:
            first_delivery = ingress.submit(self.deliver, first)
            try:
                self.assertTrue(self.entered.wait(5))
                first_delivery.result(timeout=2)
                self.fixture.handle.assert_called_once()
                ingress.submit(self.deliver, second).result(timeout=2)
                self.assertEqual(2, self.fixture.handle.call_count)
                self.assertEqual([], dispatch.pending())
            finally:
                self.release.set()
        self.assertTrue(self.publisher.wait_idle())
        self.assertEqual(2, self.fixture.publish.call_count)
        self.assertTrue(all(call.args[2]["delivery_status"] == "RX_STORED"
                            for call in self.fixture.publish.call_args_list))

    def test_replays_coalesce_while_ack_is_in_flight_without_redispatch(self):
        self.fixture.publish.side_effect = self.block_ack
        envelope = self.envelope()
        self.deliver(envelope)
        self.assertTrue(self.entered.wait(2))
        for _ in range(8):
            self.deliver(envelope, store=False)
        self.fixture.handle.assert_called_once()
        self.assertEqual(8, self.publisher.snapshot()["coalesced"])
        self.release.set()
        self.assertTrue(self.publisher.wait_idle())
        self.fixture.publish.assert_called_once()

    def test_real_recall_waiter_receives_original_result_while_ack_is_blocked(self):
        from collaboration_recall_bridge import RecallBroker, RESPONSE
        broker = RecallBroker()
        snapshot = dict(task_id="task", client_route_id="pair", client_conversation_id="group",
            client_turn_id="turn", source_message_id="42", contact_id="codex-contact", agent_id="codex",
            status="running", execution_generation=1)
        requests, requested = [], threading.Event()
        def publish(request):
            requests.append(request)
            requested.set()
            return True
        result = {"success": True, "milestones": [{"evidence": "original-observation"}], "next_cursor": None}
        self.fixture.publish.side_effect = self.block_ack
        self.fixture.handle.side_effect = lambda _m, paired, _w, _e, payload, _t: broker.receive(payload, paired["client_route_id"])
        with ThreadPoolExecutor(max_workers=2) as workers:
            query = workers.submit(broker.query, lambda: snapshot, {"mode": "team_updates"}, publish, timeout=5)
            try:
                self.assertTrue(requested.wait(2))
                envelope = link_protocol.make_envelope({**requests[0], "type": RESPONSE, "result": result},
                    source_id="phone", target_id="desktop", conversation_id="group")
                inbound = workers.submit(self.deliver, envelope)
                self.assertTrue(self.entered.wait(2))
                self.assertEqual(result, query.result(timeout=2))
                inbound.result(timeout=2)
                self.assertEqual(1, len(requests))
            finally:
                self.release.set()
        self.assertTrue(self.publisher.wait_idle())
        self.assertEqual({}, broker._pending)

    def test_full_queue_keeps_proof_and_later_replay_confirms_without_rerun(self):
        self.fixture.publish.side_effect = self.block_ack
        first, second, third = self.envelope(), self.envelope(), self.envelope()
        self.deliver(first)
        self.assertTrue(self.entered.wait(2))
        self.deliver(second)
        self.deliver(third)
        self.assertEqual(3, self.fixture.handle.call_count)
        self.assertEqual(1, self.publisher.snapshot()["rejected"]["route_pending"])
        self.assertEqual(content_hash(self.fixture.wire),
                         delivery.stored_wire_receipt("pair", third["message_id"]))
        self.release.set()
        self.assertTrue(self.publisher.wait_idle())
        self.deliver(third, store=False)
        self.assertTrue(self.publisher.wait_idle())
        self.assertEqual(3, self.fixture.publish.call_count)
        self.assertEqual(3, self.fixture.handle.call_count)

    def test_publisher_restart_recovers_lost_receipt_from_existing_inbox(self):
        self.fixture.publish.side_effect = self.block_ack
        first, second = self.envelope(), self.envelope()
        self.deliver(first)
        self.assertTrue(self.entered.wait(2))
        self.deliver(second)
        self.publisher.close(wait=False)
        self.assertEqual(1, self.publisher.snapshot()["cancelled"])
        self.release.set()
        self.assertTrue(self.publisher.close())
        replacement = StoredReceiptPublisher()
        self.fixture.mock("stored_receipt_publisher", new=replacement)
        try:
            self.deliver(second, store=False)
            self.assertTrue(replacement.wait_idle())
            self.assertEqual(2, self.fixture.handle.call_count)
            self.assertEqual(2, self.fixture.publish.call_count)
        finally:
            replacement.close()

    def test_publish_error_keeps_durable_proof_and_does_not_block_business(self):
        self.fixture.publish.side_effect = OSError("offline")
        envelope = self.envelope()
        self.deliver(envelope)
        self.assertTrue(self.publisher.wait_idle())
        self.assertEqual(1, self.publisher.snapshot()["failed"])
        self.fixture.handle.assert_called_once()
        self.fixture.publish.side_effect = None
        self.fixture.publish.return_value = True
        self.deliver(envelope, store=False)
        self.assertTrue(self.publisher.wait_idle())
        self.fixture.handle.assert_called_once()
        self.assertEqual(2, self.fixture.publish.call_count)

    def test_unstored_body_never_enters_receipt_queue(self):
        with self.assertRaises(RuntimeError):
            self.deliver(self.envelope(), store=False)
        self.assertEqual(0, self.publisher.snapshot()["accepted"])
        self.fixture.handle.assert_not_called()

    def test_receipts_do_not_create_receipts_or_retain_inbound_ciphertext(self):
        envelope = self.envelope()
        envelope["payload"] = {"type": "delivery_ack", "transport_message_id": "missing"}
        self.fixture.mock("_acknowledge_registered_outbound", return_value=False)
        self.deliver(envelope)
        self.assertEqual(0, self.publisher.snapshot()["accepted"])
        self.fixture.publish.assert_not_called()
        self.deliver(self.envelope())
        self.assertTrue(self.publisher.wait_idle())
        sent = self.fixture.publish.call_args
        self.assertEqual({"_client_route_id": "pair"}, sent.args[1])
        self.assertNotIn(self.fixture.wire["body"], json.dumps(sent.args[2]))
        self.assertEqual(bridge._receipt_binding_for_client(self.fixture.paired),
                         sent.kwargs["expected_receipt_binding"])


class StoredReceiptPairBindingTest(unittest.TestCase):
    def test_pair_change_or_revocation_before_publish_rejects_receipt(self):
        paired = {"client_route_id": "pair", "signal_name": "phone", "link_secret": "A" * 43,
                  "identity_fingerprint": "a" * 64, "local_identity_fingerprint": "b" * 64}
        expected = bridge._receipt_binding_for_client(paired)
        for replacement in (None, {**paired, "revoked_at": 1}, {**paired, "link_secret": "B" * 43},
                            {**paired, "identity_fingerprint": "c" * 64},
                            {**paired, "local_identity_fingerprint": "d" * 64}):
            with self.subTest(replacement=replacement is None), \
                    patch.object(bridge, "_wire_client", side_effect=[paired, replacement]), \
                    patch.object(bridge, "_topics_for_client"), \
                    patch("agent_worker_routing.recipient_allowed", return_value=True), \
                    patch.object(bridge, "_publish_to_registered_client") as publish:
                self.assertFalse(bridge._publish_phone_payload(Mock(), {"_client_route_id": "pair"},
                    {"type": "delivery_ack"}, expected_receipt_binding=expected))
                publish.assert_not_called()


if __name__ == "__main__":
    unittest.main()
