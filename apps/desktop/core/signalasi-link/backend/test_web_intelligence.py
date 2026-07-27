import json
import tempfile
import time
import unittest
from pathlib import Path
from urllib.parse import urlsplit

from web_intelligence import (
    AGENT,
    CACHE,
    CRAWL,
    DIFF,
    EXTRACT,
    FETCH,
    FIND_SIMILAR,
    PROTOCOL,
    RESEARCH,
    SEARCH,
    WATCH,
    ENGINE_SPECS,
    EngineReceipt,
    HttpResponse,
    PublicWebTransport,
    WebIntelligenceError,
    WebIntelligenceService,
    WebIntelligenceStore,
    SourceHealth,
    cloud_current_time_prompt,
    cloud_openai_tools,
    contains_internal_tool_protocol,
    execute_cloud_web_tool,
    engine_catalog,
    evolve_source_health,
    parse_inline_tool_calls,
    strip_internal_tool_protocol,
)


class FakeTransport:
    def __init__(self):
        self.calls = []
        self.pages = {
            "https://docs.example.com/root": """
                <html><head><title>SignalASI documentation</title></head>
                <body><main><h1>SignalASI Web Intelligence</h1>
                <p>The local engine searches, ranks, cites, and monitors public evidence.</p>
                <a href="/guide">Guide</a></main></body></html>
            """,
            "https://docs.example.com/guide": """
                <html><head><title>Guide</title></head>
                <body><main><p>The guide explains local cache and source receipts.</p></main></body></html>
            """,
            "https://news.example.com/report": """
                <html><head><title>Independent report</title></head>
                <body><article><p>Independent evidence confirms the research workflow.</p></article></body></html>
            """,
        }

    def fetch(self, url, *, timeout_seconds, max_bytes, headers=None):
        self.calls.append(url)
        started = time.monotonic()
        if "bing.com/search" in url:
            body = """
                <html><body>
                <a href="https://docs.example.com/root?utm_source=bing">SignalASI documentation</a>
                <a href="https://news.example.com/report">Independent report</a>
                </body></html>
            """
            content_type = "text/html; charset=utf-8"
        elif "duckduckgo.com/html" in url:
            body = """
                <html><body>
                <a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fdocs.example.com%2Froot">SignalASI docs</a>
                <a href="https://other.example.net/review">Technical review</a>
                </body></html>
            """
            content_type = "text/html; charset=utf-8"
        elif url in self.pages:
            body = self.pages[url]
            content_type = "text/html; charset=utf-8"
        elif url == "https://other.example.net/review":
            body = "<html><head><title>Review</title></head><body><p>A separate source reviews SignalASI evidence ranking.</p></body></html>"
            content_type = "text/html; charset=utf-8"
        else:
            raise WebIntelligenceError("missing_fake_route", url, retryable=False)
        encoded = body.encode("utf-8")
        if len(encoded) > max_bytes:
            raise WebIntelligenceError("response_too_large", "fake response too large")
        return HttpResponse(
            url=url,
            status=200,
            headers={"content-type": content_type},
            body=encoded,
            duration_ms=int((time.monotonic() - started) * 1000),
        )


class WebIntelligenceServiceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.transport = FakeTransport()
        self.service = WebIntelligenceService(
            self.root,
            transport=self.transport,
            max_workers=4,
        )

    def tearDown(self):
        self.temporary.cleanup()

    def test_catalog_exceeds_eighteen_real_source_adapters_and_exposes_ten_tools(self):
        self.assertGreaterEqual(len(ENGINE_SPECS), 30)
        self.assertEqual(len(ENGINE_SPECS), len(engine_catalog()))
        self.assertEqual(
            {
                SEARCH, FETCH, CRAWL, EXTRACT, CACHE, FIND_SIMILAR,
                RESEARCH, AGENT, DIFF, WATCH,
            },
            {
                "signalasi.web.intelligence.search",
                "signalasi.web.intelligence.fetch",
                "signalasi.web.intelligence.crawl",
                "signalasi.web.intelligence.extract",
                "signalasi.web.intelligence.cache",
                "signalasi.web.intelligence.find_similar",
                "signalasi.web.intelligence.research",
                "signalasi.web.intelligence.agent",
                "signalasi.web.intelligence.diff",
                "signalasi.web.intelligence.watch",
            },
        )

    def test_cloud_adapter_exposes_ten_operations_and_current_time(self):
        names = [
            item["function"]["name"]
            for item in cloud_openai_tools()
        ]

        self.assertEqual(
            [
                "web_search", "web_fetch", "web_crawl", "web_extract", "web_cache",
                "web_find_similar", "web_research", "web_agent", "web_diff", "web_watch",
            ],
            names,
        )
        self.assertIn(str(time.localtime().tm_year), cloud_current_time_prompt())
        self.assertIn("Decide from the user's meaning", cloud_current_time_prompt())
        self.assertNotIn("Asia/Shanghai", cloud_current_time_prompt())

    def test_cloud_adapter_parses_and_hides_deepseek_dsml(self):
        content = """
            <\uff5cDSML\uff5ctool_calls>
            <\uff5cDSML\uff5cinvoke name="web_search">
            <\uff5cDSML\uff5cparam name="query">current technology news</\uff5cDSML\uff5c/param>
            <\uff5cDSML\uff5cparam name="max_results">6</\uff5cDSML\uff5c/param>
            <\uff5cDSML\uff5c/invoke>
            <\uff5cDSML\uff5c/tool_calls>
        """.strip()

        calls = parse_inline_tool_calls(content)

        self.assertTrue(contains_internal_tool_protocol(content))
        self.assertEqual(1, len(calls))
        self.assertEqual("web_search", calls[0].name)
        self.assertEqual("current technology news", calls[0].arguments["query"])
        self.assertEqual(6, calls[0].arguments["max_results"])
        self.assertEqual("", strip_internal_tool_protocol(content))

    def test_cloud_adapter_executes_through_shared_web_intelligence(self):
        result = json.loads(execute_cloud_web_tool(
            self.service,
            "web_search",
            {
                "query": "SignalASI web intelligence",
                "max_results": 4,
                "engines": ["bing", "duckduckgo"],
                "engine_fanout": 2,
                "use_cache": False,
            },
        ))

        self.assertEqual(PROTOCOL, result["protocol"])
        self.assertEqual("search", result["operation"])
        self.assertTrue(result["results"])

    def test_parallel_search_deduplicates_and_explains_score(self):
        result = self.service.search({
            "query": "SignalASI web intelligence",
            "engines": ["bing", "duckduckgo"],
            "engine_fanout": 2,
            "limit": 10,
            "use_cache": False,
        })

        self.assertEqual(PROTOCOL, result["protocol"])
        self.assertEqual("completed", result["status"])
        self.assertEqual(3, len(result["results"]))
        first = result["results"][0]
        self.assertEqual("https://docs.example.com/root", first["url"])
        self.assertEqual(["bing", "duckduckgo"], first["engines"])
        self.assertEqual(
            {
                "final", "reciprocal_rank", "lexical", "consensus",
                "authority", "freshness", "local_model",
            },
            set(first["score"]),
        )
        self.assertEqual(2, len(result["receipts"]))

    def test_search_response_is_persistently_cached(self):
        first = self.service.search({
            "query": "SignalASI cache",
            "engines": ["bing"],
            "engine_fanout": 1,
            "limit": 5,
        })
        calls = len(self.transport.calls)
        second = self.service.search({
            "query": "SignalASI cache",
            "engines": ["bing"],
            "engine_fanout": 1,
            "limit": 5,
        })

        self.assertFalse(first["cache"]["hit"])
        self.assertTrue(second["cache"]["hit"])
        self.assertEqual(calls, len(self.transport.calls))

    def test_fetch_extract_cache_and_similarity_share_local_evidence(self):
        fetched = self.service.fetch({"url": "https://docs.example.com/root"})
        extracted = self.service.extract({
            "url": "https://docs.example.com/root",
            "fields": ["title", "description", "language", "links"],
        })
        similar = self.service.find_similar({
            "query": "local source receipts",
            "limit": 5,
            "search_web": False,
        })

        self.assertIn("searches, ranks, cites", fetched["documents"][0]["content"])
        self.assertTrue(extracted["cache"]["hit"])
        self.assertEqual("SignalASI documentation", extracted["metadata"]["structured"]["title"])
        self.assertEqual("https://docs.example.com/root", similar["results"][0]["url"])

    def test_crawl_stays_on_origin_and_follows_links(self):
        result = self.service.crawl({
            "url": "https://docs.example.com/root",
            "max_pages": 5,
            "max_depth": 2,
            "same_origin": True,
        })

        self.assertEqual("completed", result["status"])
        self.assertEqual(
            {"https://docs.example.com/root", "https://docs.example.com/guide"},
            {item["url"] for item in result["documents"]},
        )

    def test_research_builds_cited_brief_without_cloud_model(self):
        result = self.service.research({
            "query": "How does SignalASI web intelligence work?",
            "max_rounds": 1,
            "source_budget": 3,
            "timeout_seconds": 20,
            "request_id": "research-one",
        } | {
            # Restrict the test to deterministic fake routes.
            "engines": ["bing", "duckduckgo"],
        })

        # Research performs its own intent-selected search, so seed a cached
        # deterministic response through the public search method first.
        if result["status"] == "failed":
            self.fail(json.dumps(result, indent=2))
        self.assertTrue(result["brief"])
        self.assertTrue(result["citations"])
        self.assertEqual("research", result["operation"])

    def test_diff_and_watch_record_integrity_hashes(self):
        first = self.service.fetch({"url": "https://docs.example.com/root"})
        created = self.service.watch({
            "action": "create",
            "url": "https://docs.example.com/root",
            "watch_id": "docs-watch",
            "interval_minutes": 15,
        })
        self.transport.pages["https://docs.example.com/root"] = """
            <html><head><title>SignalASI documentation</title></head>
            <body><main><p>The local engine now includes verified change monitoring.</p></main></body></html>
        """
        changed = self.service.diff({"url": "https://docs.example.com/root"})
        checked = self.service.watch({"action": "check", "watch_id": "docs-watch"})

        self.assertEqual("docs-watch", created["watch"]["watch_id"])
        self.assertNotEqual(
            first["documents"][0]["content_sha256"],
            changed["diff"]["current_sha256"],
        )
        self.assertTrue(changed["diff"]["changed"])
        self.assertEqual("docs-watch", checked["watch"]["watch_id"])

    def test_private_targets_are_blocked_before_transport(self):
        transport = PublicWebTransport(resolver=lambda _host: ["127.0.0.1"])
        with self.assertRaises(WebIntelligenceError) as caught:
            transport.fetch(
                "https://example.com/private",
                timeout_seconds=1,
                max_bytes=4096,
            )
        self.assertEqual("private_network_blocked", caught.exception.code)

    def test_source_health_opens_circuit_and_explicit_source_can_probe(self):
        for _ in range(3):
            self.service.store.record_source_receipt(
                EngineReceipt("bing", "timeout", 5_000, 0, "engine_timeout", "timeout", True)
            )

        health = self.service.store.source_health(["bing"])["bing"]
        self.assertEqual("open", health.circuit_state(int(time.time() * 1_000)))
        adaptive = self.service._select_engines(
            "current SignalASI news",
            32,
            (),
            (),
        )
        explicit = self.service._select_engines(
            "current SignalASI news",
            1,
            ("bing",),
            (),
        )

        self.assertNotIn("bing", adaptive.selected)
        self.assertIn("bing", [item.source_id for item in adaptive.skipped])
        self.assertEqual(("bing",), explicit.selected)
        self.assertTrue(explicit.explicit)

    def test_source_health_is_inspectable_and_resettable(self):
        self.service.store.record_source_receipt(
            EngineReceipt("duckduckgo", "completed", 120, 4)
        )

        inspected = self.service.cache({
            "action": "source_health",
            "engines": ["duckduckgo"],
        })
        rows = inspected["metadata"]["source_health"]
        self.assertEqual(1, len(rows))
        self.assertEqual("duckduckgo", rows[0]["source_id"])
        self.assertEqual("closed", rows[0]["circuit_state"])

        reset = self.service.cache({"action": "reset_source_health"})
        self.assertEqual(1, reset["metadata"]["source_health_removed"])
        self.assertEqual(0, reset["metadata"]["source_health_count"])

    def test_source_health_persists_and_recovers_after_cooldown_probe(self):
        now = [100.0]
        path = self.root / "source-health.sqlite3"
        store = WebIntelligenceStore(path, now=lambda: now[0])
        for _ in range(3):
            store.record_source_receipt(
                EngineReceipt("bing", "failed", 1_000, 0, "source_failed", "failed", True)
            )

        reopened = WebIntelligenceStore(path, now=lambda: now[0])
        self.assertEqual("open", reopened.source_health(["bing"])["bing"].circuit_state(100_000))
        now[0] = 161.0
        self.assertEqual("half_open", reopened.source_health(["bing"])["bing"].circuit_state(161_000))

        recovered = reopened.record_source_receipt(
            EngineReceipt("bing", "completed", 100, 5)
        )
        self.assertEqual("closed", recovered.circuit_state(161_000))
        self.assertEqual(0, recovered.consecutive_failures)

    def test_cancelled_receipt_does_not_reduce_source_reliability(self):
        previous = SourceHealth("bing", attempts=2, successes=2)
        current = evolve_source_health(
            previous,
            EngineReceipt("bing", "cancelled", 10, 0),
            1_000,
        )

        self.assertEqual(previous.attempts, current.attempts)
        self.assertEqual(previous.failures, current.failures)
        self.assertEqual("cancelled", current.last_status)

    def test_search_profiles_supply_budget_defaults_and_metadata(self):
        result = self.service.search({
            "query": "SignalASI profile",
            "profile": "fast",
            "engines": ["bing"],
            "use_cache": False,
        })

        self.assertEqual("fast", result["metadata"]["profile"])
        self.assertEqual("explicit_sources", result["metadata"]["source_selection"])
        self.assertEqual(1, len(result["metadata"]["source_health"]))


if __name__ == "__main__":
    unittest.main()
