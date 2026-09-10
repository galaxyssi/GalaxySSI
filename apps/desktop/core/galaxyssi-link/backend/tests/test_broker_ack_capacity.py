"""Application receipt debt must not reserve a physical MQTT publish slot."""

import threading
import unittest
from unittest.mock import patch

import link_delivery as store
import mqtt_bridge as bridge
from tests import test_durable_reserve_capacity as capacity


class BrokerAckCapacityTest(unittest.TestCase):
    setUp = capacity.DurableReserveCapacityTest.setUp
    wire = capacity.DurableReserveCapacityTest.wire
    track = capacity.DurableReserveCapacityTest.track
    queue = capacity.DurableReserveCapacityTest.queue
    occupy = capacity.DurableReserveCapacityTest.occupy
    fill_ordinary = capacity.DurableReserveCapacityTest.fill_ordinary

    def published(self, route, message, priority=95, attempts=5):
        self.queue(route, message, priority)
        for _ in range(attempts):
            store.mark_outbound_sending(route, message)
        store.mark_outbound_published(route, message)

    def test_new_recovery_bypasses_app_receipts_without_deleting_them(self):
        for index in range(3):
            self.published("app-a", f"old-{index}")
        self.queue("app-a", "current", 95)
        self.assertEqual({("app-a", "current")}, set(bridge.flush_outbound_messages(self.mqtt)))
        for index in range(3):
            self.assertEqual("published", store.outbound_status("app-a", f"old-{index}"))
        self.assertEqual(1, len(self.owned))

    def test_fresh_same_priority_precedes_due_retries(self):
        for index in range(6):
            self.published("app-a", f"old-{index}", attempts=1)
        self.now.return_value = 200.0
        self.queue("app-a", "current", 95)
        sent = bridge.flush_outbound_messages(self.mqtt)
        self.assertIn(("app-a", "current"), sent)
        self.assertEqual(("app-a", "current"), next(iter(sent)))
        self.assertTrue(any(message.startswith("old-") for _, message in sent))

    def test_receipt_debt_does_not_block_normal_chat_or_another_route(self):
        for route in ("app-a", "app-b"):
            for index in range(3):
                self.published(route, f"old-{index}")
        self.queue("app-a", "chat", 50)
        self.queue("app-b", "chat", 50)
        sent = bridge.flush_outbound_messages(self.mqtt)
        self.assertEqual({("app-a", "chat"), ("app-b", "chat")}, set(sent))

    def test_early_peer_receipt_cannot_delete_an_unregistered_publish_reservation(self):
        self.fill_ordinary()
        self.queue("app-a", "first", 95)
        self.queue("app-a", "second", 95)
        entered, release = threading.Event(), threading.Event()
        errors = []
        def delayed(*args, **kwargs):
            entered.set()
            if not release.wait(5):
                raise TimeoutError("Test did not release publish")
            return self.wire(*args, **kwargs)
        def flush():
            try:
                bridge.flush_outbound_messages(self.mqtt)
            except BaseException as error:
                errors.append(error)
        self.publish.side_effect = delayed
        worker = threading.Thread(target=flush)
        worker.start()
        try:
            self.assertTrue(entered.wait(5))
            self.assertTrue(store.acknowledge_outbound("app-a", "first"))
            self.assertEqual({}, bridge.flush_outbound_messages(self.mqtt))
        finally:
            release.set()
            worker.join(5)
        self.assertFalse(worker.is_alive())
        self.assertEqual([], errors)
        self.assertEqual(1, self.publish.call_count)

    def test_pairing_lookup_failure_releases_entire_claim_batch(self):
        self.queue("app-a", "first")
        self.queue("app-b", "second")
        with patch.object(bridge, "get_client", side_effect=[self.clients[0], OSError("lookup failed")]):
            with self.assertRaisesRegex(OSError, "lookup failed"):
                bridge.flush_outbound_messages(self.mqtt)
        self.assertEqual({}, bridge.outbound_publish_reservations)
        self.publish.assert_not_called()
        self.now.return_value = 200.0
        self.assertEqual(2, len(bridge.flush_outbound_messages(self.mqtt)))

    def test_failed_publish_releases_all_reservations_without_losing_rows(self):
        self.queue("app-a", "first")
        self.queue("app-b", "second")
        self.publish.side_effect = OSError("disconnected")
        self.assertEqual({}, bridge.flush_outbound_messages(self.mqtt))
        self.assertEqual({}, bridge.outbound_publish_reservations)
        for route, message in (("app-a", "first"), ("app-b", "second")):
            self.assertEqual("queued", store.outbound_status(route, message))

    def test_failure_after_claim_releases_unpublished_remainder(self):
        self.queue("app-a", "first")
        self.queue("app-b", "second")
        with patch.object(bridge, "_publish_reserved_outbound", side_effect=RuntimeError("batch failed")):
            with self.assertRaisesRegex(RuntimeError, "batch failed"):
                bridge.flush_outbound_messages(self.mqtt)
        self.assertEqual({}, bridge.outbound_publish_reservations)
        self.now.return_value = 200.0
        self.assertEqual(2, len(bridge.flush_outbound_messages(self.mqtt)))

    def test_deleted_artifact_row_still_occupies_its_physical_lane(self):
        self.occupy("app-a", "old-image", bridge.OUTBOUND_PRIORITY_ARTIFACT)
        key = ("app-a", "old-image")
        bridge.pending_outbound_priorities[key] = bridge.OUTBOUND_PRIORITY_ARTIFACT
        self.assertTrue(store.acknowledge_outbound(*key))
        self.queue("app-a", "next-image", bridge.OUTBOUND_PRIORITY_ARTIFACT)
        self.queue("app-a", "chat")
        self.assertEqual({("app-a", "chat")}, set(bridge.flush_outbound_messages(self.mqtt)))
        self.assertEqual("queued", store.outbound_status("app-a", "next-image"))


if __name__ == "__main__":
    unittest.main()
