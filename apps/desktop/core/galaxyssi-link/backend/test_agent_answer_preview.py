import json
import unittest

from agent_answer_preview import supervised_answer_preview


class AnswerPreviewTest(unittest.TestCase):
    def test_every_split_is_a_prefix_never_control_or_broken_escape(self):
        answer = 'A readable first paragraph with "quoted text".\nSecond paragraph: \U0001f4a7.'
        raw = json.dumps(dict(disposition="respond", final_response=answer, rich_output={"hidden": "metadata"}))
        previews = [supervised_answer_preview(raw[:i]) for i in range(len(raw) + 1)]
        self.assertTrue(all(answer.startswith(v) for v in previews))
        self.assertTrue(any(len(v) >= 24 for v in previews[:raw.index("Second")]))
        self.assertEqual(answer, previews[-1])

    def test_plan_or_nested_lookalike_never_becomes_answer(self):
        for raw in ('{"disposition":"plan","final_response":"do something"}',
                    '{"args":{"disposition":"respond","final_response":"private argument"}}',
                    '{"disposition":"respond","final_response":{"tool":"x"}}', 'Planning...'):
            self.assertEqual("", supervised_answer_preview(raw))
