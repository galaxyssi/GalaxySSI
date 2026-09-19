import unittest
from research_trace import search_receipt, replay_receipts
import json


class ResearchTraceTests(unittest.TestCase):
    def test_all_explicit_queries_are_kept_and_deduplicated(self):
        result = search_receipt({"type": "webSearch", "query": "AI news",
                                 "action": {"queries": ["ai news", "Chip news"]}}, completed=False)
        self.assertEqual(["AI news", "Chip news"], result["queries"])
        self.assertEqual([], result["sources"])

    def test_sources_require_completion_and_safe_urls(self):
        item = {"type": "webSearch", "results": [
            {"url": "https://example.org/a#one", "title": "Source"},
            {"url": "https://example.org/a#two", "title": "Same"},
            {"url": "javascript:alert(1)"}, {"url": "https://secret@example.org"}]}
        self.assertEqual([], search_receipt(item, completed=False)["sources"])
        self.assertEqual([{"url": "https://example.org/a", "title": "Source"}], search_receipt(item, completed=True)["sources"])

    def test_hidden_sources_and_prose_are_not_invented(self):
        result = search_receipt({"type": "webSearch", "query": "news", "text": "Read 80 sources"}, completed=True)
        self.assertEqual([], result["sources"])
        self.assertEqual({}, search_receipt({"type": "reasoning", "query": "private"}, completed=True))

    def test_open_page_is_a_source_not_a_keyword(self):
        result = search_receipt({"type": "webSearch", "action": {"type": "openPage", "url": "https://example.org"}}, completed=True)
        self.assertEqual([], result["queries"])
        self.assertEqual("https://example.org", result["sources"][0]["url"])

    def test_reconnect_replays_receipts_without_double_counting(self):
        receipt = search_receipt({"type": "webSearch", "query": "news",
                                  "sources": [{"url": "https://example.org", "title": "Source"}]}, completed=True)
        events = [{"metadata": {"research_trace": receipt}}] * 2
        replay = replay_receipts(events)
        self.assertEqual(["news"], replay["queries"])
        self.assertEqual(1, len(replay["sources"]))
        self.assertFalse(replay["truncated"])

    def test_large_receipt_stays_under_task_metadata_limit(self):
        receipt = search_receipt({"type": "webSearch", "action": {"queries": [str(i) + "x" * 1000 for i in range(128)]},
                                  "sources": [{"url": "https://example.org/" + str(i), "title": "x" * 512} for i in range(512)]}, completed=True)
        self.assertLessEqual(len(json.dumps(receipt, ensure_ascii=False, separators=(",", ":")).encode()), 12000)
        self.assertTrue(receipt["truncated"])

    def test_codex_event_adapters_preserve_receipt_metadata(self):
        from codex_app_server import CodexAppServer
        item = {"id": "search", "type": "webSearch", "query": "news"}
        event = CodexAppServer._item_event(item, "completed")
        self.assertEqual(["news"], event["event_metadata"]["research_trace"]["queries"])
