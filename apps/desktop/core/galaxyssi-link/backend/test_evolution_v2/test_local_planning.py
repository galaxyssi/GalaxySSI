from __future__ import annotations

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import threading
import unittest
from unittest.mock import patch

from evolution_v2.local_planning import LocalPlannerUnavailable, infer_local_plan, messages_with_response_schema


class LocalPlanningTests(unittest.TestCase):
    def server(self, status=200, message=None):
        received = []
        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                received.append((self.path, json.loads(self.rfile.read(int(self.headers["Content-Length"])))))
                self.send_response(status)
                self.send_header("Location", "https://example.com/private-data")
                self.end_headers()
                self.wfile.write(json.dumps({"choices": [{"message": message or {"content": '{"operation":"wait","reason":"Need evidence"}'}}]}).encode())
            def log_message(self, *args):
                pass
        server = HTTPServer(("127.0.0.1", 0), Handler)
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        def close():
            server.shutdown()
            worker.join(5)
            server.server_close()
        self.addCleanup(close)
        return {"url": f"http://127.0.0.1:{server.server_port}/api/generate", "model": "local-test"}, received

    def test_literal_loopback_bypasses_proxy_and_sends_no_tools(self):
        config, received = self.server()
        with patch.dict("os.environ", {"HTTP_PROXY": "http://127.0.0.1:1", "HTTPS_PROXY": "http://127.0.0.1:1"}):
            answer = infer_local_plan([{"role": "user", "content": "private observation"}], config=config)
        self.assertEqual("wait", json.loads(answer)["operation"])
        self.assertEqual("/v1/chat/completions", received[0][0])
        self.assertNotIn("tools", received[0][1])
        self.assertTrue(received[0][1]["stream"])

    def test_remote_and_ambiguous_endpoints_never_connect(self):
        for url in ("", "https://example.com/v1/chat/completions", "http://192.168.1.2/v1/chat/completions",
                    "http://127.0.0.1.evil.test/v1/chat/completions", "http://user@127.0.0.1/v1/chat/completions",
                    "file:///private", "http://127.0.0.1/v1/chat/completions?target=remote"):
            with self.subTest(url=url), patch("http.client.HTTPConnection") as connect:
                with self.assertRaises(LocalPlannerUnavailable):
                    infer_local_plan([], config={"url": url, "model": "local"})
                connect.assert_not_called()

    def test_redirect_is_not_followed(self):
        config, received = self.server(status=302)
        with self.assertRaises(LocalPlannerUnavailable):
            infer_local_plan([], config=config)
        self.assertEqual(1, len(received))

    def test_tool_requests_are_not_executed(self):
        config, _ = self.server(message={"content": "", "tool_calls": [{"function": {"name": "web_search"}}]})
        with self.assertRaises(LocalPlannerUnavailable):
            infer_local_plan([], config=config)

    def test_unconfigured_model_does_not_guess_or_fallback(self):
        with patch("http.client.HTTPConnection") as connect:
            with self.assertRaises(LocalPlannerUnavailable):
                infer_local_plan([], config={"url": "http://127.0.0.1:11434/v1/chat/completions"})
            connect.assert_not_called()

    def test_schema_is_opt_in_and_transported_only_to_local_provider(self):
        from evolution_v2.local_action_contract import action_schema
        config, received = self.server()
        infer_local_plan([], config=config)
        self.assertNotIn("response_format", received[-1][1])
        infer_local_plan([], config=config, response_schema=action_schema())
        self.assertEqual({"type": "json_schema", "json_schema": {
            "name": "local_file_action", "schema": action_schema()}}, received[-1][1]["response_format"])
        self.assertNotIn("tools", received[-1][1])
        visible = received[-1][1]["messages"][0]
        self.assertEqual("system", visible["role"])
        self.assertIn(json.dumps(action_schema(), ensure_ascii=False, separators=(",", ":")), visible["content"])

    def test_schema_enriches_the_system_prompt_without_changing_source_or_history(self):
        config, received = self.server()
        messages = [{"role": "system", "content": "Verify the source goal."},
                    {"role": "user", "content": "private original goal"},
                    {"role": "assistant", "content": "previous decision"},
                    {"role": "user", "content": "actual failure observation"}]
        original = json.loads(json.dumps(messages))
        schema = {"type": "object", "properties": {"verdict": {"enum": ["pass", "fail"]}}}
        for _ in range(2):
            infer_local_plan(messages, config=config, response_schema=schema)
        for _, request in received:
            self.assertEqual(messages[1:], request["messages"][1:])
            self.assertTrue(request["messages"][0]["content"].startswith(messages[0]["content"]))
            self.assertEqual(1, request["messages"][0]["content"].count("following response schema"))
            self.assertEqual(schema, request["response_format"]["json_schema"]["schema"])
            self.assertTrue(request["stream"])
        self.assertEqual(original, messages)

    def test_unconstrained_request_messages_are_unchanged(self):
        config, received = self.server()
        messages = [{"role": "system", "content": "Plan normally."}, {"role": "user", "content": "goal"}]
        infer_local_plan(messages, config=config)
        self.assertEqual(messages, received[0][1]["messages"])
        self.assertNotIn("response_format", received[0][1])

    def test_visible_schema_preserves_nested_required_fields_and_unicode(self):
        schema = {"type": "object", "properties": {"checks": {"type": "array", "items": {
            "type": "object", "properties": {"kind": {"enum": ["contains", "markdown_heading"]},
            "path": {"enum": ["docs/\u8bf4\u660e.md"]}}, "required": ["kind", "path"],
            "additionalProperties": False}}}, "required": ["checks"], "additionalProperties": False}
        result = messages_with_response_schema([], schema)
        encoded = result[0]["content"].split("\n", 1)[1]
        self.assertEqual(schema, json.loads(encoded))
        self.assertIn("\u8bf4\u660e", encoded)

    def test_boolean_schema_and_non_string_system_content_are_preserved(self):
        messages = [{"role": "system", "content": [{"type": "text", "text": "policy"}]},
                    {"role": "user", "content": "goal"}]
        result = messages_with_response_schema(messages, False)
        self.assertEqual("false", result[0]["content"].split("\n", 1)[1])
        self.assertEqual(messages, result[1:])

    def test_empty_or_absent_system_prompt_gets_one_format_instruction(self):
        for messages in ([], [{"role": "user", "content": "goal"}], [{"role": "system", "content": ""}]):
            with self.subTest(messages=messages):
                result = messages_with_response_schema(messages, {"type": "object"})
                self.assertEqual(1, sum(row["role"] == "system" for row in result))
                self.assertIn("response structure, not additional task requirements", result[0]["content"])

    def test_rejected_schema_request_does_not_silently_retry_or_use_cloud(self):
        config, received = self.server(status=400)
        with self.assertRaises(LocalPlannerUnavailable):
            infer_local_plan([], config=config, response_schema={"type": "object"})
        self.assertEqual(1, len(received))


if __name__ == "__main__":
    unittest.main()
