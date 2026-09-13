"""Real SQLite validation of the immutable part of the shared delivery ledger."""
import concurrent.futures
from contextlib import closing
import copy
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import link_delivery as delivery


class InboundContentBindingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "delivery.db"
        self.patch = patch.object(delivery, "DB_PATH", self.path)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.envelope = {"message_id": "m1", "source_id": "sender", "target_id": "receiver",
                         "conversation_id": "c1", "payload": {"type": "text", "content": "hello"}}

    def bind(self, envelope=None, peer="p1"):
        return delivery.bind_message_content(peer, "m1", self.envelope if envelope is None else envelope)

    def test_reordered_object_keys_are_identical_content(self):
        digest = self.bind()
        reordered = dict(reversed(list(self.envelope.items())))
        reordered["payload"] = dict(reversed(list(reordered["payload"].items())))
        self.assertEqual(digest, self.bind(reordered))
        with closing(sqlite3.connect(self.path)) as db:
            self.assertEqual(1, db.execute("SELECT count(*) FROM inbound_content_hashes").fetchone()[0])

    def test_same_id_changed_body_rejected_without_replacing_original(self):
        original = self.bind()
        changed = copy.deepcopy(self.envelope)
        changed["payload"]["content"] = "changed"
        with self.assertRaises(delivery.InboundContentConflict):
            self.bind(changed)
        self.assertEqual(original, self.bind())

    def test_envelope_routing_and_run_fields_are_immutable_too(self):
        self.bind()
        for key in ("source_id", "target_id", "conversation_id", "turn_id", "run_id"):
            with self.subTest(key=key):
                changed = copy.deepcopy(self.envelope)
                changed[key] = "different"
                with self.assertRaises(delivery.InboundContentConflict):
                    self.bind(changed)

    def test_id_is_scoped_to_configured_pair(self):
        first = self.bind()
        changed = copy.deepcopy(self.envelope)
        changed["payload"]["content"] = "peer two"
        self.assertNotEqual(first, self.bind(changed, peer="p2"))
        self.assertEqual(first, self.bind())

    def test_concurrent_three_broker_copies_have_one_binding(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as workers:
            digests = list(workers.map(lambda _: self.bind(), range(36)))
        self.assertEqual(1, len(set(digests)))
        self.assertTrue(delivery.claim_message("p1", "m1"))
        self.assertFalse(delivery.claim_message("p1", "m1"))

    def test_concurrent_conflicting_copies_cannot_both_win(self):
        def attempt(i):
            changed = copy.deepcopy(self.envelope)
            changed["payload"]["content"] = str(i)
            try:
                self.bind(changed)
                return True
            except delivery.InboundContentConflict:
                return False
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as workers:
            self.assertEqual(1, sum(workers.map(attempt, range(3))))

    def test_sqlite_uniqueness_also_holds_across_separate_processes(self):
        delivery._connect().close()
        delivery._route("p1")
        script = """
import json, sys
from pathlib import Path
import link_delivery as delivery
delivery.DB_PATH = Path(sys.argv[1])
try:
    delivery.bind_message_content('p1', 'm1', json.loads(sys.argv[2]))
except delivery.InboundContentConflict:
    sys.exit(3)
"""
        children = []
        try:
            for i in range(3):
                changed = copy.deepcopy(self.envelope)
                changed["payload"]["content"] = str(i)
                children.append(subprocess.Popen(
                    [sys.executable, "-c", script, str(self.path), json.dumps(changed)],
                    cwd=Path(delivery.__file__).parent, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                ))
            codes = []
            for child in children:
                _, errors = child.communicate(timeout=30)
                self.assertIn(child.returncode, (0, 3), errors.decode("utf-8", errors="replace"))
                codes.append(child.returncode)
            self.assertEqual([0, 3, 3], sorted(codes))
        finally:
            for child in children:
                if child.poll() is None:
                    child.kill()
                child.communicate(timeout=5)

    def test_binding_survives_connection_reopen_and_does_not_claim_delivery(self):
        digest = self.bind()
        self.assertEqual({}, delivery.previous_acknowledgement("p1", "m1"))
        self.assertIsNone(delivery.message_for_ciphertext("p1", "unknown"))
        self.assertEqual(digest, self.bind())
        with closing(sqlite3.connect(self.path)) as db:
            self.assertEqual(0, db.execute("SELECT count(*) FROM inbound_messages").fetchone()[0])

    def test_bad_input_does_not_poison_later_valid_binding(self):
        bad = copy.deepcopy(self.envelope)
        bad["payload"]["content"] = float("nan")
        with self.assertRaises(ValueError):
            self.bind(bad)
        with self.assertRaises(ValueError):
            delivery.bind_message_content("p1", "different-id", self.envelope)
        self.assertEqual(64, len(self.bind()))

    def test_oversized_content_is_not_written(self):
        changed = copy.deepcopy(self.envelope)
        changed["payload"]["content"] = "x" * (2 * 1024 * 1024)
        with self.assertRaises(ValueError):
            self.bind(changed)
        self.assertEqual(64, len(self.bind()))

    def test_revocation_forgets_only_the_revoked_pair_binding(self):
        self.bind()
        self.bind(peer="p2")
        delivery.discard_route("p1")
        changed = copy.deepcopy(self.envelope)
        changed["payload"]["content"] = "new relationship"
        self.bind(changed)
        with self.assertRaises(delivery.InboundContentConflict):
            self.bind(changed, peer="p2")

    def test_database_does_not_store_plaintext_content(self):
        self.envelope["payload"]["content"] = "private-plaintext-canary"
        self.bind()
        with closing(sqlite3.connect(self.path)) as db:
            dump = "\n".join(db.iterdump())
        self.assertNotIn("private-plaintext-canary", dump)
        self.assertNotIn(json.dumps(self.envelope), dump)


if __name__ == "__main__":
    unittest.main()
