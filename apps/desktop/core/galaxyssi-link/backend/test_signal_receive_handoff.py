import base64
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
import copy
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

import galaxyssi_client as client
import link_delivery as delivery
import signal_receive_handoff as handoff


class SignalReceiveHandoffTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="galaxyssi-receive-handoff-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "delivery.db"
        override = patch.object(delivery, "DB_PATH", self.path)
        override.start()
        self.addCleanup(override.stop)
        self.wire = {"_client_route_id": "pair-one", "signal_type": "prekey", "message_type": 3,
                     "body": base64.b64encode(b"cipher-one").decode()}
        self.envelope = {"message_id": "message-one", "source_id": "phone", "target_id": "desktop",
                         "payload": {"type": "text", "content": "private-receive-marker"}}
        self.receipt = self.make_receipt()

    def make_receipt(self, envelope=None, index=None):
        plaintext = json.dumps(envelope or self.envelope, ensure_ascii=False)
        digest = hashlib.sha256(b"\x01cipher-one" if index is None else str(index).encode()).hexdigest()
        return {"plaintext": plaintext, "receiveDigest": digest,
                "contentHash": hashlib.sha256(plaintext.encode()).hexdigest()}

    def persist(self, receipt=None, route="pair-one"):
        handoff.persist_receive(route, "phone", 1, receipt or self.receipt)

    def cached(self, route="pair-one", receipt=None):
        return handoff.cached_receive(route, "phone", 1, (receipt or self.receipt)["receiveDigest"])

    def count(self, table):
        with closing(sqlite3.connect(self.path)) as db:
            return db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]

    def test_complete_body_is_durable_before_any_task_claim(self):
        self.persist()
        self.assertEqual(self.envelope, json.loads(self.cached()["plaintext"]))
        self.assertEqual(1, self.count("inbound_messages"))
        with closing(sqlite3.connect(self.path)) as db:
            self.assertEqual(("RX_STORED", "stored", 0), db.execute(
                "SELECT status,dispatch_state,dispatch_attempts FROM inbound_messages").fetchone())
        self.assertEqual(1, self.count("inbound_signal_bodies"))

    def test_same_id_is_scoped_to_pair(self):
        self.persist()
        other = copy.deepcopy(self.envelope)
        other["payload"]["content"] = "other peer"
        receipt = self.make_receipt(other)
        self.persist(receipt, route="pair-two")
        self.assertEqual(other, json.loads(self.cached("pair-two")["plaintext"]))
        self.assertEqual(self.envelope, json.loads(self.cached()["plaintext"]))

    def test_concurrent_copies_create_one_body_and_binding(self):
        with ThreadPoolExecutor(max_workers=10) as workers:
            list(workers.map(lambda _: self.persist(), range(30)))
        self.assertEqual(1, self.count("inbound_signal_bodies"))
        self.assertEqual(1, self.count("inbound_signal_handoffs"))

    def test_changed_content_cannot_replace_body(self):
        self.persist()
        changed = copy.deepcopy(self.envelope)
        changed["payload"]["content"] = "different"
        with self.assertRaises(delivery.InboundContentConflict):
            self.persist(self.make_receipt(changed, 2))
        self.assertEqual(self.envelope, json.loads(self.cached()["plaintext"]))

    def test_conflict_with_existing_delivery_binding_is_rejected(self):
        changed = copy.deepcopy(self.envelope)
        changed["payload"]["content"] = "old content"
        delivery.bind_message_content("pair-one", "message-one", changed)
        with self.assertRaises(delivery.InboundContentConflict):
            self.persist()
        self.assertEqual(0, self.count("inbound_signal_bodies"))

    def test_wrong_raw_hash_never_reaches_database(self):
        receipt = {**self.receipt, "contentHash": "0" * 64}
        with self.assertRaises(ValueError):
            self.persist(receipt)
        self.assertFalse(self.path.exists())

    def test_per_peer_quota_rolls_back_binding_and_usage(self):
        with patch.object(handoff, "MAX_PEER_BYTES", 1):
            with self.assertRaises(RuntimeError):
                self.persist()
        self.assertEqual(0, self.count("inbound_signal_bodies"))
        self.assertEqual(0, self.count("inbound_content_hashes"))
        self.assertEqual(0, self.count("inbound_signal_usage"))
        self.persist()
        self.assertIsNotNone(self.cached())

    def test_cipher_variants_are_bounded_without_replicating_body(self):
        for index in range(handoff.MAX_CIPHER_BINDINGS):
            self.persist(self.make_receipt(index=index))
        with self.assertRaises(RuntimeError):
            self.persist(self.make_receipt(index=100))
        self.assertEqual(1, self.count("inbound_signal_bodies"))
        self.assertEqual(8, self.count("inbound_signal_handoffs"))

    def test_deleted_or_corrupted_body_does_not_count_as_received(self):
        self.persist()
        with closing(sqlite3.connect(self.path)) as db:
            db.execute("UPDATE inbound_signal_bodies SET body='corrupt'")
            db.commit()
        with self.assertRaises(Exception):
            self.cached()

    def test_wrong_peer_cannot_read_body(self):
        self.persist()
        self.assertIsNone(handoff.cached_receive("pair-one", "different-phone", 1, self.receipt["receiveDigest"]))
        self.assertIsNone(handoff.cached_receive("pair-one", "phone", 2, self.receipt["receiveDigest"]))

    def test_discard_route_clears_only_its_body_and_usage(self):
        self.persist()
        self.persist(route="pair-two")
        delivery.discard_route("pair-one")
        self.assertIsNone(self.cached())
        self.assertIsNotNone(self.cached("pair-two"))
        self.assertEqual(1, self.count("inbound_signal_bodies"))
        delivery.discard_route("pair-two")
        self.assertEqual(0, self.count("inbound_signal_usage"))

    def test_body_not_plaintext_on_disk(self):
        self.persist()
        for path in self.path.parent.glob("delivery.db*"):
            self.assertNotIn(b"private-receive-marker", path.read_bytes())

    def test_python_releases_jvm_copy_only_after_sqlite_commit(self):
        calls = []
        def request(method, path, payload):
            calls.append(path)
            if path == "/decrypt":
                return self.receipt
            self.assertEqual(self.envelope, json.loads(self.cached()["plaintext"]))
            self.assertEqual(self.receipt["contentHash"], payload["contentHash"])
            return {"ok": True, "released": True}
        with patch.object(client, "start_signal_sidecar"), patch.object(client, "_request", side_effect=request):
            self.assertEqual(self.envelope, client.decrypt_signal_envelope(self.wire, "phone"))
            self.assertEqual(self.envelope, client.decrypt_signal_envelope(self.wire, "phone"))
        self.assertEqual(["/decrypt", "/receive-stored"], calls)
        self.assertTrue(self.cached()["released"])

    def test_persistence_failure_keeps_jvm_copy(self):
        with patch.object(client, "start_signal_sidecar"), patch.object(client, "_request", return_value=self.receipt) as request, \
                patch.object(handoff, "persist_receive", side_effect=OSError("disk failure")):
            with self.assertRaises(OSError):
                client.decrypt_signal_envelope(self.wire, "phone")
        self.assertEqual(["/decrypt"], [call.args[1] for call in request.call_args_list])

    def test_lost_release_response_retries_without_decrypting_again(self):
        with patch.object(client, "start_signal_sidecar"), patch.object(client, "_request", side_effect=[self.receipt, OSError("response lost")]):
            self.assertEqual(self.envelope, client.decrypt_signal_envelope(self.wire, "phone"))
        self.assertFalse(self.cached()["released"])
        with patch.object(client, "start_signal_sidecar"), patch.object(client, "_request", return_value={"ok": True, "released": False}) as request:
            self.assertEqual(self.envelope, client.decrypt_signal_envelope(self.wire, "phone"))
        self.assertEqual(["/receive-stored"], [call.args[1] for call in request.call_args_list])
        self.assertTrue(self.cached()["released"])

    def test_supervised_cleanup_recovers_without_another_incoming_copy(self):
        self.persist()
        with patch.object(client, "_request", return_value={"ok": True}) as request:
            client.drain_signal_receive_handoffs()
        self.assertTrue(self.cached()["released"])
        self.assertEqual("/receive-stored", request.call_args.args[1])
        self.assertEqual(0.5, request.call_args.kwargs["timeout"])
        self.assertEqual([], handoff.pending_releases())

    def test_cleanup_does_not_release_missing_body(self):
        self.persist()
        with closing(sqlite3.connect(self.path)) as db:
            db.execute("DELETE FROM inbound_signal_bodies")
            db.commit()
        with patch.object(client, "_request") as request:
            with self.assertRaises(RuntimeError):
                client.drain_signal_receive_handoffs()
        request.assert_not_called()
