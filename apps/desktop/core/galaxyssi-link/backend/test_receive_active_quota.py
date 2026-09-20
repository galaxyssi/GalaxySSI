from contextlib import closing
import copy
from unittest.mock import patch

import link_delivery as delivery
import signal_receive_compaction as compaction
import signal_receive_dispatch as dispatch
import signal_receive_handoff as handoff
from test_signal_receive_compaction import ReceiveCompactionTest


class ActiveReceiveQuotaTest(ReceiveCompactionTest):
    def test_small_control_history_does_not_exhaust_pending_quota(self):
        self.release()
        self.finish()
        with patch.object(handoff, "MAX_PEER_BYTES", 4096), patch.object(handoff, "MAX_PEER_RECORDS", 2):
            for index in range(100):
                envelope = copy.deepcopy(self.envelope)
                envelope["message_id"] = f"control-{index}"
                envelope["payload"] = {"type": "delivery_ack", "source_message_id": str(index)}
                receipt = self.persist(envelope, f"control-{index}")
                delivery.bind_ciphertext("pair", f"wire-{index}", envelope["message_id"], receipt_hash="c" * 64)
                self.release(receipt)
                with dispatch.DispatchGuard("pair", envelope["message_id"]) as guard:
                    dispatch.finish(guard, dispatch.begin(guard, envelope))
        with closing(delivery._connect()) as db:
            self.assertEqual(101, db.execute("SELECT COUNT(*) FROM inbound_signal_completed").fetchone()[0])
            self.assertEqual(0, db.execute("SELECT COUNT(*) FROM inbound_signal_usage").fetchone()[0])
        self.assertEqual("control-0", delivery.message_for_ciphertext("pair", "wire-0"))
        with dispatch.DispatchGuard("pair", envelope["message_id"]) as guard:
            self.assertEqual("dispatched", dispatch.begin(guard, envelope).state)

    def test_old_quota_migration_preserves_history_and_recovers_small_bodies(self):
        self.release()
        self.finish()
        envelope = copy.deepcopy(self.envelope)
        envelope["message_id"] = "old-small"
        envelope["payload"] = {"type": "artifact_blob_capability", "revision": 1, "enabled": False}
        receipt = self.persist(envelope, "small")
        delivery.bind_ciphertext("pair", "small-wire", "old-small", receipt_hash="d" * 64)
        self.release(receipt)
        with patch.object(compaction, "compact_in_transaction", return_value=False):
            with dispatch.DispatchGuard("pair", "old-small") as guard:
                dispatch.finish(guard, dispatch.begin(guard, envelope))
        with closing(delivery._connect()) as db:
            db.execute("DELETE FROM delivery_metadata WHERE key='receive_active_usage_v1'")
            db.execute("DELETE FROM inbound_signal_compaction_queue")
            db.execute("UPDATE inbound_signal_usage SET byte_count=16776939,record_count=11502")
            db.commit()
        self.assertEqual(1, compaction.compact_completed())
        self.assertEqual(0, compaction.compact_completed())
        with closing(delivery._connect()) as db:
            self.assertEqual(2, db.execute("SELECT COUNT(*) FROM inbound_signal_completed").fetchone()[0])
            self.assertEqual(0, db.execute("SELECT COUNT(*) FROM inbound_signal_usage").fetchone()[0])

    def test_pending_quota_remains_enforced_and_error_is_not_decryption(self):
        from link_transport_diagnostics import classify_decryption_error, LinkTransportDiagnostics
        envelope = copy.deepcopy(self.envelope)
        envelope["message_id"] = "pending-next"
        with patch.object(handoff, "MAX_PEER_RECORDS", 1):
            with self.assertRaises(handoff.ReceiveStorageFull) as caught:
                self.persist(envelope, "pending-next")
        self.assertEqual("receive_storage_full", classify_decryption_error(caught.exception))
        diagnostics = LinkTransportDiagnostics(delivery.DB_PATH.parent / "diagnostics.json")
        diagnostics.record(classify_decryption_error(caught.exception), route_id="pair")
        self.assertEqual(1, diagnostics.snapshot()["counts"]["receive_storage_full"])
        self.assertEqual(self.envelope, dispatch.load_envelope("pair", self.mid))
