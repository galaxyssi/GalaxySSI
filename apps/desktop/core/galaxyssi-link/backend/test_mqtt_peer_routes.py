import json
import tempfile
import time
import unittest
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import link_delivery
from link_protocol import new_link_secret, open_wire_packet
from mqtt_broker_catalog import BROKER_IDS
from mqtt_broker_pool import Ingress
from mqtt_peer_routes import PeerBinding, PeerRoutes
from mqtt_pool_client import MqttPoolClient
from tests.mqtt_pool_fixture import ManualPool


class PeerRouteExchangeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        db_patch = patch.object(link_delivery, "DB_PATH", Path(self.temp.name) / "delivery.db")
        db_patch.start()
        self.addCleanup(db_patch.stop)
        self.offset = 0
        secret = new_link_secret()
        self.left_binding = PeerBinding("left", "a" * 64, "b" * 64, secret, "to-right", frozenset({"to-left"}))
        self.right_binding = PeerBinding("right", "b" * 64, "a" * 64, secret, "to-left", frozenset({"to-right"}))
        self.left = self.endpoint(self.left_binding)
        self.right = self.endpoint(self.right_binding)

    def endpoint(self, binding):
        client = MqttPoolClient(classify_publication=lambda *args: routes.classify(*args), pool_factory=ManualPool)
        self.addCleanup(client.disconnect)
        ready = Mock()
        routes = PeerRoutes(client, on_ready=ready, clock=lambda: time.monotonic() + self.offset,
                            wall_clock=lambda: time.time() + self.offset)
        routes.replace([binding])
        client.subscribe({topic: 1 for topic in binding.receive_topics})
        endpoint = SimpleNamespace(client=client, pool=client._pool, routes=routes, binding=binding,
                                   cursor=0, received=[], ready=ready)

        def receive(_client, _data, message):
            payload = json.loads(open_wire_packet(message.payload, endpoint.binding.secret))
            if not routes.handle_verified(binding.scope, payload, broker_id=message.broker_id,
                                          generation=message.broker_generation,
                                          authenticated_identity=endpoint.binding.identity):
                endpoint.received.append(payload)
        client.on_message = receive
        return endpoint

    def connect(self, brokers=BROKER_IDS):
        for broker in brokers:
            self.left.pool.connect(broker)
            self.right.pool.connect(broker)

    def deliver(self, target, packet):
        broker, _generation, topic, encoded, _logical = packet
        path = target.pool.paths[broker]
        if path["connected"] and topic in path["topics"]:
            target.client._packet(Ingress(broker, path["generation"], time.monotonic()), topic, encoded)

    def pump(self):
        for _ in range(50):
            count = 0
            for source, target in ((self.left, self.right), (self.right, self.left)):
                packets = source.pool.sent[source.cursor:]
                source.cursor += len(packets)
                for packet in packets:
                    self.deliver(target, packet)
                    count += 1
            if not count:
                return
        self.fail("resume exchange did not settle; possible ACK storm")

    def exchange(self):
        for _ in range(2):
            self.left.routes.maintenance()
            self.right.routes.maintenance()
            self.pump()

    def decoded(self, endpoint, index=-1):
        return json.loads(open_wire_packet(endpoint.pool.sent[index][3], endpoint.binding.secret))

    def test_first_common_path_is_sufficient_for_authenticated_bidirectional_send(self):
        for broker in BROKER_IDS:
            with self.subTest(broker=broker):
                self.connect([broker])
                self.exchange()
                self.assertTrue(self.left.routes.ready("left"))
                self.assertTrue(self.right.routes.ready("right"))
                self.assertIsNotNone(self.left.routes.classify("to-right", b"encrypted"))
                for endpoint in (self.left, self.right):
                    endpoint.pool.lose(broker)
                    self.assertFalse(endpoint.routes.ready(endpoint.binding.scope))

    def test_connection_and_puback_without_remote_resume_ack_are_not_business_ready(self):
        self.connect()
        self.left.routes.maintenance()
        self.assertTrue(self.left.client.is_connected())
        self.assertEqual({}, self.left.pool.pending)
        self.assertFalse(self.left.routes.ready("left"))
        self.assertIsNone(self.left.routes.classify("to-right", b"encrypted"))
        self.assertEqual({"configured": 1, "ready": 0}, self.left.routes.status())

    def test_three_brokers_exchange_settles_without_ack_of_ack(self):
        self.connect()
        self.exchange()
        self.assertEqual(6, len(self.left.pool.sent))
        self.assertEqual(6, len(self.right.pool.sent))
        self.assertEqual({"configured": 1, "ready": 1}, self.left.routes.status())
        self.left.ready.assert_called_once_with("left")
        self.right.ready.assert_called_once_with("right")
        self.exchange()
        self.assertEqual(6, len(self.left.pool.sent))
        self.assertEqual(6, len(self.right.pool.sent))

    def test_no_common_broker_queues_business_until_a_shared_path_recovers(self):
        self.left.pool.connect("hivemq")
        self.right.pool.connect("mosquitto")
        self.exchange()
        self.assertFalse(self.left.routes.ready("left"))
        self.assertFalse(self.right.routes.ready("right"))
        self.left.pool.connect("mosquitto")
        self.exchange()
        self.assertTrue(self.left.routes.ready("left"))
        self.assertTrue(self.right.routes.ready("right"))

    def test_one_failed_broker_does_not_revoke_other_business_paths(self):
        self.connect()
        self.exchange()
        self.left.pool.lose("emqx")
        self.right.pool.lose("emqx")
        self.assertTrue(self.left.routes.ready("left"))
        self.exchange()
        self.assertEqual({"hivemq", "mosquitto"}, self.left.routes._peers["left"].local.receive_brokers)
        self.assertTrue(self.left.routes.ready("left"))

    def test_all_failed_then_one_restored_requires_fresh_authenticated_ack(self):
        self.connect()
        self.exchange()
        for broker in BROKER_IDS:
            self.left.pool.lose(broker)
            self.right.pool.lose(broker)
        self.assertFalse(self.left.routes.ready("left"))
        self.left.pool.connect("hivemq", 2)
        self.right.pool.connect("hivemq", 2)
        self.left.routes.maintenance()
        self.assertFalse(self.left.routes.ready("left"))
        self.exchange()
        self.assertTrue(self.left.routes.ready("left"))

    def test_same_single_broker_reconnection_does_not_reuse_old_ready_epoch(self):
        self.connect(["hivemq"])
        self.exchange()
        old = self.left.routes._peers["left"].local.epoch
        descriptor = self.left.routes.classify("to-right", b"encrypted")
        self.left.pool.lose("hivemq")
        self.left.pool.connect("hivemq", 2)
        self.assertFalse(self.left.routes.ready("left"))
        self.assertNotEqual(0, self.left.client.publish("to-right", b"encrypted", publication=descriptor).rc)
        self.exchange()
        self.assertGreater(self.left.routes._peers["left"].local.epoch, old)
        self.assertTrue(self.left.routes.ready("left"))

    def test_wrong_fingerprint_or_pending_pair_secret_cannot_poison_route(self):
        self.connect(["hivemq"])
        self.right.routes.maintenance()
        payload = self.decoded(self.right)
        with self.assertRaises(ValueError):
            self.left.routes.handle_verified("left", payload, broker_id="hivemq", generation=1,
                                             authenticated_identity=replace(self.left_binding, secret=new_link_secret()).identity)
        payload["sender_fingerprint"] = "c" * 64
        with self.assertRaises(ValueError):
            self.left.routes.handle_verified("left", payload, broker_id="hivemq", generation=1,
                                             authenticated_identity=self.left_binding.identity)
        self.assertEqual(0, self.left.routes._peers["left"].remote_epoch)
        self.exchange()
        self.assertTrue(self.left.routes.ready("left"))

    def test_unrequested_or_mismatched_ack_is_rejected_before_route_persistence(self):
        self.connect(["hivemq"])
        self.right.routes.maintenance()
        payload = {"type": "link_resume_ack", "advertisement": self.decoded(self.right),
                   "acknowledged_resume_id": "a" * 32, "acknowledged_route_epoch": 1,
                   "acknowledged_digest": "a" * 64}
        with self.assertRaises(ValueError):
            self.left.routes.handle_verified("left", payload, broker_id="hivemq", generation=1,
                                             authenticated_identity=self.left_binding.identity)
        self.assertEqual(0, self.left.routes._peers["left"].remote_epoch)

    def test_old_generation_cannot_change_authenticated_receive_set(self):
        self.connect(["hivemq"])
        self.right.routes.maintenance()
        payload = self.decoded(self.right)
        self.left.pool.lose("hivemq")
        self.left.pool.connect("hivemq", 2)
        self.assertTrue(self.left.routes.handle_verified("left", payload, broker_id="hivemq", generation=1,
                                                        authenticated_identity=self.left_binding.identity))
        self.assertEqual(0, self.left.routes._peers["left"].remote_epoch)

    def delayed_ack(self):
        self.connect()
        self.exchange()
        packet = next(packet for packet in self.right.pool.sent if packet[0] == "hivemq" and
                      json.loads(open_wire_packet(packet[3], self.left_binding.secret))["type"] == "link_resume_ack")
        payload = json.loads(open_wire_packet(packet[3], self.left_binding.secret))
        self.left.pool.lose("emqx")
        self.right.pool.lose("emqx")
        self.left.routes.maintenance()
        return payload

    def test_delayed_old_ack_does_not_persist_advertisement_or_confirm_new_epoch(self):
        payload = self.delayed_ack()
        peer = self.left.routes._peers["left"]
        old_remote = peer.remote_epoch
        before_sent = len(self.left.pool.sent)
        # Even a newer remote advertisement cannot be accepted via an old ACK.
        payload["advertisement"]["route_epoch"] += 100
        with patch("mqtt_peer_routes.record_verified_resume") as record:
            self.assertTrue(self.left.routes.handle_verified("left", payload, broker_id="hivemq", generation=1,
                                                            authenticated_identity=self.left_binding.identity))
        record.assert_not_called()
        self.assertEqual(old_remote, peer.remote_epoch)
        self.assertEqual(0, peer.local_confirmed_epoch)
        self.assertFalse(self.left.routes.ready("left"))
        self.assertEqual(before_sent, len(self.left.pool.sent))
        self.left.ready.assert_called_once_with("left")
        self.exchange()
        self.assertTrue(self.left.routes.ready("left"))

    def test_malformed_or_current_mismatched_ack_is_not_treated_as_late(self):
        payload = self.delayed_ack()
        peer = self.left.routes._peers["left"]
        for field, value in (("acknowledged_route_epoch", True), ("acknowledged_route_epoch", "1"),
                             ("acknowledged_route_epoch", 0), ("acknowledged_route_epoch", peer.local.epoch),
                             ("acknowledged_route_epoch", peer.local.epoch + 1),
                             ("acknowledged_resume_id", "invalid"), ("acknowledged_digest", None)):
            with self.subTest(field=field, value=value), patch("mqtt_peer_routes.record_verified_resume") as record:
                changed = dict(payload, **{field: value})
                with self.assertRaises(ValueError):
                    self.left.routes.handle_verified("left", changed, broker_id="hivemq", generation=1,
                                                     authenticated_identity=self.left_binding.identity)
                record.assert_not_called()
        self.assertFalse(self.left.routes.ready("left"))

    def test_missing_local_suback_cannot_accept_resume(self):
        self.left.pool.auto_suback = False
        self.connect(["hivemq"])
        self.right.routes.maintenance()
        payload = self.decoded(self.right)
        self.left.routes.handle_verified("left", payload, broker_id="hivemq", generation=1,
                                         authenticated_identity=self.left_binding.identity)
        self.assertEqual(0, self.left.routes._peers["left"].remote_epoch)

    def test_replay_does_not_extend_authenticated_route_lifetime(self):
        self.connect(["hivemq"])
        self.exchange()
        request = self.right.pool.sent[0]
        original = self.left.routes._peers["left"].remote_epoch
        self.offset = 299
        self.deliver(self.left, request)
        self.assertEqual(original, self.left.routes._peers["left"].remote_epoch)
        self.offset = 301
        self.assertFalse(self.left.routes.ready("left"))
        with self.assertRaises(ValueError):
            self.deliver(self.left, request)

    def test_process_restart_reuses_durable_watermarks_but_not_ready_permission(self):
        self.connect(["hivemq"])
        self.exchange()
        old = self.left.routes._peers["left"].local.epoch
        self.left.client.disconnect()
        self.left = self.endpoint(self.left_binding)
        self.left.pool.connect("hivemq")
        self.assertFalse(self.left.routes.ready("left"))
        self.exchange()
        self.assertGreater(self.left.routes._peers["left"].local.epoch, old)
        self.assertTrue(self.left.routes.ready("left"))

    def test_replaced_pair_retires_old_peer_and_cannot_receive_old_authenticated_callbacks(self):
        self.connect(["hivemq"])
        self.exchange()
        old = self.left.routes._peers["left"]
        binding = replace(self.left_binding, secret=new_link_secret(), receiver="c" * 64)
        self.left.routes.replace([binding])
        self.assertFalse(old.active)
        self.assertFalse(self.left.routes.ready("left"))
        with self.assertRaises(ValueError):
            self.left.routes.handle_verified("left", self.decoded(self.right, 0), broker_id="hivemq", generation=1,
                                             authenticated_identity=self.left_binding.identity)

    def test_revocation_removes_send_mailbox_and_does_not_touch_other_pairs(self):
        self.connect(["hivemq"])
        self.exchange()
        second = replace(self.left_binding, scope="second", send_topic="other")
        self.left.routes.replace([self.left_binding, second])
        self.left.routes.replace([self.left_binding])
        self.assertTrue(self.left.routes.ready("left"))
        self.assertIsNone(self.left.routes.classify("other", b"ciphertext"))

    def test_explicit_pair_replacement_resets_only_that_pairs_old_epoch_watermark(self):
        from mqtt_route_state import issue_local_resume
        self.connect(["hivemq"])
        self.exchange()
        binding = replace(self.left_binding, secret=new_link_secret(), receiver="c" * 64)
        self.left.routes.replace([binding])
        remote = issue_local_resume("replacement-remote", sender=binding.receiver, receiver=binding.sender,
                                    receive_brokers=frozenset({"hivemq"}), now_ms=int(time.time() * 1000))
        self.assertEqual(1, remote.epoch)
        self.left.routes.handle_verified("left", remote.to_wire(), broker_id="hivemq", generation=1,
                                         authenticated_identity=binding.identity)
        self.assertEqual(1, self.left.routes._peers["left"].remote_epoch)
        self.assertFalse(self.left.routes.ready("left"))

    def test_invalid_binding_batch_does_not_partially_revoke_current_pair(self):
        self.connect(["hivemq"])
        self.exchange()
        changed = replace(self.left_binding, secret=new_link_secret())
        conflicting = replace(changed, scope="other")
        with self.assertRaises(ValueError):
            self.left.routes.replace([changed, conflicting])
        self.assertTrue(self.left.routes.ready("left"))
        self.assertEqual(self.left_binding, self.left.routes._peers["left"].binding)

    def test_topic_rotation_requires_new_receive_advertisement(self):
        self.connect(["hivemq"])
        self.exchange()
        original = self.left.routes._peers["left"].local.epoch
        changed = replace(self.left_binding, receive_topics=frozenset({"rotated"}))
        self.left.routes.replace([changed])
        self.assertFalse(self.left.routes.ready("left"))
        self.left.client.subscribe({"rotated": 1})
        self.left.routes.maintenance()
        self.assertGreater(self.left.routes._peers["left"].local.epoch, original)

    def test_database_failure_is_backed_off_and_does_not_block_another_peer(self):
        self.connect(["hivemq"])
        other = replace(self.left_binding, scope="other", send_topic="other")
        self.left.routes.replace([self.left_binding, other])
        with patch("mqtt_peer_routes.issue_local_resume", side_effect=OSError("private error details")) as issue:
            with self.assertLogs("mqtt_peer_routes", level="WARNING") as logs:
                self.left.routes.maintenance()
            self.left.routes.maintenance()
            self.assertEqual(2, issue.call_count)
            self.assertNotIn("private error details", "".join(logs.output))
        self.offset = 6
        self.left.routes.maintenance()
        self.assertEqual({"to-right", "other"}, {packet[2] for packet in self.left.pool.sent})

    def test_failed_bootstrap_publication_does_not_block_other_brokers(self):
        self.connect()
        actual = self.left.routes._publish_control
        def fail_one(binding, payload, broker):
            if broker == "emqx":
                raise OSError("test failure")
            return actual(binding, payload, broker)
        with patch.object(self.left.routes, "_publish_control", side_effect=fail_one):
            with self.assertLogs("mqtt_peer_routes", level="WARNING"):
                self.left.routes.maintenance()
        self.assertEqual({"hivemq", "mosquitto"}, {packet[0] for packet in self.left.pool.sent})

    def test_ten_thousand_peers_use_bounded_fair_admission_across_refreshes(self):
        bindings = [replace(self.left_binding, scope=f"peer-{i}", send_topic=f"out-{i}") for i in range(10000)]
        self.left.routes.replace(bindings)
        visited = []
        def observe(peer, _now):
            visited.append(peer.binding.scope)
            return None
        with patch.object(self.left.routes, "_local_advertisement", side_effect=observe):
            for _ in range(4):
                self.left.routes.maintenance()
                self.left.routes.replace(bindings)
        self.assertEqual(64, len(visited))
        self.assertEqual(64, len(set(visited)))
        self.assertEqual([], self.left.pool.sent)

    def test_real_bridge_ingress_authenticates_resume_without_entering_signal_or_business_dispatch(self):
        import mqtt_bridge
        pairs = {}
        for endpoint in (self.left, self.right):
            binding = endpoint.binding
            endpoint.client.peer_routes = endpoint.routes
            endpoint.client.on_message = mqtt_bridge.on_mqtt_message
            for topic in binding.receive_topics:
                pairs[topic] = ("client", {"client_route_id": binding.scope, "link_secret": binding.secret,
                    "local_identity_fingerprint": binding.sender, "identity_fingerprint": binding.receiver,
                    "signal_name": "phone-" + binding.scope})
        queued = []
        def process(mqttc, identity, message, **_admission):
            queued.append((identity, message.broker_id, message.broker_generation))
            mqtt_bridge._process_message(mqttc, None, message)
            return True
        with (patch.object(mqtt_bridge, "_resolve_inbound_topic", side_effect=pairs.get),
              patch.object(mqtt_bridge, "_queue_inbound_message", side_effect=process),
              patch.object(mqtt_bridge, "decrypt_signal_envelope") as decrypt,
              patch.object(mqtt_bridge, "_dispatch_application_payload") as dispatch):
            self.connect()
            self.exchange()
        self.assertTrue(self.left.routes.ready("left"))
        self.assertTrue(self.right.routes.ready("right"))
        self.assertEqual(BROKER_IDS, {item[1] for item in queued})
        self.assertEqual({"transport:phone-left", "transport:phone-right"}, {item[0] for item in queued})
        decrypt.assert_not_called()
        dispatch.assert_not_called()

    def test_corrupt_packet_rejected_by_real_bridge_before_route_state_changes(self):
        import mqtt_bridge
        self.left.client.peer_routes = self.left.routes
        self.connect(["hivemq"])
        self.right.routes.maintenance()
        packet = self.right.pool.sent[0]
        wire = bytearray(packet[3])
        wire[-8] = ord("A") if wire[-8] != ord("A") else ord("B")
        pair = {"client_route_id": "left", "link_secret": self.left_binding.secret,
                "local_identity_fingerprint": self.left_binding.sender,
                "identity_fingerprint": self.left_binding.receiver, "signal_name": "phone-right"}
        message = SimpleNamespace(topic="to-left", payload=bytes(wire), broker_id="hivemq", broker_generation=1)
        with (patch.object(mqtt_bridge, "_resolve_inbound_topic", return_value=("client", pair)),
              self.assertLogs(mqtt_bridge.log, level="WARNING")):
            mqtt_bridge._process_message(self.left.client, None, message)
        self.assertEqual(0, self.left.routes._peers["left"].remote_epoch)
        self.exchange()
        self.assertTrue(self.left.routes.ready("left"))


if __name__ == "__main__":
    unittest.main()
