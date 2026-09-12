"""Actual Desktop ingress, pair AEAD and SQLite; Signal JNI is a durable fixture."""
import base64
import json
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import link_delivery
from link_protocol import seal_wire_packet
import mqtt_bridge as bridge
from mqtt_delivery_envelope import content_hash
from mqtt_durable_chunks import DurableChunkAssembler
from mqtt_wire_chunking import encode_wire_payload
import test_mqtt_stored_dispatch as stored_fixture


class DurableChunkBridgeTest(unittest.TestCase):
    def setUp(self):
        self.base = stored_fixture.MqttStoredDispatchTest()
        self.base.setUp()
        self.addCleanup(self.base.doCleanups)
        self.base.wire["body"] = "x" * 700_000
        self.wire = json.dumps(self.base.wire, separators=(",", ":"))
        self.parts = [json.loads(value) for value in encode_wire_payload(self.wire)]
        self.store = DurableChunkAssembler(lambda: link_delivery._connect())
        self.base.stack.enter_context(patch.object(bridge, "inbound_chunk_assembler", self.store))
        self.scope = bridge._receipt_binding_for_client(self.base.paired)
        self.transfer = self.parts[0]["transfer_id"]

    def send(self, part, topic="current-receive-topic", broker="hivemq"):
        packet = SimpleNamespace(topic=topic, broker_id=broker, broker_generation=1,
            payload=seal_wire_packet(json.dumps(part), self.base.paired["link_secret"]).encode())
        bridge.on_message(object(), None, packet)

    def test_disconnect_and_topic_rotation_preserve_partial_then_handoff_once(self):
        self.send(self.parts[0])
        self.base.decrypt.assert_not_called()
        self.base.publish.assert_not_called()
        bridge._clear_mqtt_wire_transport_state()
        reopened = DurableChunkAssembler(lambda: link_delivery._connect())
        self.assertEqual((0,), reopened.stored_indices(self.scope, self.transfer))
        with patch.object(bridge, "inbound_chunk_assembler", reopened):
            self.send(self.parts[1], topic="next-receive-topic", broker="emqx")
        self.base.log.error.assert_not_called()
        self.base.decrypt.assert_called_once()
        self.base.handle.assert_called_once()
        self.assertEqual(content_hash(self.base.wire), link_delivery.stored_wire_receipt("pair", self.base.mid))
        self.assertEqual((), reopened.stored_indices(self.scope, self.transfer))
        for part in self.parts:
            self.send(part, broker="mosquitto")
        self.base.decrypt.assert_called_once()
        self.base.handle.assert_called_once()
        self.assertEqual(("dispatched", 1), self.base.state())

    def test_corrupt_first_copy_cannot_poison_the_durable_transfer(self):
        self.send({**self.parts[0], "data": base64.b64encode(b"invalid").decode()})
        self.base.decrypt.assert_not_called()
        self.assertEqual((), self.store.stored_indices(self.scope, self.transfer))
        for part in self.parts:
            self.send(part)
        self.base.handle.assert_called_once()

    def test_completed_wire_survives_missing_signal_handoff_without_reuploading_all_parts(self):
        self.base.decrypt.side_effect = lambda *_args, **_kwargs: self.base.envelope
        for part in self.parts:
            self.send(part)
        self.base.handle.assert_not_called()
        self.base.publish.assert_not_called()
        self.assertEqual((0, 1), self.store.stored_indices(self.scope, self.transfer))
        self.base.decrypt.side_effect = self.base.receive
        self.send(self.parts[-1])
        self.base.handle.assert_called_once()
        self.assertEqual((), self.store.stored_indices(self.scope, self.transfer))


if __name__ == "__main__":
    unittest.main()
