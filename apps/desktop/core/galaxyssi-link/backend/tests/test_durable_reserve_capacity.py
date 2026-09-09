"""Exercise capacity across repeated flushes using the real encrypted queue."""

from contextlib import ExitStack
from pathlib import Path
from types import SimpleNamespace
import tempfile
import threading
import unittest
from unittest.mock import patch

import link_delivery as store
import mqtt_bridge as bridge
from tests.test_mqtt_durable_delivery import DurableMqttClient, paired_client


class DurableReserveCapacityTest(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        directory = self.stack.enter_context(tempfile.TemporaryDirectory())
        self.stack.enter_context(patch.object(store, "DB_PATH", Path(directory) / "delivery.db"))
        self.now = self.stack.enter_context(patch.object(store.time, "time", return_value=100.0))
        self.clients = [paired_client("app-a"), paired_client("app-b"), paired_client("app-c")]
        self.stack.enter_context(patch.object(bridge, "list_clients", return_value=self.clients))
        self.stack.enter_context(patch.object(bridge, "get_client", side_effect=lambda route:
            next(client for client in self.clients if client["client_route_id"] == route)))
        self.owned = {}
        self.stack.enter_context(patch.object(bridge, "pending_outbound_acks", self.owned))
        self.stack.enter_context(patch.object(bridge, "outbound_publish_reservations", {}))
        self.stack.enter_context(patch.object(bridge, "pending_outbound_priorities", {}))
        self.stack.enter_context(patch.object(bridge, "track_outbound_publish", side_effect=self.track))
        self.mid = 0
        self.publish = self.stack.enter_context(patch.object(bridge, "_publish_mqtt_wire_payload",
                                                            side_effect=self.wire))
        self.mqtt = DurableMqttClient()

    def wire(self, *args, **kwargs):
        self.mid += 1
        return SimpleNamespace(rc=0, mid=self.mid)

    def track(self, info, route, message, **kwargs):
        self.owned[info.mid] = (route, message)

    def queue(self, route, message, priority=50):
        store.queue_outbound(route, message, "fixture-topic", "unchanged-ciphertext", priority=priority)

    def occupy(self, route, message, priority=50):
        self.queue(route, message, priority)
        store.mark_outbound_sending(route, message)
        self.mid += 1
        self.owned[self.mid] = (route, message)

    def fill_ordinary(self):
        for route in ("app-a", "app-b"):
            for index in range(2):
                self.occupy(route, f"old-{index}")

    def test_repeated_flushes_cannot_reissue_the_emergency_slot(self):
        self.fill_ordinary()
        for route in ("app-a", "app-b", "app-c"):
            for index in range(5):
                self.queue(route, f"recovery-{index}", bridge.OUTBOUND_PRIORITY_DEPENDENCY)
        first = bridge.flush_outbound_messages(self.mqtt)
        self.assertEqual(1, len(first))
        for _ in range(20):
            self.assertEqual({}, bridge.flush_outbound_messages(self.mqtt))
        self.assertEqual(5, len(self.owned))
        self.assertEqual(1, self.publish.call_count)
        self.assertEqual("queued", store.outbound_status("app-c", "recovery-4"))

    def test_retry_age_does_not_release_broker_owned_capacity(self):
        self.fill_ordinary()
        self.queue("app-c", "normal")
        self.now.return_value = 200.0
        for _ in range(10):
            self.assertEqual({}, bridge.flush_outbound_messages(self.mqtt))
        self.assertEqual(4, len(self.owned))
        self.assertEqual("queued", store.outbound_status("app-c", "normal"))
        self.publish.assert_not_called()

    def test_route_reserve_cannot_consume_other_routes_normal_slots(self):
        self.occupy("app-a", "old-0")
        self.occupy("app-a", "old-1")
        for index in range(8):
            self.queue("app-a", f"recovery-{index}", bridge.OUTBOUND_PRIORITY_DEPENDENCY)
        self.assertEqual(1, len(bridge.flush_outbound_messages(self.mqtt)))
        for _ in range(5):
            self.assertEqual({}, bridge.flush_outbound_messages(self.mqtt))
        self.queue("app-b", "healthy")
        self.assertEqual({("app-b", "healthy")}, set(bridge.flush_outbound_messages(self.mqtt)))
        self.assertEqual(3, sum(route == "app-a" for route, _ in self.owned.values()))

    def test_broker_ack_releases_one_reserved_slot_without_deleting_other_work(self):
        self.fill_ordinary()
        self.queue("app-a", "recovery-0", bridge.OUTBOUND_PRIORITY_DEPENDENCY)
        self.queue("app-a", "recovery-1", bridge.OUTBOUND_PRIORITY_DEPENDENCY)
        self.assertEqual({("app-a", "recovery-0")}, set(bridge.flush_outbound_messages(self.mqtt)))
        mid = next(mid for mid, key in self.owned.items() if key == ("app-a", "recovery-0"))
        self.owned.pop(mid)
        store.mark_outbound_published("app-a", "recovery-0")
        self.assertEqual({("app-a", "recovery-1")}, set(bridge.flush_outbound_messages(self.mqtt)))
        self.assertEqual("published", store.outbound_status("app-a", "recovery-0"))
        self.assertTrue(store.acknowledge_outbound("app-a", "recovery-0"))
        self.assertEqual({}, bridge.flush_outbound_messages(self.mqtt))
        self.assertEqual("sending", store.outbound_status("app-a", "old-0"))
        self.assertEqual(5, len(self.owned))

    def test_artifacts_and_recovery_keep_independent_bounded_capacity(self):
        self.fill_ordinary()
        for route in ("app-a", "app-b"):
            self.queue(route, "image", bridge.OUTBOUND_PRIORITY_ARTIFACT)
        self.assertEqual(2, len(bridge.flush_outbound_messages(self.mqtt)))
        self.queue("app-a", "recovery", bridge.OUTBOUND_PRIORITY_DEPENDENCY)
        self.assertEqual({("app-a", "recovery")}, set(bridge.flush_outbound_messages(self.mqtt)))
        for _ in range(5):
            self.assertEqual({}, bridge.flush_outbound_messages(self.mqtt))
        self.assertEqual(7, len(self.owned))

    def test_peer_receipt_before_puback_does_not_free_physical_capacity(self):
        self.fill_ordinary()
        store.acknowledge_outbound("app-a", "old-0")
        self.queue("app-c", "normal")
        self.assertEqual({}, bridge.flush_outbound_messages(self.mqtt))
        mid = next(mid for mid, key in self.owned.items() if key == ("app-a", "old-0"))
        self.owned.pop(mid)
        self.assertEqual({("app-c", "normal")}, set(bridge.flush_outbound_messages(self.mqtt)))

    def test_concurrent_flush_cannot_borrow_an_unregistered_publish_slot(self):
        self.fill_ordinary()
        for index in range(3):
            self.queue("app-a", f"recovery-{index}", bridge.OUTBOUND_PRIORITY_DEPENDENCY)
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
            self.assertEqual({}, bridge.flush_outbound_messages(self.mqtt))
        finally:
            release.set()
            worker.join(5)
        self.assertFalse(worker.is_alive())
        self.assertEqual([], errors)
        self.assertEqual(1, self.publish.call_count)

    def test_failed_publish_retries_after_backoff_without_losing_ciphertext(self):
        self.fill_ordinary()
        self.queue("app-a", "recovery", bridge.OUTBOUND_PRIORITY_DEPENDENCY)
        self.publish.side_effect = OSError("fixture disconnect")
        self.assertEqual({}, bridge.flush_outbound_messages(self.mqtt))
        self.assertEqual("queued", store.outbound_status("app-a", "recovery"))
        self.publish.side_effect = self.wire
        self.now.return_value = 200.0
        self.assertEqual({("app-a", "recovery")}, set(bridge.flush_outbound_messages(self.mqtt)))
        self.assertEqual("unchanged-ciphertext", self.publish.call_args.args[2])
        self.assertEqual(5, len(self.owned))

    def test_disconnect_releases_broker_ownership_but_preserves_retry_records(self):
        self.fill_ordinary()
        self.queue("app-c", "normal")
        self.now.return_value = 200.0
        self.owned.clear()
        published = bridge.flush_outbound_messages(self.mqtt)
        self.assertEqual(4, len(published))
        self.assertEqual(4, len(self.owned))
        self.assertEqual("queued", store.outbound_status("app-c", "normal"))
        self.assertTrue(all(message.startswith("old-") for _, message in published))

    def test_lane_filter_counts_unacked_work_even_after_row_state_changes(self):
        self.occupy("app-a", "image", bridge.OUTBOUND_PRIORITY_ARTIFACT)
        self.occupy("app-b", "normal")
        store.mark_outbound_retryable("app-a", "image")
        self.now.return_value = 200.0
        active = set(self.owned.values())
        self.assertEqual(2, store.outbound_inflight_count(active_messages=active))
        self.assertEqual(1, store.outbound_inflight_count(priority=bridge.OUTBOUND_PRIORITY_ARTIFACT,
                                                        active_messages=active))
        self.assertEqual(1, store.outbound_inflight_count(exclude_priority=bridge.OUTBOUND_PRIORITY_ARTIFACT,
                                                        active_messages=active))
        self.assertEqual(0, store.outbound_inflight_count(client_route_id="app-c", active_messages=active))


if __name__ == "__main__":
    unittest.main()
