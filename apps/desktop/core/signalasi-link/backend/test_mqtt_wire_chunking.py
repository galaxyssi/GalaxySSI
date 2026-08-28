from __future__ import annotations

import base64
import json
import unittest

import link_protocol
import mqtt_wire_chunking


def _wire_payload(size: int = 180_000) -> str:
    return json.dumps(
        {
            "scheme": "signal",
            "from": "signalasi:phone",
            "to": "desktop_test",
            "body": "x" * size,
        },
        separators=(",", ":"),
    )


class MqttWireChunkingTests(unittest.TestCase):
    def test_small_encrypted_wire_payload_remains_direct(self) -> None:
        wire = _wire_payload(100)
        self.assertEqual([wire], mqtt_wire_chunking.encode_wire_payload(wire))

    def test_payload_below_largest_wire_bucket_remains_direct(self) -> None:
        wire = _wire_payload(50_000)
        packets = mqtt_wire_chunking.encode_wire_payload(wire)

        self.assertEqual(1, len(packets))
        self.assertEqual(wire, packets[0])

    def test_four_hundred_eighty_three_kib_payload_uses_one_mqtt_packet(self) -> None:
        wire = _wire_payload(483 * 1024)
        packets = mqtt_wire_chunking.encode_wire_payload(wire)

        self.assertEqual(1, len(packets))
        self.assertEqual(wire, packets[0])

    def test_large_payload_round_trips_out_of_order_with_duplicates(self) -> None:
        wire = _wire_payload(700_000)
        packets = mqtt_wire_chunking.encode_wire_payload(wire)
        self.assertEqual(6, len(packets))
        self.assertEqual(
            mqtt_wire_chunking.CHUNK_DATA_BYTES,
            len(base64.b64decode(json.loads(packets[0])["data"])),
        )
        self.assertTrue(all(len(packet.encode("utf-8")) <= mqtt_wire_chunking.MAX_PACKET_BYTES for packet in packets))

        assembler = mqtt_wire_chunking.MqttWireChunkAssembler()
        decoded = [json.loads(packet) for packet in packets]
        self.assertIsNone(assembler.accept("route", decoded[-1]))
        self.assertIsNone(assembler.accept("route", decoded[-1]))
        result = None
        for packet in decoded[:-1]:
            result = assembler.accept("route", packet)
        self.assertEqual(wire, result)

    def test_receiver_still_accepts_legacy_24_kib_chunks(self) -> None:
        wire = _wire_payload()
        packets = mqtt_wire_chunking.encode_wire_payload(
            wire,
            direct_limit_bytes=1,
            chunk_data_bytes=24 * 1024,
        )
        assembler = mqtt_wire_chunking.MqttWireChunkAssembler()
        result = None

        for packet in packets:
            result = assembler.accept("route", json.loads(packet))

        self.assertEqual(wire, result)

    def test_four_hundred_eighty_three_kib_envelope_uses_one_512_kib_bucket_packet(self) -> None:
        packets = mqtt_wire_chunking.encode_wire_payload(_wire_payload(483 * 1024))
        secret = link_protocol.new_link_secret()
        sealed = [link_protocol.seal_wire_packet(packet, secret) for packet in packets]
        expected_packet_bytes = ((12 + 512 * 1024 + 16) * 8 + 5) // 6

        self.assertEqual(1, len(packets))
        self.assertTrue(all(len(packet.encode("ascii")) == expected_packet_bytes for packet in sealed))

    def test_modified_chunk_is_rejected_before_reassembly(self) -> None:
        packet = json.loads(mqtt_wire_chunking.encode_wire_payload(_wire_payload(700_000))[0])
        chunk = bytearray(base64.b64decode(packet["data"]))
        chunk[0] ^= 0x01
        packet["data"] = base64.b64encode(chunk).decode("ascii")
        with self.assertRaisesRegex(ValueError, "chunk integrity"):
            mqtt_wire_chunking.MqttWireChunkAssembler().accept("route", packet)

    def test_modified_transfer_is_rejected_by_whole_payload_hash(self) -> None:
        packets = [
            json.loads(packet)
            for packet in mqtt_wire_chunking.encode_wire_payload(_wire_payload(700_000))
        ]
        last = packets[-1]
        chunk = bytearray(base64.b64decode(last["data"]))
        chunk[-1] ^= 0x01
        last["data"] = base64.b64encode(chunk).decode("ascii")
        last["chunk_sha256"] = mqtt_wire_chunking._sha256(bytes(chunk))

        assembler = mqtt_wire_chunking.MqttWireChunkAssembler()
        with self.assertRaisesRegex(ValueError, "transfer integrity"):
            for packet in packets:
                assembler.accept("route", packet)

    def test_conflicting_duplicate_is_rejected(self) -> None:
        packet = json.loads(mqtt_wire_chunking.encode_wire_payload(_wire_payload(700_000))[0])
        assembler = mqtt_wire_chunking.MqttWireChunkAssembler()
        self.assertIsNone(assembler.accept("route", packet))
        duplicate = dict(packet)
        changed = base64.b64decode(duplicate["data"])[:-1] + b"y"
        duplicate["data"] = base64.b64encode(changed).decode("ascii")
        duplicate["chunk_sha256"] = mqtt_wire_chunking._sha256(changed)
        with self.assertRaisesRegex(ValueError, "Conflicting"):
            assembler.accept("route", duplicate)


if __name__ == "__main__":
    unittest.main()
