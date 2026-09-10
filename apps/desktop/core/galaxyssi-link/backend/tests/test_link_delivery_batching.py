"""Backlog size must not determine ciphertext work for one publish batch."""
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import link_delivery as delivery


class DeliveryBatchingTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.patch = patch.object(delivery, "DB_PATH", Path(temporary.name) / "delivery.db")
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.now = time.time()

    def seed(self, count, *, status="queued", attempts=0):
        db = delivery._connect()
        try:
            route = delivery._route("phone-a")
            topic = delivery._protect("opaque/topic", "topic")
            wire = delivery._protect("encrypted-wire-fixture", "wire-payload")
            with db:
                db.executemany("""INSERT INTO outbound_messages
                    (client_route_id,message_id,topic,wire_payload,created_at,updated_at,attempts,status)
                    VALUES(?,?,?,?,?,?,?,?)""",
                    ((route, f"message-{index:05d}", topic, wire, self.now + index / 100000,
                      self.now, attempts, status) for index in range(count)))
        finally:
            db.close()

    def test_ten_thousand_rows_decrypt_only_the_selected_batch(self):
        self.seed(10000)
        with patch.object(delivery, "_reveal", wraps=delivery._reveal) as reveal, \
                patch.object(delivery, "_unroute", wraps=delivery._unroute) as unroute:
            started = time.monotonic()
            rows = delivery.pending_outbound(client_route_id="phone-a", limit=8, now=self.now)
            print(f"BATCH_PROBE backlog=10000 selected=8 elapsed_ms={(time.monotonic()-started)*1000:.1f}")
        self.assertEqual([f"message-{i:05d}" for i in range(8)], [row["message_id"] for row in rows])
        self.assertEqual(16, reveal.call_count)
        self.assertEqual(8, unroute.call_count)
        self.assertTrue(all(row["wire_payload"] == "encrypted-wire-fixture" for row in rows))

    def test_not_due_messages_are_not_decrypted(self):
        self.seed(1000, status="published", attempts=1)
        with patch.object(delivery, "_reveal", side_effect=AssertionError("unnecessary decryption")):
            self.assertEqual([], delivery.pending_outbound(limit=8, now=self.now + 1))

    def test_zero_limit_does_not_open_storage(self):
        with patch.object(delivery, "_connect", side_effect=AssertionError("unnecessary storage")):
            self.assertEqual([], delivery.pending_outbound(limit=0))
            self.assertEqual([], delivery.pending_outbound(limit=-1))

    def test_fresh_messages_pass_retry_backoff_and_keep_other_route_isolated(self):
        self.seed(1, attempts=1)
        delivery.queue_outbound("phone-a", "later", "topic", "later-wire")
        delivery.queue_outbound("phone-b", "other", "topic", "other-wire")
        with patch.object(delivery, "_reveal", wraps=delivery._reveal) as reveal:
            self.assertEqual(["later"], [row["message_id"] for row in delivery.pending_outbound(
                client_route_id="phone-a", limit=8, now=self.now + 1)])
            self.assertEqual(2, reveal.call_count)
        self.assertEqual(["other"], [row["message_id"] for row in delivery.pending_outbound(
            client_route_id="phone-b", limit=8, now=self.now + 1)])

    def test_terminal_priority_precedes_backlog_and_expired_rows_are_pruned(self):
        self.seed(1000)
        delivery.queue_outbound("phone-a", "terminal", "topic", "terminal-wire", priority=100)
        self.assertEqual("terminal", delivery.pending_outbound(client_route_id="phone-a", limit=1)[0]["message_id"])
        db = delivery._connect()
        try:
            with db:
                db.execute("UPDATE outbound_messages SET created_at=0 WHERE message_id='terminal'")
        finally:
            db.close()
        self.assertEqual("message-00000", delivery.pending_outbound(client_route_id="phone-a", limit=1)[0]["message_id"])
