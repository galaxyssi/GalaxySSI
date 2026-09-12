import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

import link_delivery
from mqtt_broker_catalog import BROKER_IDS
from mqtt_route_state import (
    ResumeResult, RouteAdvertisement, forget_route, issue_local_resume, load_verified_resume,
    parse_verified_resume, record_verified_resume,
)


class RouteStateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.patch = patch.object(link_delivery, "DB_PATH", Path(self.temp.name) / "delivery.db")
        self.patch.start()
        self.sender, self.receiver = "a" * 64, "b" * 64

    def tearDown(self):
        self.patch.stop()
        self.temp.cleanup()

    def issue(self, peer="peer", now=1000, brokers=BROKER_IDS):
        return issue_local_resume(peer, sender=self.sender, receiver=self.receiver,
                                  receive_brokers=brokers, now_ms=now)

    def parse(self, payload, now=1000):
        return parse_verified_resume(payload, sender=self.sender, receiver=self.receiver, now_ms=now)

    def test_roundtrip_contains_only_fully_automatic_v1_capabilities(self):
        advertisement = self.issue()
        self.assertEqual(advertisement, self.parse(advertisement.to_wire()))
        self.assertEqual(BROKER_IDS, set(advertisement.to_wire()["supported_brokers"]))
        self.assertNotIn("default_broker", advertisement.to_wire())

    def test_canonical_digest_matches_android_contract_vector(self):
        advertisement = RouteAdvertisement(self.sender, self.receiver, 1, "c" * 32, 1000, 301000, BROKER_IDS, 1048576)
        self.assertEqual("37f78495c5b244fdd53a9b6441eb50bc0d34807729a52b1e72b583b23cdb4c5f", advertisement.digest())

    def test_epoch_is_durable_and_isolated_per_pair(self):
        self.assertEqual(1, self.issue().epoch)
        self.assertEqual(2, self.issue().epoch)
        self.assertEqual(1, self.issue("other").epoch)
        self.assertEqual(3, self.issue().epoch)

    def test_parallel_epoch_updates_are_unique(self):
        with ThreadPoolExecutor(max_workers=10) as executor:
            epochs = list(executor.map(lambda _: self.issue().epoch, range(30)))
        self.assertEqual(list(range(1, 31)), sorted(epochs))

    def test_received_epoch_survives_reload_and_rejects_rollback(self):
        old, latest = self.issue(), self.issue()
        self.assertEqual(ResumeResult.NEW, record_verified_resume("peer", latest, now_ms=1000))
        self.assertEqual(latest, load_verified_resume("peer", sender=self.sender, receiver=self.receiver, now_ms=1001))
        self.assertEqual(ResumeResult.STALE, record_verified_resume("peer", old, now_ms=1001))

    def test_duplicate_does_not_refresh_expiry_or_allow_changed_receive_set(self):
        original = self.issue()
        record_verified_resume("peer", original, now_ms=1000)
        self.assertEqual(ResumeResult.DUPLICATE, record_verified_resume("peer", original, now_ms=2000))
        changed = replace(original, receive_brokers=frozenset({"emqx"}))
        self.assertEqual(ResumeResult.CONFLICT, record_verified_resume("peer", changed, now_ms=2000))
        self.assertIsNone(load_verified_resume("peer", sender=self.sender, receiver=self.receiver, now_ms=301_000))

    def test_expired_routes_keep_epoch_watermark(self):
        original = self.issue()
        record_verified_resume("peer", original, now_ms=1000)
        self.assertIsNone(load_verified_resume("peer", sender=self.sender, receiver=self.receiver, now_ms=500_000))
        replay = replace(original, issued_at_ms=500_000, expires_at_ms=800_000)
        self.assertEqual(ResumeResult.CONFLICT, record_verified_resume("peer", replay, now_ms=500_000))

    def test_wrong_identity_or_direction_is_rejected(self):
        payload = self.issue().to_wire()
        payload["sender_fingerprint"], payload["receiver_fingerprint"] = self.receiver, self.sender
        with self.assertRaises(ValueError):
            self.parse(payload)

    def test_legacy_or_partial_protocol_is_not_accepted(self):
        for change in [{"transport_version": 0}, {"transport_version": True}, {"multipath": False},
                       {"chunk_acks": False}, {"supported_brokers": ["emqx"]}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.parse(self.issue().to_wire() | change)

    def test_strict_integer_and_bound_validation(self):
        for change in [{"route_epoch": True}, {"route_epoch": 0}, {"route_epoch": 1.0},
                       {"route_epoch": 9_007_199_254_740_992}, {"max_encoded_packet_bytes": 1_048_577},
                       {"max_encoded_packet_bytes": 0}, {"expires_at_ms": 999},
                       {"expires_at_ms": 1_000_000}, {"issued_at_ms": -1}, {"resume_id": "bad"},
                       {"receive_brokers": ["emqx", "emqx"]}, {"receive_brokers": ["unknown"]},
                       {"receive_brokers": "emqx"}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.parse(self.issue().to_wire() | change)

    def test_empty_receive_set_is_a_valid_withdrawal(self):
        self.assertEqual(frozenset(), self.parse(self.issue(brokers=frozenset()).to_wire()).receive_brokers)

    def test_broker_order_does_not_change_capability_digest(self):
        advertisement = self.issue()
        payload = advertisement.to_wire()
        payload["receive_brokers"].reverse()
        payload["supported_brokers"].reverse()
        self.assertEqual(advertisement.digest(), self.parse(payload).digest())

    def test_revocation_does_not_delete_other_peers_or_business_outbox(self):
        original = self.issue()
        record_verified_resume("peer", original, now_ms=1000)
        record_verified_resume("other", self.issue("other"), now_ms=1000)
        link_delivery.queue_outbound("other", "message", "topic", "wire")
        forget_route("peer")
        self.assertIsNone(load_verified_resume("peer", sender=self.sender, receiver=self.receiver, now_ms=1000))
        self.assertIsNotNone(load_verified_resume("other", sender=self.sender, receiver=self.receiver, now_ms=1000))
        self.assertEqual("queued", link_delivery.outbound_status("other", "message"))


if __name__ == "__main__":
    unittest.main()
