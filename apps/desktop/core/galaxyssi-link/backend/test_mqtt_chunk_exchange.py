"""Actual pool/route/AEAD/publisher/bridge, with manual physical brokers and Signal fixture."""
import json
import time
import unittest
from unittest.mock import patch

import link_delivery
import mqtt_bridge as bridge
import test_mqtt_delivery_bridge as fixture
from link_protocol import open_wire_packet, seal_wire_packet
from mqtt_broker_pool import Ingress
from mqtt_chunk_receipts import OutgoingChunks, Query, PROBE, STATE
from mqtt_delivery_envelope import receipt_binding, content_hash
from mqtt_durable_chunks import DurableChunkAssembler
from mqtt_wire_chunking import encode_wire_payload


class ChunkExchangeTest(unittest.TestCase):
    def setUp(self):
        self.base = fixture.DeliveryBridgeTest()
        self.base.setUp(); self.addCleanup(self.base.doCleanups)
        self.base.base.wire["body"] = "x" * 700000
        self.incoming_wire = json.dumps(self.base.base.wire, separators=(",", ":"))
        self.outgoing_wire = json.dumps({**self.base.base.wire, "from": "desktop", "to": "phone"}, separators=(",", ":"))
        self.receiver = DurableChunkAssembler(link_delivery._connect)
        self.sender = OutgoingChunks(link_delivery._connect)
        self.base.base.stack.enter_context(patch.object(bridge, "inbound_chunk_assembler", self.receiver))
        self.base.base.stack.enter_context(patch.object(bridge, "outbound_chunk_states", self.sender))
        bridge._clear_mqtt_wire_transport_state()

    def decoded(self, packet):
        return json.loads(open_wire_packet(packet[3], self.base.desktop_binding.secret))

    def send_desktop(self):
        before = len(self.base.desktop._pool.sent)
        info = bridge._publish_mqtt_wire_payload(self.base.desktop, "to-phone", self.outgoing_wire,
            self.base.desktop_binding.secret, timing_scope=("pair", self.base.base.mid))
        self.assertTrue(info.is_published())
        return self.base.desktop._pool.sent[before:]

    def phone_stored(self, packet):
        raw = self.decoded(packet)
        query = Query.from_chunk(raw)
        self.receiver.accept("phone-inbound", raw)
        state, _ = self.receiver.snapshot("phone-inbound", query)
        self.base.phone.peer_routes.publish_chunk_state("phone-pair", state,
            authenticated_identity=self.base.phone_binding.identity, broker_id=packet[0], urgent=True)
        self.base.deliver_desktop(self.base.phone._pool.sent[-1])

    def test_actual_sender_retries_only_missing_fragment_on_another_broker(self):
        first = self.send_desktop()
        self.assertEqual(2, len(first))
        self.phone_stored(first[0])
        self.base.base.decrypt.assert_not_called()
        retried = self.send_desktop()
        self.assertEqual(1, len(retried))
        self.assertEqual(1, self.decoded(retried[0])["chunk_index"])
        self.assertNotEqual(first[1][0], retried[0][0])
        self.phone_stored(retried[0])
        self.base.base.log.error.assert_not_called()

    def test_all_fragments_stored_sends_a_small_probe_instead_of_reuploading(self):
        first = self.send_desktop()
        for packet in first:
            self.phone_stored(packet)
        retried = self.send_desktop()
        self.assertEqual(1, len(retried))
        self.assertEqual(PROBE, self.decoded(retried[0])["type"])
        self.assertLess(len(retried[0][3]), 8192)
        self.base.base.decrypt.assert_not_called()
        self.base.base.publish.assert_not_called()

    def send_phone_payload(self, payload):
        descriptor = self.base.phone.peer_routes.chunk_publication("to-desktop", payload,
            authenticated_identity=self.base.phone_binding.identity)
        before = len(self.base.phone._pool.sent)
        info = self.base.phone.publish("to-desktop", seal_wire_packet(json.dumps(payload), self.base.phone_binding.secret), publication=descriptor)
        self.assertTrue(info.is_published())
        self.base.deliver_desktop(self.base.phone._pool.sent[before])

    def test_actual_receiver_stores_then_probes_repeat_receipt_without_decrypt_or_task_repetition(self):
        parts = [json.loads(value) for value in encode_wire_payload(self.incoming_wire)]
        scope = receipt_binding(*self.base.phone_binding.identity)
        query, selected, _ = self.sender.prepare(scope, parts)
        for _, payload in selected:
            self.send_phone_payload(payload)
        self.base.base.decrypt.assert_called_once()
        self.base.base.handle.assert_called_once()
        self.base.base.publish.assert_called_once()
        states = [self.decoded(packet) for packet in self.base.desktop._pool.sent]
        self.assertTrue(all(state["type"] == STATE for state in states))
        self.assertEqual("Aw==", states[-1]["stored_bitmap"])
        self.assertEqual(content_hash(self.base.base.wire), link_delivery.stored_wire_receipt("pair", self.base.base.mid))
        self.send_phone_payload(query.wire())
        self.assertEqual(2, self.base.base.publish.call_count)
        self.base.base.decrypt.assert_called_once()
        self.base.base.handle.assert_called_once()
        self.base.base.log.error.assert_not_called()

    def test_probe_recovers_complete_wire_when_signal_handoff_previously_failed(self):
        self.base.base.decrypt.side_effect = lambda *_args, **_kwargs: self.base.base.envelope
        parts = [json.loads(value) for value in encode_wire_payload(self.incoming_wire)]
        query, selected, _ = self.sender.prepare("phone-inbound", parts)
        for _, payload in selected:
            self.send_phone_payload(payload)
        self.base.base.handle.assert_not_called()
        self.base.base.publish.assert_not_called()
        self.base.base.decrypt.side_effect = self.base.base.receive
        self.send_phone_payload(query.wire())
        self.base.base.handle.assert_called_once()
        self.base.base.publish.assert_called_once()

    def test_stale_connection_generation_cannot_supply_bitmap_receipt(self):
        packet = self.send_desktop()[0]
        raw = self.decoded(packet)
        query = Query.from_chunk(raw)
        state = query.response("a" * 32, 1, (0, 1))
        self.base.desktop._packet(Ingress(packet[0], 99, time.monotonic()), "to-desktop",
            seal_wire_packet(json.dumps(state), self.base.desktop_binding.secret).encode())
        self.assertEqual(2, len(self.send_desktop()))


if __name__ == "__main__":
    unittest.main()
