"""Real pool adapter, authenticated resume/AEAD, bridge ingress and SQLite.

Only physical brokers and Signal JNI decrypt are fixtures. No public traffic.
"""
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
import json
import time
from unittest import TestCase, main
from unittest.mock import Mock, patch

import link_delivery
import mqtt_bridge as bridge
import test_mqtt_stored_dispatch as stored_fixture
from link_protocol import open_wire_packet, seal_wire_packet, new_link_secret, make_envelope
from mqtt_broker_catalog import BROKER_IDS
from mqtt_broker_pool import Ingress
from mqtt_delivery_envelope import (Frame, content_hash, parse_verified_frame, receipt_binding, stored_receipt)
from mqtt_multipath_policy import Traffic
from mqtt_peer_routes import PeerBinding, PeerRoutes
from mqtt_pool_client import MqttPoolClient
from mqtt_inbound_pool import InboundRoutePool
from tests.mqtt_pool_fixture import ManualPool


class DeliveryBridgeTest(TestCase):
    def setUp(self):
        self.base = stored_fixture.MqttStoredDispatchTest()
        self.base.setUp()
        self.addCleanup(self.base.doCleanups)
        self.offset = 0
        secret = self.base.paired["link_secret"]
        self.desktop_binding = PeerBinding("pair", "a" * 64, "b" * 64, secret, "to-phone", frozenset({"to-desktop"}))
        self.phone_binding = PeerBinding("phone-pair", "b" * 64, "a" * 64, secret, "to-desktop", frozenset({"to-phone"}))
        self.desktop = self.endpoint(self.desktop_binding)
        self.phone = self.endpoint(self.phone_binding)
        self.desktop.on_message = bridge.on_message
        self.base.mock("flush_outbound_messages")
        self.exchange()
        for client in (self.desktop, self.phone):
            client._pool.sent.clear()

    def endpoint(self, binding):
        client = MqttPoolClient(classify_publication=lambda *args: client.peer_routes.classify(*args),
                                pool_factory=ManualPool, clock=lambda: time.monotonic() + self.offset)
        client.peer_routes = PeerRoutes(client, clock=lambda: time.monotonic() + self.offset,
                                        wall_clock=lambda: time.time() + self.offset)
        client.peer_routes.replace([binding])
        client.subscribe({topic: 1 for topic in binding.receive_topics})
        for broker in BROKER_IDS:
            client._pool.connect(broker)
        self.addCleanup(client.disconnect)
        return client

    def exchange(self):
        cursors = {id(self.desktop): 0, id(self.phone): 0}
        for _ in range(2):
            self.desktop.peer_routes.maintenance()
            self.phone.peer_routes.maintenance()
            for _ in range(20):
                count = 0
                for source, target, binding in ((self.desktop, self.phone, self.phone_binding),
                                                (self.phone, self.desktop, self.desktop_binding)):
                    packets = source._pool.sent[cursors[id(source)]:]
                    cursors[id(source)] += len(packets)
                    for broker, _, _, encoded, _ in packets:
                        payload = json.loads(open_wire_packet(encoded, binding.secret))
                        self.assertTrue(target.peer_routes.handle_verified(binding.scope, payload, broker_id=broker,
                            generation=1, authenticated_identity=binding.identity))
                        count += 1
                if count == 0:
                    break
        self.assertTrue(self.desktop.peer_routes.ready("pair"))
        self.assertTrue(self.phone.peer_routes.ready("phone-pair"))

    def prepare_phone(self, traffic=Traffic.MESSAGE):
        return self.phone.peer_routes.prepare_delivery("to-desktop", self.base.wire, self.base.mid, traffic)

    def send_phone(self, traffic=Traffic.MESSAGE):
        descriptor = self.prepare_phone(traffic)
        link_delivery.queue_outbound("phone-pair", self.base.mid, "to-desktop", json.dumps(self.base.wire),
            receipt_binding=receipt_binding(*self.phone_binding.identity), transport_traffic=traffic.value)
        return self.phone.publish_delivery("to-desktop", descriptor)

    def deliver_desktop(self, packet):
        broker, _, topic, payload, _ = packet
        self.desktop._packet(Ingress(broker, 1, time.monotonic()), topic, payload)

    def receipt_phone(self, packet):
        broker, _, _, encoded, _ = packet
        payload = json.loads(open_wire_packet(encoded, self.phone_binding.secret))
        return self.phone.peer_routes.accept_delivery_receipt("phone-pair", payload, broker_id=broker, generation=1,
            authenticated_identity=self.phone_binding.identity, commit=lambda frame: link_delivery.acknowledge_verified_outbound(
                "phone-pair", stored_receipt(frame.message.message_id, frame.message.content_hash),
                receipt_binding(*self.phone_binding.identity)))

    def test_actual_bridge_stores_before_receipt_and_sender_retires_exact_outbox(self):
        info = self.send_phone()
        self.assertTrue(info.is_published())
        self.assertIsNotNone(link_delivery.outbound_status("phone-pair", self.base.mid))
        self.deliver_desktop(self.phone._pool.sent[0])
        self.base.log.error.assert_not_called()
        self.base.handle.assert_called_once()
        self.assertEqual(content_hash(self.base.wire), link_delivery.stored_wire_receipt("pair", self.base.mid))
        self.assertEqual(1, len(self.desktop._pool.sent))
        self.assertEqual((True, True), self.receipt_phone(self.desktop._pool.sent[0]))
        self.assertIsNone(link_delivery.outbound_status("phone-pair", self.base.mid))
        self.offset += 2
        self.phone._tick()
        self.assertEqual(1, len(self.phone._pool.sent))

    def test_three_different_outer_copies_share_one_signal_decrypt_and_business_dispatch(self):
        self.send_phone(Traffic.CONTROL)
        self.assertEqual(3, len(self.phone._pool.sent))
        self.assertEqual(3, len({packet[3] for packet in self.phone._pool.sent}))
        inbound = InboundRoutePool(self.deliver_desktop)
        self.addCleanup(inbound.close)
        with ThreadPoolExecutor(max_workers=3) as pool:
            results = list(pool.map(lambda packet: inbound.submit("signal:phone", packet, len(packet[3])), self.phone._pool.sent))
        self.assertEqual(["accepted"] * 3, results)
        self.assertTrue(inbound.wait_idle())
        self.assertTrue(inbound.close())
        self.base.log.error.assert_not_called()
        self.base.handle.assert_called_once()
        self.base.decrypt.assert_called_once()
        self.assertEqual(("dispatched", 1), self.base.state())
        self.deliver_desktop(self.phone._pool.sent[0])
        results = [self.receipt_phone(packet) for packet in self.desktop._pool.sent]
        self.assertEqual(1, sum(accepted for handled, accepted in results))
        self.assertIsNone(link_delivery.outbound_status("phone-pair", self.base.mid))

    def test_wire_corruption_is_rejected_before_signal_decrypt_or_storage(self):
        self.send_phone()
        broker, generation, topic, encoded, mid = self.phone._pool.sent[0]
        payload = json.loads(open_wire_packet(encoded, self.phone_binding.secret))
        payload["body"] = "ZGlmZmVyZW50"
        self.deliver_desktop((broker, generation, topic, seal_wire_packet(json.dumps(payload), self.phone_binding.secret).encode(), mid))
        self.base.decrypt.assert_not_called()
        self.base.handle.assert_not_called()
        self.assertEqual([], self.desktop._pool.sent)
        self.deliver_desktop(self.phone._pool.sent[0])
        self.base.handle.assert_called_once()

    def test_lost_peer_receipt_retries_on_other_broker_without_new_task(self):
        self.send_phone()
        self.deliver_desktop(self.phone._pool.sent[0])
        self.offset += 0.6
        self.phone._tick()
        self.assertEqual(2, len(self.phone._pool.sent))
        self.deliver_desktop(self.phone._pool.sent[1])
        self.base.handle.assert_called_once()
        self.base.decrypt.assert_called_once()
        self.assertEqual((True, True), self.receipt_phone(self.desktop._pool.sent[-1]))

    def test_bad_receipt_identity_and_rotated_pair_cannot_retire_outbox(self):
        self.send_phone()
        self.deliver_desktop(self.phone._pool.sent[0])
        packet = self.desktop._pool.sent[0]
        payload = json.loads(open_wire_packet(packet[3], self.phone_binding.secret))
        commit = Mock()
        with self.assertRaises(ValueError):
            self.phone.peer_routes.accept_delivery_receipt("phone-pair", payload, broker_id=packet[0], generation=1,
                authenticated_identity=("other", *self.phone_binding.identity[1:]), commit=commit)
        self.phone.peer_routes.replace([replace(self.phone_binding, secret=new_link_secret())])
        with self.assertRaises(ValueError):
            self.receipt_phone(packet)
        self.assertIsNotNone(link_delivery.outbound_status("phone-pair", self.base.mid))
        commit.assert_not_called()

    def test_real_wire_publish_entrypoint_uses_business_id_and_final_traffic(self):
        wire = {**self.base.wire, "from": "desktop", "to": "phone"}
        info = bridge._publish_mqtt_wire_payload(self.desktop, "to-phone", json.dumps(wire), self.desktop_binding.secret,
                                                timing_scope=("pair", "final-id"), transport_traffic="final")
        self.assertTrue(info.is_published())
        packet = self.desktop._pool.sent[0]
        frame = parse_verified_frame(json.loads(open_wire_packet(packet[3], self.phone_binding.secret)),
                                    sender="a" * 64, receiver="b" * 64, ingress_broker=packet[0])
        self.assertEqual("final-id", frame.message.message_id)
        self.assertEqual("final", frame.message.traffic)
        self.assertEqual(content_hash(wire), frame.message.content_hash)

    def test_delayed_copy_rechecks_pair_key_and_does_not_use_closed_over_old_secret(self):
        self.send_phone()
        self.phone.peer_routes.replace([replace(self.phone_binding, secret=new_link_secret())])
        self.offset += 1
        self.phone._tick()
        self.assertEqual(1, len(self.phone._pool.sent))

    def test_traffic_persists_in_existing_outbox_and_is_not_inferred_from_ciphertext(self):
        self.send_phone(Traffic.CONTROL)
        rows = link_delivery.pending_outbound(client_route_id="phone-pair")
        self.assertEqual("control", rows[0]["transport_traffic"])
        for payload, expected in [({"type": "agent_task_cancel"}, "control"),
                                  ({"type": "agent_task_event", "status": "running"}, "progress"),
                                  ({"type": "agent_task_event", "status": "completed"}, "final"),
                                  ({"type": "delivery_ack"}, "receipt"),
                                  ({"type": "text", "content": "cancel something"}, "message")]:
            self.assertEqual(expected, bridge._outbound_transport_traffic(payload))

    def queue_desktop(self):
        wire = {**self.base.wire, "from": "desktop", "to": "phone"}
        link_delivery.queue_outbound("pair", "outgoing", "to-phone", json.dumps(wire),
                                    receipt_binding=receipt_binding(*self.desktop_binding.identity))
        bridge._publish_mqtt_wire_payload(self.desktop, "to-phone", json.dumps(wire), self.desktop_binding.secret,
                                         timing_scope=("pair", "outgoing"))
        return wire

    def test_actual_bridge_receipt_ingress_retires_local_attempt_and_never_dispatches_task(self):
        wire = self.queue_desktop()
        broker, _, _, encoded, _ = self.desktop._pool.sent[0]
        frame = parse_verified_frame(json.loads(open_wire_packet(encoded, self.phone_binding.secret)),
                                    sender="a" * 64, receiver="b" * 64, ingress_broker=broker)
        receipt = frame.receipt_after_store(stored_message_id="outgoing", stored_content_hash=content_hash(wire))
        # A receipt may return on a different authenticated broker.
        ack_broker = next(item for item in BROKER_IDS if item != broker)
        sealed = seal_wire_packet(json.dumps(receipt), self.phone_binding.secret).encode()
        self.desktop._packet(Ingress(ack_broker, 1, time.monotonic()), "to-desktop", sealed)
        self.base.log.error.assert_not_called()
        self.assertIsNone(link_delivery.outbound_status("pair", "outgoing"))
        self.base.decrypt.assert_not_called()
        self.base.handle.assert_not_called()
        self.offset += 2
        self.desktop._tick()
        self.assertEqual(1, len(self.desktop._pool.sent))
        self.assertEqual(1, len(self.desktop.policy._rtt[("pair", broker)]))

    def test_actual_existing_signal_receipt_cancels_pending_copies_without_rtt_attribution(self):
        wire = self.queue_desktop()
        self.base.envelope = make_envelope(stored_receipt("outgoing", content_hash(wire)), source_id="phone", target_id="desktop")
        packet = self.base.packet()
        self.desktop._packet(Ingress("hivemq", 1, time.monotonic()), "to-desktop", packet.payload)
        self.base.log.error.assert_not_called()
        self.assertIsNone(link_delivery.outbound_status("pair", "outgoing"))
        self.offset += 2
        self.desktop._tick()
        self.assertEqual(1, len(self.desktop._pool.sent))
        self.assertEqual({}, self.desktop.policy._rtt)
        self.base.handle.assert_not_called()

    def test_wrong_actual_signal_receipt_cannot_clear_outbox_or_cancel_delayed_copies(self):
        self.queue_desktop()
        self.base.envelope = make_envelope(stored_receipt("outgoing", "e" * 64), source_id="phone", target_id="desktop")
        self.desktop._packet(Ingress("hivemq", 1, time.monotonic()), "to-desktop", self.base.packet().payload)
        self.assertIsNotNone(link_delivery.outbound_status("pair", "outgoing"))
        self.offset += 1.1
        self.desktop._tick()
        self.assertEqual(3, len(self.desktop._pool.sent))
        self.assertEqual({}, self.desktop.policy._rtt)

    def test_send_and_receipt_do_not_invert_registry_and_peer_lock_order(self):
        for endpoint, binding in ((self.phone, self.phone_binding), (self.desktop, self.desktop_binding)):
            routes = endpoint.peer_routes
            original = routes.ready
            peer = routes._peers[binding.scope]

            def checked(scope, original=original, peer=peer):
                self.assertFalse(peer.lock._is_owned(), "Registry lookup while holding a peer lock can deadlock replacement")
                return original(scope)

            self.base.stack.enter_context(patch.object(routes, "ready", side_effect=checked))
        self.send_phone()
        self.deliver_desktop(self.phone._pool.sent[0])
        self.assertEqual(1, len(self.desktop._pool.sent))
        self.base.log.error.assert_not_called()


if __name__ == "__main__":
    main()
