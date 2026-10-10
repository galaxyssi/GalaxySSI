from dataclasses import replace
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import json

import mqtt_bridge as bridge
from mqtt_broker_catalog import BROKER_IDS
from mqtt_multipath_policy import Traffic
from link_protocol import open_wire_packet
import test_mqtt_transient_priority as fixtures


class TransientPathRaceTest(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.TransientPriorityTest()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.client = self.fixture.client
        self.pool = self.fixture.endpoint.pool

    def send(self, encoded=b"same-encrypted-packet", traffic=Traffic.CONTROL):
        descriptor = self.fixture.publication(traffic, encoded)
        return self.client.publish_transient_control("to-right", encoded, publication=descriptor)

    def test_small_control_uses_all_authorized_paths_with_identical_bytes(self):
        result = self.send()
        self.assertEqual(0, result.rc)
        self.assertEqual(set(BROKER_IDS), {item[0] for item in self.pool.sent})
        self.assertEqual(3, len(self.pool.sent))
        self.assertEqual({b"same-encrypted-packet"}, {item[3] for item in self.pool.sent})
        self.assertEqual(3, self.client.policy.diagnostics()["inflight_packets"])

    def test_capacity_reserve_is_shared_not_multiplied_by_paths(self):
        self.fixture.fill_ordinary_slots()
        self.assertEqual(0, self.send().rc)
        self.assertEqual(4, len(self.pool.sent))
        self.assertNotEqual(0, self.send(b"next-request").rc)
        self.assertEqual(4, self.client.policy.diagnostics()["inflight_packets"])

    def test_large_pages_and_receipts_stay_single_path(self):
        for encoded, traffic in ((b"receipt", Traffic.RECEIPT),
                                 (b"x" * self.client.policy.limits.small_packet_bytes, Traffic.CONTROL)):
            before = len(self.pool.sent)
            self.assertEqual(0, self.send(encoded, traffic).rc)
            self.assertEqual(before + 1, len(self.pool.sent))

    def test_each_copy_revalidates_generation_and_revocation(self):
        descriptor = self.fixture.publication(encoded=b"packet")
        original = descriptor.on_path
        checked = []
        def authorize(broker, generation):
            checked.append((broker, generation))
            original(broker, generation)
            self.fixture.endpoint.routes._peers["left"].active = False
        descriptor = replace(descriptor, on_path=authorize)
        result = self.client.publish_transient_control("to-right", b"packet", publication=descriptor)
        self.assertEqual(0, result.rc)
        self.assertEqual(1, len(self.pool.sent))
        self.assertEqual(3, len(checked))
        self.assertEqual(1, self.client.policy.diagnostics()["inflight_packets"])

    def test_revocation_before_first_copy_cannot_publish(self):
        descriptor = self.fixture.publication(encoded=b"packet")
        self.fixture.endpoint.routes._peers["left"].active = False
        with self.assertRaisesRegex(ValueError, "route changed"):
            self.client.publish_transient_control("to-right", b"packet", publication=descriptor)
        self.assertEqual([], self.pool.sent)
        self.assertEqual(0, self.client.policy.diagnostics()["inflight_packets"])

    def test_one_failed_physical_path_does_not_prevent_other_copies(self):
        original = self.pool.publish
        failed = []
        def publish(broker, *args, **kwargs):
            if not failed:
                failed.append(broker)
                return None
            return original(broker, *args, **kwargs)
        with patch.object(self.pool, "publish", side_effect=publish):
            self.assertEqual(0, self.send().rc)
        self.assertEqual(2, len(self.pool.sent))
        self.assertNotIn(failed[0], {item[0] for item in self.pool.sent})

    def test_broker_ack_failure_is_scoped_to_its_copy_and_releases_all_slots(self):
        self.assertEqual(0, self.send().rc)
        logicals = [item[4] for item in self.pool.sent]
        self.pool.ack(logicals[-1], False)
        for logical in logicals[:-1]:
            self.pool.ack(logical, True)
        self.assertEqual(0, self.client.policy.diagnostics()["inflight_packets"])
        self.assertEqual({}, self.client._publications)
        self.assertEqual({}, self.pool.pending)

    def test_only_current_authorized_path_is_used_after_reconnect(self):
        descriptor = self.fixture.publication(encoded=b"packet")
        blocked = descriptor.authorized_paths[0][0]
        self.pool.lose(blocked)
        self.pool.connect(blocked, 2)
        self.assertEqual(0, self.client.publish_transient_control("to-right", b"packet", publication=descriptor).rc)
        self.assertNotIn(blocked, {item[0] for item in self.pool.sent})
        self.assertEqual(2, len(self.pool.sent))

    def test_one_path_generation_race_does_not_block_other_authorized_paths(self):
        descriptor = self.fixture.publication(encoded=b"packet")
        original = descriptor.on_path
        changed = []
        def authorize(broker, generation):
            if not changed:
                changed.append(broker)
                self.pool.lose(broker)
                self.pool.connect(broker, generation + 1)
            original(broker, generation)
        descriptor = replace(descriptor, on_path=authorize)
        self.assertEqual(0, self.client.publish_transient_control("to-right", b"packet", publication=descriptor).rc)
        self.assertEqual(2, len(self.pool.sent))
        self.assertNotIn(changed[0], {item[0] for item in self.pool.sent})

    def test_registered_query_encrypts_once_and_races_same_wire_without_outbox(self):
        binding = self.fixture.endpoint.binding
        paired = {"client_route_id": binding.scope, "signal_name": "phone", "link_secret": binding.secret,
                  "local_identity_fingerprint": binding.sender, "identity_fingerprint": binding.receiver}
        wire = {"scheme": "signal", "from": "desktop", "to": "phone", "body": "synthetic-ciphertext"}
        with patch.object(bridge, "desktop_id", return_value="desktop"), \
                patch.object(bridge, "_topics_for_client", return_value=SimpleNamespace(send="to-right")), \
                patch.object(bridge, "encrypt_signal_payload", return_value=wire) as encrypt, \
                patch.object(bridge, "queue_outbound") as queue:
            result = bridge._publish_to_registered_client(self.client, paired,
                {"type": "agent_task_evidence", "request_id": "fixture"}, durable=False)
        self.assertEqual(0, result.rc)
        encrypt.assert_called_once()
        queue.assert_not_called()
        self.assertEqual(3, len(self.pool.sent))
        self.assertEqual(1, len({item[3] for item in self.pool.sent}))
        self.assertEqual(wire, json.loads(open_wire_packet(self.pool.sent[0][3], binding.secret)))
