import json
import unittest
from unittest.mock import Mock, patch

from mqtt_ingress_admission import classify, failure_key


class IngressAdmissionTest(unittest.TestCase):
    def setUp(self):
        self.peer = dict(client_route_id="route", link_secret="secret", signal_name="phone",
                         local_identity_fingerprint="a" * 64)
        self.backoff = Mock()
        self.backoff.defer.return_value = False
        self.digest = Mock(return_value="cipher-sha256")

    def classify(self, wire):
        with patch("mqtt_ingress_admission.open_wire_packet", return_value=json.dumps(wire).encode()):
            return classify(b"sealed", self.peer, self.digest, self.backoff)

    def test_invalid_outer_authentication_cannot_use_dedup_or_negative_cache(self):
        with patch("mqtt_ingress_admission.open_wire_packet", side_effect=ValueError("invalid")):
            with self.assertRaises(ValueError):
                classify(b"bad", self.peer, self.digest, self.backoff)
        self.digest.assert_not_called()
        self.backoff.defer.assert_not_called()

    def test_resealed_signal_retries_use_ciphertext_not_outer_nonce(self):
        wire = dict(scheme="signal", **{"from": "phone", "to": "desktop_" + "a" * 16})
        lane, key, deferred = self.classify(wire)
        self.assertEqual("signal", lane)
        self.assertEqual(failure_key(self.peer, "cipher-sha256"), key)
        self.assertFalse(deferred)
        self.backoff.defer.return_value = True
        self.assertTrue(self.classify(wire)[2])

    def test_only_non_signal_transport_frames_get_the_independent_lane(self):
        for kind in ("link_resume", "link_resume_ack", "link_rx_stored"):
            self.assertEqual("transport", self.classify(dict(type=kind))[0])
        for kind in ("agent_task_cancel", "agent_task", "chunk_state", "anything"):
            self.assertEqual("signal", self.classify(dict(type=kind))[0])
        self.backoff.defer.assert_not_called()

    def test_endpoint_mismatch_cannot_poison_another_peer(self):
        with self.assertRaises(ValueError):
            self.classify(dict(scheme="signal", **{"from": "other", "to": "desktop_" + "a" * 16}))
        self.backoff.defer.assert_not_called()

    def test_rotated_pairing_has_an_independent_failure_cache(self):
        first = failure_key(self.peer, "cipher")
        self.assertNotEqual(first, failure_key({**self.peer, "link_secret": "new"}, "cipher"))


if __name__ == "__main__":
    unittest.main()
