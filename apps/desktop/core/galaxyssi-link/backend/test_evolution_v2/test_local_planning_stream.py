from __future__ import annotations

import http.client
from http.server import BaseHTTPRequestHandler, HTTPServer
from io import BytesIO
import json
import threading
import time
import unittest
from unittest.mock import patch

from evolution_v2.local_planning import LocalPlannerUnavailable, infer_local_plan
from evolution_v2.local_planning_stream import PlanningStreamError, read_decision_stream


def event(delta=None, finish=None):
    return b"data: " + json.dumps({"choices": [{"index": 0, "delta": delta or {},
        "finish_reason": finish}]}).encode() + b"\n\n"


class PlanningStreamTests(unittest.TestCase):
    socket_timeout = .25

    def test_reasoning_is_not_retained_and_utf8_content_is_joined(self):
        wire = event({"reasoning_content": "private intermediate reasoning"})
        wire += event({"content": '{"operation":'}) + event({"content": '"wait"}'})
        wire += event(finish="stop") + b'data: {"choices":[],"usage":{}}\n\ndata: [DONE]\n\n'
        self.assertEqual('{"operation":"wait"}', read_decision_stream(BytesIO(wire)))

    def test_partial_truncated_and_tool_responses_are_not_decisions(self):
        for wire in (event({"content": "{"}), event({"content": "{}"}) + b"data: [DONE]\n\n",
                     event({"content": "{}"}, "length") + b"data: [DONE]\n\n",
                     event({"tool_calls": [{"id": "tool"}]}),
                     event({"function_call": {"name": "execute"}}),
                     event(finish="stop") + b"data: [DONE]\n\n"):
            with self.subTest(wire=wire), self.assertRaises(PlanningStreamError):
                read_decision_stream(BytesIO(wire))

    def test_response_envelope_counts_ignored_reasoning_and_comments(self):
        with patch("evolution_v2.local_planning_stream.RESPONSE_LIMIT", 30):
            with self.assertRaises(PlanningStreamError):
                read_decision_stream(BytesIO(b":" + b"x" * 30 + b"\n\n"))

    def test_context_or_output_exhaustion_has_an_actionable_reason(self):
        with self.assertRaisesRegex(PlanningStreamError, "context or output limit"):
            read_decision_stream(BytesIO(event({"content": "{"}, "length")))

    def run_stream(self, silence=False):
        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                self.rfile.read(int(self.headers["Content-Length"]))
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream; charset=utf-8")
                self.end_headers()
                try:
                    for _ in range(12):
                        time.sleep(.4 if silence else .05)
                        self.wfile.write(event({"reasoning_content": "progress"}))
                        self.wfile.flush()
                    self.wfile.write(event({"content": '{"operation":"wait"}'}, "stop") + b"data: [DONE]\n\n")
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                    pass
            def log_message(self, *args):
                pass
        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        original = http.client.HTTPConnection
        try:
            with patch("http.client.HTTPConnection", side_effect=lambda host, port, timeout: original(host, port, timeout=self.socket_timeout)):
                began = time.perf_counter()
                result = infer_local_plan([], config={
                    "url": f"http://127.0.0.1:{server.server_port}/v1/chat/completions", "model": "test"})
                self.request_elapsed = time.perf_counter() - began
                return result
        finally:
            server.shutdown()
            thread.join(5)
            server.server_close()

    def test_active_stream_can_exceed_socket_inactivity_timeout(self):
        self.assertEqual("wait", json.loads(self.run_stream())["operation"])
        # Exclude server teardown and compare with the actual socket timeout, not the intended sleep total.
        self.assertGreater(self.request_elapsed, self.socket_timeout)

    def test_silent_stream_still_times_out(self):
        with self.assertRaises(LocalPlannerUnavailable):
            self.run_stream(silence=True)


if __name__ == "__main__":
    unittest.main()
