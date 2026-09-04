import unittest

from model_directed_search import (
    CODEX_DYNAMIC_FETCH_TOOL,
    CODEX_DYNAMIC_SEARCH_TOOL,
    _engine_query,
    codex_dynamic_fetch_tool_spec,
    codex_dynamic_search_tool_spec,
    execute_codex_dynamic_fetch,
    execute_codex_dynamic_search,
    render_search_evidence,
    retrieve_model_selected_evidence,
)


class ModelDirectedSearchTests(unittest.TestCase):
    def test_dynamic_fetch_tool_reads_explicit_url_and_preserves_images(self):
        calls = []

        class Registry:
            def invoke(self, tool_id, arguments, context):
                calls.append((tool_id, arguments, context))
                return {
                    "status": "succeeded",
                    "output": {
                        "documents": [{
                            "title": "Public article",
                            "url": arguments["url"],
                            "content": "Article evidence from the Desktop.",
                            "metadata": {
                                "images": [{"url": "https://mmbiz.qpic.cn/article/image.png"}],
                            },
                        }],
                    },
                }

        spec = codex_dynamic_fetch_tool_spec()
        response = execute_codex_dynamic_fetch(
            {"urls": ["https://mp.weixin.qq.com/s/example"]},
            "task-fetch",
            registry=Registry(),
        )

        self.assertEqual(CODEX_DYNAMIC_FETCH_TOOL, spec["name"])
        self.assertTrue(response["success"])
        self.assertEqual(
            "galaxyssi.web-evidence-pack.v1",
            response["_galaxyssi_evidence_pack"]["protocol"],
        )
        evidence = response["contentItems"][0]["text"]
        self.assertIn("Article evidence from the Desktop.", evidence)
        self.assertIn("https://mmbiz.qpic.cn/article/image.png", evidence)
        self.assertEqual(10 * 1024 * 1024, calls[0][1]["max_bytes"])
        self.assertEqual("model_selected_direct_web_read", calls[0][2]["source"])

    def test_dynamic_fetch_strips_prose_after_an_explicit_url(self):
        calls = []

        class Registry:
            def invoke(self, _tool_id, arguments, _context):
                calls.append(arguments)
                return {
                    "status": "succeeded",
                    "output": {"documents": [{
                        "title": "Article",
                        "url": arguments["url"],
                        "content": "Evidence",
                    }]},
                }

        response = execute_codex_dynamic_fetch(
            {"urls": ["https://mp.weixin.qq.com/s/example\uff0c\u8bf7\u4e0b\u8f7d\u4fdd\u5b58"]},
            "task-normalize",
            registry=Registry(),
        )

        self.assertTrue(response["success"])
        self.assertEqual("https://mp.weixin.qq.com/s/example", calls[0]["url"])

    def test_engine_query_keeps_intent_but_drops_expanded_current_date(self):
        query = _engine_query(
            "北京今天（2026年8月6日）天气、气温和降雨情况；优先权威来源"
        )

        self.assertEqual("北京 今天天气", query)
        self.assertIn("2024-08-06", _engine_query("北京 2024-08-06 历史天气"))

    def test_model_selected_weather_query_is_search_engine_friendly(self):
        self.assertEqual(
            "上海 今天天气",
            _engine_query("上海今天气温和降雨", ("weather",)),
        )
        self.assertIn(
            "2024-08-06",
            _engine_query("上海 2024-08-06 历史天气", ("weather",)),
        )

    def test_live_chinese_query_drops_expanded_date_but_keeps_intent(self):
        query = _engine_query(
            "\u4e0a\u6d77\u4eca\u5929\u5929\u6c14 2026\u5e748\u67086\u65e5 "
            "\u5f53\u524d\u6c14\u6e29 \u5929\u6c14\u9884\u62a5",
            ("weather",),
        )

        self.assertNotIn("2026", query)
        self.assertIn("\u4e0a\u6d77", query)
        self.assertIn("\u4eca\u5929\u5929\u6c14", query)

    def test_dynamic_tool_requires_a_self_contained_query(self):
        spec = codex_dynamic_search_tool_spec()

        self.assertEqual(CODEX_DYNAMIC_SEARCH_TOOL, spec["name"])
        self.assertEqual("function", spec["type"])
        self.assertEqual(["query"], spec["inputSchema"]["required"])
        self.assertIn("full conversation", spec["description"])
        self.assertIn("native model web search", spec["description"])

        response = execute_codex_dynamic_search({}, "task-empty")
        self.assertFalse(response["success"])
        self.assertIn("self-contained", response["contentItems"][0]["text"])

    def test_dynamic_tool_returns_cited_parallel_evidence(self):
        class Registry:
            def invoke(self, _tool_id, _arguments, _context):
                return {
                    "status": "succeeded",
                    "output": {
                        "status": "completed",
                        "results": [{
                            "title": "Zhuhai weather authority",
                            "url": "https://weather.example/current",
                            "excerpt": "Sunny, 27 to 33 C.",
                        }],
                    },
                    "receipt": {"duration_ms": 450},
                }

        response = execute_codex_dynamic_search(
            {"query": "Zhuhai current weather"},
            "task-search",
            registry=Registry(),
        )

        self.assertTrue(response["success"])
        self.assertEqual(
            "galaxyssi.web-evidence-pack.v1",
            response["_galaxyssi_evidence_pack"]["protocol"],
        )
        output = response["contentItems"][0]["text"]
        self.assertIn("Zhuhai current weather", output)
        self.assertIn("https://weather.example/current", output)

    def test_parallel_retrieval_uses_fast_multi_source_profile(self):
        calls = []

        class Registry:
            def invoke(self, tool_id, arguments, context):
                calls.append((tool_id, arguments, context))
                return {
                    "status": "succeeded",
                    "output": {
                        "status": "partial",
                        "results": [
                            {
                                "title": "Zhuhai weather authority",
                                "url": "https://weather.example/current",
                                "excerpt": "Sunny, 27 to 33 C.",
                                "published_at": "2026-08-06T10:00:00+08:00",
                                "engines": ["bing", "brave"],
                            },
                        ],
                    },
                    "receipt": {"duration_ms": 1870},
                }

        evidence = retrieve_model_selected_evidence(
            "Zhuhai current weather",
            "task-1",
            registry=Registry(),
        )

        self.assertEqual(1, evidence.result_count)
        self.assertGreaterEqual(evidence.elapsed_ms, 0)
        self.assertIn("untrusted source data", evidence.prompt)
        self.assertIn("https://weather.example/current", evidence.prompt)
        self.assertIn("instead of repeating the same search", evidence.prompt)
        _tool_id, arguments, context = calls[0]
        self.assertEqual("fast", arguments["profile"])
        self.assertEqual(6, arguments["engine_fanout"])
        self.assertIsInstance(arguments["timeout_seconds"], int)
        self.assertEqual(
            ["bing", "duckduckgo", "brave", "mojeek", "qwant", "ecosia"],
            arguments["engines"],
        )
        self.assertFalse(arguments["use_cache"])
        self.assertEqual("model_selected_web_search", context["source"])

    def test_model_selected_vertical_reads_source_page_in_same_call(self):
        calls = []

        class Registry:
            def invoke(self, tool_id, arguments, context):
                calls.append((tool_id, arguments, context))
                if tool_id.endswith(".fetch"):
                    return {
                        "status": "succeeded",
                        "output": {
                            "documents": [{
                                "title": "Zhuhai forecast",
                                "url": arguments["url"],
                                "content": (
                                    "Zhuhai forecast for tomorrow. High 31 C, low 27 C, "
                                    "with a 36 percent chance of rain."
                                ),
                            }],
                        },
                    }
                return {
                    "status": "succeeded",
                    "output": {
                        "status": "completed",
                        "results": [{
                            "title": "Zhuhai weather tomorrow",
                            "url": "https://weather.example/zhuhai/tomorrow",
                            "excerpt": "Forecast page",
                            "score": {"lexical": 0.8},
                        }],
                    },
                    "receipt": {"duration_ms": 250},
                }

        response = execute_codex_dynamic_search(
            {
                "query": "Zhuhai weather tomorrow",
                "verticals": ["weather"],
                "read_pages": True,
            },
            "task-vertical",
            registry=Registry(),
        )

        self.assertTrue(response["success"])
        self.assertEqual(
            "galaxyssi.web-evidence-pack.v1",
            response["_galaxyssi_evidence_pack"]["protocol"],
        )
        output = response["contentItems"][0]["text"]
        self.assertIn("High 31 C", output)
        search_call = next(call for call in calls if call[1].get("verticals") == ["weather"])
        self.assertEqual(["weather"], search_call[1]["verticals"])
        self.assertNotIn("engines", search_call[1])
        general_call = next(call for call in calls if call[1].get("engines"))
        self.assertEqual(["bing", "duckduckgo", "mojeek"], general_call[1]["engines"])
        fetch_call = next(call for call in calls if call[0].endswith(".fetch"))
        self.assertIsInstance(fetch_call[1]["timeout_seconds"], int)

    def test_vertical_search_races_general_sources_and_uses_the_fallback_results(self):
        class Registry:
            def invoke(self, _tool_id, arguments, _context):
                if arguments.get("verticals"):
                    return {
                        "status": "succeeded",
                        "output": {"status": "failed", "results": []},
                    }
                return {
                    "status": "succeeded",
                    "output": {
                        "status": "completed",
                        "results": [{
                            "title": "Shanghai current weather",
                            "url": "https://weather.example/shanghai",
                            "excerpt": "Cloudy, 28 C.",
                            "score": {"lexical": 0.8},
                        }],
                    },
                }

        evidence = retrieve_model_selected_evidence(
            "Shanghai current weather",
            "task-race",
            registry=Registry(),
            verticals=["weather"],
            read_pages=False,
        )

        self.assertEqual("completed", evidence.status)
        self.assertEqual(1, evidence.result_count)
        self.assertIn("Cloudy, 28 C", evidence.prompt)

    def test_rich_search_snippets_skip_redundant_page_reads(self):
        calls = []

        class Registry:
            def invoke(self, tool_id, _arguments, _context):
                calls.append(tool_id)
                return {
                    "status": "succeeded",
                    "output": {
                        "status": "completed",
                        "results": [
                            {
                                "title": "Source one current result",
                                "url": "https://one.example/current",
                                "excerpt": "Current result details " * 8,
                            },
                            {
                                "title": "Source two current result",
                                "url": "https://two.example/current",
                                "excerpt": "Independent current result details " * 8,
                            },
                        ],
                    },
                }

        evidence = retrieve_model_selected_evidence(
            "current result details",
            "task-rich-snippets",
            registry=Registry(),
            read_pages=True,
        )

        self.assertEqual(2, evidence.result_count)
        self.assertEqual(0, evidence.page_count)
        self.assertEqual(["galaxyssi.web.intelligence.search"], calls)

    def test_irrelevant_search_results_are_not_reported_as_success(self):
        class Registry:
            def invoke(self, _tool_id, _arguments, _context):
                return {
                    "status": "succeeded",
                    "output": {
                        "status": "partial",
                        "results": [{
                            "title": "2026 baseball schedule",
                            "url": "https://sports.example/schedule",
                            "excerpt": "August fixtures",
                            "score": {"lexical": 0.0},
                        }],
                    },
                }

        response = execute_codex_dynamic_search(
            {"query": "Zhuhai weather forecast tomorrow", "read_pages": False},
            "task-irrelevant",
            registry=Registry(),
        )

        self.assertTrue(response["success"])
        self.assertIn("no sufficiently relevant", response["contentItems"][0]["text"])
        self.assertIn("Do not retry", response["contentItems"][0]["text"])

    def test_ranker_score_cannot_make_a_topic_mismatch_relevant(self):
        class Registry:
            def invoke(self, _tool_id, _arguments, _context):
                return {
                    "status": "succeeded",
                    "output": {
                        "status": "completed",
                        "results": [{
                            "title": "Shanghai city history",
                            "url": "https://example.com/shanghai-history",
                            "excerpt": "A history of the city and its economy.",
                            "score": {"lexical": 0.99},
                        }],
                    },
                }

        response = execute_codex_dynamic_search(
            {"query": "Shanghai current weather", "read_pages": False},
            "task-topic-mismatch",
            registry=Registry(),
        )

        self.assertTrue(response["success"])
        self.assertIn("no sufficiently relevant", response["contentItems"][0]["text"])

    def test_rendered_evidence_is_bounded_and_contains_citations(self):
        prompt = render_search_evidence(
            "current result",
            [
                {
                    "title": "A" * 1_000,
                    "url": "https://example.com/" + "u" * 3_000,
                    "excerpt": "E" * 3_000,
                    "engines": ["bing"],
                },
            ],
        )

        self.assertLess(len(prompt), 12_000)
        self.assertIn("https://example.com/", prompt)
        self.assertIn("Cite only URLs listed in the Evidence Pack", prompt)


if __name__ == "__main__":
    unittest.main()
