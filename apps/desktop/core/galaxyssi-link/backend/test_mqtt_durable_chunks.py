import base64
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import link_delivery
from mqtt_delivery_envelope import content_hash
from mqtt_durable_chunks import Chunk, DurableChunkAssembler
from mqtt_wire_chunking import encode_wire_payload, _sha256


class DurableChunksTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)
        self.path = Path(self.root.name) / "existing-link.db"
        location = patch.object(link_delivery, "DB_PATH", self.path)
        location.start()
        self.addCleanup(location.stop)
        self.now = 1_000_000.0
        self.wire = json.dumps({"scheme": "signal", "from": "phone", "to": "desktop", "body": "x" * 700_000}, separators=(",", ":"))
        self.parts = [json.loads(value) for value in encode_wire_payload(self.wire)]
        self.transfer = self.parts[0]["transfer_id"]
        self.store = self.reopen()

    def connect(self):
        return link_delivery._connect()

    def reopen(self, **kwargs):
        return DurableChunkAssembler(self.connect, clock=lambda: self.now, **kwargs)

    def test_reopen_preserves_out_of_order_partial_and_complete_wire_until_handoff(self):
        self.assertIsNone(self.store.accept("pair", self.parts[1]))
        resumed = self.reopen()
        self.assertEqual((1,), resumed.stored_indices("pair", self.transfer))
        self.assertEqual(self.wire, resumed.accept("pair", self.parts[0]))
        self.assertEqual(self.wire, self.reopen().accept("pair", self.parts[1]))
        self.assertEqual((0, 1), self.reopen().stored_indices("pair", self.transfer))

    def test_concurrent_broker_copies_share_persistent_unique_rows(self):
        with ThreadPoolExecutor(max_workers=3) as executor:
            results = list(executor.map(lambda _: self.reopen().accept("pair", self.parts[0]), range(12)))
        self.assertEqual([None] * 12, results)
        with closing(self.connect()) as db:
            self.assertEqual(1, db.execute("SELECT COUNT(*) FROM mqtt_wire_parts").fetchone()[0])
        self.assertEqual(self.wire, self.store.accept("pair", self.parts[1]))

    def test_route_and_key_scopes_cannot_mix_same_transfer(self):
        self.store.accept("pair-old-key", self.parts[0])
        self.assertIsNone(self.store.accept("pair-new-key", self.parts[1]))
        self.assertIsNone(self.store.accept("other-pair", self.parts[1]))
        self.assertEqual(self.wire, self.store.accept("pair-old-key", self.parts[1]))

    def test_corrupt_first_chunk_cannot_reserve_capacity(self):
        bad = {**self.parts[0], "data": base64.b64encode(b"changed").decode()}
        with self.assertRaises(ValueError):
            self.store.accept("pair", bad)
        self.assertEqual((), self.store.stored_indices("pair", self.transfer))
        self.assertIsNone(self.store.accept("pair", self.parts[0]))

    def test_conflicting_duplicate_does_not_overwrite_or_erase_valid_chunk(self):
        self.store.accept("pair", self.parts[0])
        changed = b"y" * len(base64.b64decode(self.parts[0]["data"]))
        bad = {**self.parts[0], "data": base64.b64encode(changed).decode(), "chunk_sha256": _sha256(changed)}
        with self.assertRaisesRegex(ValueError, "Conflicting"):
            self.store.accept("pair", bad)
        self.assertEqual(self.wire, self.store.accept("pair", self.parts[1]))

    def test_bad_full_hash_rolls_back_last_chunk_and_allows_valid_retry(self):
        self.store.accept("pair", self.parts[0])
        changed = base64.b64decode(self.parts[1]["data"])[:-1] + b"!"
        bad = {**self.parts[1], "data": base64.b64encode(changed).decode(), "chunk_sha256": _sha256(changed)}
        with self.assertRaisesRegex(ValueError, "transfer integrity"):
            self.store.accept("pair", bad)
        self.assertEqual((0,), self.store.stored_indices("pair", self.transfer))
        self.assertEqual(self.wire, self.store.accept("pair", self.parts[1]))

    def test_geometry_conflict_cannot_replace_manifest(self):
        self.store.accept("pair", self.parts[0])
        with self.assertRaisesRegex(ValueError, "metadata"):
            self.store.accept("pair", {**self.parts[1], "total_bytes": self.parts[1]["total_bytes"] + 1})
        self.assertEqual(self.wire, self.store.accept("pair", self.parts[1]))

    def test_disk_corruption_is_detected_before_completed_wire_is_returned(self):
        self.store.accept("pair", self.parts[0])
        with closing(self.connect()) as db:
            db.execute("UPDATE mqtt_wire_parts SET data=?", (b"corrupt",))
            db.commit()
        with self.assertRaisesRegex(ValueError, "Stored MQTT chunk integrity"):
            self.store.accept("pair", self.parts[1])
        self.assertIsNone(self.store.accept("pair", self.parts[0]))
        self.assertEqual(self.wire, self.store.accept("pair", self.parts[1]))

    def test_quota_reserves_whole_transfer_and_never_evicts_existing_partial(self):
        store = self.reopen(max_transfers=1)
        store.accept("pair", self.parts[0])
        with self.assertRaisesRegex(ValueError, "capacity"):
            store.accept("other", self.parts[1])
        self.assertEqual(self.wire, store.accept("pair", self.parts[1]))
        self.assertFalse(store.release_after_store("pair", self.transfer, "f" * 64))
        self.assertTrue(store.release_after_store("pair", self.transfer, content_hash(json.loads(self.wire))))
        self.assertIsNone(store.accept("other", self.parts[0]))

    def test_per_peer_quota_leaves_room_for_other_pairs(self):
        store = self.reopen(max_peer_transfers=1)
        store.accept("pair", self.parts[0])
        different = encode_wire_payload(self.wire.replace("phone", "other"))
        with self.assertRaisesRegex(ValueError, "capacity"):
            store.accept("pair", json.loads(different[0]))
        self.assertIsNone(store.accept("other-pair", self.parts[0]))

    def test_completion_cannot_release_another_pair_or_unassembled_bytes(self):
        digest = content_hash(json.loads(self.wire))
        self.store.accept("pair", self.parts[0])
        self.assertFalse(self.store.release_after_store("pair", self.transfer, digest))
        self.store.accept("pair", self.parts[1])
        self.assertFalse(self.store.release_after_store("other", self.transfer, digest))
        self.assertEqual((0, 1), self.store.stored_indices("pair", self.transfer))

    def test_fixed_retention_does_not_extend_on_duplicate_traffic(self):
        self.store.accept("pair", self.parts[0])
        self.now += DurableChunkAssembler.RETENTION_SECONDS - 1
        self.store.accept("pair", self.parts[0])
        self.now += 2
        self.assertEqual((), self.store.stored_indices("pair", self.transfer))
        self.assertIsNone(self.store.accept("pair", self.parts[1]))
        self.assertEqual((1,), self.store.stored_indices("pair", self.transfer))

    def test_bad_counter_types_and_oversize_encoding_are_rejected(self):
        for key, value in (("chunk_index", "0"), ("chunk_index", False), ("chunk_count", 0),
                           ("total_bytes", 2**63), ("data", "x" * 600_000), ("transfer_id", "G" * 64)):
            with self.subTest(key=key, value=str(value)[:20]), self.assertRaises(ValueError):
                Chunk.parse({**self.parts[0], key: value})


if __name__ == "__main__":
    unittest.main()
