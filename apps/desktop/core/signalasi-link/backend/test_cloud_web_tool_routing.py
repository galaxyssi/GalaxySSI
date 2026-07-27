import unittest
from unittest.mock import patch

import agent_gateway


class FakeWebIntelligence:
    def __init__(self):
        self.calls = []

    def invoke(self, operation, arguments):
        self.calls.append((operation, dict(arguments)))
        return {
            "protocol": "signalasi.web-intelligence.v1",
            "operation": operation,
            "status": "completed",
            "results": [
                {
                    "title": "Current technology report",
                    "url": "https://news.example/current",
                    "excerpt": "Current verified evidence.",
                }
            ],
        }


class CloudWebToolRoutingTests(unittest.TestCase):
    def test_deepseek_inline_tool_call_is_executed_then_synthesized(self):
        service = FakeWebIntelligence()
        payloads = []
        responses = [
            {
                "choices": [{
                    "message": {
                        "role": "assistant",
                        "content": (
                            '<\uff5cDSML\uff5ctool_calls>'
                            '<\uff5cDSML\uff5cinvoke name="web_search">'
                            '<\uff5cDSML\uff5cparam name="query">\u73b0\u5728\u7684\u79d1\u6280\u65b0\u95fb</\uff5cDSML\uff5c/param>'
                            '<\uff5cDSML\uff5cparam name="max_results">6</\uff5cDSML\uff5c/param>'
                            '<\uff5cDSML\uff5c/invoke>'
                            '<\uff5cDSML\uff5c/tool_calls>'
                        ),
                    }
                }]
            },
            {
                "choices": [{
                    "message": {
                        "role": "assistant",
                        "content": "Here is the current technology news summary [https://news.example/current].",
                    }
                }]
            },
        ]

        def fake_post(_url, payload, timeout, headers=None):
            payloads.append(payload)
            return responses.pop(0)

        with (
            patch.object(
                agent_gateway,
                "cloud_model_config",
                return_value={
                    "url": "https://api.example/chat/completions",
                    "api_key": "secret",
                    "model": "deepseek-current",
                },
            ),
            patch.object(agent_gateway, "_post_json", side_effect=fake_post),
            patch.object(agent_gateway, "_desktop_cloud_web_service", return_value=service),
        ):
            answer = agent_gateway.ask_cloud_model(
                "\u73b0\u5728\u7684\u79d1\u6280\u65b0\u95fb",
                raise_errors=True,
            )

        self.assertEqual(
            "Here is the current technology news summary [https://news.example/current].",
            answer,
        )
        self.assertEqual([("search", {"query": "\u73b0\u5728\u7684\u79d1\u6280\u65b0\u95fb", "limit": 6, "profile": "balanced"})], service.calls)
        self.assertEqual(2, len(payloads))
        self.assertEqual(10, len(payloads[0]["tools"]))
        self.assertIn("Current local date, time, and UTC offset", payloads[0]["messages"][0]["content"])
        self.assertNotIn("Asia/Shanghai", payloads[0]["messages"][0]["content"])
        self.assertIn("untrusted public evidence", payloads[1]["messages"][-1]["content"])
        self.assertNotIn("DSML", answer)

    def test_repeated_tool_calls_finalize_without_exposing_an_internal_error(self):
        service = FakeWebIntelligence()
        payloads = []
        tool_markup = (
            '<\uff5cDSML\uff5ctool_calls>'
            '<\uff5cDSML\uff5cinvoke name="web_search">'
            '<\uff5cDSML\uff5cparam name="query">\u4eca\u5929\u7684\u79d1\u6280\u65b0\u95fb</\uff5cDSML\uff5c/param>'
            '<\uff5cDSML\uff5c/invoke>'
            '<\uff5cDSML\uff5c/tool_calls>'
        )
        responses = [
            {"choices": [{"message": {"role": "assistant", "content": tool_markup}}]}
            for _ in range(4)
        ]
        responses.append({"choices": []})

        def fake_post(_url, payload, timeout, headers=None):
            payloads.append(payload)
            return responses.pop(0)

        with (
            patch.object(
                agent_gateway,
                "cloud_model_config",
                return_value={
                    "url": "https://api.example/chat/completions",
                    "api_key": "secret",
                    "model": "deepseek-current",
                },
            ),
            patch.object(agent_gateway, "_post_json", side_effect=fake_post),
            patch.object(agent_gateway, "_desktop_cloud_web_service", return_value=service),
        ):
            answer = agent_gateway.ask_cloud_model(
                "\u4eca\u5929\u7684\u79d1\u6280\u65b0\u95fb",
                raise_errors=True,
            )

        self.assertIn("\u6211\u627e\u5230\u4e86\u4ee5\u4e0b\u5f53\u524d\u6765\u6e90", answer)
        self.assertIn("https://news.example/current", answer)
        self.assertNotIn("did not produce a final answer", answer)
        self.assertEqual(5, len(payloads))
        self.assertNotIn("tools", payloads[-1])
        self.assertIn("Return only the final user-facing answer", payloads[-1]["messages"][-1]["content"])


if __name__ == "__main__":
    unittest.main()
