import json
import unittest
from unittest.mock import patch

import agent_gateway
from tool_call_audit import ToolCallAuditStore
from untrusted_evidence import CONTRACT_VERSION, METADATA_KEY, POLICY_MARKER


class FakeWebIntelligence:
    def __init__(self):
        self.calls = []

    def invoke(self, operation, arguments):
        self.calls.append((operation, dict(arguments)))
        return {
            "protocol": "galaxyssi.web-intelligence.v1",
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
    def test_local_openai_model_selects_web_tool_and_synthesizes_result(self):
        service = FakeWebIntelligence()
        audit_store = ToolCallAuditStore(None)
        payloads = []
        responses = [
            {
                "choices": [{
                    "message": {
                        "role": "assistant",
                        "content": "",
                        "tool_calls": [{
                            "id": "local-search-1",
                            "type": "function",
                            "function": {
                                "name": "web_search",
                                "arguments": {"query": "current local weather", "max_results": 5},
                            },
                        }],
                    }
                }]
            },
            {
                "choices": [{
                    "message": {
                        "role": "assistant",
                        "content": "The current result is available [https://news.example/current].",
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
                "local_model_config",
                return_value={
                    "provider": "openai",
                    "url": "http://127.0.0.1:11434/v1/chat/completions",
                    "api_key": "",
                    "model": "local-tool-model",
                },
            ),
            patch.object(agent_gateway, "_post_json", side_effect=fake_post),
            patch.object(agent_gateway, "_desktop_cloud_web_service", return_value=service),
            patch.object(agent_gateway, "desktop_tool_call_audit_store", return_value=audit_store),
        ):
            answer = agent_gateway.ask_local_model("What is the current local weather?")

        self.assertIn("current result", answer)
        self.assertEqual(2, len(payloads))
        self.assertEqual("auto", payloads[0]["tool_choice"])
        self.assertEqual(10, len(payloads[0]["tools"]))
        self.assertEqual(
            [("search", {"query": "current local weather", "limit": 5, "profile": "balanced"})],
            service.calls,
        )
        self.assertEqual("galaxyssi.local.web_search", audit_store.list()[0]["tool_id"])

    def test_local_model_without_tool_support_falls_back_to_plain_inference(self):
        payloads = []

        def fake_post(_url, payload, timeout, headers=None):
            payloads.append(payload)
            if len(payloads) == 1:
                raise agent_gateway.ModelHttpError(400, "tools are not supported")
            return {"choices": [{"message": {"content": "Plain local answer."}}]}

        with (
            patch.object(
                agent_gateway,
                "local_model_config",
                return_value={
                    "provider": "openai",
                    "url": "http://127.0.0.1:11434/v1/chat/completions",
                    "api_key": "",
                    "model": "plain-local-model",
                },
            ),
            patch.object(agent_gateway, "_post_json", side_effect=fake_post),
        ):
            answer = agent_gateway.ask_local_model("Hello")

        self.assertEqual("Plain local answer.", answer)
        self.assertEqual(2, len(payloads))
        self.assertIn("tools", payloads[0])
        self.assertNotIn("tools", payloads[1])

    def test_deepseek_inline_tool_call_is_executed_then_synthesized(self):
        service = FakeWebIntelligence()
        audit_store = ToolCallAuditStore(None)
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
            patch.object(agent_gateway, "desktop_tool_call_audit_store", return_value=audit_store),
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
        self.assertIn(CONTRACT_VERSION, payloads[1]["messages"][-1]["content"])
        self.assertNotIn("DSML", answer)
        audit = audit_store.list()
        self.assertEqual("galaxyssi.cloud.web_search", audit[0]["tool_id"])
        self.assertEqual("succeeded", audit[0]["status"])

    def test_repeated_tool_calls_finalize_without_exposing_an_internal_error(self):
        service = FakeWebIntelligence()
        audit_store = ToolCallAuditStore(None)
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
            patch.object(agent_gateway, "desktop_tool_call_audit_store", return_value=audit_store),
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
        self.assertEqual(3, len(audit_store.list()))

    def test_structured_web_result_has_no_instruction_authority(self):
        service = FakeWebIntelligence()
        audit_store = ToolCallAuditStore(None)
        payloads = []
        responses = [
            {
                "choices": [{
                    "message": {
                        "role": "assistant",
                        "content": "",
                        "tool_calls": [{
                            "id": "call-web-1",
                            "type": "function",
                            "function": {
                                "name": "web_fetch",
                                "arguments": '{"url":"https://news.example/current"}',
                            },
                        }],
                    }
                }]
            },
            {
                "choices": [{
                    "message": {
                        "role": "assistant",
                        "content": "Verified summary.",
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
                    "model": "test-model",
                },
            ),
            patch.object(agent_gateway, "_post_json", side_effect=fake_post),
            patch.object(agent_gateway, "_desktop_cloud_web_service", return_value=service),
            patch.object(agent_gateway, "desktop_tool_call_audit_store", return_value=audit_store),
        ):
            answer = agent_gateway.ask_cloud_model("Fetch the report.", raise_errors=True)

        self.assertEqual("Verified summary.", answer)
        second_messages = payloads[1]["messages"]
        self.assertTrue(any(
            item.get("role") == "system" and POLICY_MARKER in item.get("content", "")
            for item in second_messages
        ))
        tool_message = next(item for item in second_messages if item.get("role") == "tool")
        envelope = json.loads(tool_message["content"].split("\n", 1)[1])
        self.assertEqual("untrusted", envelope[METADATA_KEY]["trust"])
        self.assertEqual("none", envelope[METADATA_KEY]["instruction_authority"])


if __name__ == "__main__":
    unittest.main()
