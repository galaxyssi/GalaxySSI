import json
import unittest
from dataclasses import replace
from unittest.mock import Mock

from mqtt_broker_catalog import BROKER_IDS, CATALOG
from mqtt_broker_pool import PublishReceipt
from mqtt_delivery_dispatch import Delivery
from mqtt_delivery_envelope import Attempt, Frame, Message
from mqtt_multipath_policy import PeerRoute, PhysicalKey
from mqtt_pool_client import MqttPoolClient
from tests.mqtt_pool_fixture import ManualPool


class DeliveryDispatchTest(unittest.TestCase):
    def setUp(self):
        self.now = 100.0
        self.client = MqttPoolClient(classify_publication=lambda *_: None, pool_factory=ManualPool, clock=lambda: self.now)
        self.addCleanup(self.client.disconnect)
        self.pool = self.client._pool
        self.client.subscribe("inbox")
        for broker in BROKER_IDS:
            self.pool.connect(broker)
        self.client.policy.accept_verified_resume("peer", PeerRoute(1, BROKER_IDS, 1048576, True, 300), now=self.now)
        self.client.on_publish = Mock()
        self.authorized = Mock(return_value=True)

    def delivery(self, message_id="message", traffic="message", **changes):
        message = Message(message_id, "a" * 64, "b" * 64, "c" * 64, traffic)
        return replace(Delivery("peer", message, frozenset({"inbox"}),
                       lambda frame: json.dumps(frame.metadata()), self.authorized, 2048), **changes)

    def send(self, delivery=None):
        return self.client.publish_delivery("outbox", delivery or self.delivery())

    def frame(self, index=-1):
        packet = json.loads(self.pool.sent[index][3])
        return Frame(Message(packet["message_id"], packet["content_hash"], packet["sender"], packet["receiver"], packet["traffic"]),
                     Attempt(packet["attempt_id"], packet["broker_id"], packet["generation"]))

    def tick(self, seconds):
        self.now += seconds
        self.client._tick()

    def test_puback_completes_logical_token_but_does_not_cancel_delayed_copies(self):
        info = self.send()
        self.assertTrue(info.is_published())
        self.assertEqual(1, len(self.pool.sent))
        self.tick(0.499)
        self.assertEqual(1, len(self.pool.sent))
        self.tick(0.001)
        self.assertEqual(2, len(self.pool.sent))
        self.tick(0.5)
        self.assertEqual(3, len(self.pool.sent))
        self.assertEqual(BROKER_IDS, {packet[0] for packet in self.pool.sent})
        self.assertEqual(3, len({self.frame(index).attempt.attempt_id for index in range(3)}))
        self.assertEqual(1, self.client.on_publish.call_count)
        self.assertTrue(self.client.policy.pending("peer", "message"))

    def test_verified_storage_cancels_only_unsent_copies(self):
        self.send()
        commit = Mock()
        self.assertTrue(self.client.delivery.accept_verified_receipt("peer", self.frame(), commit))
        self.tick(2)
        self.assertEqual(1, len(self.pool.sent))
        commit.assert_called_once()
        self.assertFalse(self.client.policy.pending("peer", "message"))
        self.assertEqual(0, self.client.delivery.diagnostics()["messages"])

    def test_critical_control_races_all_paths_and_keeps_physical_slots_until_puback(self):
        self.pool.auto_ack = False
        info = self.send(self.delivery(traffic="control"))
        self.assertEqual(3, len(self.pool.sent))
        self.assertFalse(info.is_published())
        self.assertTrue(self.client.delivery.accept_verified_receipt("peer", self.frame(), Mock()))
        self.assertEqual(3, self.client.policy.diagnostics()["inflight_packets"])
        for mid in list(self.pool.pending):
            self.pool.ack(mid)
        self.tick(0)
        self.assertEqual(0, self.client.policy.diagnostics()["inflight_packets"])
        self.assertEqual(1, self.client.on_publish.call_count)

    def test_wrong_attempt_message_hash_pair_path_or_generation_never_commits(self):
        self.send()
        original = self.frame()
        variants = [replace(original, attempt=replace(original.attempt, attempt_id="f" * 32)),
                    replace(original, attempt=replace(original.attempt, generation=2)),
                    replace(original, attempt=replace(original.attempt, broker_id=next(b for b in BROKER_IDS if b != original.attempt.broker_id))),
                    replace(original, message=replace(original.message, message_id="other")),
                    replace(original, message=replace(original.message, content_hash="d" * 64)),
                    replace(original, message=replace(original.message, receiver="d" * 64))]
        commit = Mock()
        for frame in variants:
            self.assertFalse(self.client.delivery.accept_verified_receipt("peer", frame, commit))
        self.assertFalse(self.client.delivery.accept_verified_receipt("other-peer", original, commit))
        commit.assert_not_called()
        self.tick(1)
        self.assertEqual(3, len(self.pool.sent))

    def test_failed_durable_commit_does_not_cancel_retry(self):
        self.send()
        with self.assertRaises(OSError):
            self.client.delivery.accept_verified_receipt("peer", self.frame(), Mock(side_effect=OSError("disk")))
        self.tick(0.5)
        self.assertEqual(2, len(self.pool.sent))

    def test_verified_legacy_stored_ack_cancels_without_inventing_path_rtt(self):
        self.send()
        self.client.delivery.accept_verified_message("peer", "message", "a" * 64)
        self.tick(1)
        self.assertEqual(1, len(self.pool.sent))
        self.assertEqual({}, self.client.policy._rtt)

    def test_wrong_stored_message_hash_does_not_cancel(self):
        self.send()
        self.client.delivery.accept_verified_message("peer", "message", "d" * 64)
        self.tick(1)
        self.assertEqual(3, len(self.pool.sent))

    def test_duplicate_receipt_does_not_repeat_commit_or_rtt_sample(self):
        self.send()
        frame = self.frame()
        commit = Mock()
        self.assertTrue(self.client.delivery.accept_verified_receipt("peer", frame, commit))
        self.assertFalse(self.client.delivery.accept_verified_receipt("peer", frame, commit))
        commit.assert_called_once()
        self.assertEqual(1, len(self.client.policy._rtt[("peer", frame.attempt.broker_id)]))

    def test_pair_revocation_between_initial_send_and_hedge_blocks_both_copies(self):
        self.send()
        self.authorized.return_value = False
        self.tick(1)
        self.assertEqual(1, len(self.pool.sent))

    def test_subscription_revocation_blocks_hedges(self):
        self.send()
        self.client.unsubscribe("inbox")
        self.tick(1)
        self.assertEqual(1, len(self.pool.sent))

    def test_stale_route_expiry_blocks_hedges(self):
        self.send()
        self.client.policy.forget_peer("peer")
        self.tick(1)
        self.assertEqual(1, len(self.pool.sent))

    def test_old_generation_cannot_send_after_reconnect(self):
        self.send()
        first = self.pool.sent[0][0]
        for broker in BROKER_IDS - {first}:
            self.pool.lose(broker)
            self.pool.connect(broker, 2)
        self.tick(1)
        self.assertEqual(1, len(self.pool.sent))

    def test_progress_and_large_payloads_do_not_broadcast(self):
        self.send(self.delivery("progress", "progress"))
        self.send(self.delivery("large", size_bound=CATALOG["limits"]["small_packet_bytes"] + 1))
        self.tick(2)
        self.assertEqual(2, len(self.pool.sent))

    def test_repeated_outbox_call_reuses_one_live_round(self):
        first = self.send()
        second = self.send()
        self.assertIs(first, second)
        self.assertEqual(1, len(self.pool.sent))

    def test_outbox_retry_after_observation_expiry_starts_new_round(self):
        first = self.send()
        self.tick(31)
        second = self.send()
        self.assertIsNot(first, second)
        self.assertEqual(2, len(self.pool.sent))
        self.assertEqual(1, self.client.delivery.diagnostics()["messages"])

    def test_one_peer_cannot_cancel_other_peer_copies(self):
        self.send()
        other = replace(self.delivery(), peer="other")
        self.client.policy.accept_verified_resume("other", PeerRoute(1, BROKER_IDS, 1048576, True, 300), now=self.now)
        self.send(other)
        self.client.delivery.accept_verified_receipt("other", self.frame(), Mock())
        self.tick(1)
        self.assertEqual(4, len(self.pool.sent))

    def test_shared_twelve_slot_limit_and_control_reservation(self):
        self.pool.auto_ack = False
        for index in range(10):
            self.assertEqual(0, self.send(self.delivery(str(index))).rc)
        self.assertNotEqual(0, self.send(self.delivery("overflow")).rc)
        self.send(self.delivery("stop", "control"))
        self.assertEqual(12, self.client.policy.diagnostics()["inflight_packets"])
        self.tick(1)
        self.assertEqual(12, len(self.pool.sent))
        for mid in list(self.pool.pending):
            self.pool.ack(mid)
        self.tick(0.3)
        self.assertEqual("stop", self.frame(12).message.message_id)
        self.assertLessEqual(self.client.policy.diagnostics()["inflight_packets"], 12)

    def test_physical_failure_promotes_backup_without_waiting_full_hedge(self):
        self.pool.auto_ack = False
        info = self.send()
        first = self.pool.sent[0][0]
        self.pool.lose(first)
        self.tick(0.01)
        self.assertEqual(3, len(self.pool.sent))
        self.pool.ack(self.pool.sent[1][4])
        self.assertTrue(info.is_published())

    def test_wrong_puback_generation_cannot_free_slot(self):
        self.pool.auto_ack = False
        self.send()
        frame = self.frame()
        self.client._published(PublishReceipt(1, PhysicalKey(frame.attempt.broker_id, 99, 1), frame.attempt.attempt_id, True))
        self.assertEqual(1, self.client.policy.diagnostics()["inflight_packets"])
        self.client.on_publish.assert_not_called()

    def test_underestimated_final_packet_size_is_rejected_before_publish(self):
        with self.assertRaises(ValueError):
            self.send(self.delivery(size_bound=50))
        self.assertEqual([], self.pool.sent)
        self.assertEqual(0, self.client.delivery.diagnostics()["messages"])

    def test_close_cancels_unsent_copies_and_fails_pending_token_once(self):
        self.pool.auto_ack = False
        info = self.send()
        self.client.disconnect()
        self.tick(2)
        self.assertFalse(info.is_published())
        self.assertEqual(1, len(self.pool.sent))
        self.assertEqual(1, self.client.on_publish.call_count)
        self.assertEqual(0, self.client.delivery.diagnostics()["messages"])
        self.assertEqual(0, self.client.delivery.diagnostics()["tracked_attempts"])

    def test_tick_has_a_bounded_batch_and_rotates_due_messages(self):
        for index in range(32):
            self.send(self.delivery(str(index)))
        self.assertEqual(32, len(self.pool.sent))
        self.tick(1.1)
        self.assertEqual(64, len(self.pool.sent))
        self.tick(0)
        self.assertEqual(96, len(self.pool.sent))
        self.assertEqual(32, len({self.frame(index).message.message_id for index in range(32, 96)}))


if __name__ == "__main__":
    unittest.main()
