"""Abrupt Python process exit on either side of the actual SQLite chunk commit."""
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

from mqtt_delivery_envelope import content_hash
from mqtt_durable_chunks import DurableChunkAssembler
from mqtt_wire_chunking import encode_wire_payload


CHILD = r"""
import json, os, sqlite3, sys
from mqtt_durable_chunks import DurableChunkAssembler
from mqtt_wire_chunking import encode_wire_payload

class InterruptedCommit(sqlite3.Connection):
    def commit(self):
        os._exit(24)

def connect():
    factory = InterruptedCommit if sys.argv[2] == 'before' else sqlite3.Connection
    db = sqlite3.connect(sys.argv[1], factory=factory)
    db.execute('PRAGMA journal_mode=WAL')
    db.execute('PRAGMA synchronous=FULL')
    return db

wire = json.dumps({'scheme': 'signal', 'from': 'phone', 'to': 'desktop', 'body': 'x' * 700000}, separators=(',', ':'))
store = DurableChunkAssembler(connect)
assert store.accept('pair', json.loads(encode_wire_payload(wire)[0])) is None
os._exit(23)
"""


class ChunkProcessRecoveryTest(unittest.TestCase):
    def exercise(self, phase):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "link.db"
            result = subprocess.run([sys.executable, "-c", CHILD, str(path), phase],
                                    cwd=Path(__file__).parent, capture_output=True, timeout=30)
            self.assertEqual(24 if phase == "before" else 23, result.returncode,
                             result.stderr.decode(errors="replace"))

            def connect():
                db = sqlite3.connect(path)
                db.execute("PRAGMA journal_mode=WAL")
                db.execute("PRAGMA synchronous=FULL")
                return db

            wire = json.dumps({"scheme": "signal", "from": "phone", "to": "desktop",
                               "body": "x" * 700000}, separators=(",", ":"))
            parts = [json.loads(part) for part in encode_wire_payload(wire)]
            transfer = parts[0]["transfer_id"]
            store = DurableChunkAssembler(connect)
            self.assertEqual(() if phase == "before" else (0,), store.stored_indices("pair", transfer))
            if phase == "before":
                self.assertIsNone(store.accept("pair", parts[0]))
            self.assertEqual(wire, store.accept("pair", parts[1]))
            self.assertTrue(store.release_after_store("pair", transfer, content_hash(json.loads(wire))))

    def test_exit_before_commit_does_not_claim_or_poison_a_stored_chunk(self):
        self.exercise("before")

    def test_exit_after_commit_recovers_without_retransmitting_the_saved_chunk(self):
        self.exercise("after")


if __name__ == "__main__":
    unittest.main()
