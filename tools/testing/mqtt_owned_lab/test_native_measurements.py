import unittest

from native_measurements import Measurements, summarize


class MeasurementTest(unittest.TestCase):
    def setUp(self):
        self.now = 0
        self.metrics = Measurements(clock=lambda: self.now, limit=32)

    def sample(self, mid, duration):
        self.metrics.begin(mid)
        self.now += 1_000_000
        self.metrics.stage(mid, "queued")
        self.metrics.physical_start(mid, mid, "emqx", 1024)
        self.metrics.physical_end(mid, mid, True)
        self.now += duration * 1_000_000
        self.metrics.stage(mid, "receipt_committed")
        return self.metrics.snapshot(mid)

    def test_late_polling_does_not_change_receipt_latency(self):
        sample = self.sample("one", 3)
        self.now += 99_000_000_000
        self.assertEqual(sample, self.metrics.snapshot("one"))
        self.metrics.stage("one", "receipt_committed")
        self.assertEqual(4, summarize([self.metrics.snapshot("one")])["request_to_rx_stored_ms"]["p95"])

    def test_nearest_rank_uses_all_samples_and_not_only_fastest(self):
        samples = [self.sample(str(i), i) for i in range(1, 31)]
        result = summarize(samples)
        self.assertEqual(30, result["samples"])
        self.assertEqual({"p50": 15, "p95": 29, "max": 30}, result["first_publish_to_rx_stored_ms"])

    def test_missing_receipt_is_not_zero_or_success(self):
        self.metrics.begin("missing")
        with self.assertRaises(ValueError):
            summarize([self.metrics.snapshot("missing")])

    def test_duplicate_ids_and_capacity_are_rejected(self):
        metrics = Measurements(limit=1)
        metrics.begin("one")
        for mid in ("one", "two"):
            with self.assertRaises(ValueError):
                metrics.begin(mid)

    def test_redundancy_counts_accepted_mqtt_submissions_not_failed_attempts(self):
        self.sample("one", 3)
        self.metrics.physical_start("one", "two", "hivemq", 1100)
        self.metrics.physical_end("one", "two", True)
        self.metrics.physical_start("one", "failed", "mosquitto", 1200)
        with self.assertRaises(ValueError):
            summarize([self.metrics.snapshot("one")])
        self.metrics.physical_end("one", "failed", False)
        result = summarize([self.metrics.snapshot("one")])
        self.assertEqual(2124, result["submitted_mqtt_bytes"])
        self.assertEqual(1100, result["redundant_submitted_mqtt_bytes"])
        self.assertEqual({"emqx": 1, "hivemq": 1}, result["submitted_packets_by_path"])

    def test_snapshot_cannot_mutate_samples_and_ready_is_recorded_once(self):
        sample = self.sample("one", 3)
        sample["stages"].clear()
        self.assertTrue(self.metrics.snapshot("one")["stages"])
        self.metrics.first_ready()
        self.now += 1_000_000
        self.metrics.first_ready()
        self.assertEqual(4, self.metrics.snapshot()["startup_to_authenticated_ready_ms"])

    def test_rejected_publication_is_not_the_first_actual_submission(self):
        self.metrics.begin("one")
        self.metrics.stage("one", "queued")
        self.metrics.physical_start("one", "failed", "emqx", 1024)
        self.metrics.physical_end("one", "failed", False)
        self.now = 10_000_000
        self.metrics.physical_start("one", "sent", "hivemq", 1024)
        self.metrics.physical_end("one", "sent", True)
        self.now = 11_000_000
        self.metrics.stage("one", "receipt_committed")
        result = summarize([self.metrics.snapshot("one")])
        self.assertEqual(1, result["first_publish_to_rx_stored_ms"]["p95"])
        self.assertEqual(1, result["submitted_packets"])


if __name__ == "__main__":
    unittest.main()
