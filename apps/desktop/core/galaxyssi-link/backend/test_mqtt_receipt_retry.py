import unittest
from unittest.mock import Mock

from mqtt_broker_catalog import CATALOG
from mqtt_receipt_retry import ReceiptRetry


class ReceiptRetryTest(unittest.TestCase):
    def setUp(self):
        self.queue = ReceiptRetry()
        self.delay = CATALOG["timing"]["receipt_retry_ms"] / 1000

    def tick(self, now, limit=16):
        for send in self.queue.drain(now, limit):
            send()

    def test_success_does_not_generate_receipt_storm(self):
        send = Mock(return_value=True)
        self.queue.offer("peer", "message", "attempt", send, 0)
        self.tick(20)
        send.assert_called_once()

    def test_unready_and_exception_retry_at_bounded_interval(self):
        send = Mock(side_effect=[False, RuntimeError("full"), True])
        self.queue.offer("peer", "message", "attempt", send, 0)
        self.tick(self.delay / 2)
        send.assert_called_once()
        with self.assertRaises(RuntimeError):
            self.tick(self.delay)
        self.tick(self.delay * 2)
        self.tick(self.delay * 3)
        self.assertEqual(3, send.call_count)

    def test_duplicate_does_not_replace_proof_or_extend_expiry(self):
        send, replacement = Mock(return_value=False), Mock(return_value=True)
        self.queue.offer("peer", "message", "attempt", send, 0)
        self.queue.offer("peer", "message", "attempt", replacement, 1)
        self.tick(CATALOG["timing"]["receipt_retry_ttl_seconds"])
        send.assert_called_once()
        replacement.assert_not_called()
        self.assertEqual({}, self.queue.pending)

    def test_scope_cancellation_invalidates_already_drained_callbacks(self):
        send = Mock(return_value=False)
        self.queue.offer("peer", "message", "attempt", send, 0)
        work = self.queue.drain(self.delay)
        self.queue.forget("peer")
        for callback in work:
            callback()
        send.assert_called_once()

    def test_per_peer_and_global_capacities(self):
        per_peer = CATALOG["limits"]["per_peer_pending_receipts"]
        total = CATALOG["limits"]["max_pending_receipts"]
        send, overflow = Mock(return_value=False), Mock(return_value=False)
        for index in range(total):
            self.queue.offer(str(index // per_peer), str(index), "attempt", send, 0)
        self.queue.offer("0", "overflow", "attempt", overflow, 0)
        self.queue.offer("new", "overflow", "attempt", overflow, 0)
        self.assertEqual(total, send.call_count)
        overflow.assert_not_called()

    def test_bounded_drain_rotates_unready_peer_and_preserves_other_peer(self):
        calls = []
        for peer in ("a", "b", "c"):
            self.queue.offer(peer, "message", "attempt", lambda peer=peer: calls.append(peer) or False, 0)
        calls.clear()
        self.tick(self.delay, 1)
        self.tick(self.delay * 2, 1)
        self.assertEqual(["a", "b"], calls)
        self.queue.forget("a")
        self.assertEqual(2, len(self.queue.pending))

    def test_reentrant_drain_cannot_send_same_receipt_twice(self):
        send = Mock(side_effect=lambda: self.tick(self.delay) or True)
        self.queue.offer("peer", "message", "attempt", send, 0)
        send.assert_called_once()


if __name__ == "__main__":
    unittest.main()
