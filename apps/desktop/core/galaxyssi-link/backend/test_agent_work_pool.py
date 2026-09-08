"""Deterministic admission and bounded-thread tests, without real model calls."""
import threading
import time
import unittest

from agent_work_pool import AgentQueueFull, AgentWorkPool, ExecutionKey


def key(task, app="a", conversation="c", generation=1):
    return ExecutionKey(app, conversation, "turn", task, generation)


class AgentWorkPoolTest(unittest.TestCase):
    def pool(self, **kwargs):
        pool = AgentWorkPool(**kwargs)
        self.addCleanup(pool.close)
        return pool

    def occupy(self, pool, count=1):
        release = threading.Event()
        self.addCleanup(release.set)
        futures = []
        for i in range(count):
            started = threading.Event()
            def blocked(started=started):
                started.set()
                if not release.wait(10):
                    raise TimeoutError("Test did not release worker")
            futures.append(pool.submit(key(f"block-{i}", app="blocker"), blocked))
            self.assertTrue(started.wait(2))
        return release, futures

    def test_round_robin_apps_before_a_second_slot_for_one_app(self):
        pool = self.pool(max_workers=1)
        release, _ = self.occupy(pool)
        observed = []
        futures = [pool.submit(key(f"{app}-{i}", app=app), lambda app=app: observed.append(app))
                   for app in "abc" for i in range(3)]
        release.set()
        for future in futures:
            future.result(3)
        self.assertEqual(list("abcabcabc"), observed)

    def test_conversations_alternate_inside_one_app(self):
        pool = self.pool(max_workers=1)
        release, _ = self.occupy(pool)
        observed = []
        for conversation in "xy":
            for i in range(3):
                pool.submit(key(f"{conversation}-{i}", conversation=conversation),
                            lambda conversation=conversation: observed.append(conversation))
        release.set()
        self.assertTrue(pool.wait_idle(3))
        self.assertEqual(list("xyxyxy"), observed)

    def test_same_execution_is_idempotent_and_other_generations_are_distinct(self):
        pool = self.pool(max_workers=1)
        release, _ = self.occupy(pool)
        first = pool.submit(key("same"), lambda: 1)
        self.assertIs(first, pool.submit(key("same"), lambda: 999))
        next_generation = pool.submit(key("same", generation=2), lambda: 2)
        other_app = pool.submit(key("same", app="b"), lambda: 3)
        release.set()
        self.assertEqual([1, 2, 3], [item.result(3) for item in (first, next_generation, other_app)])

    def test_full_queue_rejects_without_creating_another_worker(self):
        pool = self.pool(max_workers=1, max_pending=2)
        release, _ = self.occupy(pool)
        for i in range(2):
            pool.submit(key(str(i)), lambda: None)
        with self.assertRaises(AgentQueueFull):
            pool.submit(key("overflow"), lambda: None)
        self.assertEqual(1, pool.snapshot()["workers"])
        self.assertEqual(2, pool.snapshot()["pending"])
        self.assertEqual(1, pool.snapshot()["rejected"])
        release.set()

    def test_cancel_queued_execution_releases_capacity_without_running_it(self):
        pool = self.pool(max_workers=1, max_pending=1)
        release, _ = self.occupy(pool)
        called = []
        pending = pool.submit(key("cancel"), lambda: called.append(True))
        self.assertTrue(pool.cancel(key("cancel")))
        self.assertTrue(pending.cancelled())
        replacement = pool.submit(key("replacement"), lambda: "ok")
        release.set()
        self.assertEqual("ok", replacement.result(3))
        self.assertEqual([], called)

    def test_ten_thousand_pending_jobs_use_only_ten_workers(self):
        pool = self.pool(max_workers=10, max_pending=10000)
        release, active = self.occupy(pool, 10)
        started = time.monotonic()
        futures = [pool.submit(key(str(i), app=f"app-{i % 100}", conversation=f"session-{i % 37}"),
                               lambda i=i: i) for i in range(10000)]
        state = pool.snapshot()
        self.assertEqual((10, 10, 10000), (state["workers"], state["active"], state["pending"]))
        release.set()
        self.assertEqual(list(range(10000)), [future.result(10) for future in futures])
        self.assertTrue(pool.wait_idle(3))
        print(f"WORK_POOL_PROBE jobs=10000 workers=10 elapsed_ms={(time.monotonic()-started)*1000:.1f}")

    def test_failed_callback_does_not_kill_worker_or_strand_queue(self):
        pool = self.pool(max_workers=1)
        def fail():
            raise ValueError("test failure")
        failure = pool.submit(key("failure"), fail)
        success = pool.submit(key("success"), lambda: 42)
        with self.assertRaises(ValueError):
            failure.result(3)
        self.assertEqual(42, success.result(3))

    def test_idle_workers_exit_and_restart_on_new_admission(self):
        pool = self.pool(max_workers=1, idle_seconds=.02)
        self.assertEqual(1, pool.submit(key("first"), lambda: 1).result(3))
        deadline = time.monotonic() + 2
        while pool.snapshot()["workers"] and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertEqual(0, pool.snapshot()["workers"])
        self.assertEqual(2, pool.submit(key("second"), lambda: 2).result(3))

    def test_close_cancels_pending_but_does_not_stop_active_callback(self):
        pool = self.pool(max_workers=1)
        release, active = self.occupy(pool)
        pending = pool.submit(key("pending"), lambda: 42)
        self.assertFalse(pool.close(wait=False, cancel_pending=True))
        self.assertTrue(pending.cancelled())
        self.assertFalse(active[0].done())
        with self.assertRaises(RuntimeError):
            pool.submit(key("closed"), lambda: None)
        release.set()
        self.assertTrue(pool.close())

    def test_incomplete_execution_identity_is_rejected(self):
        pool = self.pool()
        for value in (key(""), key("t", app=""), key("t", generation=0), key("t", generation=True)):
            with self.subTest(value=value), self.assertRaises(ValueError):
                pool.submit(value, lambda: None)
