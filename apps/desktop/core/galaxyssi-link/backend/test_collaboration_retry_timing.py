import unittest

from collaboration_retry_timing import ResponseRetryTiming
from collaboration_recall_bridge import RecallBroker, RESPONSE
from test_collaboration_recall_bridge import task
from test_collaboration_recall_retry import simulated_time


class ResponseRetryTimingTest(unittest.TestCase):
    def test_cold_default_then_completion_margin_and_fast_recovery(self):
        timing = ResponseRetryTiming()
        self.assertEqual(2, timing.delay("phone", 0))
        timing.completed("phone", 3, 3)
        self.assertEqual(8, timing.delay("phone", 3))
        for now in range(4, 64):
            timing.completed("phone", .1, now)
        self.assertEqual(2, timing.delay("phone", 64))

    def test_peer_isolation_expiry_clock_reset_and_bounded_memory(self):
        timing = ResponseRetryTiming(capacity=2, ttl=10)
        timing.completed("a", 3, 10)
        self.assertEqual(2, timing.delay("b", 11))
        self.assertEqual(8, timing.delay("a", 19))
        self.assertEqual(2, timing.delay("a", 20))
        timing.completed("a", 3, 20)
        self.assertEqual(2, timing.delay("a", 19))
        for peer in ("a", "b", "c"):
            timing.completed(peer, 3, 30)
        self.assertEqual(2, len(timing._peers))
        self.assertEqual(2, timing.delay("a", 30))
        self.assertEqual(8, timing.delay("c", 30))

    def test_timeout_backoff_capped_and_invalid_samples_ignored(self):
        timing = ResponseRetryTiming()
        for value in (0, -1, float("nan"), float("inf")):
            timing.completed("a", value, 0)
        self.assertEqual(2, timing.delay("a", 0))
        timing.timed_out("a", 1)
        self.assertEqual(4, timing.delay("a", 1))
        timing.timed_out("a", 2)
        timing.timed_out("a", 3)
        self.assertEqual(8, timing.delay("a", 3))

    def test_slower_valid_reply_does_not_trigger_retries_on_following_exchange(self):
        with simulated_time() as clock:
            broker, calls, pending = RecallBroker(), [], []
            def publish(request):
                calls.append((clock.now, request))
                pending.append((clock.now + 3, request))
                return True
            def respond():
                for due, request in list(pending):
                    if due <= clock.now:
                        pending.remove((due, request))
                        broker.receive({**request, "type": RESPONSE, "result": {"success": True}}, "phone")
            clock.on_wait = respond
            self.assertTrue(broker.query(task, {"mode": "workspace"}, publish)["success"])
            self.assertEqual(2, len(calls))
            self.assertTrue(broker.query(task, {"mode": "workspace"}, publish)["success"])
            self.assertEqual(3, len(calls))
            self.assertEqual(6, clock.now)

    def test_known_slow_peer_still_retries_loss_with_original_deadline(self):
        with simulated_time() as clock:
            broker, calls = RecallBroker(), []
            broker._retry_timing.completed("phone", 3, 0)
            def publish(request):
                calls.append((clock.now, request))
                if len(calls) == 2:
                    broker.receive({**request, "type": RESPONSE, "result": {"success": True}}, "phone")
                return True
            self.assertTrue(broker.query(task, {"mode": "workspace"}, publish)["success"])
            self.assertEqual([0, 8], [at for at, _ in calls])
            self.assertEqual(calls[0][1], calls[1][1])
            self.assertEqual(1020000, calls[0][1]["expires_at"])

    def test_unauthenticated_or_rejected_scope_reply_does_not_train_timing(self):
        with simulated_time() as clock:
            broker, calls = RecallBroker(), []
            def publish(request):
                calls.append(request)
                clock.now += 3
                self.assertFalse(broker.receive({**request, "type": RESPONSE, "result": {"success": True}}, "wrong"))
                self.assertFalse(broker.receive({**request, "type": RESPONSE, "execution_generation": 2,
                    "result": {"success": True}}, "phone"))
                raise RuntimeError("end test without a valid reply")
            with self.assertRaises(RuntimeError):
                broker.query(task, {"mode": "workspace"}, publish)
            self.assertEqual(2, broker._retry_timing.delay("phone", clock.now))

    def test_publish_rejection_does_not_wait_for_slow_reply_estimate(self):
        with simulated_time() as clock:
            broker, calls = RecallBroker(), []
            broker._retry_timing.completed("phone", 3, 0)
            def publish(request):
                calls.append(clock.now)
                if len(calls) == 1:
                    return False
                broker.receive({**request, "type": RESPONSE, "result": {"success": True}}, "phone")
                return True
            self.assertTrue(broker.query(task, {"mode": "workspace"}, publish)["success"])
            self.assertEqual([0, 2], calls)

    def test_short_deadline_and_cancellation_remain_authoritative_for_slow_peer(self):
        with simulated_time() as clock:
            broker, calls = RecallBroker(), []
            broker._retry_timing.completed("phone", 3, 0)
            def publish(request):
                calls.append(clock.now)
                return True
            with self.assertRaises(TimeoutError):
                broker.query(task, {"mode": "workspace"}, publish, timeout=1)
            self.assertEqual([0], calls)
            self.assertEqual(1, clock.now)
            live = [True]
            clock.on_wait = lambda: live.__setitem__(0, False)
            with self.assertRaises(ValueError):
                broker.query(task, {"mode": "workspace"}, publish, active=lambda: live[0])
            self.assertEqual([0, 1], calls)
            self.assertEqual({}, broker._pending)

    def test_serial_receiver_model_avoids_retry_amplification(self):
        def run(adaptive):
            with simulated_time() as clock:
                broker, queued, calls, finished, failures = RecallBroker(), [], [], [0], 0
                if not adaptive:
                    class Fixed:
                        def delay(self, *args): return 2
                        def completed(self, *args): pass
                        def timed_out(self, *args): pass
                    broker._retry_timing = Fixed()
                def publish(request):
                    calls.append(request)
                    finished[0] = max(clock.now + .5, finished[0]) + 2
                    queued.append((finished[0], request))
                    return True
                def respond():
                    for due, request in list(queued):
                        if due <= clock.now:
                            queued.remove((due, request))
                            broker.receive({**request, "type": RESPONSE, "result": {"success": True}}, "phone")
                clock.on_wait = respond
                for _ in range(12):
                    try:
                        broker.query(task, {"mode": "workspace"}, publish)
                    except TimeoutError:
                        failures += 1
                return len(calls), failures, clock.now
        fixed, adaptive = run(False), run(True)
        self.assertEqual((13, 0), adaptive[:2])
        self.assertGreater(fixed[0], adaptive[0])
        self.assertGreaterEqual(fixed[1], adaptive[1])
        self.assertGreater(fixed[2], adaptive[2])


if __name__ == "__main__":
    unittest.main()
