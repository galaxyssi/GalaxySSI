import contextlib
import concurrent.futures
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from test_web_intelligence import FakeTransport
from web_intelligence import EngineReceipt, RawSearchResult, WebIntelligenceService, WebIntelligenceError
from web_search_timing import SearchResponseTiming


class Clock:
    def __init__(self):
        self.ns = 0

    def __call__(self):
        return self.ns

    def advance(self, ms):
        self.ns += int(ms * 1_000_000)


class SearchResponseTimingTests(unittest.TestCase):
    def test_elapsed_and_phases_include_preparation_and_final_persistence(self):
        clock = Clock()
        timing = SearchResponseTiming(clock)
        clock.advance(200)
        timing.mark("prepare")
        clock.advance(1000)
        timing.mark("sources")
        clock.advance(300)
        timing.mark("cache_write")
        result = timing.finish({}, completed_at_millis=123, source_budget_seconds=1)
        self.assertEqual(1500, result["metadata"]["elapsed_millis"])
        details = result["metadata"]["response_timing"]
        self.assertEqual({"prepare": 200, "sources": 1000, "cache_write": 300, "finalize": 0}, details["phases_ms"])
        self.assertEqual(1000, details["source_budget_ms"])
        self.assertEqual(123, result["completed_at_millis"])

    def test_simultaneous_responses_do_not_share_phases(self):
        clock = Clock()
        first = SearchResponseTiming(clock)
        clock.advance(100)
        second = SearchResponseTiming(clock)
        clock.advance(200)
        a = first.finish({}, completed_at_millis=0, source_budget_seconds=1)
        b = second.finish({}, completed_at_millis=0, source_budget_seconds=1)
        self.assertEqual(300, a["metadata"]["elapsed_millis"])
        self.assertEqual(200, b["metadata"]["elapsed_millis"])

    def test_wall_clock_changes_do_not_change_monotonic_duration(self):
        clock = Clock()
        timing = SearchResponseTiming(clock)
        clock.advance(50)
        result = timing.finish({"started_at_millis": 10000}, completed_at_millis=1, source_budget_seconds=3)
        self.assertEqual(50, result["metadata"]["elapsed_millis"])


class WebSearchTimingIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.service = WebIntelligenceService(Path(self.temporary.name), transport=FakeTransport())
        self.arguments = {"query": "GalaxySSI timing", "engines": ["bing"], "timeout_seconds": 1}

    def tearDown(self):
        self.temporary.cleanup()

    def test_every_cache_connection_preserves_full_durable_wal_commits(self):
        for _ in range(3):
            with contextlib.closing(self.service.store._connect()) as connection:
                self.assertEqual(2, connection.execute("PRAGMA synchronous").fetchone()[0])
                self.assertEqual("wal", connection.execute("PRAGMA journal_mode").fetchone()[0])

    def test_cache_transactions_still_rollback_failures(self):
        with self.assertRaisesRegex(RuntimeError, "rollback"):
            with self.service.store._connection() as connection:
                connection.execute("INSERT INTO source_health (source_id, attempts, successes, empty_responses, failures, consecutive_failures, ewma_latency_millis, ewma_result_count, last_status, last_attempt_at_millis, last_success_at_millis, circuit_open_until_millis) VALUES ('rollback-test', 1, 1, 0, 0, 0, 1, 1, 'completed', 1, 1, 0)")
                raise RuntimeError("rollback")
        self.assertNotIn("rollback-test", self.service.store.source_health())

    def test_batch_health_update_commits_all_receipts_using_one_connection(self):
        receipts = [EngineReceipt("bing", "completed", 50, 2), EngineReceipt("duckduckgo", "timeout", 1000, 0)]
        with patch.object(self.service.store, "_connect", wraps=self.service.store._connect) as connect:
            updated = self.service.store.record_source_receipts(receipts)
            self.assertEqual(1, connect.call_count)
        self.assertEqual(["bing", "duckduckgo"], [row.source_id for row in updated])
        stored = self.service.store.source_health()
        self.assertEqual(1, stored["bing"].successes)
        self.assertEqual("timeout", stored["duckduckgo"].last_status)

    def test_batch_health_failure_rolls_back_prior_receipts(self):
        write = self.service.store._write_source_receipt
        def fail_second(connection, receipt, now):
            if receipt.source_id == "duckduckgo":
                raise RuntimeError("second receipt failed")
            return write(connection, receipt, now)
        with patch.object(self.service.store, "_write_source_receipt", side_effect=fail_second), \
             self.assertRaisesRegex(RuntimeError, "second receipt"):
            self.service.store.record_source_receipts([
                EngineReceipt("bing", "completed", 1, 1), EngineReceipt("duckduckgo", "completed", 2, 1)])
        self.assertEqual({}, self.service.store.source_health())

    def test_empty_batch_does_not_open_a_database_connection(self):
        with patch.object(self.service.store, "_connect", side_effect=AssertionError("unnecessary I/O")):
            self.assertEqual((), self.service.store.record_source_receipts([]))

    def test_actual_search_includes_preparation_and_cache_write_before_return(self):
        clock = Clock()
        refresh = self.service._refresh_learned_sources
        write = self.service.store.put_search
        def delayed_refresh():
            clock.advance(100)
            return refresh()
        def delayed_write(*args, **kwargs):
            clock.advance(400)
            return write(*args, **kwargs)
        with patch("web_search_timing.SearchResponseTiming", side_effect=lambda: SearchResponseTiming(clock)), \
             patch.object(self.service, "_refresh_learned_sources", side_effect=delayed_refresh), \
             patch.object(self.service.store, "put_search", side_effect=delayed_write):
            result = self.service.search(self.arguments)
        timing = result["metadata"]["response_timing"]
        self.assertEqual(600, timing["elapsed_ms"])
        self.assertEqual(600, result["metadata"]["elapsed_millis"])
        self.assertEqual(100, timing["phases_ms"]["prepare"])
        self.assertEqual(100, timing["phases_ms"]["learning"])
        self.assertEqual(400, timing["phases_ms"]["cache_write"])
        self.assertTrue(result["results"])

    def test_cache_hit_has_fresh_timings_not_previous_source_or_write_duration(self):
        first = self.service.search(self.arguments)
        self.assertIn("sources", first["metadata"]["response_timing"]["phases_ms"])
        clock = Clock()
        read = self.service.store.get_search
        def delayed_read(*args):
            clock.advance(25)
            return read(*args)
        with patch("web_search_timing.SearchResponseTiming", side_effect=lambda: SearchResponseTiming(clock)), \
             patch.object(self.service.store, "get_search", side_effect=delayed_read):
            result = self.service.search(self.arguments)
        self.assertTrue(result["cache"]["hit"])
        timing = result["metadata"]["response_timing"]
        self.assertEqual(25, timing["elapsed_ms"])
        self.assertEqual({"prepare": 25, "finalize": 0}, timing["phases_ms"])

    def test_failed_search_still_has_total_timing_and_real_failure_receipt(self):
        class FailingSource:
            def search(self, *_args):
                raise WebIntelligenceError("unavailable", "Unavailable", retryable=True)
        self.service.engines["bing"] = FailingSource()
        result = self.service.search({**self.arguments, "use_cache": False})
        self.assertEqual("failed", result["status"])
        self.assertEqual("unavailable", result["receipts"][0]["error_code"])
        timing = result["metadata"]["response_timing"]
        self.assertGreaterEqual(timing["elapsed_ms"], 0)
        self.assertAlmostEqual(timing["elapsed_ms"], sum(timing["phases_ms"].values()), delta=.01)

    def test_shared_source_deadline_does_not_restart_after_a_source_completes(self):
        fast = concurrent.futures.Future()
        fast.set_result([RawSearchResult("bing", 1, "Evidence", "https://example.com/a", "Evidence")])
        slow = concurrent.futures.Future()
        slow.set_running_or_notify_cancel()
        executor = SimpleNamespace(submit=Mock(side_effect=[fast, slow]), shutdown=Mock())
        clock = Clock()
        waits = []
        def wait(pending, *, timeout, return_when):
            waits.append(timeout)
            self.assertEqual(concurrent.futures.FIRST_COMPLETED, return_when)
            if len(waits) == 1:
                self.assertEqual({fast, slow}, pending)
                clock.advance(250)
                return {fast}, {slow}
            self.assertEqual({slow}, pending)
            clock.advance(750)
            return set(), {slow}
        controlled = SimpleNamespace(futures=SimpleNamespace(
            ThreadPoolExecutor=Mock(return_value=executor), wait=wait,
            FIRST_COMPLETED=concurrent.futures.FIRST_COMPLETED))
        import web_intelligence
        with patch.object(web_intelligence, "concurrent", controlled), \
             patch.object(web_intelligence, "time", SimpleNamespace(monotonic=lambda: clock() / 1_000_000_000)):
            result = self.service.search({**self.arguments, "engines": ["bing", "duckduckgo"],
                                          "engine_fanout": 2, "use_cache": False})
        self.assertEqual([1, .75], waits)
        executor.shutdown.assert_called_once_with(wait=False, cancel_futures=True)
        self.assertEqual("partial", result["status"])
        receipts = {row["source_id"]: row for row in result["receipts"]}
        self.assertEqual("timeout", receipts["duckduckgo"]["status"])
        self.assertEqual(1000, receipts["duckduckgo"]["duration_millis"])
        self.assertFalse(slow.done())


if __name__ == "__main__":
    unittest.main()
