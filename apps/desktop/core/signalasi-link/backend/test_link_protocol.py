from __future__ import annotations

import json
import tempfile
import time
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

import link_delivery
import link_protocol
import pairing_state


class LinkProtocolTests(unittest.TestCase):
    def test_route_ids_are_128_bit_base64url(self):
        values = {link_protocol.new_route_id() for _ in range(100)}
        self.assertEqual(100, len(values))
        self.assertTrue(all(link_protocol.valid_route_id(value) for value in values))

    def test_relationship_topics_are_opaque_directional_and_rotating(self):
        secret = link_protocol._b64url_encode(b"k" * 32)
        local = "a" * 64
        remote = "b" * 64
        first = link_protocol.LinkTopics(secret, local, remote, epoch=42)
        second = link_protocol.LinkTopics(secret, local, remote, epoch=43)
        self.assertTrue(link_protocol.valid_topic(first.send))
        self.assertTrue(link_protocol.valid_topic(first.receive))
        self.assertNotIn("/", first.send)
        self.assertNotEqual(first.send, first.receive)
        self.assertNotEqual(first.send, second.send)
        self.assertNotIn("signalasi", first.send.lower())

    def test_receive_window_covers_adjacent_rotation_epochs(self):
        secret = link_protocol._b64url_encode(b"k" * 32)
        topics = link_protocol.LinkTopics(secret, "a" * 64, "b" * 64, epoch=42)
        self.assertEqual(3, len(topics.receive_window))
        self.assertIn(
            link_protocol.relationship_topic(secret, "b" * 64, "a" * 64, epoch=42),
            topics.receive_window,
        )

    def test_application_envelope_validation(self):
        now = int(time.time() * 1000)
        envelope = link_protocol.make_envelope(
            {"type": "text", "content": "hello"}, source_id="source", target_id="target"
        )
        self.assertEqual(envelope, link_protocol.validate_envelope(envelope, now))
        envelope["message_id"] = "not-a-uuid"
        with self.assertRaises(ValueError):
            link_protocol.validate_envelope(envelope, now)

    def test_oversized_text_is_rejected_before_encryption(self):
        with self.assertRaises(ValueError):
            link_protocol.make_envelope(
                {"type": "text", "content": "x" * (link_protocol.MAX_TEXT_BYTES + 1)},
                source_id="source",
                target_id="target",
            )

    def test_pairing_claim_is_confidential_and_bound_to_route(self):
        secret = link_protocol._b64url_encode(b"k" * 32)
        claim = {"type": "signalasi_pairing_claim", "client_name": "Private phone name"}
        wire = link_protocol.encrypt_pairing_claim(claim, secret)
        self.assertNotIn("Private phone name", wire)
        self.assertNotIn("signalasi_pairing_claim", wire)
        self.assertEqual(claim, link_protocol.decrypt_pairing_claim(wire, secret))
        offset = len(wire) // 2
        wire = wire[:offset] + ("A" if wire[offset] != "A" else "B") + wire[offset + 1 :]
        with self.assertRaises(Exception):
            link_protocol.decrypt_pairing_claim(wire, secret)

    def test_wire_padding_hides_small_payload_lengths(self):
        secret = link_protocol._b64url_encode(b"k" * 32)
        first = link_protocol.seal_wire_packet("a", secret)
        second = link_protocol.seal_wire_packet("a" * 500, secret)
        self.assertEqual(len(first), len(second))
        self.assertEqual(b"a", link_protocol.open_wire_packet(first, secret))


class PairingRegistryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.state_path = Path(self.temp.name) / "registry.json"
        self.delivery_path = Path(self.temp.name) / "delivery.db"
        self.state_patch = patch.object(pairing_state, "STATE_PATH", self.state_path)
        self.delivery_patch = patch.object(link_delivery, "DB_PATH", self.delivery_path)
        self.state_patch.start()
        self.delivery_patch.start()
        pairing_state._tokens.clear()

    def record(self, fingerprint: str, remote_name: str, route_id: str) -> dict:
        return pairing_state.record_pairing_success(
            fingerprint,
            remote_name,
            client_route_id=route_id,
            link_secret=link_protocol.new_link_secret(),
            local_identity_fingerprint="f" * 64,
        )

    def tearDown(self):
        self.delivery_patch.stop()
        self.state_patch.stop()
        self.temp.cleanup()

    def test_multiple_clients_coexist_and_revoke_independently(self):
        first_id = link_protocol.new_route_id()
        second_id = link_protocol.new_route_id()
        self.record("a" * 64, "signalasi:first", first_id)
        self.record("b" * 64, "signalasi:second", second_id)
        self.assertEqual(2, pairing_state.pairing_status()["client_count"])
        pairing_state.revoke_client(first_id)
        self.assertIsNone(pairing_state.get_client(first_id))
        self.assertIsNotNone(pairing_state.get_client(second_id))
        self.assertTrue(pairing_state.is_paired())

    def test_clear_pairing_permanently_forgets_only_selected_client(self):
        first_id = link_protocol.new_route_id()
        second_id = link_protocol.new_route_id()
        self.record("a" * 64, "signalasi:first", first_id)
        self.record("b" * 64, "signalasi:second", second_id)

        status = pairing_state.clear_pairing_state(first_id)

        self.assertEqual(1, status["client_count"])
        self.assertIsNone(pairing_state.get_client(first_id, include_revoked=True))
        self.assertIsNotNone(pairing_state.get_client(second_id))
        pairing_state._last_good_state = None
        pairing_state._last_good_path = ""
        self.assertIsNone(pairing_state.get_client(first_id, include_revoked=True))
        self.assertIsNotNone(pairing_state.get_client(second_id))

    def test_clear_all_pairings_removes_revoked_history_too(self):
        first_id = link_protocol.new_route_id()
        second_id = link_protocol.new_route_id()
        self.record("a" * 64, "signalasi:first", first_id)
        self.record("b" * 64, "signalasi:second", second_id)
        pairing_state.revoke_client(first_id)

        pairing_state.clear_pairing_state()

        self.assertEqual([], pairing_state.list_clients(include_revoked=True))
        self.assertFalse(pairing_state.is_paired())

    def test_identity_lookup_only_returns_active_replaced_routes(self):
        first_id = link_protocol.new_route_id()
        second_id = link_protocol.new_route_id()
        other_id = link_protocol.new_route_id()
        fingerprint = "a" * 64
        self.record(fingerprint, "signalasi:shared", first_id)
        self.record(fingerprint, "signalasi:shared", second_id)
        self.record("b" * 64, "signalasi:other", other_id)

        matches = pairing_state.clients_for_identity(
            fingerprint,
            "signalasi:shared",
            exclude_route_id=second_id,
        )
        self.assertEqual([first_id], [client["client_route_id"] for client in matches])
        pairing_state.revoke_client(first_id, "replaced_by_new_pairing")
        self.assertEqual(
            [],
            pairing_state.clients_for_identity(
                fingerprint,
                "signalasi:shared",
                exclude_route_id=second_id,
            ),
        )

    def test_pairing_token_is_one_time(self):
        token = pairing_state.new_pairing_token()
        self.assertTrue(pairing_state.validate_pairing_token(token, consume=True))
        self.assertFalse(pairing_state.validate_pairing_token(token, consume=True))

    def test_pairing_token_claim_can_replay_only_for_the_same_identity_and_route(self):
        pairing = pairing_state.new_pairing_session()
        token = pairing["token"]
        route_id = link_protocol.new_route_id()

        self.assertIsNotNone(pairing_state.claim_pairing_session(token, "a" * 64, route_id))
        self.assertIsNotNone(pairing_state.claim_pairing_session(token, "a" * 64, route_id))
        self.assertIsNone(
            pairing_state.claim_pairing_session(token, "b" * 64, route_id)
        )
        self.assertIsNone(
            pairing_state.claim_pairing_session(
                token,
                "a" * 64,
                link_protocol.new_route_id(),
            )
        )

    def test_duplicate_message_is_claimed_once(self):
        route_id = link_protocol.new_route_id()
        message_id = str(uuid.uuid4())
        self.assertTrue(link_delivery.claim_message(route_id, message_id))
        self.assertFalse(link_delivery.claim_message(route_id, message_id))
        link_delivery.complete_message(route_id, message_id, "accepted", {"status": "accepted"})
        self.assertEqual("accepted", link_delivery.previous_acknowledgement(route_id, message_id)["status"])

    def test_signal_ciphertext_is_bound_to_one_logical_message(self):
        route_id = link_protocol.new_route_id()
        message_id = str(uuid.uuid4())
        digest = "a" * 64

        self.assertIsNone(link_delivery.message_for_ciphertext(route_id, digest))
        link_delivery.bind_ciphertext(route_id, digest, message_id)
        link_delivery.bind_ciphertext(route_id, digest, message_id)

        self.assertEqual(message_id, link_delivery.message_for_ciphertext(route_id, digest))
        with self.assertRaises(ValueError):
            link_delivery.bind_ciphertext(route_id, digest, str(uuid.uuid4()))

    def test_outbound_message_survives_until_client_ack(self):
        route_id = link_protocol.new_route_id()
        message_id = str(uuid.uuid4())
        link_delivery.queue_outbound(route_id, message_id, "topic/down", '{"ciphertext":true}')
        self.assertEqual(1, len(link_delivery.pending_outbound()))
        self.assertEqual("queued", link_delivery.outbound_status(route_id, message_id))
        link_delivery.mark_outbound_published(route_id, message_id)
        self.assertEqual([], link_delivery.pending_outbound())
        self.assertEqual("published", link_delivery.outbound_status(route_id, message_id))
        link_delivery.acknowledge_outbound(route_id, message_id)
        self.assertEqual([], link_delivery.pending_outbound())
        self.assertIsNone(link_delivery.outbound_status(route_id, message_id))


if __name__ == "__main__":
    unittest.main()
