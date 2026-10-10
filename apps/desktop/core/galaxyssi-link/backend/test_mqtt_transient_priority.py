"""Real scheduling, paired-route checks and encrypted bridge wire; no public broker."""
from dataclasses import replace
import json
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import mqtt_bridge as bridge
import test_mqtt_peer_routes as fixture
from link_protocol import open_wire_packet, new_link_secret
from mqtt_multipath_policy import Traffic


class TransientPriorityTest(unittest.TestCase):
    def setUp(self):
        self.base = fixture.PeerRouteExchangeTest()
        self.base.setUp()
        self.addCleanup(self.base.doCleanups)
        self.base.connect()
        self.base.exchange()
        self.endpoint = self.base.left
        self.client = self.endpoint.client
        self.client.peer_routes = self.endpoint.routes
        self.client.policy.limits = replace(self.client.policy.limits, inflight_packets=4, control_reserve=1)
        self.endpoint.pool.auto_ack = False
        self.endpoint.pool.sent.clear()

    def publication(self, traffic=Traffic.CONTROL, encoded=b"opaque", identity=None):
        return self.endpoint.routes.transient_publication("to-right", encoded, traffic,
            authenticated_identity=self.endpoint.binding.identity if identity is None else identity)

    def fill_ordinary_slots(self):
        for index in range(3):
            self.assertEqual(0, self.client.publish("to-right", f"ordinary-{index}".encode()).rc)
        self.assertEqual(15, self.client.publish("to-right", b"ordinary-overflow").rc)

    def test_small_query_passes_full_ordinary_lane_but_not_global_capacity(self):
        self.fill_ordinary_slots()
        descriptor = self.publication()
        self.assertEqual(Traffic.CONTROL, descriptor.traffic)
        self.assertEqual(0, self.client.publish("to-right", b"opaque", publication=descriptor).rc)
        self.assertEqual(15, self.client.publish("to-right", b"next", publication=self.publication(encoded=b"next")).rc)
        self.assertEqual(4, len(self.endpoint.pool.sent))

    def test_receipt_passes_full_ordinary_lane(self):
        self.fill_ordinary_slots()
        self.assertEqual(0, self.client.publish("to-right", b"receipt",
            publication=self.publication(Traffic.RECEIPT, b"receipt")).rc)

    def test_large_evidence_does_not_consume_small_control_reserve(self):
        self.fill_ordinary_slots()
        encoded = b"x" * self.client.policy.limits.small_packet_bytes
        descriptor = self.publication(encoded=encoded)
        self.assertEqual(Traffic.MESSAGE, descriptor.traffic)
        self.assertEqual(15, self.client.publish("to-right", encoded, publication=descriptor).rc)

    def test_wrong_pair_and_unconfirmed_epoch_cannot_use_reserve(self):
        self.assertIsNone(self.publication(identity=replace(self.endpoint.binding, secret=new_link_secret()).identity))
        self.endpoint.routes._peers["left"].local_confirmed_epoch = 0
        self.assertIsNone(self.publication())

    def test_revocation_after_classification_is_checked_at_publication(self):
        descriptor = self.publication()
        self.endpoint.routes._peers["left"].active = False
        with self.assertRaisesRegex(ValueError, "route changed"):
            self.client.publish("to-right", b"opaque", publication=descriptor)
        self.assertEqual([], self.endpoint.pool.sent)
        self.assertEqual(0, self.client.policy.diagnostics()["inflight_packets"])

    def test_reconnect_does_not_reuse_a_descriptor_from_old_generation(self):
        descriptor = self.publication()
        for broker in list(self.endpoint.pool.paths):
            self.endpoint.pool.lose(broker)
            self.endpoint.pool.connect(broker, 2)
        self.assertNotEqual(0, self.client.publish("to-right", b"opaque", publication=descriptor).rc)

    def test_registered_query_entrypoint_keeps_priority_and_has_no_second_outbox(self):
        self.fill_ordinary_slots()
        binding = self.endpoint.binding
        paired = {"client_route_id": binding.scope, "signal_name": "phone", "link_secret": binding.secret,
                  "local_identity_fingerprint": binding.sender, "identity_fingerprint": binding.receiver}
        wire = {"scheme": "signal", "from": "desktop", "to": "phone", "body": "synthetic-ciphertext"}
        with patch.object(bridge, "desktop_id", return_value="desktop"), \
                patch.object(bridge, "_topics_for_client", return_value=SimpleNamespace(send="to-right")), \
                patch.object(bridge, "encrypt_signal_payload", return_value=wire), \
                patch.object(bridge, "queue_outbound") as queue:
            result = bridge._publish_to_registered_client(self.client, paired,
                {"type": "collaboration_recall_request", "request_id": "fixture"}, durable=False)
        self.assertEqual(0, result.rc)
        queue.assert_not_called()
        self.assertEqual(wire, json.loads(open_wire_packet(self.endpoint.pool.sent[-1][3], binding.secret)))
        self.assertEqual(Traffic.CONTROL, next(reversed(self.client.policy._attempts.values())).traffic)


if __name__ == "__main__":
    unittest.main()
