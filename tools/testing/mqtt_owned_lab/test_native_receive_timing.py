from types import SimpleNamespace
import threading
import unittest

from native_receive_timing import ReceiveTiming


class ReceiveTimingTests(unittest.TestCase):
    def fixture(self, deliver, **limits):
        observer = ReceiveTiming(**limits)
        bridge = SimpleNamespace(_deliver_stored_application=deliver,
            _ack_stored_application=lambda *a, **kw: "ack",
            _publish_phone_payload=lambda *a, **kw: "publish",
            _dispatch_application_payload=lambda *a, **kw: "dispatch")
        observer.install(bridge)
        return observer, bridge

    def call(self, bridge, mid="one", **kwargs):
        return bridge._deliver_stored_application(None, {}, {}, {"message_id": mid},
            {"type": "peer_message", "text": "must not be captured"}, [], **kwargs)

    def test_preserves_calls_return_value_and_original_timing(self):
        def deliver(*args, **kwargs):
            self.assertEqual("ack", bridge._ack_stored_application(*args, **kwargs))
            self.assertEqual("publish", bridge._publish_phone_payload(None, {}, {}))
            return bridge._dispatch_application_payload(*args)
        observer, bridge = self.fixture(deliver)
        self.assertEqual("dispatch", self.call(bridge, timings=[("received", 123)]))
        result = observer.snapshot()["samples"]["one"][0]
        self.assertEqual(123, result["stages"]["received"])
        self.assertEqual({"kind", "stages"}, set(result))
        for name in ("delivery", "ack", "publish", "dispatch"):
            self.assertLessEqual(result["stages"][name + "_enter"], result["stages"][name + "_return"])
        result["stages"].clear()
        self.assertTrue(observer.snapshot()["samples"]["one"][0]["stages"])

    def test_exception_propagates_and_context_is_cleared(self):
        def deliver(*args, **kwargs):
            raise RuntimeError("original failure")
        observer, bridge = self.fixture(deliver)
        with self.assertRaisesRegex(RuntimeError, "original failure"):
            self.call(bridge)
        observer.stage("unrelated")
        stages = observer.snapshot()["samples"]["one"][0]["stages"]
        self.assertIn("delivery_return", stages)
        self.assertNotIn("unrelated", stages)

    def test_bounds_do_not_stop_real_delivery(self):
        calls = []
        observer, bridge = self.fixture(lambda *a, **k: calls.append(a[3]["message_id"]),
            limit=1, calls_per_message=1)
        for mid in ("one", "one", "two"):
            self.call(bridge, mid)
        self.assertEqual(["one", "one", "two"], calls)
        self.assertEqual(2, observer.snapshot()["dropped_calls"])
        self.assertEqual(["one"], list(observer.snapshot()["samples"]))

    def test_concurrent_threads_keep_separate_samples(self):
        barrier = threading.Barrier(2)
        def deliver(*args, **kwargs):
            barrier.wait(timeout=5)
            observer.stage(args[3]["message_id"])
        observer, bridge = self.fixture(deliver)
        threads = [threading.Thread(target=self.call, args=(bridge, mid)) for mid in ("one", "two")]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=6)
            self.assertFalse(thread.is_alive())
        samples = observer.snapshot()["samples"]
        for mid, other in (("one", "two"), ("two", "one")):
            self.assertIn(mid, samples[mid][0]["stages"])
            self.assertNotIn(other, samples[mid][0]["stages"])

    def test_nested_delivery_restores_outer_context(self):
        def deliver(*args, **kwargs):
            if args[3]["message_id"] == "outer":
                self.call(bridge, "inner")
                observer.stage("outer_only")
        observer, bridge = self.fixture(deliver)
        self.call(bridge, "outer")
        samples = observer.snapshot()["samples"]
        self.assertIn("outer_only", samples["outer"][0]["stages"])
        self.assertNotIn("outer_only", samples["inner"][0]["stages"])
