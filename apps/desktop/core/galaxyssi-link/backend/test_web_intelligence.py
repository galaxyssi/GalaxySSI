import hashlib
import json
import tempfile
import threading
import time
import unittest
from collections import Counter
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
    EVIDENCE_PACK_PROTOCOL,
    WEB_VERTICALS,
    _compact_cloud_evidence_pack,
    EngineReceipt,
    FusedSearchResult,
    HttpResponse,
    MAX_CLOUD_TOOL_RESULT_CHARS,
    PublicWebTransport,
    RawSearchResult,
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
from web_evidence_pack import build_evidence_pack


class FakeTransport:
    def __init__(self):
        self.calls = []
        self.requests = []
        self.pages = {
            "https://docs.example.com/root": """
                <html><head><title>GalaxySSI documentation</title></head>
                <body><main><h1>GalaxySSI Web Intelligence</h1>
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
        self.requests.append({"url": url, "headers": dict(headers or {})})
        started = time.monotonic()
        if "site%3Atripadvisor.com" in url:
            body = """<?xml version="1.0" encoding="utf-8"?>
                <rss version="2.0"><channel>
                <item><title>Trusted result</title>
                <link>https://www.tripadvisor.com/Hotel_Review-test</link>
                <description>Trusted hotel evidence.</description></item>
                <item><title>Injected result</title>
                <link>https://attacker.example/fake</link>
                <description>Must be filtered.</description></item>
                </channel></rss>
            """
            content_type = "application/rss+xml; charset=utf-8"
        elif "bing.com/search" in url:
            body = """<?xml version="1.0" encoding="utf-8"?>
                <rss version="2.0"><channel>
                <item><title>GalaxySSI documentation</title>
                <link>https://docs.example.com/root?utm_source=bing</link>
                <description>GalaxySSI web intelligence documentation.</description></item>
                <item><title>Independent report</title>
                <link>https://news.example.com/report</link>
                <description>Independent GalaxySSI report.</description></item>
                </channel></rss>
            """
            content_type = "application/rss+xml; charset=utf-8"
        elif "duckduckgo.com/html" in url:
            body = """
                <html><body>
                <a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fdocs.example.com%2Froot">GalaxySSI docs</a>
                <a href="https://other.example.net/review">Technical review</a>
                </body></html>
            """
            content_type = "text/html; charset=utf-8"
        elif "duckduckgo.com/?" in url and "iax=images" in url:
            body = """<script>window.__search = {vqd='123-456'};</script>"""
            content_type = "text/html; charset=utf-8"
        elif "duckduckgo.com/i.js" in url:
            body = json.dumps({
                "results": [{
                    "title": "GalaxySSI mobile agent",
                    "url": "https://images.example.com/article",
                    "image": "https://cdn.example.com/galaxyssi.png",
                    "thumbnail": "https://cdn.example.com/galaxyssi-thumb.png",
                    "width": 1200,
                    "height": 800,
                }]
            })
            content_type = "application/json"
        elif "api2.marginalia-search.com/search" in url:
            body = json.dumps({
                "results": [{
                    "title": "Independent GalaxySSI notes",
                    "url": "https://indie.example.com/galaxyssi",
                    "description": "A small-web source about GalaxySSI.",
                }]
            })
            content_type = "application/json"
        elif "api.github.com/search/code" in url:
            body = json.dumps({
                "items": [{
                    "name": "AgentLoop.kt",
                    "path": "apps/android/AgentLoop.kt",
                    "html_url": "https://github.com/galaxyssi/GalaxySSI/blob/main/apps/android/AgentLoop.kt",
                    "repository": {
                        "full_name": "galaxyssi/GalaxySSI",
                        "description": "GalaxySSI mobile super agent",
                        "updated_at": "2026-07-27T00:00:00Z",
                    },
                }]
            })
            content_type = "application/json"
        elif "api.search.brave.com/res/v1/images/search" in url:
            body = json.dumps({
                "results": [{
                    "title": "GalaxySSI interface",
                    "url": "https://design.example.com/galaxyssi",
                    "source": "design.example.com",
                    "properties": {
                        "url": "https://cdn.example.com/galaxyssi-interface.jpg",
                        "width": 1600,
                        "height": 900,
                    },
                    "thumbnail": {
                        "src": "https://cdn.example.com/galaxyssi-interface-thumb.jpg",
                    },
                }]
            })
            content_type = "application/json"
        elif url in self.pages:
            body = self.pages[url]
            content_type = "text/html; charset=utf-8"
        elif url == "https://other.example.net/review":
            body = "<html><head><title>Review</title></head><body><p>A separate source reviews GalaxySSI evidence ranking.</p></body></html>"
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
        self.assertEqual(287, len(ENGINE_SPECS))
        self.assertEqual(len(ENGINE_SPECS), len(engine_catalog()))
        self.assertTrue({
            "bing", "bing_news", "brave", "brave_image", "duckduckgo",
            "duckduckgo_image", "mojeek", "marginalia", "wikipedia",
            "stackoverflow", "hacker_news", "lobsters", "github_code",
            "devdocs", "mdn", "arxiv", "semantic_scholar", "crates_io",
        }.issubset({spec.engine_id for spec in ENGINE_SPECS}))
        counts = Counter(
            spec.vertical
            for spec in ENGINE_SPECS
            if spec.default_enabled
        )
        for vertical in set(WEB_VERTICALS) - {"local"}:
            self.assertIn(
                counts[vertical],
                range(5, 11),
                f"{vertical} must expose five to ten sources",
            )
        digest = hashlib.sha256(
            "\n".join(sorted(spec.engine_id for spec in ENGINE_SPECS)).encode()
        ).hexdigest()
        self.assertEqual(
            "ebe2e39787edab5166db322b0322e1440ccc733a150db5375443e6bd721f56a9",
            digest,
        )

    def test_bing_rss_adapter_parses_fast_search_evidence(self):
        spec = next(item for item in ENGINE_SPECS if item.engine_id == "bing")
        self.assertEqual("rss", spec.parser)
        self.assertIn("format=rss", spec.endpoint)
        feed = """<?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0"><channel><item>
          <title>Beijing weather today</title>
          <link>https://weather.example/beijing</link>
          <description>Sunny, 25 to 35 C.</description>
          <pubDate>Thu, 06 Aug 2026 02:00:00 GMT</pubDate>
        </item></channel></rss>"""

        results = self.service.engines["bing"]._parse_rss(feed, 5)

        self.assertEqual(1, len(results))
        self.assertEqual("https://weather.example/beijing", results[0].url)
        self.assertIn("25 to 35 C", results[0].excerpt)

    def test_indexed_sources_use_rss_and_reject_results_from_other_hosts(self):
        spec = next(item for item in ENGINE_SPECS if item.engine_id == "china_weather")
        self.assertEqual("site_rss", spec.parser)
        self.assertIn("format=rss", spec.endpoint)
        feed = """<?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0"><channel>
          <item><title>Beijing weather</title>
            <link>https://bj.weather.com.cn/index.shtml</link>
            <description>Beijing 35 C / 26 C.</description></item>
          <item><title>Unrelated result</title>
            <link>https://example.com/weather</link>
            <description>Must not escape the indexed source.</description></item>
        </channel></rss>"""

        results = self.service.engines["china_weather"]._parse_site_rss(feed, 5)

        self.assertEqual(1, len(results))
        self.assertEqual("https://bj.weather.com.cn/index.shtml", results[0].url)

    def test_vertical_search_reserves_a_general_fallback_source(self):
        selection = self.service._select_engines(
            "Beijing conditions",
            6,
            (),
            ("weather", "regional"),
            (),
        )

        selected_verticals = {
            self.service.specs[source_id].vertical for source_id in selection.selected
        }
        self.assertIn("weather", selected_verticals)
        self.assertIn("regional", selected_verticals)
        self.assertIn("general", selected_verticals)
        self.assertIn("bing", selection.selected)

    def test_semantic_routing_prioritizes_matching_official_documentation(self):
        query = "Android app process lifecycle and WorkManager official documentation"

        self.assertIn("docs", self.service._infer_verticals(query))
        selection = self.service._select_engines(query, 6, (), (), ())

        self.assertEqual("android_developers", selection.selected[0])

    def test_repeated_independent_evidence_promotes_restricted_learned_source(self):
        result = FusedSearchResult(
            title="Independent travel guide",
            url="https://independent-travel.example/shanghai",
            excerpt="A current destination guide",
            vertical="travel",
            published_at="",
        )
        self.service.store.observe_source_candidates(
            "Shanghai hotel guide", ("travel",), (result,)
        )
        self.service.store.observe_source_candidates(
            "Shanghai visitor itinerary", ("travel",), (result,)
        )
        self.service.store.observe_source_candidates(
            "Shanghai hotel guide", ("travel",), (result,)
        )

        learned = self.service.store.learned_sources()
        self.assertEqual(1, len(learned))
        self.assertEqual("verified", learned[0].status)
        self.assertEqual(("independent-travel.example",), learned[0].engine_spec(0).allowed_hosts)
        self.service._refresh_learned_sources()
        selection = self.service._select_engines(
            "Shanghai travel",
            32,
            (),
            ("travel",),
            (),
        )
        self.assertIn(learned[0].source_id, selection.selected)

    def test_indexed_source_rejects_results_outside_declared_domain(self):
        result = self.service.search({
            "query": "Shanghai hotel",
            "engines": ["tripadvisor"],
            "engine_fanout": 1,
            "use_cache": False,
        })

        self.assertEqual(1, len(result["results"]))
        self.assertEqual(
            "tripadvisor.com",
            (urlsplit(result["results"][0]["url"]).hostname or "").removeprefix("www."),
        )

    def test_learned_category_tags_can_extend_the_builtin_taxonomy(self):
        result = FusedSearchResult(
            title="Robotics field notes",
            url="https://robotics-field-notes.example/latest",
            excerpt="Independent robotics engineering evidence",
            published_at="",
            vertical="technology",
        )
        self.service.store.observe_source_candidates(
            "robot motion planning", ("robotics",), (result,)
        )
        self.service.store.observe_source_candidates(
            "robot actuator guide", ("robotics",), (result,)
        )
        self.service.store.observe_source_candidates(
            "robot motion planning", ("robotics",), (result,)
        )
        learned = self.service.store.learned_sources()[0]
        self.service._refresh_learned_sources()

        selection = self.service._select_engines(
            "specialized field notes",
            1,
            (),
            (),
            ("robotics",),
        )

        self.assertEqual("verified", learned.status)
        self.assertIn("robotics", learned.category_tags)
        self.assertEqual((learned.source_id,), selection.selected)
        self.assertEqual(
            {
                SEARCH, FETCH, CRAWL, EXTRACT, CACHE, FIND_SIMILAR,
                RESEARCH, AGENT, DIFF, WATCH,
            },
            {
                "galaxyssi.web.intelligence.search",
                "galaxyssi.web.intelligence.fetch",
                "galaxyssi.web.intelligence.crawl",
                "galaxyssi.web.intelligence.extract",
                "galaxyssi.web.intelligence.cache",
                "galaxyssi.web.intelligence.find_similar",
                "galaxyssi.web.intelligence.research",
                "galaxyssi.web.intelligence.agent",
                "galaxyssi.web.intelligence.diff",
                "galaxyssi.web.intelligence.watch",
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
        search_schema = cloud_openai_tools()[0]["function"]["parameters"]["properties"]
        self.assertIn("verticals", search_schema)
        self.assertIn("image", search_schema["verticals"]["items"]["enum"])

    def test_wigolo_gap_sources_use_native_adapters_and_preserve_images(self):
        result = self.service.search({
            "query": "React GalaxySSI image code",
            "engines": [
                "duckduckgo_image", "marginalia", "devdocs", "github_code",
            ],
            "engine_fanout": 4,
            "limit": 10,
            "use_cache": False,
        })

        self.assertEqual("completed", result["status"])
        engines = {
            engine
            for row in result["results"]
            for engine in row["engines"]
        }
        self.assertTrue({
            "duckduckgo_image", "marginalia", "devdocs", "github_code",
        }.issubset(engines))
        image = next(row for row in result["results"] if row["vertical"] == "image")
        self.assertEqual("https://cdn.example.com/galaxyssi.png", image["image_url"])
        self.assertEqual("https://cdn.example.com/galaxyssi-thumb.png", image["thumbnail_url"])
        self.assertEqual(1200, image["image_width"])
        self.assertEqual(800, image["image_height"])
        image_request = next(
            request
            for request in self.transport.requests
            if "duckduckgo.com/i.js" in request["url"]
        )
        self.assertIn("Referer", image_request["headers"])

    def test_brave_image_requires_key_and_never_leaks_it_into_results(self):
        adaptive = self.service._select_engines(
            "GalaxySSI image",
            32,
            (),
            ("image",),
        )
        self.assertNotIn("brave_image", adaptive.selected)

        service = WebIntelligenceService(
            self.root / "with-brave",
            transport=self.transport,
            credentials={"brave_api_key": "brave-secret"},
        )
        result = service.search({
            "query": "GalaxySSI image",
            "engines": ["brave_image"],
            "engine_fanout": 1,
            "limit": 4,
            "use_cache": False,
        })

        self.assertEqual("completed", result["status"])
        request = next(
            item
            for item in self.transport.requests
            if "api.search.brave.com/res/v1/images/search" in item["url"]
        )
        self.assertEqual("brave-secret", request["headers"]["X-Subscription-Token"])
        self.assertNotIn("brave-secret", json.dumps(result))

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
        encoded = execute_cloud_web_tool(
            self.service,
            "web_search",
            {
                "query": "GalaxySSI web intelligence",
                "max_results": 4,
                "engines": ["bing", "duckduckgo"],
                "engine_fanout": 2,
                "use_cache": False,
            },
        )
        result = json.loads(encoded)

        self.assertLessEqual(len(encoded), MAX_CLOUD_TOOL_RESULT_CHARS)
        self.assertNotIn("truncated", result)
        self.assertEqual(PROTOCOL, result["protocol"])
        self.assertEqual("search", result["operation"])
        self.assertEqual(EVIDENCE_PACK_PROTOCOL, result["evidence_pack"]["protocol"])
        self.assertTrue(result["evidence_pack"]["items"])

    def test_native_invoke_returns_compact_unified_evidence_pack(self):
        result = self.service.invoke("fetch", {"url": "https://docs.example.com/root"})

        self.assertEqual(EVIDENCE_PACK_PROTOCOL, result["evidence_pack"]["protocol"])
        self.assertNotIn("content", result["documents"][0])
        item = result["evidence_pack"]["items"][0]
        self.assertEqual("document", item["source_kind"])
        self.assertEqual("retrieved_body", item["evidence_level"])
        self.assertRegex(item["content_sha256"], r"^[a-f0-9]{64}$")
        self.assertTrue(item["excerpt"])

    def test_oversized_evidence_pack_has_a_bounded_valid_cloud_form(self):
        pack = {
            "protocol": EVIDENCE_PACK_PROTOCOL,
            "query": "large evidence",
            "status": "completed",
            "generated_at_millis": 1,
            "items": [
                {
                    "citation_id": f"citation-{index}",
                    "source_kind": "document",
                    "evidence_level": "retrieved_body",
                    "url": f"https://example-{index}.test/" + "path" * 1_000,
                    "title": "Title " * 200,
                    "published_at": "2026-08-31",
                    "content_sha256": "a" * 64,
                    "excerpt": "Evidence " * 2_000,
                    "source_ids": [f"engine-{item}" for item in range(16)],
                }
                for index in range(12)
            ],
            "receipts": [],
            "stats": {"item_count": 12},
            "synthesis_contract": {"require_source_citations": True},
        }

        compact = _compact_cloud_evidence_pack(pack, 8, 500, 1_024, 4)
        encoded = json.dumps(compact, ensure_ascii=False, separators=(",", ":"))

        self.assertLessEqual(len(encoded), MAX_CLOUD_TOOL_RESULT_CHARS)
        self.assertEqual(EVIDENCE_PACK_PROTOCOL, json.loads(encoded)["protocol"])
        self.assertGreaterEqual(len(json.loads(encoded)["items"]), 1)
        self.assertLessEqual(len(json.loads(encoded)["items"]), 8)
        compact_items = json.loads(encoded)["items"]
        verification = json.loads(encoded)["verification"]
        original_urls = {item["citation_id"]: item["url"] for item in pack["items"]}
        self.assertEqual(len(compact_items), verification["item_count"])
        self.assertTrue(all(len(item["url"]) <= 4_096 for item in compact_items))
        self.assertTrue(all(
            item["url"] == original_urls[item["citation_id"]]
            for item in compact_items
        ))

    def test_evidence_pack_citation_matches_cross_platform_fixture(self):
        pack = build_evidence_pack(
            query="fixture",
            status="completed",
            documents=[{
                "url": "https://www.example.com/a?utm_source=x&b=2&a=1",
                "title": "Fixture",
                "content": "Fixture evidence",
                "content_sha256": "a" * 64,
            }],
            results=[],
            receipts=[],
            generated_at_millis=1,
        )
        item = pack["items"][0]

        self.assertEqual("https://example.com/a?a=1&b=2", item["url"])
        self.assertEqual("2a6252e1a64266545ebcf887", item["citation_id"])
        self.assertEqual(
            "e8cab87e170d719115ce193ca893dfdaa5a50e2ec880b07045cf93628f54879a",
            pack["verification"]["citation_manifest_sha256"],
        )

    def test_parallel_search_deduplicates_and_explains_score(self):
        result = self.service.search({
            "query": "GalaxySSI web intelligence",
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

    def test_parallel_search_returns_at_shared_deadline_without_waiting_for_slow_source(self):
        class SlowAdapter:
            def search(self, _query, _limit, _timeout_seconds):
                time.sleep(1.6)
                return []

        self.service.engines["duckduckgo"] = SlowAdapter()
        started = time.monotonic()

        result = self.service.search({
            "query": "GalaxySSI deadline",
            "engines": ["bing", "duckduckgo"],
            "engine_fanout": 2,
            "limit": 5,
            "timeout_seconds": 1,
            "use_cache": False,
        })

        elapsed = time.monotonic() - started
        self.assertLess(elapsed, 1.35)
        self.assertTrue(result["results"])
        receipts = {item["source_id"]: item for item in result["receipts"]}
        self.assertEqual("completed", receipts["bing"]["status"])
        self.assertEqual("timeout", receipts["duckduckgo"]["status"])

    def test_fast_search_returns_when_relevant_evidence_is_already_sufficient(self):
        slow_started = threading.Event()
        slow_release = threading.Event()
        slow_finished = threading.Event()

        class FastAdapter:
            def search(self, query, limit, _timeout_seconds):
                if not slow_started.wait(timeout=5):
                    raise AssertionError("slow search source did not start")
                return [
                    RawSearchResult(
                        "bing",
                        index,
                        f"Beijing weather today forecast {index}",
                        f"https://weather.example/{index}",
                        "Beijing weather today includes temperature and rain.",
                    )
                    for index in range(1, min(limit, 5) + 1)
                ]

        class SlowAdapter:
            def search(self, _query, _limit, _timeout_seconds):
                slow_started.set()
                try:
                    slow_release.wait(timeout=30)
                    return []
                finally:
                    slow_finished.set()

        self.service.engines["bing"] = FastAdapter()
        self.service.engines["duckduckgo"] = SlowAdapter()
        try:
            result = self.service.search({
                "query": "Beijing weather today",
                "profile": "fast",
                "engines": ["bing", "duckduckgo"],
                "engine_fanout": 2,
                "limit": 5,
                "timeout_seconds": 3,
                "use_cache": False,
            })

            self.assertFalse(
                slow_finished.is_set(),
                "fast search waited for the unfinished slow source",
            )
            self.assertTrue(result["metadata"]["fast_path_satisfied"])
            receipts = {item["source_id"]: item for item in result["receipts"]}
            self.assertEqual("completed", receipts["bing"]["status"])
            self.assertEqual("cancelled", receipts["duckduckgo"]["status"])
        finally:
            slow_release.set()
            self.assertTrue(slow_finished.wait(timeout=5))

    def test_search_response_is_persistently_cached(self):
        first = self.service.search({
            "query": "GalaxySSI cache",
            "engines": ["bing"],
            "engine_fanout": 1,
            "limit": 5,
        })
        calls = len(self.transport.calls)
        second = self.service.search({
            "query": "GalaxySSI cache",
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
        self.assertEqual("GalaxySSI documentation", extracted["metadata"]["structured"]["title"])
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
            "query": "How does GalaxySSI web intelligence work?",
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
            <html><head><title>GalaxySSI documentation</title></head>
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
            "current GalaxySSI news",
            32,
            (),
            (),
        )
        explicit = self.service._select_engines(
            "current GalaxySSI news",
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
            "query": "GalaxySSI profile",
            "profile": "fast",
            "engines": ["bing"],
            "use_cache": False,
        })

        self.assertEqual("fast", result["metadata"]["profile"])
        self.assertEqual("explicit_sources", result["metadata"]["source_selection"])
        self.assertEqual(1, len(result["metadata"]["source_health"]))


if __name__ == "__main__":
    unittest.main()
