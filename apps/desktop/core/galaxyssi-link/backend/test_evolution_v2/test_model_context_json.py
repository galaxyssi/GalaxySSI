import json
from dataclasses import dataclass
from pathlib import Path
import unittest

from evolution_v2.common import model_context_json, sha256_text, stable_json


class ModelContextJsonTests(unittest.TestCase):
    def test_canonical_ascii_representation_is_unchanged(self):
        value = {"title": "\u6062\u590d"}
        self.assertEqual('{"title":"\\u6062\\u590d"}', stable_json(value))
        self.assertEqual('{"title":"\u6062\u590d"}', model_context_json(value))
        self.assertEqual(sha256_text(stable_json(value)),
                         sha256_text(stable_json(json.loads(model_context_json(value)))))

    def test_unicode_control_characters_and_literal_escapes_round_trip(self):
        value = {"\u6807\u9898": "\u6062\u590d", "emoji": "\U0001f680", "literal": r"\u6062",
                 "lines": "one\ntwo\tthree", "quote": '"quoted"', "nested": ["\u00c9tat", "e\u0301"]}
        readable = model_context_json(value)
        self.assertEqual(value, json.loads(readable))
        self.assertEqual(json.loads(stable_json(value)), json.loads(readable))
        self.assertIn("\U0001f680", readable)
        self.assertIn("e\u0301", readable)
        self.assertIn(r"\\u6062", readable)
        self.assertIn(r"one\ntwo\tthree", readable)

    def test_existing_jsonable_conversions_are_preserved(self):
        @dataclass
        class Evidence:
            title: str
            path: Path
        value = Evidence("\u6062\u590d", Path("docs") / "\u8bf4\u660e.md")
        self.assertEqual(json.loads(stable_json(value)), json.loads(model_context_json(value)))

    def test_ascii_context_keeps_the_same_bytes(self):
        value = {"operation": "inspect", "ids": [1, 2], "enabled": True, "result": None}
        self.assertEqual(stable_json(value), model_context_json(value))


if __name__ == "__main__":
    unittest.main()
