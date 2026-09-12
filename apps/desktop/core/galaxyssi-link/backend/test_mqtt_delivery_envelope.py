from dataclasses import replace
import unittest

from link_protocol import open_wire_packet, seal_wire_packet
from mqtt_delivery_envelope import (ALGORITHM, FIELD, Attempt, Frame, Message, content_hash,
                                    parse_stored_receipt, parse_verified_frame, parse_verified_receipt,
                                    receipt_binding, stored_receipt)


class MqttDeliveryEnvelopeTest(unittest.TestCase):
    def setUp(self):
        self.wire = {"scheme": "signal", "from": "phone-A", "to": "desktop-B", "signal_type": "prekey",
                     "message_type": 3, "body": "AQIDBA==", "version": 1}
        self.message = Message("message-1", content_hash(self.wire), "a" * 64, "b" * 64, "message")
        self.frame = Frame(self.message, Attempt("c" * 32, "hivemq", 7))

    def test_shared_android_golden_digest(self):
        self.assertEqual("d8d7f88a7543d8bd82fc4d7c364283923a15752ba6d1f23af4903d19a544d581", content_hash(self.wire))
        unicode_wire = {"scheme": "signal", "from": "手机-A", "to": "电脑-B", "signal_type": "signal",
                        "message_type": 2, "body": "AA==", "device_id": 1, "version": 1}
        self.assertEqual("94c78f615ab4f6d1e8120091f1d0e25f57eeb4b2beb94833b1b6507f957f2d3c", content_hash(unicode_wire))

    def test_time_json_order_and_attempt_changes_do_not_change_ciphertext_hash(self):
        changed = dict(reversed(list(self.wire.items())))
        changed.update(time=1.25, _mqtt_delivery={"untrusted": True})
        self.assertEqual(content_hash(self.wire), content_hash(changed))

    def test_each_signal_field_is_bound(self):
        for key, value in self.wire.items():
            with self.subTest(key=key):
                if key == "scheme":
                    with self.assertRaises(ValueError):
                        content_hash({**self.wire, key: "other"})
                else:
                    changed = value + 1 if type(value) is int else value + "x"
                    self.assertNotEqual(content_hash(self.wire), content_hash({**self.wire, key: changed}))

    def test_round_trip_and_cross_path_receipt(self):
        wire = self.frame.attach(self.wire)
        self.assertNotIn(FIELD, self.wire)
        self.assertEqual(self.frame, parse_verified_frame(wire, sender="a" * 64, receiver="b" * 64, ingress_broker="hivemq"))
        receipt = self.frame.receipt_after_store(stored_message_id="message-1", stored_content_hash=self.message.content_hash)
        self.assertEqual(self.frame, parse_verified_receipt(receipt, original_sender="a" * 64, original_receiver="b" * 64))

    def test_pair_and_ingress_are_not_self_reported_authority(self):
        wire = self.frame.attach(self.wire)
        for sender, receiver, broker in (("d" * 64, "b" * 64, "hivemq"), ("a" * 64, "d" * 64, "hivemq"),
                                         ("a" * 64, "b" * 64, "emqx")):
            with self.assertRaises(ValueError):
                parse_verified_frame(wire, sender=sender, receiver=receiver, ingress_broker=broker)

    def test_tampered_wire_and_repeated_wrapping_are_rejected(self):
        wire = self.frame.attach(self.wire)
        with self.assertRaises(ValueError):
            self.frame.attach(wire)
        wire["body"] = "AA=="
        with self.assertRaises(ValueError):
            parse_verified_frame(wire, sender="a" * 64, receiver="b" * 64, ingress_broker="hivemq")

    def test_uncommitted_or_conflicting_message_cannot_produce_receipt(self):
        for message, digest in (("other", self.message.content_hash), ("message-1", "d" * 64)):
            with self.assertRaises(ValueError):
                self.frame.receipt_after_store(stored_message_id=message, stored_content_hash=digest)

    def test_receipt_never_produces_ack_of_ack(self):
        frame = replace(self.frame, message=replace(self.message, traffic="receipt"))
        with self.assertRaises(ValueError):
            frame.receipt_after_store(stored_message_id="message-1", stored_content_hash=self.message.content_hash)

    def test_strict_metadata_types(self):
        for field, values in {"generation": [True, 1.0, "7", 0, -1, 9_007_199_254_740_992],
                              "version": [True, 1.0, "1", 2], "broker_id": ["unknown", []],
                              "traffic": ["unknown", []], "attempt_id": ["", "C" * 32],
                              "content_hash_algorithm": ["sha256", None]}.items():
            for value in values:
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    wire = self.frame.attach(self.wire)
                    wire[FIELD][field] = value
                    parse_verified_frame(wire, sender="a" * 64, receiver="b" * 64, ingress_broker="hivemq")

    def test_durable_receipt_is_not_broker_or_task_ack(self):
        receipt = stored_receipt("message-1", self.message.content_hash)
        self.assertEqual(("message-1", self.message.content_hash), parse_stored_receipt(receipt))
        for status in ("accepted", "BROKER_ACKED", "CHUNK_STORED", "TASK_ACCEPTED", "RUN_FINISHED", ""):
            with self.assertRaises(ValueError):
                parse_stored_receipt({**receipt, "delivery_status": status})
        with self.assertRaises(ValueError):
            parse_stored_receipt({**receipt, "content_hash_algorithm": ""})

    def test_binding_separates_all_identity_components(self):
        original = ["pair", "a" * 64, "b" * 64, "secret"]
        expected = receipt_binding(*original)
        for index in range(4):
            changed = original.copy()
            changed[index] += "x"
            self.assertNotEqual(expected, receipt_binding(*changed))
        self.assertNotEqual(receipt_binding("ab", "c", "d", "e"), receipt_binding("a", "bc", "d", "e"))

    def test_existing_aead_seals_receipt_without_exposing_metadata(self):
        import json
        secret = "A" * 43
        receipt = stored_receipt("message-1", self.message.content_hash)
        sealed = seal_wire_packet(json.dumps(receipt), secret)
        self.assertNotIn("message-1", sealed)
        opened = json.loads(open_wire_packet(sealed, secret))
        self.assertEqual(receipt, opened)
        with self.assertRaises(Exception):
            open_wire_packet(sealed, "B" * 43)


if __name__ == "__main__":
    unittest.main()
