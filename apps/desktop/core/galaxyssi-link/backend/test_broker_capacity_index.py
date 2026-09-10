"""Physical capacity must not decrypt or scan the application-receipt backlog."""
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

import link_delivery as delivery


class BrokerCapacityIndexTest(unittest.TestCase):
    def setUp(self):
        root = tempfile.TemporaryDirectory(prefix="broker-capacity-index-")
        self.addCleanup(root.cleanup)
        target = patch.object(delivery, "DB_PATH", Path(root.name) / "delivery.db")
        target.start()
        self.addCleanup(target.stop)
        self.now = time.time()
        self.db = delivery._connect()
        self.addCleanup(self.db.close)

    def seed(self, route, status, count=1, *, priority=50, age=0, attempts=1):
        sealed = delivery._route(route)
        rows = [(sealed, f"{route}-{status}-{index}", "unused-encrypted-topic",
                 "unused-encrypted-payload", self.now, self.now - age, attempts, status, priority)
                for index in range(count)]
        self.db.executemany("""INSERT INTO outbound_messages
            (client_route_id,message_id,topic,wire_payload,created_at,updated_at,attempts,status,priority)
            VALUES(?,?,?,?,?,?,?,?,?)""", rows)
        self.db.commit()
        return {(route, row[1]) for row in rows}

    def count(self, **kwargs):
        return delivery.outbound_inflight_count(now=self.now, awaiting_broker_only=True, **kwargs)

    def test_twenty_thousand_published_receipts_require_no_route_decryption(self):
        self.seed("debt", "published", 20_000)
        active = self.seed("live", "published", priority=95)
        self.seed("fresh", "sending")
        with patch.object(delivery, "_unroute", wraps=delivery._unroute) as decode:
            self.assertEqual(2, self.count(active_messages=active))
        self.assertEqual(0, decode.call_count, "Receipt backlog is not physical capacity")
        self.assertEqual(20_000, self.db.execute(
            "SELECT COUNT(*) FROM outbound_messages WHERE client_route_id=?",
            (delivery._route("debt"),)).fetchone()[0])

    def test_sending_recovery_uses_a_status_index(self):
        self.seed("debt", "published", 1_000)
        plan = " ".join(str(row[3]) for row in self.db.execute(
            "EXPLAIN QUERY PLAN SELECT client_route_id,message_id,attempts,updated_at,priority "
            "FROM outbound_messages WHERE status='sending'"))
        self.assertIn("SEARCH", plan)
        self.assertIn("INDEX", plan)

    def test_preserves_orphan_sending_timer_and_physical_ownership(self):
        current = self.seed("fresh", "sending")
        overdue = self.seed("overdue", "sending", age=100)
        self.seed("debt", "published")
        self.seed("queued", "queued", attempts=0)
        self.assertEqual(1, self.count())
        self.assertEqual(2, self.count(active_messages=current | overdue))
        self.assertEqual(1, self.count(client_route_id="overdue", active_messages=current | overdue))
        self.assertEqual(0, self.count(client_route_id="debt", active_messages=current | overdue))

    def test_priority_metadata_survives_peer_receipt_before_puback(self):
        active = {("phone", "already-removed"), ("phone", "unknown-priority")}
        priorities = {("phone", "already-removed"): 10}
        self.assertEqual(1, self.count(active_messages=active, active_priorities=priorities, priority=10))
        self.assertEqual(1, self.count(active_messages=active, active_priorities=priorities, exclude_priority=10))
        self.assertEqual(0, self.count(active_messages=active, active_priorities=priorities, client_route_id="other"))

    def test_durable_row_priority_wins_while_row_is_sending_or_published(self):
        active = self.seed("phone", "published", priority=95)
        stale_metadata = dict.fromkeys(active, 10)
        self.assertEqual(1, self.count(active_messages=active, active_priorities=stale_metadata, priority=95))
        self.assertEqual(0, self.count(active_messages=active, active_priorities=stale_metadata, priority=10))

    def test_active_queued_row_uses_reservation_priority(self):
        active = self.seed("phone", "queued", priority=50)
        self.assertEqual(1, self.count(active_messages=active, active_priorities=dict.fromkeys(active, 95), priority=95))
        self.assertEqual(1, self.count(active_messages=active, priority=50))

    def test_legacy_application_receipt_count_remains_unchanged(self):
        self.seed("phone", "published", 3)
        self.seed("old", "published", 2, age=100)
        self.assertEqual(3, delivery.outbound_inflight_count(now=self.now))
        self.assertEqual(0, self.count())


if __name__ == "__main__":
    unittest.main()
