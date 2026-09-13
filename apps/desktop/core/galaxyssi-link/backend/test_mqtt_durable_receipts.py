import json
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import Mock, patch

import link_delivery as delivery
from mqtt_delivery_envelope import content_hash, receipt_binding, stored_receipt


class MqttDurableReceiptsTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="mqtt-receipt-")
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / "delivery.db"
        patcher = patch.object(delivery, "DB_PATH", self.path)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.wire = {"scheme": "signal", "from": "phone", "to": "desktop", "signal_type": "signal", "body": "AQIDBA=="}
        self.binding = receipt_binding("pair", "a" * 64, "b" * 64, "secret")
        self.receipt = stored_receipt("message", content_hash(self.wire))
        self.queue()

    def queue(self, *, route="pair", message="message", wire=None, binding=None):
        delivery.queue_outbound(route, message, "opaque-topic", json.dumps(wire or self.wire),
                                receipt_binding=self.binding if binding is None else binding)

    def test_receipt_binding_survives_reopen_and_is_encrypted_at_rest(self):
        with closing(sqlite3.connect(self.path)) as db:
            proof = db.execute("SELECT receipt_proof FROM outbound_messages").fetchone()[0]
            self.assertNotIn(self.binding, proof)
            self.assertNotIn(self.receipt["content_hash"], proof)
        self.assertTrue(delivery.acknowledge_verified_outbound("pair", self.receipt, self.binding))
        self.assertFalse(delivery.acknowledge_verified_outbound("pair", self.receipt, self.binding))

    def test_wrong_pair_key_or_digest_keeps_original_outbox_row(self):
        for route, binding, receipt in (("other", self.binding, self.receipt),
                                        ("pair", "c" * 64, self.receipt),
                                        ("pair", self.binding, {**self.receipt, "content_hash": "d" * 64}),
                                        ("pair", self.binding, {**self.receipt, "transport_message_id": "other"})):
            self.assertFalse(delivery.acknowledge_verified_outbound(route, receipt, binding))
        self.assertTrue(delivery.outbound_status("pair", "message"))
        self.assertTrue(delivery.acknowledge_verified_outbound("pair", self.receipt, self.binding))

    def test_broker_ack_does_not_retire_durable_message(self):
        delivery.mark_outbound_published("pair", "message")
        self.assertFalse(delivery.acknowledge_verified_outbound("pair", {**self.receipt, "delivery_status": "BROKER_ACKED"}, self.binding))
        self.assertEqual("published", delivery.outbound_status("pair", "message"))

    def test_unbound_rows_cannot_be_acked_from_the_network(self):
        self.queue(message="unbound", binding="")
        self.assertFalse(delivery.acknowledge_verified_outbound("pair", stored_receipt("unbound", self.receipt["content_hash"]), self.binding))
        self.assertTrue(delivery.outbound_status("pair", "unbound"))

    def test_same_message_id_in_another_pair_is_not_removed(self):
        self.queue(route="other")
        self.assertTrue(delivery.acknowledge_verified_outbound("pair", self.receipt, self.binding))
        self.assertTrue(delivery.outbound_status("other", "message"))

    def test_late_old_ciphertext_receipt_cannot_retire_new_ciphertext(self):
        delivery.acknowledge_outbound("pair", "message")
        new_wire = {**self.wire, "body": "AA=="}
        self.queue(wire=new_wire)
        self.assertFalse(delivery.acknowledge_verified_outbound("pair", self.receipt, self.binding))
        self.assertTrue(delivery.acknowledge_verified_outbound("pair", stored_receipt("message", content_hash(new_wire)), self.binding))

    def test_encrypted_proof_copied_to_another_row_cannot_authorize_receipt(self):
        self.queue(message="other-message")
        with closing(sqlite3.connect(self.path)) as db:
            db.execute("UPDATE outbound_messages SET receipt_proof=(SELECT receipt_proof FROM outbound_messages WHERE message_id='message') "
                       "WHERE message_id='other-message'")
            db.commit()
        receipt = stored_receipt("other-message", self.receipt["content_hash"])
        self.assertFalse(delivery.acknowledge_verified_outbound("pair", receipt, self.binding))
        self.assertTrue(delivery.outbound_status("pair", "other-message"))

    def test_receive_hash_cannot_be_changed_and_is_pair_scoped(self):
        wire_hash = self.receipt["content_hash"]
        delivery.bind_ciphertext("pair", "c" * 64, "message", receipt_hash=wire_hash)
        self.assertEqual(wire_hash, delivery.stored_wire_receipt("pair", "message"))
        self.assertEqual("", delivery.stored_wire_receipt("other", "message"))
        with self.assertRaises(ValueError):
            delivery.bind_ciphertext("pair", "c" * 64, "message", receipt_hash="d" * 64)
        self.assertEqual(wire_hash, delivery.stored_wire_receipt("pair", "message"))

    def test_projection_runs_only_after_exact_proof_and_before_retry_state_is_retired(self):
        project = Mock(side_effect=lambda _mid: self.assertIsNotNone(delivery.outbound_status("pair", "message")))
        self.assertFalse(delivery.acknowledge_verified_outbound("pair", {**self.receipt, "content_hash": "d" * 64},
                                                               self.binding, before_retire=project))
        project.assert_not_called()
        self.assertTrue(delivery.acknowledge_verified_outbound("pair", self.receipt, self.binding, before_retire=project))
        project.assert_called_once_with("message")
        self.assertFalse(delivery.acknowledge_verified_outbound("pair", self.receipt, self.binding, before_retire=project))
        project.assert_called_once()

    def test_failed_projection_keeps_ciphertext_for_cross_path_retry(self):
        with self.assertRaises(sqlite3.OperationalError):
            delivery.acknowledge_verified_outbound("pair", self.receipt, self.binding,
                before_retire=Mock(side_effect=sqlite3.OperationalError("projection unavailable")))
        self.assertEqual("queued", delivery.outbound_status("pair", "message"))
        self.assertTrue(delivery.acknowledge_verified_outbound("pair", self.receipt, self.binding))

    def test_retire_failure_after_projection_can_repeat_the_idempotent_projection(self):
        with closing(sqlite3.connect(self.path)) as db:
            db.execute("CREATE TRIGGER reject_retire BEFORE DELETE ON outbound_messages BEGIN SELECT RAISE(ABORT, 'test fault'); END")
        project = Mock()
        with self.assertRaises(sqlite3.IntegrityError):
            delivery.acknowledge_verified_outbound("pair", self.receipt, self.binding, before_retire=project)
        self.assertEqual("queued", delivery.outbound_status("pair", "message"))
        with closing(sqlite3.connect(self.path)) as db:
            db.execute("DROP TRIGGER reject_retire")
        self.assertTrue(delivery.acknowledge_verified_outbound("pair", self.receipt, self.binding, before_retire=project))
        self.assertEqual(2, project.call_count)


if __name__ == "__main__":
    unittest.main()
