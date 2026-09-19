from __future__ import annotations

import copy
import json
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

import link_protocol
import link_delivery
import mqtt_bridge
from link_transport_diagnostics import LinkTransportDiagnostics
from mqtt_receipt_replay_gate import ReceiptReplayGate
from mqtt_decrypt_backoff import DecryptBackoff
from galaxyssi_client import SignalSidecarError
from tests.receive_test_support import store_received_envelope, complete_received_envelope


class FakeMessage:
    def __init__(self, topic: str, payload: dict, link_secret: str) -> None:
        self.topic = topic
        self.payload = link_protocol.seal_wire_packet(
            json.dumps(payload, separators=(",", ":")),
            link_secret,
        ).encode("ascii")
        self.received_at_ms = 1_000


class MqttLinkDiagnosticsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.diagnostics = LinkTransportDiagnostics(
            Path(self.temp.name) / "diagnostics.json"
        )
        self.client_route_id = link_protocol.new_route_id()
        self.desktop_id = "desktop-test"
        self.signal_name = "galaxyssi:test-phone"
        self.link_secret = link_protocol.new_link_secret()
        self.desktop_fingerprint = "a" * 64
        self.phone_fingerprint = "b" * 64
        self.topics = link_protocol.LinkTopics(
            self.link_secret,
            self.desktop_fingerprint,
            self.phone_fingerprint,
        )
        self.client = {
            "client_route_id": self.client_route_id,
            "signal_name": self.signal_name,
            "signal_device_id": 1,
            "link_secret": self.link_secret,
            "local_identity_fingerprint": self.desktop_fingerprint,
            "identity_fingerprint": self.phone_fingerprint,
        }
        self.wire = {
            "version": 1,
            "scheme": "signal",
            "from": self.signal_name,
            "to": self.desktop_id,
            "signal_type": "signal",
            "message_type": 2,
            "body": "ciphertext",
        }
        self.base_patches = [
            patch.object(link_delivery, "DB_PATH", Path(self.temp.name) / "delivery.db"),
            patch.object(mqtt_bridge, "desktop_id", return_value=self.desktop_id),
            patch.object(mqtt_bridge, "get_client", return_value=self.client),
            patch.object(
                mqtt_bridge,
                "_resolve_inbound_topic",
                return_value=("client", self.client),
            ),
            patch.object(
                mqtt_bridge,
                "link_transport_diagnostics",
                return_value=self.diagnostics,
            ),
            patch.object(mqtt_bridge, "_publish_phone_payload", return_value=True),
        ]
        for item in self.base_patches:
            item.start()

    def tearDown(self) -> None:
        for item in reversed(self.base_patches):
            item.stop()
        self.temp.cleanup()

    def stored(self, payload=None):
        envelope = link_protocol.make_envelope(
            payload or {"type": "text", "source_message_id": "210"},
            source_id=self.signal_name, target_id=self.desktop_id)
        complete_received_envelope(self.client_route_id, envelope)
        return envelope["message_id"]

    def test_encrypted_replay_is_visible_before_signal_decrypt(self) -> None:
        message_id = self.stored()
        with (
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=message_id),
            patch.object(mqtt_bridge, "decrypt_signal_envelope") as decrypt,
        ):
            mqtt_bridge.on_message(
                object(),
                None,
                FakeMessage(self.topics.receive, self.wire, self.link_secret),
            )

        decrypt.assert_not_called()
        snapshot = self.diagnostics.snapshot()
        self.assertEqual(1, snapshot["counts"]["encrypted_replay"])
        self.assertEqual(1, snapshot["summary"]["replay"])

    def test_old_signal_counter_is_classified_at_decrypt_boundary(self) -> None:
        with (
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=None),
            patch.object(
                mqtt_bridge,
                "decrypt_signal_envelope",
                side_effect=RuntimeError("Signal sidecar: old counter 12"),
            ),
        ):
            mqtt_bridge.on_message(
                object(),
                None,
                FakeMessage(self.topics.receive, self.wire, self.link_secret),
            )

        snapshot = self.diagnostics.snapshot()
        self.assertEqual(1, snapshot["counts"]["old_counter"])
        self.assertEqual(1, snapshot["summary"]["old_counter"])

    def test_replayed_receipt_does_not_create_ack_of_ack(self) -> None:
        message_id = self.stored({"type": "delivery_ack"})
        with (
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=message_id),
            patch.object(mqtt_bridge, "decrypt_signal_envelope") as decrypt,
            patch.object(mqtt_bridge, "_publish_phone_payload") as publish,
            patch.object(mqtt_bridge, "_start_remote_agent_task") as start_task,
        ):
            mqtt_bridge.on_message(object(), None,
                FakeMessage(self.topics.receive, self.wire, self.link_secret))
        decrypt.assert_not_called()
        publish.assert_not_called()
        start_task.assert_not_called()

    def test_replayed_request_resends_ack_without_executing_again(self) -> None:
        message_id = self.stored()
        now = [0.0]
        with (
            patch.object(mqtt_bridge, "signal_receipt_replay_gate", ReceiptReplayGate(clock=lambda: now[0])),
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=message_id),
            patch.object(mqtt_bridge, "decrypt_signal_envelope") as decrypt,
            patch.object(mqtt_bridge, "_publish_phone_payload") as publish,
            patch.object(mqtt_bridge, "_start_remote_agent_task") as start_task,
        ):
            for _ in range(12):
                mqtt_bridge.on_message(object(), None,
                    FakeMessage(self.topics.receive, self.wire, self.link_secret))
            self.assertEqual(1, publish.call_count)
            now[0] = 3.0
            mqtt_bridge.on_message(object(), None,
                FakeMessage(self.topics.receive, self.wire, self.link_secret))
        self.assertEqual(2, publish.call_count)
        self.assertEqual(message_id, publish.call_args.args[2]["transport_message_id"])
        self.assertEqual("210", publish.call_args.args[2]["client_source_message_id"])
        decrypt.assert_not_called()
        start_task.assert_not_called()

    def test_invalid_ciphertext_backoff_never_acknowledges_or_dispatches(self) -> None:
        now = [0.0]
        failure = SignalSidecarError(500, json.dumps({"error": "InvalidMessageException"}))
        with (
            patch.object(mqtt_bridge, "decrypt_backoff", DecryptBackoff(clock=lambda: now[0])) as gate,
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=None),
            patch.object(mqtt_bridge, "decrypt_signal_envelope", side_effect=failure) as decrypt,
            patch.object(mqtt_bridge, "_publish_phone_payload") as publish,
            patch.object(mqtt_bridge, "_start_remote_agent_task") as dispatch,
        ):
            for _ in range(100):
                mqtt_bridge.on_message(object(), None, FakeMessage(self.topics.receive, self.wire, self.link_secret))
            self.assertEqual(1, decrypt.call_count)
            self.assertEqual(99, gate.snapshot()["deferred"])
            now[0] = 3.0
            mqtt_bridge.on_message(object(), None, FakeMessage(self.topics.receive, self.wire, self.link_secret))
            self.assertEqual(2, decrypt.call_count)
            publish.assert_not_called()
            dispatch.assert_not_called()

    def test_durable_receive_proof_bypasses_negative_cache(self) -> None:
        message_id = self.stored()
        with (
            patch.object(mqtt_bridge, "decrypt_backoff") as gate,
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=message_id),
            patch.object(mqtt_bridge, "decrypt_signal_envelope") as decrypt,
            patch.object(mqtt_bridge, "_publish_phone_payload", return_value=True) as publish,
        ):
            gate.defer.return_value = True
            mqtt_bridge.on_message(object(), None, FakeMessage(self.topics.receive, self.wire, self.link_secret))
            gate.defer.assert_not_called()
            decrypt.assert_not_called()
            publish.assert_called_once()

    def test_missing_durable_receipt_body_cannot_restart_ack_exchange(self) -> None:
        with (
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value="old-receipt"),
            patch.object(mqtt_bridge, "decrypt_signal_envelope") as decrypt,
            patch.object(mqtt_bridge, "_publish_phone_payload") as publish,
        ):
            for _ in range(12):
                mqtt_bridge.on_message(object(), None,
                    FakeMessage(self.topics.receive, self.wire, self.link_secret))
        decrypt.assert_not_called()
        publish.assert_not_called()

    def test_duplicate_application_message_is_visible_and_not_dispatched(self) -> None:
        message_id = str(uuid.uuid4())
        application_envelope = link_protocol.make_envelope(
            {
                "type": "text",
                "message_id": message_id,
                "content": "hello",
            },
            source_id=self.signal_name,
            target_id=self.desktop_id,
            conversation_id="conversation-1",
        )
        complete_received_envelope(self.client_route_id, application_envelope)
        with (
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=None),
            patch.object(
                mqtt_bridge,
                "decrypt_signal_envelope",
                return_value=application_envelope,
            ),
            patch.object(mqtt_bridge, "bind_ciphertext"),
            patch.object(mqtt_bridge, "_start_remote_agent_task") as start_task,
        ):
            mqtt_bridge.on_message(
                object(),
                None,
                FakeMessage(self.topics.receive, self.wire, self.link_secret),
            )

        start_task.assert_not_called()
        snapshot = self.diagnostics.snapshot()
        self.assertEqual(1, snapshot["counts"]["duplicate_message"])
        self.assertEqual(1, snapshot["summary"]["duplicate"])

    def test_content_conflict_is_rejected_before_blob_persistence_or_ack(self) -> None:
        envelope = link_protocol.make_envelope(
            {"type": "text", "content": "original", "contact_id": "system"}, source_id=self.signal_name,
            target_id=self.desktop_id, conversation_id="c1")
        store_received_envelope(self.client_route_id, envelope)
        with (
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=None),
            patch.object(mqtt_bridge, "decrypt_signal_envelope") as decrypt,
            patch("blob_input_bridge.persist_before_ack") as persist,
            patch.object(mqtt_bridge, "bind_ciphertext", wraps=link_delivery.bind_ciphertext) as bind_cipher,
            patch.object(mqtt_bridge, "_publish_phone_payload") as publish,
            patch.object(mqtt_bridge, "_start_remote_agent_task") as task,
        ):
            decrypt.return_value = copy.deepcopy(envelope)
            mqtt_bridge.on_message(object(), None, FakeMessage(self.topics.receive, self.wire, self.link_secret))
            changed = copy.deepcopy(envelope)
            changed["payload"]["content"] = "different content"
            decrypt.return_value = changed
            wire = dict(self.wire, body="different-ciphertext")
            mqtt_bridge.on_message(object(), None, FakeMessage(self.topics.receive, wire, self.link_secret))
        self.assertEqual(1, persist.call_count)
        self.assertEqual(1, bind_cipher.call_count)
        self.assertEqual(1, publish.call_count)
        task.assert_not_called()
        self.assertEqual(1, self.diagnostics.snapshot()["counts"]["message_content_conflict"])

    def test_identity_mismatch_cannot_create_a_content_binding(self) -> None:
        envelope = link_protocol.make_envelope(
            {"type": "text", "content": "untrusted"}, source_id="other-peer",
            target_id=self.desktop_id, conversation_id="c1")
        with (
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=None),
            patch.object(mqtt_bridge, "decrypt_signal_envelope", return_value=envelope),
            patch.object(mqtt_bridge, "bind_message_content") as bind,
            patch("blob_input_bridge.persist_before_ack") as persist,
        ):
            mqtt_bridge.on_message(object(), None, FakeMessage(self.topics.receive, self.wire, self.link_secret))
        bind.assert_not_called()
        persist.assert_not_called()

    def test_multiple_relationship_routes_for_one_signal_peer_share_ingress_lane(self) -> None:
        with (
            patch.object(mqtt_bridge, "_handle_transport_probe_message", return_value=False),
            patch.object(mqtt_bridge, "_resolve_inbound_topic") as resolve,
            patch.object(mqtt_bridge, "_queue_inbound_message", return_value=True) as queue,
        ):
            for route in ("route-a", "route-b", "route-c"):
                resolve.return_value = ("client", dict(self.client, client_route_id=route))
                mqtt_bridge.on_mqtt_message(object(), None, FakeMessage(self.topics.receive, self.wire, self.link_secret))
        self.assertEqual(3, queue.call_count)
        self.assertEqual({"signal:" + self.signal_name}, {call.args[1] for call in queue.call_args_list})

    def test_wrong_recipient_cannot_create_a_content_binding(self) -> None:
        envelope = link_protocol.make_envelope(
            {"type": "text", "content": "wrong target"}, source_id=self.signal_name,
            target_id="another-desktop", conversation_id="c1")
        with (
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=None),
            patch.object(mqtt_bridge, "decrypt_signal_envelope", return_value=envelope),
            patch.object(mqtt_bridge, "bind_message_content") as bind,
            patch("blob_input_bridge.persist_before_ack") as persist,
        ):
            mqtt_bridge.on_message(object(), None, FakeMessage(self.topics.receive, self.wire, self.link_secret))
        bind.assert_not_called()
        persist.assert_not_called()

    def test_missing_configured_signal_identity_is_not_queued(self) -> None:
        with (
            patch.object(mqtt_bridge, "_handle_transport_probe_message", return_value=False),
            patch.object(mqtt_bridge, "_resolve_inbound_topic", return_value=("client", {"client_route_id": "a"})),
            patch.object(mqtt_bridge, "_queue_inbound_message") as queue,
        ):
            self.assertFalse(mqtt_bridge.on_mqtt_message(object(), None,
                FakeMessage(self.topics.receive, self.wire, self.link_secret)))
        queue.assert_not_called()


if __name__ == "__main__":
    unittest.main()
