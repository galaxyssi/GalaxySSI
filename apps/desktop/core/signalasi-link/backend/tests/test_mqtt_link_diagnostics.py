from __future__ import annotations

import json
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

import link_protocol
import mqtt_bridge
from link_transport_diagnostics import LinkTransportDiagnostics


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
        self.signal_name = "signalasi:test-phone"
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

    def test_encrypted_replay_is_visible_before_signal_decrypt(self) -> None:
        with (
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value="known-message"),
            patch.object(mqtt_bridge, "previous_acknowledgement", return_value={}),
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
        with (
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=None),
            patch.object(
                mqtt_bridge,
                "decrypt_signal_envelope",
                return_value=application_envelope,
            ),
            patch.object(mqtt_bridge, "bind_ciphertext"),
            patch.object(mqtt_bridge, "claim_message", return_value=False),
            patch.object(mqtt_bridge, "previous_acknowledgement", return_value={}),
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


if __name__ == "__main__":
    unittest.main()
