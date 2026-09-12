from contextlib import closing
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import link_delivery
from mqtt_chunk_receipts import OutgoingChunks, Query, parse_state, FIELD, PROBE
from mqtt_delivery_envelope import content_hash
from mqtt_durable_chunks import Chunk, DurableChunkAssembler
from mqtt_wire_chunking import encode_wire_payload


class ChunkReceiptTest(unittest.TestCase):
    def test_android_manifest_and_bitmap_golden(self):
        chunk = Chunk.parse({"scheme": "signal-chunk", "transfer_id": "a" * 64, "sha256": "a" * 64,
                             "chunk_count": 2, "total_bytes": 7, "chunk_index": 0, "from": "\u624b\u673a\U0001f600",
                             "to": "desktop", "data": "YWJj",
                             "chunk_sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"})
        self.assertEqual("eee0631bb0d8524c203df7990e983fbfdfabfaddf73c6fb4febf67a06ee30a28", chunk.manifest_hash)
        query = Query("a" * 64, "b" * 64, 9, "c" * 32)
        self.assertEqual("gQE=", query.response("d" * 32, 3, (0, 7, 8))["stored_bitmap"])

    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)
        location = patch.object(link_delivery, "DB_PATH", Path(self.root.name) / "link.db")
        location.start(); self.addCleanup(location.stop)
        self.now = 1000000.0
        self.sender = OutgoingChunks(link_delivery._connect, clock=lambda: self.now)
        self.receiver = DurableChunkAssembler(link_delivery._connect, clock=lambda: self.now)
        self.wire = json.dumps({"scheme": "signal", "from": "a", "to": "b", "body": "x" * 700000}, separators=(",", ":"))
        self.parts = [json.loads(value) for value in encode_wire_payload(self.wire)]

    def begin(self):
        return self.sender.prepare("outbound-pair", self.parts)

    def state(self, query, indices=(0,), epoch="a" * 32, revision=1):
        return query.response(epoch, revision, indices)

    def test_saved_bitmap_reopens_and_only_missing_index_is_selected(self):
        query, selected, _ = self.begin()
        self.assertEqual([0, 1], [index for index, _ in selected])
        self.assertEqual(query, Query.from_chunk(selected[0][1]))
        self.assertTrue(self.sender.accept("outbound-pair", self.state(query)))
        reopened = OutgoingChunks(link_delivery._connect, clock=lambda: self.now)
        next_query, selected, _ = reopened.prepare("outbound-pair", self.parts)
        self.assertEqual([1], [index for index, _ in selected])
        self.assertNotEqual(query.request, next_query.request)

    def test_target_expiry_is_respected_even_with_more_than_one_cleanup_batch(self):
        query, _, _ = self.begin()
        self.sender.accept("outbound-pair", self.state(query))
        self.receiver.accept("inbound-pair", self.parts[0])
        with closing(link_delivery._connect()) as db, db:
            for index in range(300):
                dummy = f"{index:064x}"
                db.execute("INSERT INTO mqtt_outgoing_chunks SELECT scope_digest,?,manifest_hash,chunk_count,request_id,store_epoch,revision,stored_bitmap,path_bits,0 FROM mqtt_outgoing_chunks WHERE transfer_id=?",
                           (dummy, query.transfer))
                db.execute("INSERT INTO mqtt_wire_transfers SELECT scope_digest,?,manifest_hash,chunk_count,total_bytes,stored_bytes,0,wire_hash,source,target,store_epoch,revision,'completed' FROM mqtt_wire_transfers WHERE transfer_id=?",
                           (dummy, query.transfer))
        self.now += self.receiver.RETENTION_SECONDS + 1
        self.assertEqual([0, 1], [index for index, _ in self.begin()[1]])
        self.assertIsNone(self.receiver.accept("inbound-pair", self.parts[1]))
        self.assertEqual((1,), self.receiver.stored_indices("inbound-pair", query.transfer))

    def test_all_stored_sends_only_small_probe_not_a_completed_business_claim(self):
        query, _, _ = self.begin()
        self.sender.accept("outbound-pair", self.state(query, (0, 1)))
        next_query, selected, _ = self.begin()
        self.assertEqual([(-1, next_query.wire())], selected)
        self.assertEqual(PROBE, selected[0][1]["type"])
        self.assertLess(len(json.dumps(selected[0][1])), 1024)
        self.assertNotIn("RX_STORED", json.dumps(selected))

    def test_unsolicited_old_round_or_other_pair_receipts_cannot_advance_bitmap(self):
        query, _, _ = self.begin()
        self.assertFalse(self.sender.accept("other-pair", self.state(query)))
        next_query, _, _ = self.begin()
        self.assertFalse(self.sender.accept("outbound-pair", self.state(query)))
        self.assertTrue(self.sender.accept("outbound-pair", self.state(next_query)))
        self.assertEqual([1], [index for index, _ in self.begin()[1]])

    def test_conflicting_same_revision_is_rejected_and_older_state_cannot_roll_back(self):
        query, _, _ = self.begin()
        self.sender.accept("outbound-pair", self.state(query, (0, 1), revision=2))
        self.assertFalse(self.sender.accept("outbound-pair", self.state(query, (0,), revision=1)))
        with self.assertRaises(ValueError):
            self.sender.accept("outbound-pair", self.state(query, (0,), revision=2))
        self.assertEqual(-1, self.begin()[1][0][0])

    def test_newer_revision_can_retract_corrupted_part_but_old_epoch_cannot_replace_it(self):
        query, _, _ = self.begin()
        self.sender.accept("outbound-pair", self.state(query, (0, 1), revision=2))
        self.assertTrue(self.sender.accept("outbound-pair", self.state(query, (1,), revision=3)))
        self.assertFalse(self.sender.accept("outbound-pair", self.state(query, (), epoch="b" * 32, revision=10)))
        self.assertEqual([0], [index for index, _ in self.begin()[1]])

    def test_fresh_round_can_accept_receiver_state_reset_and_request_missing_data(self):
        query, _, _ = self.begin()
        self.sender.accept("outbound-pair", self.state(query, (0, 1), revision=2))
        query, _, _ = self.begin()
        self.assertTrue(self.sender.accept("outbound-pair", self.state(query, (), epoch="0" * 32, revision=0)))
        self.assertEqual([0, 1], [index for index, _ in self.begin()[1]])

    def test_bitmap_and_request_must_be_exact_and_bounded(self):
        query, selected, _ = self.begin()
        for field, value in (("stored_bitmap", "BA=="), ("stored_bitmap", "AA"), ("stored_bitmap", ""),
                             ("revision", True), ("chunk_count", "2"), ("version", True), ("request_id", "x" * 32)):
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                parse_state({**self.state(query), field: value})
        with self.assertRaises(ValueError):
            Query.from_chunk({**selected[0][1], FIELD: {**query.wire(), "manifest_hash": "f" * 64}})

    def test_path_attempts_survive_restart_without_becoming_a_business_ack(self):
        query, _, _ = self.begin()
        self.sender.record_path("outbound-pair", query, 1, "hivemq")
        self.sender.record_path("outbound-pair", query, 1, "mosquitto")
        _, selected, paths = self.begin()
        self.assertEqual([0, 1], [index for index, _ in selected])
        self.assertEqual(frozenset({"hivemq", "mosquitto"}), self.sender.attempted(paths, 1))
        self.assertEqual(frozenset(), self.sender.attempted(paths, 0))

    def test_receiver_snapshot_is_durable_and_repairs_corruption_by_retracting_bits(self):
        query, _, _ = self.begin()
        self.receiver.accept("receiver", self.parts[0])
        before, proof = self.receiver.snapshot("receiver", query)
        self.assertIsNone(proof)
        self.assertEqual(b"\x01", parse_state(before)[3])
        with closing(link_delivery._connect()) as db:
            db.execute("UPDATE mqtt_wire_parts SET data=?", (b"corrupt",)); db.commit()
        after, proof = self.receiver.snapshot("receiver", query)
        self.assertGreater(after["revision"], before["revision"])
        self.assertEqual(b"\x00", parse_state(after)[3])
        self.assertIsNone(self.receiver.accept("receiver", self.parts[0]))
        self.assertEqual(self.wire, self.receiver.accept("receiver", self.parts[1]))

    def test_completed_wire_recovers_handoff_and_compact_tombstone_can_repeat_receipt(self):
        query, _, _ = self.begin()
        for part in self.parts:
            self.receiver.accept("receiver", part)
        self.assertEqual(self.wire, self.receiver.recover_complete("receiver", query))
        digest = content_hash(json.loads(self.wire))
        self.assertTrue(self.receiver.release_after_store("receiver", query.transfer, digest, "message"))
        state, proof = self.receiver.snapshot("receiver", query)
        self.assertEqual(("message", digest), proof)
        self.assertEqual(b"\x03", parse_state(state)[3])
        self.assertEqual((), self.receiver.stored_indices("receiver", query.transfer))
        self.assertIsNone(self.receiver.recover_complete("receiver", query))
        self.assertIsNone(self.receiver.accept("receiver", self.parts[0]))
        self.assertEqual(proof, self.receiver.snapshot("receiver", query)[1])

    def test_unknown_receiver_does_not_reserve_space_for_probes(self):
        query, _, _ = self.begin()
        state, proof = self.receiver.snapshot("unknown", query)
        self.assertEqual("0" * 32, state["store_epoch"])
        self.assertIsNone(proof)
        self.assertEqual(b"\x00", parse_state(state)[3])
        with closing(link_delivery._connect()) as db:
            self.assertEqual(0, db.execute("SELECT COUNT(*) FROM mqtt_wire_transfers").fetchone()[0])

    def test_metadata_retention_is_not_extended_by_retry_rounds(self):
        query, _, _ = self.begin()
        self.sender.accept("outbound-pair", self.state(query))
        self.now += 7 * 86400 - 1
        self.begin()
        self.now += 2
        self.assertEqual([0, 1], [index for index, _ in self.begin()[1]])


if __name__ == "__main__":
    unittest.main()
