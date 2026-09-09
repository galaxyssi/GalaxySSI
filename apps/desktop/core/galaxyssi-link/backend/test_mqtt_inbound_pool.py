"""Bounded pre-decryption buffering without per-route threads or concurrent ratchets."""
from concurrent.futures import ThreadPoolExecutor
import threading
import time
import unittest
from unittest.mock import patch

from mqtt_inbound_pool import InboundRoutePool


class InboundPoolTest(unittest.TestCase):
    def pool(self, process, **limits):
        pool = InboundRoutePool(process, **limits)
        self.addCleanup(pool.close)
        return pool

    def hold(self, *, size=1, **limits):
        entered, release = threading.Event(), threading.Event()
        processed = []
        def process(item):
            if item == "held":
                entered.set()
                release.wait(5)
            processed.append(item)
        pool = self.pool(process, **limits)
        self.addCleanup(release.set)
        self.assertEqual("accepted", pool.submit("a", "held", size))
        self.assertTrue(entered.wait(1))
        return pool, release, processed

    def test_active_route_is_serial_and_other_routes_progress(self):
        pool, release, processed = self.hold(max_workers=3)
        pool.submit("a", "second-a", 1)
        pool.submit("b", "first-b", 1)
        deadline = time.monotonic() + 1
        while "first-b" not in processed and time.monotonic() < deadline:
            time.sleep(0.005)
        self.assertIn("first-b", processed)
        self.assertNotIn("second-a", processed)
        release.set()
        self.assertTrue(pool.wait_idle())
        self.assertEqual(["held", "second-a"], [item for item in processed if item != "first-b"])

    def test_route_rotation_is_fair_and_fifo(self):
        pool, release, processed = self.hold(max_workers=1)
        for route, value in (("a", "a2"), ("a", "a3"), ("b", "b1"), ("b", "b2"), ("c", "c1")):
            pool.submit(route, value, 1)
        release.set()
        self.assertTrue(pool.wait_idle())
        self.assertEqual(["held", "b1", "c1", "a2", "b2", "a3"], processed)

    def test_global_pending_bound_and_retry_after_capacity_release(self):
        pool, release, _ = self.hold(max_workers=1, max_pending=2)
        self.assertEqual("accepted", pool.submit("b", "b", 1))
        self.assertEqual("accepted", pool.submit("c", "c", 1))
        self.assertEqual("global_pending", pool.submit("d", "d", 1))
        self.assertEqual(2, pool.snapshot()["pending"])
        release.set()
        self.assertTrue(pool.wait_idle())
        self.assertEqual("accepted", pool.submit("d", "retry", 1))
        self.assertTrue(pool.wait_idle())

    def test_active_payload_is_charged_to_global_and_route_byte_limits(self):
        pool, release, _ = self.hold(size=60, max_workers=1, max_bytes=100, route_bytes=80)
        self.assertEqual("global_bytes", pool.submit("b", "too-large-globally", 50))
        self.assertEqual("route_bytes", pool.submit("a", "too-large-for-route", 21))
        self.assertEqual("accepted", pool.submit("a", "fits", 20))
        self.assertEqual(80, pool.snapshot()["retained_bytes"])
        release.set()
        self.assertTrue(pool.wait_idle())
        self.assertEqual(0, pool.snapshot()["retained_bytes"])
        self.assertEqual(0, pool.snapshot()["routes"])

    def test_route_pending_limit_leaves_capacity_for_other_peers(self):
        pool, release, _ = self.hold(max_workers=1, max_pending=10, route_pending=2)
        self.assertEqual("accepted", pool.submit("a", "a2", 1))
        self.assertEqual("accepted", pool.submit("a", "a3", 1))
        self.assertEqual("route_pending", pool.submit("a", "a4", 1))
        self.assertEqual("accepted", pool.submit("b", "b1", 1))
        self.assertEqual({"route_pending": 1}, pool.snapshot()["rejected"])
        release.set()
        self.assertTrue(pool.wait_idle())

    def test_ten_thousand_queued_routes_use_three_workers(self):
        release = threading.Event()
        started = [threading.Event() for _ in range(3)]
        processed = []
        lock = threading.Lock()
        def process(item):
            if item < 3:
                started[item].set()
                release.wait(10)
            with lock:
                processed.append(item)
        pool = self.pool(process, max_workers=3)
        self.addCleanup(release.set)
        for index in range(3):
            pool.submit("hold-" + str(index), index, 1)
        for event in started:
            self.assertTrue(event.wait(1))
        for index in range(3, 10003):
            self.assertEqual("accepted", pool.submit("route-" + str(index), index, 1))
        snapshot = pool.snapshot()
        self.assertEqual(3, snapshot["workers"])
        self.assertEqual(3, snapshot["active"])
        self.assertEqual(10000, snapshot["pending"])
        self.assertEqual(10003, snapshot["retained_bytes"])
        self.assertEqual("global_pending", pool.submit("overflow", 10004, 1))
        release.set()
        self.assertTrue(pool.wait_idle(10))
        self.assertEqual(list(range(10003)), sorted(processed))
        self.assertEqual(0, pool.snapshot()["routes"])

    def test_one_failed_message_does_not_kill_route_or_leak_budget(self):
        processed = []
        def process(value):
            processed.append(value)
            if value == "first":
                raise RuntimeError("private failure contents")
        pool = self.pool(process, max_workers=1)
        with self.assertLogs("mqtt_inbound_pool", level="ERROR") as logs:
            pool.submit("route", "first", 30)
            pool.submit("route", "second", 20)
            self.assertTrue(pool.wait_idle())
        self.assertNotIn("private failure contents", str(logs.output))
        self.assertEqual(["first", "second"], processed)
        self.assertEqual(1, pool.snapshot()["failed"])
        self.assertEqual(0, pool.snapshot()["retained_bytes"])

    def test_cancel_pending_preserves_active_charge_and_blocks_new_work(self):
        pool, release, processed = self.hold(size=10, max_workers=1)
        pool.submit("a", "discard-a", 20)
        pool.submit("b", "discard-b", 30)
        self.assertFalse(pool.close(wait=False))
        state = pool.snapshot()
        self.assertEqual(0, state["pending"])
        self.assertEqual(10, state["retained_bytes"])
        self.assertEqual(2, state["cancelled"])
        self.assertEqual("closed", pool.submit("a", "new", 1))
        release.set()
        self.assertTrue(pool.close())
        self.assertEqual(["held"], processed)
        self.assertEqual(0, pool.snapshot()["retained_bytes"])

    def test_graceful_close_drains_already_admitted_work(self):
        pool, release, processed = self.hold(max_workers=1)
        pool.submit("a", "a2", 1)
        pool.submit("b", "b1", 1)
        self.assertFalse(pool.close(wait=False, cancel_pending=False))
        release.set()
        self.assertTrue(pool.close(cancel_pending=False))
        self.assertEqual(["held", "b1", "a2"], processed)

    def test_idle_threads_retire_and_next_message_starts_a_new_worker(self):
        pool = self.pool(lambda _: None, idle_seconds=0.02)
        pool.submit("one", 1, 1)
        self.assertTrue(pool.wait_idle())
        deadline = time.monotonic() + 1
        while pool.snapshot()["workers"] and time.monotonic() < deadline:
            time.sleep(0.005)
        self.assertEqual(0, pool.snapshot()["workers"])
        self.assertEqual("accepted", pool.submit("two", 2, 1))
        self.assertTrue(pool.wait_idle())
        self.assertEqual(2, pool.snapshot()["processed"])

    def test_worker_creation_failure_rolls_back_admission(self):
        pool = self.pool(lambda _: None)
        with patch("threading.Thread.start", side_effect=RuntimeError("thread creation failed")):
            self.assertEqual("worker_unavailable", pool.submit("route", 1, 30))
        for field in ("pending", "routes", "retained_bytes", "workers", "accepted"):
            self.assertEqual(0, pool.snapshot()[field])
        self.assertEqual("accepted", pool.submit("route", 1, 30))
        self.assertTrue(pool.wait_idle())

    def test_concurrent_producers_keep_each_route_in_order(self):
        actual = {str(index): [] for index in range(4)}
        pool = self.pool(lambda item: actual[item[0]].append(item[1]), max_workers=3, route_pending=1000)
        def send(route):
            for index in range(500):
                self.assertEqual("accepted", pool.submit(route, (route, index), 1))
        with ThreadPoolExecutor(max_workers=4) as producers:
            list(producers.map(send, actual))
        self.assertTrue(pool.wait_idle())
        for values in actual.values():
            self.assertEqual(list(range(500)), values)

    def test_rejected_routes_leave_no_empty_lanes_and_metrics_expose_no_route_ids(self):
        pool, release, _ = self.hold(max_workers=1, max_pending=1)
        pool.submit("private-route", "pending", 1)
        for index in range(10000):
            self.assertEqual("global_pending", pool.submit("rejected-" + str(index), None, 1))
        self.assertEqual(2, pool.snapshot()["routes"])
        self.assertNotIn("private-route", str(pool.snapshot()))
        release.set()
        self.assertTrue(pool.wait_idle())
