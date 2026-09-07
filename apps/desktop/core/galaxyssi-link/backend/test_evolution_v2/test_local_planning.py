from __future__ import annotations

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import threading
import unittest
from unittest.mock import patch

from evolution_v2.local_planning import LocalPlannerUnavailable, infer_local_plan


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
        self.assertFalse(received[0][1]["stream"])

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


if __name__ == "__main__":
    unittest.main()
