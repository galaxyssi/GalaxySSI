import copy
from contextlib import closing
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import uuid
from unittest.mock import patch

import link_delivery as delivery
import link_protocol
import signal_receive_dispatch as dispatch
import signal_receive_handoff as handoff


class ReceiveCompactionTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="galaxyssi-receive-compaction-")
        self.addCleanup(temp.cleanup)
        override = patch.object(delivery, "DB_PATH", Path(temp.name) / "delivery.db")
        override.start()
        self.addCleanup(override.stop)
        self.envelope = link_protocol.make_envelope(
            {"type": "input_attachment_chunk", "data_b64": "x" * 350000,
             "source_message_id": "original", "contact_id": "desktop"},
            source_id="phone", target_id="desktop")
        self.mid = self.envelope["message_id"]
        self.receipt = self.persist(self.envelope)
        delivery.bind_ciphertext("pair", "cipher", self.mid, receipt_hash="a" * 64)

    def persist(self, envelope, cipher="native-cipher"):
        plain = json.dumps(envelope)
        receipt = {"plaintext": plain, "contentHash": hashlib.sha256(plain.encode()).hexdigest(),
                   "receiveDigest": hashlib.sha256(cipher.encode()).hexdigest()}
        handoff.persist_receive("pair", "phone", 1, receipt)
        return receipt

    def release(self, receipt=None):
        handoff.mark_released("pair", "phone", 1, (receipt or self.receipt)["receiveDigest"])

    def finish(self, error=None):
        with dispatch.DispatchGuard("pair", self.mid) as guard:
            claim = dispatch.begin(guard, self.envelope)
            dispatch.finish(guard, claim, error=error, replayable=True)

    def completed(self):
        from signal_receive_compaction import completed_envelope
        return completed_envelope("pair", self.mid)

    def test_success_reclaims_large_body_but_keeps_dedup_and_receipt(self):
        self.release()
        self.finish()
        summary = self.completed()
        self.assertEqual(self.mid, summary["message_id"])
        self.assertNotIn("data_b64", summary["payload"])
        self.assertEqual("original", summary["payload"]["source_message_id"])
        self.assertEqual(self.mid, delivery.message_for_ciphertext("pair", "cipher"))
        self.assertEqual("a" * 64, delivery.stored_wire_receipt("pair", self.mid))
        with closing(delivery._connect()) as db:
            self.assertEqual(0, db.execute("SELECT count(*) FROM inbound_signal_bodies").fetchone()[0])
            usage = db.execute("SELECT byte_count,record_count FROM inbound_signal_usage WHERE scope='total'").fetchone()
            self.assertLess(usage[0], 4096)
            self.assertEqual(1, usage[1])
        with dispatch.DispatchGuard("pair", self.mid) as guard:
            self.assertEqual("dispatched", dispatch.begin(guard, self.envelope).state)
        self.assertEqual([], dispatch.pending())

    def test_no_reclamation_until_both_dispatch_and_native_release_complete(self):
        self.finish()
        self.assertIsNone(self.completed())
        self.assertEqual(self.envelope, dispatch.load_envelope("pair", self.mid))
        self.release()
        self.assertIsNotNone(self.completed())

    def test_retry_and_unbound_cipher_keep_original_body(self):
        self.release()
        self.finish(OSError("retry"))
        self.assertIsNone(self.completed())
        self.assertEqual(self.envelope, dispatch.load_envelope("pair", self.mid))

    def test_missing_wire_proof_does_not_compact(self):
        with closing(delivery._connect()) as db:
            db.execute("DELETE FROM inbound_ciphertexts")
            db.commit()
        self.release()
        self.finish()
        self.assertIsNone(self.completed())

    def test_identical_new_cipher_does_not_recreate_body_or_lose_release(self):
        self.release()
        self.finish()
        receipt = self.persist(self.envelope, "second-cipher")
        self.assertEqual([receipt["receiveDigest"]], [item["receiveDigest"] for item in handoff.pending_releases()])
        self.release(receipt)
        cached = handoff.cached_receive("pair", "phone", 1, receipt["receiveDigest"])
        self.assertTrue(cached["completed"])
        self.assertEqual([], handoff.pending_releases())
        with closing(delivery._connect()) as db:
            self.assertEqual(0, db.execute("SELECT count(*) FROM inbound_signal_bodies").fetchone()[0])

    def test_conflicting_body_cannot_replace_terminal_proof(self):
        self.release()
        self.finish()
        changed = copy.deepcopy(self.envelope)
        changed["payload"]["data_b64"] = "different"
        with self.assertRaises(delivery.InboundContentConflict):
            self.persist(changed, "evil-variant")
        with dispatch.DispatchGuard("pair", self.mid) as guard:
            with self.assertRaises(delivery.InboundContentConflict):
                dispatch.begin(guard, changed)

    def test_completed_proof_is_pair_scoped_and_revoked_with_pair(self):
        from signal_receive_compaction import completed_envelope
        self.release()
        self.finish()
        self.assertIsNone(completed_envelope("other", self.mid))
        delivery.discard_route("pair")
        self.assertIsNone(self.completed())
        with closing(delivery._connect()) as db:
            self.assertEqual(0, db.execute("SELECT count(*) FROM inbound_signal_usage").fetchone()[0])

    def test_corrupt_terminal_proof_is_not_accepted(self):
        self.release()
        self.finish()
        with closing(delivery._connect()) as db:
            db.execute("UPDATE inbound_signal_completed SET proof='corrupt'")
            db.commit()
        with self.assertRaises(Exception):
            self.completed()

    def test_already_queued_recovery_skips_only_verified_completion(self):
        self.release()
        self.finish()
        self.assertIsNone(dispatch.load_envelope("pair", self.mid, skip_completed=True))
        with self.assertRaises(RuntimeError):
            dispatch.load_envelope("pair", self.mid)
        with self.assertRaises(RuntimeError):
            dispatch.load_envelope("other", self.mid, skip_completed=True)

    def test_many_completed_chunks_remain_below_existing_byte_quota(self):
        self.release()
        self.finish()
        with patch.object(handoff, "MAX_PEER_BYTES", 1024 * 1024):
            for index in range(12):
                self.envelope["message_id"] = str(uuid.uuid4())
                self.mid = self.envelope["message_id"]
                self.receipt = self.persist(self.envelope, str(index))
                delivery.bind_ciphertext("pair", "cipher-" + str(index), self.mid, receipt_hash="b" * 64)
                self.release()
                self.finish()
        with closing(delivery._connect()) as db:
            self.assertEqual(13, db.execute("SELECT count(*) FROM inbound_signal_completed").fetchone()[0])
            self.assertLess(db.execute("SELECT byte_count FROM inbound_signal_usage WHERE scope='total'").fetchone()[0], 32768)

    def test_compaction_and_quota_update_roll_back_together(self):
        self.release()
        with patch.object(handoff, "_adjust", side_effect=OSError("accounting failed")):
            with self.assertRaises(OSError):
                self.finish()
        self.assertIsNone(self.completed())
        self.assertEqual(self.envelope, dispatch.load_envelope("pair", self.mid))
        with closing(delivery._connect()) as db:
            self.assertEqual(0, db.execute("SELECT count(*) FROM inbound_signal_completed").fetchone()[0])
            self.assertEqual("running", db.execute("SELECT dispatch_state FROM inbound_messages").fetchone()[0])

    def test_deferred_backlog_is_compacted_before_new_body_budget(self):
        self.release()
        with patch("signal_receive_compaction.compact_in_transaction", return_value=False):
            self.finish()
        self.assertIsNone(self.completed())
        next_envelope = copy.deepcopy(self.envelope)
        next_envelope["message_id"] = str(uuid.uuid4())
        with patch.object(handoff, "MAX_PEER_BYTES", 650000):
            self.persist(next_envelope, "next")
        self.assertIsNotNone(self.completed())
        self.assertEqual(next_envelope, dispatch.load_envelope("pair", next_envelope["message_id"]))

    def test_completed_cache_is_not_returned_as_executable_plaintext(self):
        import base64
        import galaxyssi_client as client
        from signal_receive_compaction import CompletedReceiveReplay
        self.release()
        self.finish()
        response = handoff.cached_receive("pair", "phone", 1, self.receipt["receiveDigest"])
        wire = {"_client_route_id": "pair", "signal_type": "signal", "message_type": 2,
                "body": base64.b64encode(b"cipher").decode()}
        with patch.object(client, "start_signal_sidecar"), patch.object(client, "_request") as request, \
                patch.object(handoff, "cached_receive", return_value=response):
            with self.assertRaises(CompletedReceiveReplay) as replay:
                client.decrypt_signal_envelope(wire, "phone")
        request.assert_not_called()
        self.assertEqual(self.mid, replay.exception.envelope["message_id"])

    def test_misbound_or_unfinished_completed_proof_fails_closed(self):
        self.release()
        self.finish()
        with closing(delivery._connect()) as db:
            db.execute("UPDATE inbound_messages SET dispatch_state='running'")
            db.commit()
        with self.assertRaises(RuntimeError):
            self.completed()


if __name__ == "__main__":
    unittest.main()
